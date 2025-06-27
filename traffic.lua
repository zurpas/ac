-- Assetto Corsa Traffic Server Script - Final Version
-- CSP Compatible - No Hesi Style Traffic Server
-- Version 3.0.0 - Clean implementation with proper CSP API

-- Global variables
local initialized = false
local frameCount = 0

-- Player data
local playerData = {
    score = 0,
    personalBest = 0,
    lives = 3,
    lastCollisionTime = 0,
    speedMultiplier = 1.0,
    proximityMultiplier = 1.0,
    comboMultiplier = 1.0,
    comboCount = 0,
    lastSpeed = 0,
    lanesUsed = {},
    nearMissCount = 0,
    collisionCount = 0,
    sessionStartTime = 0,
    lastScoreTime = 0
}

-- UI state
local uiState = {
    showMainUI = true,
    showPopup = false,
    popupText = "",
    popupType = "info",
    popupStartTime = 0,
    popupDuration = 3.0,
    scoreAnimation = {
        active = false,
        startTime = 0,
        duration = 1.0,
        startValue = 0,
        endValue = 0
    },
    pbAnimation = {
        active = false,
        startTime = 0,
        duration = 2.0,
        scale = 1.0
    }
}

-- Colors using rgbm format
local colors = {
    background = rgbm(0.1, 0.1, 0.1, 0.95),
    primary = rgbm(0.6, 0.4, 1.0, 1.0),
    success = rgbm(0.2, 0.8, 0.2, 1.0),
    warning = rgbm(1.0, 0.6, 0.0, 1.0),
    error = rgbm(1.0, 0.2, 0.2, 1.0),
    text = rgbm(1.0, 1.0, 1.0, 1.0),
    textDim = rgbm(0.7, 0.7, 0.7, 1.0),
    accent = rgbm(0.0, 0.8, 1.0, 1.0)
}

-- Utility functions
local function lerp(a, b, t)
    return a + (b - a) * math.max(0, math.min(1, t))
end

local function easeOutQuart(t)
    return 1 - math.pow(1 - t, 4)
end

local function easeInOutCubic(t)
    return t < 0.5 and 4 * t * t * t or 1 - math.pow(-2 * t + 2, 3) / 2
end

local function formatTime(seconds)
    local minutes = math.floor(seconds / 60)
    local secs = math.floor(seconds % 60)
    return string.format("%02d:%02d", minutes, secs)
end

local function formatScore(score)
    local scoreInt = math.floor(score)
    local str = tostring(scoreInt)
    local len = string.len(str)
    local result = ""
    
    for i = 1, len do
        result = result .. string.sub(str, i, i)
        if (len - i) % 3 == 0 and i ~= len then
            result = result .. ","
        end
    end
    return result
end

-- Storage functions
local function savePlayerData()
    ac.storage.score = playerData.score
    ac.storage.personalBest = playerData.personalBest
    ac.storage.lives = playerData.lives
    ac.storage.collisionCount = playerData.collisionCount
end

local function loadPlayerData()
    playerData.score = ac.storage.score or 0
    playerData.personalBest = ac.storage.personalBest or 0
    playerData.lives = ac.storage.lives or 3
    playerData.collisionCount = ac.storage.collisionCount or 0
    playerData.sessionStartTime = os.clock()
end

-- Game logic functions
local function detectLane(position)
    local laneWidth = 3.5
    local lane = math.floor((position.x + 50) / laneWidth)
    return math.max(1, math.min(8, lane))
end

local function calculateSpeedMultiplier(speed)
    local speedKmh = speed * 3.6
    if speedKmh < 30 then
        return 0.1
    elseif speedKmh < 60 then
        return 0.5
    elseif speedKmh < 80 then
        return 0.8
    elseif speedKmh < 120 then
        return 1.0 + (speedKmh - 80) / 40 * 0.5
    else
        return 1.5 - (speedKmh - 120) / 50 * 0.3
    end
end

local function calculateProximityMultiplier()
    local car = ac.getCar(0)
    if not car then return 1.0 end
    
    local playerPos = car.position
    local closestDistance = math.huge
    local nearbyCount = 0
    local sim = ac.getSim()
    
    for i = 1, sim.carsCount - 1 do
        local otherCar = ac.getCar(i)
        if otherCar and otherCar.isConnected then
            local distance = playerPos:distance(otherCar.position)
            if distance < 50 then
                nearbyCount = nearbyCount + 1
                closestDistance = math.min(closestDistance, distance)
            end
        end
    end
    
    if nearbyCount == 0 then return 1.0 end
    
    local proximityBonus = 1.0
    if closestDistance > 5 and closestDistance < 20 then
        proximityBonus = 1.0 + (20 - closestDistance) / 15 * 0.8
    elseif closestDistance <= 5 then
        proximityBonus = 0.5
    end
    
    return proximityBonus * (1.0 + nearbyCount * 0.1)
end

local function detectNearMiss()
    local car = ac.getCar(0)
    if not car then return false end
    
    local playerPos = car.position
    local playerVel = car.velocity
    local sim = ac.getSim()
    
    for i = 1, sim.carsCount - 1 do
        local otherCar = ac.getCar(i)
        if otherCar and otherCar.isConnected then
            local distance = playerPos:distance(otherCar.position)
            local relativeVel = playerVel:distance(otherCar.velocity)
            
            if distance < 8 and distance > 3 and relativeVel > 5 then
                return true
            end
        end
    end
    
    return false
end

local function detectCollision()
    local car = ac.getCar(0)
    if not car then return false end
    
    local currentTime = os.clock()
    local timeSinceLastCollision = currentTime - playerData.lastCollisionTime
    
    local currentSpeed = car.speedKmh
    local speedDelta = math.abs(currentSpeed - playerData.lastSpeed)
    if speedDelta > 30 and timeSinceLastCollision > 2.0 then
        return true
    end
    
    return false
end

-- Popup system
local function showPopup(text, type)
    uiState.showPopup = true
    uiState.popupText = text
    uiState.popupType = type or "info"
    uiState.popupStartTime = os.clock()
end

-- Sound function
local function playSound(soundType)
    ac.log("Playing sound: " .. soundType)
end

-- Main update function
local function updateScore(dt)
    local car = ac.getCar(0)
    if not car or not car.isConnected then return end
    
    local currentTime = os.clock()
    local position = car.position
    local velocity = car.velocity
    local speed = velocity:length()
    
    -- Update multipliers
    playerData.speedMultiplier = calculateSpeedMultiplier(speed)
    playerData.proximityMultiplier = calculateProximityMultiplier()
    
    -- Lane diversity tracking
    local currentLane = detectLane(position)
    playerData.lanesUsed[currentLane] = true
    local uniqueLanes = 0
    for _ in pairs(playerData.lanesUsed) do
        uniqueLanes = uniqueLanes + 1
    end
    
    local laneBonus = uniqueLanes >= 3 and 1.2 or 1.0
    
    -- Near miss detection
    if detectNearMiss() then
        playerData.nearMissCount = playerData.nearMissCount + 1
        playerData.comboCount = playerData.comboCount + 1
        showPopup("NEAR MISS! +" .. math.floor(50 * playerData.comboMultiplier), "success")
    end
    
    -- Combo multiplier
    playerData.comboMultiplier = 1.0 + (playerData.comboCount * 0.1)
    
    -- Score calculation
    local baseScore = speed * 0.5
    local totalMultiplier = playerData.speedMultiplier * playerData.proximityMultiplier * 
                           playerData.comboMultiplier * laneBonus
    
    local scoreGain = baseScore * totalMultiplier * dt
    local oldScore = playerData.score
    playerData.score = playerData.score + scoreGain
    
    -- Animate score change
    if scoreGain > 0 and currentTime - playerData.lastScoreTime > 0.1 then
        uiState.scoreAnimation.active = true
        uiState.scoreAnimation.startTime = currentTime
        uiState.scoreAnimation.startValue = oldScore
        uiState.scoreAnimation.endValue = playerData.score
        playerData.lastScoreTime = currentTime
    end
    
    -- Check for new personal best
    if playerData.score > playerData.personalBest then
        playerData.personalBest = playerData.score
        uiState.pbAnimation.active = true
        uiState.pbAnimation.startTime = currentTime
        showPopup("NEW PERSONAL BEST!", "success")
        playSound("newRecord")
        savePlayerData()
    end
    
    -- Store current values for next frame
    playerData.lastSpeed = speed
end

-- Collision handler
local function handleCollision()
    local currentTime = os.clock()
    playerData.lastCollisionTime = currentTime
    playerData.collisionCount = playerData.collisionCount + 1
    playerData.comboCount = 0
    
    local penalty = 0
    local message = ""
    
    if playerData.lives == 3 then
        penalty = playerData.score * 0.05
        message = "COLLISION! -5% SCORE"
        playerData.lives = 2
    elseif playerData.lives == 2 then
        penalty = playerData.score * 0.15
        message = "COLLISION! -15% SCORE"
        playerData.lives = 1
    else
        penalty = playerData.score
        message = "COLLISION! SCORE RESET"
        playerData.lives = 3
        playerData.lanesUsed = {}
    end
    
    playerData.score = math.max(0, playerData.score - penalty)
    showPopup(message, "error")
    playSound("collision")
    savePlayerData()
end

-- Animation update
local function updateAnimations(dt)
    local currentTime = os.clock()
    
    -- Score animation
    if uiState.scoreAnimation.active then
        local elapsed = currentTime - uiState.scoreAnimation.startTime
        local progress = elapsed / uiState.scoreAnimation.duration
        
        if progress >= 1.0 then
            uiState.scoreAnimation.active = false
        end
    end
    
    -- PB animation
    if uiState.pbAnimation.active then
        local elapsed = currentTime - uiState.pbAnimation.startTime
        local progress = elapsed / uiState.pbAnimation.duration
        
        if progress >= 1.0 then
            uiState.pbAnimation.active = false
            uiState.pbAnimation.scale = 1.0
        else
            local easedProgress = easeInOutCubic(progress)
            uiState.pbAnimation.scale = 1.0 + math.sin(easedProgress * math.pi) * 0.3
        end
    end
    
    -- Popup timeout
    if uiState.showPopup then
        local elapsed = currentTime - uiState.popupStartTime
        if elapsed >= uiState.popupDuration then
            uiState.showPopup = false
        end
    end
end

-- Main CSP function
function script.windowMain(dt)
    if not initialized then
        return
    end
    
    frameCount = frameCount + 1
    
    -- Update game logic
    updateScore(dt)
    
    -- Check for collisions
    if detectCollision() then
        handleCollision()
    end
    
    -- Update animations
    updateAnimations(dt)
    
    -- Auto-save every 600 frames (10 seconds at 60fps)
    if frameCount % 600 == 0 then
        savePlayerData()
    end
    
    -- Draw main UI
    if not uiState.showMainUI then return end
    
    local currentTime = os.clock()
    local sessionTime = currentTime - playerData.sessionStartTime
    
    ui.setNextWindowPos(vec2(50, 50), ui.Cond.FirstUseEver)
    ui.setNextWindowSize(vec2(320, 220), ui.Cond.FirstUseEver)
    
    if ui.begin("Traffic Score") then
        -- Time display
        ui.text("Session: " .. formatTime(sessionTime))
        ui.separator()
        
        -- Score display
        local scoreText = formatScore(playerData.score)
        ui.textColored(colors.textDim, "SCORE")
        ui.textColored(colors.accent, scoreText)
        
        -- Personal Best
        local pbText = "PB: " .. formatScore(playerData.personalBest)
        if uiState.pbAnimation.active then
            ui.textColored(colors.success, pbText)
        else
            ui.textColored(colors.textDim, pbText)
        end
        
        ui.separator()
        
        -- Lives display
        local livesText = "LIVES: "
        for i = 1, 3 do
            livesText = livesText .. (i <= playerData.lives and "♥" or "♡")
        end
        ui.textColored(playerData.lives > 1 and colors.success or colors.error, livesText)
        
        ui.separator()
        
        -- Multipliers
        ui.text("Speed: " .. string.format("%.1fx", playerData.speedMultiplier))
        ui.sameLine()
        ui.text("Proximity: " .. string.format("%.1fx", playerData.proximityMultiplier))
        
        ui.text("Combo: " .. string.format("%.1fx", playerData.comboMultiplier))
        ui.sameLine()
        local laneCount = 0
        for _ in pairs(playerData.lanesUsed) do laneCount = laneCount + 1 end
        ui.text("Lanes: " .. laneCount)
        
    end
    ui.endWindow()
    
    -- Draw popup
    if uiState.showPopup then
        local currentTime = os.clock()
        local elapsed = currentTime - uiState.popupStartTime
        local progress = elapsed / uiState.popupDuration
        
        local alpha = 1.0 - easeInOutCubic(progress)
        
        local popupColor = colors.text
        if uiState.popupType == "success" then
            popupColor = colors.success
        elseif uiState.popupType == "warning" then
            popupColor = colors.warning
        elseif uiState.popupType == "error" then
            popupColor = colors.error
        end
        
        ui.setNextWindowPos(vec2(200, 100), ui.Cond.Always)
        ui.setNextWindowSize(vec2(200, 50), ui.Cond.Always)
        
        if ui.begin("##Popup", false, bit.bor(ui.WindowFlags.NoTitleBar, ui.WindowFlags.NoResize, ui.WindowFlags.NoMove)) then
            ui.textColored(rgbm(popupColor.r, popupColor.g, popupColor.b, alpha), uiState.popupText)
        end
        ui.endWindow()
    end
end

-- Initialize script
function script.load()
    ac.log("Traffic Server Script Loading...")
    
    loadPlayerData()
    initialized = true
    showPopup("Welcome to Traffic Server!", "info")
    
    ac.log("Traffic Server Script Loaded Successfully!")
end

function script.unload()
    if initialized then
        savePlayerData()
        ac.log("Traffic Server Script Unloaded - Data Saved")
    end
end

-- Auto-initialize
script.load()

-- Assetto Corsa Traffic Server Script - CSP Compatible
-- Version 2.0.0 - Completely rewritten for proper CSP Lua API
-- Production-ready server-side script with No Hesi-style functionality

-- Global state
local initialized = false
local playerData = {
    score = 0,
    personalBest = 0,
    lives = 3,
    lastCollisionTime = 0,
    speedMultiplier = 1.0,
    proximityMultiplier = 1.0,
    comboMultiplier = 1.0,
    comboCount = 0,
    lastPosition = vec3(0, 0, 0),
    lastSpeed = 0,
    lanesUsed = {},
    nearMissCount = 0,
    collisionCount = 0,
    sessionStartTime = 0,
    lastScoreTime = 0
}

local uiState = {
    showMainUI = true,
    showPopup = false,
    popupText = "",
    popupType = "info",
    popupStartTime = 0,
    popupDuration = 3.0,
    windowPos = vec2(50, 50),
    windowSize = vec2(320, 200),
    scoreChangeAnimation = {
        active = false,
        startTime = 0,
        duration = 1.0,
        startValue = 0,
        endValue = 0,
        currentValue = 0
    },
    newPBAnimation = {
        active = false,
        startTime = 0,
        duration = 2.0,
        scale = 1.0,
        alpha = 1.0
    }
}

-- Storage system using ac.storage
local storage = ac.storage

-- Colors
local colors = {
    background = rgbm(0.1, 0.1, 0.1, 0.95),
    backgroundDark = rgbm(0.05, 0.05, 0.05, 0.98),
    primary = rgbm(0.6, 0.4, 1.0, 1.0),
    secondary = rgbm(0.8, 0.8, 0.8, 1.0),
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
    local str = string.format("%.0f", math.floor(score))
    local formatted = ""
    local len = string.len(str)
    for i = 1, len do
        formatted = formatted .. string.sub(str, i, i)
        if (len - i) % 3 == 0 and i ~= len then
            formatted = formatted .. ","
        end
    end
    return formatted
end

-- Storage functions
local function savePlayerData()
    storage:setNumber("traffic_score", playerData.score)
    storage:setNumber("traffic_pb", playerData.personalBest)
    storage:setNumber("traffic_lives", playerData.lives)
    storage:setNumber("traffic_collision_count", playerData.collisionCount)
end

local function loadPlayerData()
    playerData.score = storage:getNumber("traffic_score", 0)
    playerData.personalBest = storage:getNumber("traffic_pb", 0)
    playerData.lives = storage:getNumber("traffic_lives", 3)
    playerData.collisionCount = storage:getNumber("traffic_collision_count", 0)
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
    
    for i = 1, ac.getSim().carsCount - 1 do
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
    
    for i = 1, ac.getSim().carsCount - 1 do
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

-- Score update function
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
        uiState.scoreChangeAnimation.active = true
        uiState.scoreChangeAnimation.startTime = currentTime
        uiState.scoreChangeAnimation.startValue = oldScore
        uiState.scoreChangeAnimation.endValue = playerData.score
        playerData.lastScoreTime = currentTime
    end
    
    -- Check for new personal best
    if playerData.score > playerData.personalBest then
        playerData.personalBest = playerData.score
        uiState.newPBAnimation.active = true
        uiState.newPBAnimation.startTime = currentTime
        showPopup("NEW PERSONAL BEST!", "success")
        playSound("newRecord")
        savePlayerData()
    end
    
    -- Store current values for next frame
    playerData.lastPosition = position
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

-- Animation update function
local function updateAnimations(dt)
    local currentTime = os.clock()
    
    -- Score change animation
    if uiState.scoreChangeAnimation.active then
        local elapsed = currentTime - uiState.scoreChangeAnimation.startTime
        local progress = elapsed / uiState.scoreChangeAnimation.duration
        
        if progress >= 1.0 then
            uiState.scoreChangeAnimation.active = false
        else
            local easedProgress = easeOutQuart(progress)
            uiState.scoreChangeAnimation.currentValue = lerp(
                uiState.scoreChangeAnimation.startValue,
                uiState.scoreChangeAnimation.endValue,
                easedProgress
            )
        end
    end
    
    -- New PB animation
    if uiState.newPBAnimation.active then
        local elapsed = currentTime - uiState.newPBAnimation.startTime
        local progress = elapsed / uiState.newPBAnimation.duration
        
        if progress >= 1.0 then
            uiState.newPBAnimation.active = false
            uiState.newPBAnimation.scale = 1.0
            uiState.newPBAnimation.alpha = 1.0
        else
            local easedProgress = easeInOutCubic(progress)
            uiState.newPBAnimation.scale = 1.0 + math.sin(easedProgress * math.pi) * 0.3
            uiState.newPBAnimation.alpha = 1.0 - easedProgress * 0.3
        end
    end
    
    -- Popup animation
    if uiState.showPopup then
        local elapsed = currentTime - uiState.popupStartTime
        if elapsed >= uiState.popupDuration then
            uiState.showPopup = false
        end
    end
end

-- UI drawing functions
local function drawMultiplierBar(label, value, maxValue, color, pos, size)
    local fillWidth = (value / maxValue) * size.x
    
    -- Background
    ui.drawRectFilled(pos, pos + size, colors.backgroundDark, 3)
    
    -- Fill
    if fillWidth > 0 then
        ui.drawRectFilled(pos, vec2(pos.x + fillWidth, pos.y + size.y), color, 3)
    end
    
    -- Border
    ui.drawRect(pos, pos + size, colors.secondary, 3, 1)
    
    -- Text
    ui.setCursor(vec2(pos.x + 5, pos.y + size.y / 2 - 6))
    ui.text(label)
    
    local valueText = string.format("%.1fx", value)
    ui.setCursor(vec2(pos.x + size.x - 35, pos.y + size.y / 2 - 6))
    ui.text(valueText)
end

-- Main script functions for CSP
function script.windowMain(dt)
    if not initialized then
        return
    end
    
    -- Update game logic
    updateScore(dt)
    
    -- Check for collisions
    if detectCollision() then
        handleCollision()
    end
    
    -- Update animations
    updateAnimations(dt)
    
    -- Auto-save periodically
    if math.floor(os.clock()) % 10 == 0 then
        savePlayerData()
    end
    
    -- Draw main UI
    if not uiState.showMainUI then return end
    
    local currentTime = os.clock()
    local sessionTime = currentTime - playerData.sessionStartTime
    
    ui.setNextWindowPos(uiState.windowPos, ui.Cond.FirstUseEver)
    ui.setNextWindowSize(uiState.windowSize, ui.Cond.FirstUseEver)
    
    if ui.begin("Traffic Score", true, ui.WindowFlags.NoCollapse) then
        uiState.windowPos = ui.getWindowPos()
        uiState.windowSize = ui.getWindowSize()
        
        -- Time display
        ui.text("Session: " .. formatTime(sessionTime))
        ui.separator()
        
        -- Score display
        local scoreText = formatScore(playerData.score)
        if uiState.scoreChangeAnimation.active then
            scoreText = formatScore(uiState.scoreChangeAnimation.currentValue)
        end
        
        ui.textColored(colors.textDim, "SCORE")
        ui.pushFont(ui.Font.Title)
        ui.textColored(colors.accent, scoreText)
        ui.popFont()
        
        -- Personal Best
        local pbText = "PB: " .. formatScore(playerData.personalBest)
        if uiState.newPBAnimation.active then
            ui.pushFont(ui.Font.Title)
            local scaledColor = rgbm(colors.success.rgb, colors.success.a * uiState.newPBAnimation.alpha)
            ui.textColored(scaledColor, pbText)
            ui.popFont()
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
        
        ui.end()
    end
    
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
        
        ui.setNextWindowPos(vec2(uiState.windowPos.x + uiState.windowSize.x / 2 - 100, 
                                uiState.windowPos.y + uiState.windowSize.y / 2 - 25), ui.Cond.Always)
        ui.setNextWindowSize(vec2(200, 50), ui.Cond.Always)
        
        ui.pushStyleColor(ui.Col.WindowBg, rgbm(colors.backgroundDark.rgb, alpha))
        if ui.begin("Popup", false, ui.WindowFlags.NoTitleBar + ui.WindowFlags.NoResize + ui.WindowFlags.NoMove) then
            local scaledColor = rgbm(popupColor.rgb, alpha)
            ui.textColored(scaledColor, uiState.popupText)
            ui.end()
        end
        ui.popStyleColor()
    end
end

-- Initialize script
function script.load()
    ac.log("Traffic Server Script Loading...")
    
    loadPlayerData()
    uiState.windowPos = vec2(50, 50)
    uiState.windowSize = vec2(320, 200)
    
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
if not initialized then
    script.load()
end

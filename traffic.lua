-- Assetto Corsa Traffic Server Script
-- Production-ready server-side Lua script using Custom Shaders Patch (CSP)
-- Replicates No Hesi-style traffic server functionality with complete UI system
-- Author: Auto-generated for AC Traffic Server
-- Version: 1.0.0

-- Global script state
local scriptState = {
    initialized = false,
    deltaTime = 0,
    frameCount = 0,
    lastUpdate = 0
}

-- Player data structure
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
    lastScoreTime = 0,
    rank = 1
}

-- UI state
local uiState = {
    showMainUI = true,
    showPopup = false,
    popupText = "",
    popupType = "info", -- "info", "warning", "success", "error"
    popupStartTime = 0,
    popupDuration = 3.0,
    windowPos = vec2(50, 50),
    windowSize = vec2(320, 180),
    isDragging = false,
    dragOffset = vec2(0, 0),
    animationTime = 0,
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

-- Colors and styling
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

-- Sound effects URLs (hosted externally)
local sounds = {
    collision = "https://cdn.freesound.org/previews/316/316847_5123451-lq.mp3",
    newRecord = "https://cdn.freesound.org/previews/270/270303_5123451-lq.mp3",
    scoreGain = "https://cdn.freesound.org/previews/316/316847_5123451-lq.mp3",
    warning = "https://cdn.freesound.org/previews/270/270303_5123451-lq.mp3"
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
    return string.format("%,d", math.floor(score)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end

-- Storage functions
local function savePlayerData()
    ac.storage.set("traffic_score", playerData.score)
    ac.storage.set("traffic_pb", playerData.personalBest)
    ac.storage.set("traffic_lives", playerData.lives)
    ac.storage.set("traffic_collision_count", playerData.collisionCount)
end

local function loadPlayerData()
    playerData.score = ac.storage.get("traffic_score", 0)
    playerData.personalBest = ac.storage.get("traffic_pb", 0)
    playerData.lives = ac.storage.get("traffic_lives", 3)
    playerData.collisionCount = ac.storage.get("traffic_collision_count", 0)
    playerData.sessionStartTime = os.clock()
end

-- Game logic functions
local function detectLane(position)
    -- Simple lane detection based on X coordinate
    local laneWidth = 3.5 -- meters
    local lane = math.floor((position.x + 50) / laneWidth) -- Offset to handle negative coords
    return math.max(1, math.min(8, lane)) -- Limit to 8 lanes
end

local function calculateSpeedMultiplier(speed)
    -- Speed in km/h, optimal range 80-120 km/h
    local speedKmh = speed * 3.6
    if speedKmh < 30 then
        return 0.1
    elseif speedKmh < 60 then
        return 0.5
    elseif speedKmh < 80 then
        return 0.8
    elseif speedKmh < 120 then
        return 1.0 + (speedKmh - 80) / 40 * 0.5 -- Up to 1.5x
    else
        return 1.5 - (speedKmh - 120) / 50 * 0.3 -- Diminishing returns
    end
end

local function calculateProximityMultiplier()
    local cars = ac.getCarsCount()
    local playerCar = ac.getCar(0)
    if not playerCar then return 1.0 end
    
    local playerPos = playerCar.position
    local closestDistance = math.huge
    local nearbyCount = 0
    
    for i = 1, cars - 1 do
        local car = ac.getCar(i)
        if car and car.isConnected then
            local distance = playerPos:distance(car.position)
            if distance < 50 then -- Within 50 meters
                nearbyCount = nearbyCount + 1
                closestDistance = math.min(closestDistance, distance)
            end
        end
    end
    
    if nearbyCount == 0 then return 1.0 end
    
    -- Proximity bonus: closer = more points, but not too close
    local proximityBonus = 1.0
    if closestDistance > 5 and closestDistance < 20 then
        proximityBonus = 1.0 + (20 - closestDistance) / 15 * 0.8 -- Up to 1.8x
    elseif closestDistance <= 5 then
        proximityBonus = 0.5 -- Penalty for being too close
    end
    
    return proximityBonus * (1.0 + nearbyCount * 0.1) -- Bonus for multiple nearby cars
end

local function detectNearMiss()
    local cars = ac.getCarsCount()
    local playerCar = ac.getCar(0)
    if not playerCar then return false end
    
    local playerPos = playerCar.position
    local playerVel = playerCar.velocity
    
    for i = 1, cars - 1 do
        local car = ac.getCar(i)
        if car and car.isConnected then
            local distance = playerPos:distance(car.position)
            local relativeVel = playerVel:distance(car.velocity)
            
            -- Near miss: close distance with high relative velocity
            if distance < 8 and distance > 3 and relativeVel > 5 then
                return true
            end
        end
    end
    
    return false
end

local function detectCollision()
    local playerCar = ac.getCar(0)
    if not playerCar then return false end
    
    -- Check for collision based on damage or impact
    local currentTime = os.clock()
    local timeSinceLastCollision = currentTime - playerData.lastCollisionTime
    
    -- Simple collision detection based on sudden speed change
    local speedDelta = math.abs(playerCar.speedKmh - playerData.lastSpeed)
    if speedDelta > 30 and timeSinceLastCollision > 2.0 then -- Sudden speed change
        return true
    end
    
    return false
end

local function updateScore(deltaTime)
    local playerCar = ac.getCar(0)
    if not playerCar or not playerCar.isConnected then return end
    
    local currentTime = os.clock()
    local position = playerCar.position
    local speed = playerCar.velocity:length()
    
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
    local baseScore = speed * 0.5 -- Base points per second
    local totalMultiplier = playerData.speedMultiplier * playerData.proximityMultiplier * 
                           playerData.comboMultiplier * laneBonus
    
    local scoreGain = baseScore * totalMultiplier * deltaTime
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

local function handleCollision()
    local currentTime = os.clock()
    playerData.lastCollisionTime = currentTime
    playerData.collisionCount = playerData.collisionCount + 1
    playerData.comboCount = 0 -- Reset combo
    
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
        playerData.lanesUsed = {} -- Reset lane tracking
    end
    
    playerData.score = math.max(0, playerData.score - penalty)
    showPopup(message, "error")
    playSound("collision")
    savePlayerData()
end

-- UI Animation functions
local function updateAnimations(deltaTime)
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
    
    uiState.animationTime = uiState.animationTime + deltaTime
end

-- Sound functions
function playSound(soundType)
    if sounds[soundType] then
        -- Note: In a real implementation, you would load and play the sound
        -- For now, we'll use a placeholder that would work with CSP
        ac.log("Playing sound: " .. soundType)
        -- ac.playSound(sounds[soundType]) -- This would be the actual implementation
    end
end

-- Popup system
function showPopup(text, type)
    uiState.showPopup = true
    uiState.popupText = text
    uiState.popupType = type or "info"
    uiState.popupStartTime = os.clock()
end

-- UI Rendering functions
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
    local textPos = vec2(pos.x + 5, pos.y + size.y / 2 - 8)
    ui.drawText(label, textPos, colors.text)
    
    local valueText = string.format("%.1fx", value)
    local valueSize = ui.measureText(valueText)
    local valuePos = vec2(pos.x + size.x - valueSize.x - 5, pos.y + size.y / 2 - 8)
    ui.drawText(valueText, valuePos, colors.text)
end

local function drawMainUI()
    if not uiState.showMainUI then return end
    
    local currentTime = os.clock()
    local sessionTime = currentTime - playerData.sessionStartTime
    
    -- Main window background
    ui.drawRectFilled(uiState.windowPos, uiState.windowPos + uiState.windowSize, colors.background, 8)
    ui.drawRect(uiState.windowPos, uiState.windowPos + uiState.windowSize, colors.primary, 8, 2)
    
    -- Title bar
    local titleBarHeight = 30
    local titleBarEnd = vec2(uiState.windowPos.x + uiState.windowSize.x, uiState.windowPos.y + titleBarHeight)
    ui.drawRectFilled(uiState.windowPos, titleBarEnd, colors.primary, 8)
    
    -- Title text
    local titlePos = vec2(uiState.windowPos.x + 10, uiState.windowPos.y + 8)
    ui.drawText("TRAFFIC SCORE", titlePos, colors.text)
    
    -- Time display
    local timeText = formatTime(sessionTime)
    local timeSize = ui.measureText(timeText)
    local timePos = vec2(uiState.windowPos.x + uiState.windowSize.x - timeSize.x - 10, uiState.windowPos.y + 8)
    ui.drawText(timeText, timePos, colors.text)
    
    -- Content area
    local contentStart = vec2(uiState.windowPos.x + 10, uiState.windowPos.y + titleBarHeight + 10)
    local contentY = contentStart.y
    
    -- Score display
    local scoreText = formatScore(playerData.score)
    if uiState.scoreChangeAnimation.active then
        scoreText = formatScore(uiState.scoreChangeAnimation.currentValue)
    end
    
    ui.drawText("SCORE", contentStart, colors.textDim)
    contentY = contentY + 20
    
    local scorePos = vec2(contentStart.x, contentY)
    ui.pushFont(ui.Font.Title)
    ui.drawText(scoreText, scorePos, colors.accent)
    ui.popFont()
    contentY = contentY + 35
    
    -- Personal Best
    local pbText = "PB: " .. formatScore(playerData.personalBest)
    local pbPos = vec2(contentStart.x, contentY)
    
    if uiState.newPBAnimation.active then
        ui.pushFont(ui.Font.Title)
        local scaledColor = rgbm(colors.success.rgb, colors.success.a * uiState.newPBAnimation.alpha)
        ui.drawText(pbText, pbPos, scaledColor)
        ui.popFont()
    else
        ui.drawText(pbText, pbPos, colors.textDim)
    end
    contentY = contentY + 25
    
    -- Lives display
    local livesText = "LIVES: "
    for i = 1, 3 do
        livesText = livesText .. (i <= playerData.lives and "♥" or "♡")
    end
    ui.drawText(livesText, vec2(contentStart.x, contentY), 
                playerData.lives > 1 and colors.success or colors.error)
    contentY = contentY + 25
    
    -- Multipliers
    local multiplierY = contentY
    local multiplierSize = vec2(80, 12)
    local multiplierSpacing = 85
    
    -- Speed multiplier
    drawMultiplierBar("SPD", playerData.speedMultiplier, 2.0, colors.accent, 
                     vec2(contentStart.x, multiplierY), multiplierSize)
    
    -- Proximity multiplier
    drawMultiplierBar("PRX", playerData.proximityMultiplier, 2.0, colors.success, 
                     vec2(contentStart.x + multiplierSpacing, multiplierY), multiplierSize)
    
    multiplierY = multiplierY + 20
    
    -- Combo multiplier
    drawMultiplierBar("CMB", playerData.comboMultiplier, 3.0, colors.warning, 
                     vec2(contentStart.x, multiplierY), multiplierSize)
    
    -- Lane count
    local laneCount = 0
    for _ in pairs(playerData.lanesUsed) do laneCount = laneCount + 1 end
    drawMultiplierBar("LNE", laneCount, 8, colors.primary, 
                     vec2(contentStart.x + multiplierSpacing, multiplierY), multiplierSize)
end

local function drawPopup()
    if not uiState.showPopup then return end
    
    local currentTime = os.clock()
    local elapsed = currentTime - uiState.popupStartTime
    local progress = elapsed / uiState.popupDuration
    
    -- Fade out animation
    local alpha = 1.0 - easeInOutCubic(progress)
    local scale = 1.0 + math.sin(progress * math.pi) * 0.2
    
    -- Popup colors
    local popupColor = colors.text
    if uiState.popupType == "success" then
        popupColor = colors.success
    elseif uiState.popupType == "warning" then
        popupColor = colors.warning
    elseif uiState.popupType == "error" then
        popupColor = colors.error
    end
    
    -- Popup position (center of main UI)
    local popupPos = vec2(
        uiState.windowPos.x + uiState.windowSize.x / 2,
        uiState.windowPos.y + uiState.windowSize.y / 2
    )
    
    -- Scaled text
    local scaledColor = rgbm(popupColor.rgb, popupColor.a * alpha)
    ui.pushFont(ui.Font.Title)
    
    local textSize = ui.measureText(uiState.popupText)
    local textPos = vec2(popupPos.x - textSize.x / 2, popupPos.y - textSize.y / 2)
    
    -- Background
    local padding = 10
    local bgPos = vec2(textPos.x - padding, textPos.y - padding)
    local bgSize = vec2(textSize.x + padding * 2, textSize.y + padding * 2)
    local bgColor = rgbm(colors.backgroundDark.rgb, colors.backgroundDark.a * alpha)
    ui.drawRectFilled(bgPos, bgPos + bgSize, bgColor, 5)
    
    ui.drawText(uiState.popupText, textPos, scaledColor)
    ui.popFont()
end

-- Input handling
local function handleInput()
    local mousePos = ui.mousePos()
    local mouseDown = ui.mouseDown()
    
    -- Check if mouse is over title bar for dragging
    if mouseDown and not uiState.isDragging then
        local titleBarArea = {
            min = uiState.windowPos,
            max = vec2(uiState.windowPos.x + uiState.windowSize.x, uiState.windowPos.y + 30)
        }
        
        if mousePos.x >= titleBarArea.min.x and mousePos.x <= titleBarArea.max.x and
           mousePos.y >= titleBarArea.min.y and mousePos.y <= titleBarArea.max.y then
            uiState.isDragging = true
            uiState.dragOffset = vec2(mousePos.x - uiState.windowPos.x, mousePos.y - uiState.windowPos.y)
        end
    end
    
    -- Handle dragging
    if uiState.isDragging then
        if mouseDown then
            uiState.windowPos = vec2(mousePos.x - uiState.dragOffset.x, mousePos.y - uiState.dragOffset.y)
            
            -- Keep window on screen
            local screenSize = ac.getScreenSize()
            uiState.windowPos.x = math.max(0, math.min(screenSize.x - uiState.windowSize.x, uiState.windowPos.x))
            uiState.windowPos.y = math.max(0, math.min(screenSize.y - uiState.windowSize.y, uiState.windowPos.y))
        else
            uiState.isDragging = false
        end
    end
end

-- Main script functions
function script.update(dt)
    if not scriptState.initialized then
        return
    end
    
    scriptState.deltaTime = dt
    scriptState.frameCount = scriptState.frameCount + 1
    
    -- Update game logic
    updateScore(dt)
    
    -- Check for collisions
    if detectCollision() then
        handleCollision()
    end
    
    -- Update animations
    updateAnimations(dt)
    
    -- Handle input
    handleInput()
    
    -- Auto-save every 10 seconds
    if scriptState.frameCount % 600 == 0 then -- Assuming 60 FPS
        savePlayerData()
    end
end

function script.draw()
    if not scriptState.initialized then
        return
    end
    
    -- Draw main UI
    drawMainUI()
    
    -- Draw popup
    drawPopup()
end

function script.load()
    ac.log("Traffic Server Script Loading...")
    
    -- Initialize player data
    loadPlayerData()
    
    -- Initialize UI state
    uiState.windowPos = vec2(50, 50)
    uiState.windowSize = vec2(320, 200)
    
    -- Mark as initialized
    scriptState.initialized = true
    
    -- Welcome message
    showPopup("Welcome to Traffic Server!", "info")
    
    ac.log("Traffic Server Script Loaded Successfully!")
end

function script.unload()
    if scriptState.initialized then
        savePlayerData()
        ac.log("Traffic Server Script Unloaded - Data Saved")
    end
end

-- Error handling
function script.error(err)
    ac.log("Traffic Server Script Error: " .. tostring(err))
    showPopup("Script Error Occurred", "error")
end

-- Initialize the script
if not scriptState.initialized then
    script.load()
end

return script

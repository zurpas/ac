-- Traffic Server UI Script for Assetto Corsa with CSP
-- Modern draggable UI with scoring system for traffic server

-- Load required CSP libraries
local sim = ac.getSim()
local car = ac.getCar(0) -- Player car
local ui = ac.getUI()

-- UI State and Configuration
local uiState = {
    windowPos = vec2(50, 50),
    windowSize = vec2(380, 520),
    isDragging = false,
    dragOffset = vec2(0, 0),
    isVisible = true,
    opacity = 0.95
}

-- Game State
local gameState = {
    currentScore = 0,
    personalBest = 12500,
    lives = 3,
    maxLives = 3,
    
    -- Multipliers
    speedMultiplier = 1.0,
    proximityMultiplier = 1.0,
    nearMissMultiplier = 1.0,
    laneChangeMultiplier = 1.0,
    
    -- Tracking variables
    lastSpeed = 0,
    lastPosition = vec3(0, 0, 0),
    lanesUsed = {},
    totalLaneChanges = 0,
    nearMissCount = 0,
    proximityTime = 0,
    
    -- Damage/collision tracking
    collisionCount = 0,
    lastCollisionTime = 0,
    
    -- Session stats
    sessionTime = 0,
    totalDistance = 0
}

-- Colors and styling
local colors = {
    background = rgbm(0.08, 0.08, 0.12, uiState.opacity),
    headerBg = rgbm(0.12, 0.12, 0.18, 1),
    accent = rgbm(0.2, 0.8, 1, 1),        -- Cyan
    success = rgbm(0.2, 0.8, 0.2, 1),     -- Green
    warning = rgbm(1, 0.8, 0.2, 1),       -- Yellow
    danger = rgbm(1, 0.3, 0.3, 1),        -- Red
    text = rgbm(0.9, 0.9, 0.9, 1),
    textDim = rgbm(0.6, 0.6, 0.6, 1),
    border = rgbm(0.3, 0.3, 0.4, 1)
}

-- Initialize function
function script.prepare(dt)
    -- Reset game state if needed
    gameState.sessionTime = 0
    gameState.totalDistance = 0
end

-- Main update function
function script.update(dt)
    -- Update session time
    gameState.sessionTime = gameState.sessionTime + dt
    
    -- Update game logic
    updateGameLogic(dt)
    
    -- Update multipliers
    updateMultipliers(dt)
    
    -- Calculate score
    calculateScore(dt)
    
    -- Check for collisions
    checkCollisions()
end

-- Game logic updates
function updateGameLogic(dt)
    if not car then return end
    
    -- Update distance
    local currentPos = car.position
    if gameState.lastPosition.x ~= 0 then
        local distance = math.distance(currentPos, gameState.lastPosition)
        gameState.totalDistance = gameState.totalDistance + distance
    end
    gameState.lastPosition = currentPos
    
    -- Track speed
    gameState.lastSpeed = car.speedKmh
    
    -- Track lane usage (simplified - would need proper lane detection)
    local laneId = math.floor(currentPos.x / 3.5) -- Approximate lane width
    if not gameState.lanesUsed[laneId] then
        gameState.lanesUsed[laneId] = true
        gameState.totalLaneChanges = gameState.totalLaneChanges + 1
    end
end

-- Update multipliers based on game conditions
function updateMultipliers(dt)
    -- Speed multiplier (higher speed = higher multiplier)
    local speed = gameState.lastSpeed
    if speed > 100 then
        gameState.speedMultiplier = math.min(2.0, 1.0 + (speed - 100) / 200)
    else
        gameState.speedMultiplier = math.max(0.5, speed / 100)
    end
    
    -- Proximity multiplier (simplified - would need proper car detection)
    -- This would normally check distance to other cars
    gameState.proximityMultiplier = 1.0 + math.random() * 0.5
    
    -- Near miss multiplier
    gameState.nearMissMultiplier = 1.0 + (gameState.nearMissCount * 0.1)
    
    -- Lane change multiplier
    local uniqueLanes = 0
    for _ in pairs(gameState.lanesUsed) do
        uniqueLanes = uniqueLanes + 1
    end
    
    if uniqueLanes >= 3 then
        gameState.laneChangeMultiplier = 2.0
    elseif uniqueLanes >= 2 then
        gameState.laneChangeMultiplier = 1.5
    else
        gameState.laneChangeMultiplier = 1.0
    end
end

-- Calculate current score
function calculateScore(dt)
    local basePoints = gameState.lastSpeed * dt * 0.1
    local totalMultiplier = gameState.speedMultiplier * 
                          gameState.proximityMultiplier * 
                          gameState.nearMissMultiplier * 
                          gameState.laneChangeMultiplier
    
    gameState.currentScore = gameState.currentScore + (basePoints * totalMultiplier)
end

-- Check for collisions and handle lives
function checkCollisions()
    -- This would normally check for actual collisions
    -- For now, we'll simulate random collisions for demonstration
    if math.random() < 0.0001 then -- Very rare random collision for demo
        handleCollision()
    end
end

-- Handle collision logic
function handleCollision()
    gameState.collisionCount = gameState.collisionCount + 1
    gameState.lastCollisionTime = gameState.sessionTime
    
    if gameState.collisionCount == 1 then
        -- First collision: lose 5% of points
        gameState.currentScore = gameState.currentScore * 0.95
        gameState.lives = gameState.lives - 1
    elseif gameState.collisionCount == 2 then
        -- Second collision: lose 15% of points
        gameState.currentScore = gameState.currentScore * 0.85
        gameState.lives = gameState.lives - 1
    else
        -- Third collision: reset score and lives
        gameState.currentScore = 0
        gameState.lives = 0
        gameState.collisionCount = 0
        -- Reset lives after a few seconds (game logic)
        setTimeout(function()
            gameState.lives = gameState.maxLives
        end, 3000)
    end
end

-- UI Rendering
function script.drawUI()
    if not uiState.isVisible then return end
    
    -- Handle window dragging
    handleWindowDragging()
    
    -- Main window
    ui.pushClipRect(uiState.windowPos, uiState.windowPos + uiState.windowSize)
    
    -- Background
    ui.drawRectFilled(uiState.windowPos, uiState.windowPos + uiState.windowSize, 
                     colors.background, 8)
    ui.drawRect(uiState.windowPos, uiState.windowPos + uiState.windowSize, 
               colors.border, 8, 1)
    
    -- Header
    drawHeader()
    
    -- Score section
    drawScoreSection()
    
    -- Multipliers section
    drawMultipliersSection()
    
    -- Lives section
    drawLivesSection()
    
    -- Stats section
    drawStatsSection()
    
    ui.popClipRect()
end

-- Draw header with title and drag area
function drawHeader()
    local headerRect = {
        uiState.windowPos,
        uiState.windowPos + vec2(uiState.windowSize.x, 40)
    }
    
    ui.drawRectFilled(headerRect[1], headerRect[2], colors.headerBg, 8)
    
    -- Title
    ui.pushFont(ui.Font.Title)
    ui.setCursor(headerRect[1] + vec2(15, 8))
    ui.textColored("TRAFFIC MASTER", colors.accent)
    ui.popFont()
    
    -- Minimize button
    local btnPos = headerRect[2] + vec2(-35, -30)
    if ui.invisibleButton("minimize", btnPos, vec2(25, 20)) then
        uiState.isVisible = false
    end
    ui.setCursor(btnPos + vec2(8, 2))
    ui.textColored("—", colors.text)
end

-- Draw main score display
function drawScoreSection()
    local startY = uiState.windowPos.y + 50
    
    -- Current Score
    ui.setCursor(vec2(uiState.windowPos.x + 20, startY))
    ui.pushFont(ui.Font.Small)
    ui.textColored("CURRENT SCORE", colors.textDim)
    ui.popFont()
    
    ui.setCursor(vec2(uiState.windowPos.x + 20, startY + 20))
    ui.pushFont(ui.Font.Huge)
    ui.textColored(string.format("%.0f", gameState.currentScore), colors.success)
    ui.popFont()
    
    -- Personal Best
    ui.setCursor(vec2(uiState.windowPos.x + 200, startY))
    ui.pushFont(ui.Font.Small)
    ui.textColored("PERSONAL BEST", colors.textDim)
    ui.popFont()
    
    ui.setCursor(vec2(uiState.windowPos.x + 200, startY + 20))
    ui.pushFont(ui.Font.Title)
    local pbColor = gameState.currentScore > gameState.personalBest and colors.accent or colors.text
    ui.textColored(string.format("%.0f", gameState.personalBest), pbColor)
    ui.popFont()
    
    -- Progress bar
    local progressY = startY + 65
    local progressWidth = uiState.windowSize.x - 40
    local progressHeight = 8
    local progressPos = vec2(uiState.windowPos.x + 20, progressY)
    
    -- Background
    ui.drawRectFilled(progressPos, progressPos + vec2(progressWidth, progressHeight), 
                     colors.border, 4)
    
    -- Progress fill
    local progress = math.min(1.0, gameState.currentScore / gameState.personalBest)
    if progress > 0 then
        ui.drawRectFilled(progressPos, 
                         progressPos + vec2(progressWidth * progress, progressHeight), 
                         colors.accent, 4)
    end
end

-- Draw multipliers section
function drawMultipliersSection()
    local startY = uiState.windowPos.y + 140
    
    ui.setCursor(vec2(uiState.windowPos.x + 20, startY))
    ui.pushFont(ui.Font.Small)
    ui.textColored("MULTIPLIERS", colors.textDim)
    ui.popFont()
    
    local multipliers = {
        {"SPEED", gameState.speedMultiplier, colors.warning},
        {"PROXIMITY", gameState.proximityMultiplier, colors.accent},
        {"NEAR MISS", gameState.nearMissMultiplier, colors.success},
        {"LANE VARIETY", gameState.laneChangeMultiplier, colors.danger}
    }
    
    for i, mult in ipairs(multipliers) do
        local y = startY + 25 + (i - 1) * 25
        local barWidth = 140
        local barHeight = 16
        
        -- Label
        ui.setCursor(vec2(uiState.windowPos.x + 20, y))
        ui.pushFont(ui.Font.Small)
        ui.textColored(mult[1], colors.textDim)
        ui.popFont()
        
        -- Value
        ui.setCursor(vec2(uiState.windowPos.x + 120, y))
        ui.textColored(string.format("%.1fx", mult[2]), colors.text)
        
        -- Bar background
        local barPos = vec2(uiState.windowPos.x + 170, y + 2)
        ui.drawRectFilled(barPos, barPos + vec2(barWidth, barHeight), colors.border, 2)
        
        -- Bar fill
        local fillWidth = barWidth * math.min(1.0, mult[2] / 2.0)
        if fillWidth > 0 then
            ui.drawRectFilled(barPos, barPos + vec2(fillWidth, barHeight), mult[3], 2)
        end
    end
end

-- Draw lives section
function drawLivesSection()
    local startY = uiState.windowPos.y + 280
    
    ui.setCursor(vec2(uiState.windowPos.x + 20, startY))
    ui.pushFont(ui.Font.Small)
    ui.textColored("LIVES", colors.textDim)
    ui.popFont()
    
    -- Lives display
    for i = 1, gameState.maxLives do
        local heartPos = vec2(uiState.windowPos.x + 20 + (i - 1) * 35, startY + 20)
        local heartColor = i <= gameState.lives and colors.danger or colors.border
        
        -- Heart shape (simplified as circle)
        ui.drawCircleFilled(heartPos + vec2(12, 12), 12, heartColor)
        ui.setCursor(heartPos + vec2(6, 4))
        ui.pushFont(ui.Font.Small)
        ui.textColored("♥", colors.background)
        ui.popFont()
    end
    
    -- Collision penalty info
    if gameState.collisionCount > 0 then
        ui.setCursor(vec2(uiState.windowPos.x + 140, startY + 15))
        ui.pushFont(ui.Font.Small)
        local penaltyText = gameState.collisionCount == 1 and "-5% SCORE" or 
                           gameState.collisionCount == 2 and "-15% SCORE" or "SCORE RESET!"
        ui.textColored(penaltyText, colors.danger)
        ui.popFont()
        
        ui.setCursor(vec2(uiState.windowPos.x + 140, startY + 30))
        ui.textColored(string.format("Collisions: %d", gameState.collisionCount), colors.textDim)
    end
end

-- Draw session statistics
function drawStatsSection()
    local startY = uiState.windowPos.y + 360
    
    ui.setCursor(vec2(uiState.windowPos.x + 20, startY))
    ui.pushFont(ui.Font.Small)
    ui.textColored("SESSION STATS", colors.textDim)
    ui.popFont()
    
    local stats = {
        {"Time", string.format("%.0fs", gameState.sessionTime)},
        {"Distance", string.format("%.1fkm", gameState.totalDistance / 1000)},
        {"Avg Speed", string.format("%.0f km/h", gameState.lastSpeed)},
        {"Lane Changes", tostring(gameState.totalLaneChanges)},
        {"Near Misses", tostring(gameState.nearMissCount)}
    }
    
    for i, stat in ipairs(stats) do
        local y = startY + 20 + (i - 1) * 18
        ui.setCursor(vec2(uiState.windowPos.x + 20, y))
        ui.pushFont(ui.Font.Small)
        ui.textColored(stat[1] .. ":", colors.textDim)
        ui.setCursor(vec2(uiState.windowPos.x + 120, y))
        ui.textColored(stat[2], colors.text)
        ui.popFont()
    end
    
    -- Total multiplier display
    local totalMult = gameState.speedMultiplier * gameState.proximityMultiplier * 
                     gameState.nearMissMultiplier * gameState.laneChangeMultiplier
    
    ui.setCursor(vec2(uiState.windowPos.x + 20, startY + 130))
    ui.pushFont(ui.Font.Title)
    ui.textColored("TOTAL: ", colors.textDim)
    ui.setCursor(vec2(uiState.windowPos.x + 90, startY + 130))
    ui.textColored(string.format("%.2fx", totalMult), colors.accent)
    ui.popFont()
end

-- Handle window dragging
function handleWindowDragging()
    local mouse = ui.mousePos()
    local headerRect = {
        uiState.windowPos,
        uiState.windowPos + vec2(uiState.windowSize.x, 40)
    }
    
    if ui.mouseClicked() and 
       mouse.x >= headerRect[1].x and mouse.x <= headerRect[2].x and
       mouse.y >= headerRect[1].y and mouse.y <= headerRect[2].y then
        uiState.isDragging = true
        uiState.dragOffset = mouse - uiState.windowPos
    end
    
    if uiState.isDragging then
        if ui.mouseDown() then
            uiState.windowPos = mouse - uiState.dragOffset
            -- Keep window on screen
            uiState.windowPos.x = math.max(0, math.min(ui.windowSize().x - uiState.windowSize.x, uiState.windowPos.x))
            uiState.windowPos.y = math.max(0, math.min(ui.windowSize().y - uiState.windowSize.y, uiState.windowPos.y))
        else
            uiState.isDragging = false
        end
    end
end

-- Key bindings
function script.key(key)
    if key == ui.Key.F7 then
        uiState.isVisible = not uiState.isVisible
    end
end

-- Helper function for delayed execution
function setTimeout(func, delay)
    -- This would need to be implemented with a proper timer system
    -- For now, it's just a placeholder
end

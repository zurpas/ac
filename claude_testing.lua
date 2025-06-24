-- Traffic Server Script for Assetto Corsa with CSP
-- Modern UI with moveable interface for traffic scoring system

-- Import required libraries
local ui = require('shared/ui')
local sim = ac.getSim()

-- Global variables for the traffic system
local trafficData = {
    personalBest = 0,
    currentScore = 0,
    lives = 3,
    maxLives = 3,
    
    -- Multipliers
    speedMultiplier = 1.0,
    proximityMultiplier = 1.0,
    nearMissMultiplier = 1.0,
    laneChangeMultiplier = 1.0,
    
    -- Tracking variables
    laneChanges = 0,
    uniqueLanesUsed = {},
    lastLaneChangeTime = 0,
    collisionCount = 0,
    
    -- UI State
    uiVisible = true,
    uiPosition = vec2(100, 100),
    uiSize = vec2(350, 450),
    isDragging = false,
    dragOffset = vec2(0, 0)
}

-- Color scheme for modern UI
local colors = {
    background = rgbm(0.08, 0.08, 0.12, 0.95),
    backgroundDark = rgbm(0.05, 0.05, 0.08, 0.98),
    accent = rgbm(0.2, 0.8, 0.9, 1),
    accentDark = rgbm(0.15, 0.6, 0.7, 1),
    success = rgbm(0.2, 0.8, 0.4, 1),
    warning = rgbm(1.0, 0.7, 0.2, 1),
    danger = rgbm(0.9, 0.3, 0.3, 1),
    text = rgbm(0.95, 0.95, 0.95, 1),
    textDim = rgbm(0.7, 0.7, 0.7, 1)
}

-- Initialize the script
function script.prepare(dt)
    -- Reset data when script loads
    trafficData.currentScore = 0
    trafficData.lives = trafficData.maxLives
    trafficData.collisionCount = 0
    trafficData.uniqueLanesUsed = {}
end

-- Main update function called every frame
function script.update(dt)
    updateTrafficLogic(dt)
    calculateMultipliers(dt)
    updateScore(dt)
end

-- Update traffic logic and detection
function updateTrafficLogic(dt)
    local car = ac.getCar(0) -- Player car
    if not car then return end
    
    -- Detect lane changes (simplified - you'd need proper lane detection)
    local currentLane = math.floor(car.position.x / 3.5) -- Rough lane calculation
    if trafficData.lastLane and trafficData.lastLane ~= currentLane then
        trafficData.laneChanges = trafficData.laneChanges + 1
        trafficData.uniqueLanesUsed[currentLane] = true
        trafficData.lastLaneChangeTime = sim.time
    end
    trafficData.lastLane = currentLane
    
    -- Check for collisions/contacts
    checkCollisions()
end

-- Calculate scoring multipliers
function calculateMultipliers(dt)
    local car = ac.getCar(0)
    if not car then return end
    
    -- Speed multiplier (higher speed = higher multiplier)
    local speedKmh = car.speedKmh
    trafficData.speedMultiplier = math.max(0.1, math.min(3.0, speedKmh / 100))
    
    -- Proximity multiplier (closer to other cars = higher multiplier)
    trafficData.proximityMultiplier = calculateProximityMultiplier()
    
    -- Near miss multiplier (recent close calls)
    trafficData.nearMissMultiplier = calculateNearMissMultiplier()
    
    -- Lane change multiplier (using 3+ lanes gives bonus)
    local uniqueLaneCount = 0
    for _ in pairs(trafficData.uniqueLanesUsed) do
        uniqueLaneCount = uniqueLaneCount + 1
    end
    trafficData.laneChangeMultiplier = uniqueLaneCount >= 3 and 2.0 or 1.0
end

-- Calculate proximity to other cars
function calculateProximityMultiplier()
    local minDistance = 999
    local playerCar = ac.getCar(0)
    if not playerCar then return 1.0 end
    
    for i = 1, sim.carsCount - 1 do
        local car = ac.getCar(i)
        if car then
            local distance = playerCar.position:distance(car.position)
            minDistance = math.min(minDistance, distance)
        end
    end
    
    -- Closer cars give higher multiplier
    if minDistance < 5 then return 2.5
    elseif minDistance < 10 then return 2.0
    elseif minDistance < 20 then return 1.5
    else return 1.0 end
end

-- Calculate near miss multiplier
function calculateNearMissMultiplier()
    -- This would need proper collision detection implementation
    return 1.0 -- Placeholder
end

-- Update the current score
function updateScore(dt)
    if trafficData.lives <= 0 then return end
    
    local basePoints = 10 * dt -- Base points per second
    local totalMultiplier = trafficData.speedMultiplier * 
                           trafficData.proximityMultiplier * 
                           trafficData.nearMissMultiplier * 
                           trafficData.laneChangeMultiplier
    
    trafficData.currentScore = trafficData.currentScore + (basePoints * totalMultiplier)
    
    -- Update personal best
    if trafficData.currentScore > trafficData.personalBest then
        trafficData.personalBest = trafficData.currentScore
    end
end

-- Check for collisions and handle life system
function checkCollisions()
    -- This would need proper collision detection
    -- For now, this is a placeholder
    local collision = false -- You'd implement actual collision detection here
    
    if collision then
        trafficData.collisionCount = trafficData.collisionCount + 1
        
        if trafficData.collisionCount == 1 then
            -- First collision: lose 5% of points
            trafficData.currentScore = trafficData.currentScore * 0.95
            trafficData.lives = trafficData.lives - 1
        elseif trafficData.collisionCount == 2 then
            -- Second collision: lose 15% of points
            trafficData.currentScore = trafficData.currentScore * 0.85
            trafficData.lives = trafficData.lives - 1
        elseif trafficData.collisionCount >= 3 then
            -- Third collision: reset score and lives
            trafficData.currentScore = 0
            trafficData.lives = 0
            trafficData.collisionCount = 0
        end
    end
end

-- Main UI rendering function
function script.drawUI()
    if not trafficData.uiVisible then return end
    
    -- Handle window dragging
    handleWindowDragging()
    
    -- Set window properties
    ui.pushStyleVar(ui.StyleVar.WindowRounding, 12)
    ui.pushStyleVar(ui.StyleVar.WindowPadding, vec2(16, 16))
    ui.pushStyleColor(ui.Col.WindowBg, colors.backgroundDark)
    ui.pushStyleColor(ui.Col.TitleBg, colors.accent)
    ui.pushStyleColor(ui.Col.TitleBgActive, colors.accentDark)
    
    -- Create the main window
    ui.setNextWindowPos(trafficData.uiPosition, ui.Cond.FirstUseEver)
    ui.setNextWindowSize(trafficData.uiSize, ui.Cond.FirstUseEver)
    
    if ui.begin('Traffic Server##TrafficUI', true, ui.WindowFlags.NoCollapse) then
        trafficData.uiPosition = ui.getWindowPos()
        trafficData.uiSize = ui.getWindowSize()
        
        drawMainInterface()
    end
    ui.endWindow()
    
    -- Pop styles
    ui.popStyleColor(3)
    ui.popStyleVar(2)
end

-- Handle window dragging functionality
function handleWindowDragging()
    local mousePos = ui.mousePos()
    local isMouseDown = ui.isMouseDown(ui.MouseButton.Left)
    
    if ui.isWindowHovered() and isMouseDown and not trafficData.isDragging then
        trafficData.isDragging = true
        trafficData.dragOffset = mousePos - trafficData.uiPosition
    elseif not isMouseDown then
        trafficData.isDragging = false
    end
    
    if trafficData.isDragging then
        trafficData.uiPosition = mousePos - trafficData.dragOffset
    end
end

-- Draw the main interface elements
function drawMainInterface()
    -- Header with title
    ui.pushFont(ui.Font.Title)
    ui.pushStyleColor(ui.Col.Text, colors.accent)
    ui.text("🏁 TRAFFIC MASTER")
    ui.popStyleColor()
    ui.popFont()
    
    ui.separator()
    ui.spacing()
    
    -- Score Section
    drawScoreSection()
    
    ui.spacing()
    ui.separator()
    ui.spacing()
    
    -- Lives Section
    drawLivesSection()
    
    ui.spacing()
    ui.separator()
    ui.spacing()
    
    -- Multipliers Section
    drawMultipliersSection()
    
    ui.spacing()
    ui.separator()
    ui.spacing()
    
    -- Statistics Section
    drawStatisticsSection()
    
    ui.spacing()
    
    -- Control buttons
    drawControlButtons()
end

-- Draw score information
function drawScoreSection()
    ui.pushFont(ui.Font.Small)
    ui.pushStyleColor(ui.Col.Text, colors.textDim)
    ui.text("SCORES")
    ui.popStyleColor()
    ui.popFont()
    
    -- Current Score
    ui.pushFont(ui.Font.Large)
    ui.pushStyleColor(ui.Col.Text, colors.success)
    ui.text(string.format("Current: %.0f", trafficData.currentScore))
    ui.popStyleColor()
    ui.popFont()
    
    -- Personal Best
    ui.pushStyleColor(ui.Col.Text, colors.warning)
    ui.text(string.format("Personal Best: %.0f", trafficData.personalBest))
    ui.popStyleColor()
end

-- Draw lives display
function drawLivesSection()
    ui.pushFont(ui.Font.Small)
    ui.pushStyleColor(ui.Col.Text, colors.textDim)
    ui.text("LIVES")
    ui.popStyleColor()
    ui.popFont()
    
    -- Lives display with hearts
    local heartColor = trafficData.lives > 0 and colors.danger or colors.textDim
    ui.pushStyleColor(ui.Col.Text, heartColor)
    
    local heartsText = ""
    for i = 1, trafficData.maxLives do
        if i <= trafficData.lives then
            heartsText = heartsText .. "♥ "
        else
            heartsText = heartsText .. "♡ "
        end
    end
    
    ui.pushFont(ui.Font.Large)
    ui.text(heartsText)
    ui.popFont()
    ui.popStyleColor()
    
    -- Collision penalties info
    ui.pushFont(ui.Font.Small)
    ui.pushStyleColor(ui.Col.Text, colors.textDim)
    ui.text("1st hit: -5% | 2nd hit: -15% | 3rd hit: Reset")
    ui.popStyleColor()
    ui.popFont()
end

-- Draw multipliers section
function drawMultipliersSection()
    ui.pushFont(ui.Font.Small)
    ui.pushStyleColor(ui.Col.Text, colors.textDim)
    ui.text("MULTIPLIERS")
    ui.popStyleColor()
    ui.popFont()
    
    local multipliers = {
        {"Speed", trafficData.speedMultiplier},
        {"Proximity", trafficData.proximityMultiplier},
        {"Near Miss", trafficData.nearMissMultiplier},
        {"Lane Usage", trafficData.laneChangeMultiplier}
    }
    
    for _, mult in ipairs(multipliers) do
        local color = mult[2] > 1.5 and colors.success or 
                     mult[2] > 1.0 and colors.warning or colors.textDim
        
        ui.pushStyleColor(ui.Col.Text, color)
        ui.text(string.format("%s: %.2fx", mult[1], mult[2]))
        ui.popStyleColor()
    end
    
    -- Total multiplier
    local totalMult = trafficData.speedMultiplier * trafficData.proximityMultiplier * 
                     trafficData.nearMissMultiplier * trafficData.laneChangeMultiplier
    
    ui.spacing()
    ui.pushStyleColor(ui.Col.Text, colors.accent)
    ui.pushFont(ui.Font.Main)
    ui.text(string.format("Total: %.2fx", totalMult))
    ui.popFont()
    ui.popStyleColor()
end

-- Draw statistics section
function drawStatisticsSection()
    ui.pushFont(ui.Font.Small)
    ui.pushStyleColor(ui.Col.Text, colors.textDim)
    ui.text("STATISTICS")
    ui.popStyleColor()
    ui.popFont()
    
    local uniqueLaneCount = 0
    for _ in pairs(trafficData.uniqueLanesUsed) do
        uniqueLaneCount = uniqueLaneCount + 1
    end
    
    ui.text(string.format("Lane Changes: %d", trafficData.laneChanges))
    ui.text(string.format("Unique Lanes: %d", uniqueLaneCount))
    ui.text(string.format("Collisions: %d", trafficData.collisionCount))
    
    if uniqueLaneCount >= 3 then
        ui.pushStyleColor(ui.Col.Text, colors.success)
        ui.text("🎉 Lane Master Bonus Active!")
        ui.popStyleColor()
    end
end

-- Draw control buttons
function drawControlButtons()
    -- Reset button
    ui.pushStyleColor(ui.Col.Button, colors.danger)
    ui.pushStyleColor(ui.Col.ButtonHovered, rgbm(0.7, 0.2, 0.2, 1))
    if ui.button("Reset Score##ResetBtn", vec2(-1, 30)) then
        resetGame()
    end
    ui.popStyleColor(2)
    
    -- Toggle visibility button
    ui.pushStyleColor(ui.Col.Button, colors.accent)
    ui.pushStyleColor(ui.Col.ButtonHovered, colors.accentDark)
    if ui.button("Hide UI##ToggleBtn", vec2(-1, 25)) then
        trafficData.uiVisible = false
    end
    ui.popStyleColor(2)
end

-- Reset game state
function resetGame()
    trafficData.currentScore = 0
    trafficData.lives = trafficData.maxLives
    trafficData.collisionCount = 0
    trafficData.laneChanges = 0
    trafficData.uniqueLanesUsed = {}
    trafficData.lastLaneChangeTime = 0
end

-- Key bindings
function script.key(key, down)
    if down then
        -- Toggle UI with F7
        if key == ui.Key.F7 then
            trafficData.uiVisible = not trafficData.uiVisible
        end
        
        -- Reset with F8
        if key == ui.Key.F8 then
            resetGame()
        end
    end
end

-- Server-side networking functions (if needed)
function script.serverMessage(senderCarID, data)
    -- Handle messages from server if needed
    -- This would be for multiplayer synchronization
end

-- Send data to server
function sendToServer(data)
    -- ac.sendServerMessage would be used here for multiplayer
    -- This is a placeholder for server communication
end

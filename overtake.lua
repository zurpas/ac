-- Advanced Traffic Server UI System for Assetto Corsa
-- Original Author: JBoondock
-- Modified: Jonfinity
-- Complete UI Overhaul: zurQ
-- Version: 2.0
-- Based on specifications for modern, tactical racing HUD
 
-- Debug initialization message
ac.debug("Traffic UI", "Script loading...")
ac.console("Traffic UI: Script loading... If you see this message, the script is being loaded correctly")
 
-- Check if we're in the correct environment
local function checkEnvironment()
    local success, result = pcall(function()
        return ac.getUI() ~= nil and ac.getCarState ~= nil
    end)
 
    if not success or not result then
        ac.console("ERROR: Traffic UI script not loaded in correct environment!")
        ac.debug("Traffic UI", "ERROR: Not in correct AC environment")
        return false
    end
 
    return true
end
 
-- Verify environment
local isValidEnvironment = checkEnvironment()
if not isValidEnvironment then
    ac.console("Traffic UI: Script failed environment check. Make sure CSP is installed and properly configured.")
    ac.debug("Traffic UI", "Environment check failed")
end
 
-- Check CSP version
local cspVersion = ac.getPatchVersionCode()
ac.debug("Traffic UI", "CSP Version: " .. tostring(cspVersion))
ac.console("Traffic UI: CSP Version: " .. tostring(cspVersion))
 
local requiredSpeed = 60
local DIAGONAL_ANGLE = 15 -- For clip-path diagonal cuts
 
-- Life system
local MAX_LIVES = 3
local currentLives = MAX_LIVES
local livesLostTimestamp = 0
local LIFE_COOLDOWN = 5 -- seconds between life loss events
 
-- Multiplier system
local PROXIMITY_LEVELS = { -- Distance thresholds
    { 7, rgbm(0.5, 0.5, 0.5, 1) },   -- Gray (far)
    { 5, rgbm(0, 0.8, 0.2, 1) },     -- Green
    { 4, rgbm(0, 0.4, 0.8, 1) },     -- Blue
    { 3, rgbm(0.9, 0.6, 0, 1) },     -- Orange
    { 2, rgbm(0.9, 0.1, 0.1, 1) }    -- Red (close)
}
 
local SPEED_LEVELS = { -- Speed thresholds
    { 80, rgbm(0.5, 0.5, 0.5, 1) },  -- Gray (slow)
    { 120, rgbm(0, 0.8, 0.2, 1) },   -- Green
    { 160, rgbm(0, 0.4, 0.8, 1) },   -- Blue
    { 200, rgbm(0.9, 0.6, 0, 1) },   -- Orange
    { 240, rgbm(0.9, 0.1, 0.1, 1) }  -- Red (fast)
}
 
local COMBO_LEVELS = { -- Visual styling for combo multiplier
    { 1, rgbm(0.5, 0.5, 0.5, 1), 0, 0 },     -- 1-3x: Standard colors
    { 4, rgbm(0.9, 0.6, 0.2, 1), 0.3, 0 },   -- 4-5x: Warm colors, gentle pulse
    { 6, rgbm(0.9, 0.2, 0.2, 1), 0.6, 1 },   -- 6-7x: Intense colors, medium pulse
    { 8, rgbm(1.0, 0.8, 0.0, 1), 1.0, 2 }    -- 8x+: Gold legendary colors, strong pulse
}
 
-- Animation and visual effects
local animations = {
    pbBeating = { active = false, intensity = 0, lastValue = 0 },
    comboFlash = { active = false, intensity = 0, timestamp = 0 },
    streakProgress = { value = 0, target = 0 },
    pulseEffects = { value = 0, speed = 1 }
}
 
-- Statistics tracking
local stats = {
    nearMisses = 0,
    cleanOvertakes = 0,
    avgSpeed = 0,
    driftPoints = 0,
    comboChain = 0,
    maxComboChain = 50
}
 
function script.prepare(dt)
    return ac.getCarState(1).speedKmh > 90
end
 
local timePassed = 0
local speedMessageTimer = 0
local totalScore = 0
local comboMeter = 1
local dangerouslySlowTimer = 0
local carsState = {}
local wheelsWarningTimeout = 0
local personalBest = 0
local ownRank = 0 
local lastProximity = 0
local sessionStartTime = os.time()
local sessionTimer = 600 -- 10 minute session
local closestDistance = 999
 
-- Multipliers
local proximityMultiplier = 1
local speedMultiplier = 1
local totalMultiplier = 1
 
local overtakeScoreEnd = ac.OnlineEvent({
    ac.StructItem.key("overtakeScoreEnd"),
    Score = ac.StructItem.int64(),
    Multiplier = ac.StructItem.int32(),
    Car = ac.StructItem.string(64),
})
 
local scoreUpdateEvent = ac.OnlineEvent({
    Score = ac.StructItem.int64(),
}, function(sender, data)
    if sender ~= nil then return end
    personalBest = data.Score
end)
 
-- UI Positioning and Toggle State
local uiCustomPos = vec2(ac.getUI().windowSize.x * 0.5 - 300, 30)
local uiMoveMode = false
local lastUiMoveKeyState = false
local UIToggle = true
local LastKeyState = false
local scriptInitTime = os.time()
local showInitMessage = true
 
-- Messages system
local messages = {}
function addMessage(text, mood)
    table.insert(messages, 1, { text = text, age = 0, mood = mood })
    while #messages > 5 do
        table.remove(messages)
    end
end
 
-- Utility functions
local function getComboLevel(combo)
    for i = #COMBO_LEVELS, 1, -1 do
        if combo >= COMBO_LEVELS[i][1] then
            return COMBO_LEVELS[i]
        end
    end
    return COMBO_LEVELS[1]
end
 
local function getProximityLevel(distance)
    for i = #PROXIMITY_LEVELS, 1, -1 do
        if distance <= PROXIMITY_LEVELS[i][1] then
            return PROXIMITY_LEVELS[i][2]
        end
    end
    return PROXIMITY_LEVELS[1][2]
end
 
local function getSpeedLevel(speed)
    for i = #SPEED_LEVELS, 1, -1 do
        if speed >= SPEED_LEVELS[i][1] then
            return SPEED_LEVELS[i][2]
        end
    end
    return SPEED_LEVELS[1][2]
end
 
local function calculateMultipliers(player, closestDist)
    -- Proximity multiplier (1.0 - 2.0)
    proximityMultiplier = math.max(1.0, 2.0 - (closestDist / 10))
 
    -- Speed multiplier (1.0 - 2.0)
    speedMultiplier = math.max(1.0, 1.0 + (player.speedKmh - 100) / 200)
 
    -- Total multiplier combines all factors
    totalMultiplier = (proximityMultiplier + speedMultiplier + comboMeter) / 3
    return totalMultiplier
end
 
local function lerpColor(c1, c2, t)
    t = math.saturate(t)
    return rgbm(
        c1.r + (c2.r - c1.r) * t,
        c1.g + (c2.g - c1.g) * t,
        c1.b + (c2.b - c1.b) * t,
        c1.a + (c2.a - c1.a) * t
    )
end
 
local function pulseValue(intensity, speed)
    return math.abs(math.sin(timePassed * speed * 3)) * intensity
end
 
local function drawClippedRect(pos, size, color, diagonalSize)
    local points = {
        vec2(pos.x + diagonalSize, pos.y),                  -- Top left after clip
        vec2(pos.x + size.x, pos.y),                        -- Top right
        vec2(pos.x + size.x, pos.y + size.y - diagonalSize), -- Bottom right before clip
        vec2(pos.x + size.x - diagonalSize, pos.y + size.y), -- Bottom right after clip
        vec2(pos.x, pos.y + size.y),                        -- Bottom left
        vec2(pos.x, pos.y + diagonalSize)                   -- Top left before clip
    }
    ui.drawPolygon(points, color)
end
 
function script.update(dt)
    -- UI Toggle Logic (CTRL+D)
    local keyState = ac.isKeyDown(ac.KeyIndex.Control) and ac.isKeyDown(ac.KeyIndex.D)
    if keyState and LastKeyState ~= keyState then
        UIToggle = not UIToggle
        LastKeyState = keyState
    elseif not keyState then
        LastKeyState = false
    end
 
    -- UI Move Mode Logic (B key)
    local uiMoveKeyState = ac.isKeyDown(ac.KeyIndex.B)
    if uiMoveKeyState and lastUiMoveKeyState ~= uiMoveKeyState then
        uiMoveMode = not uiMoveMode
        lastUiMoveKeyState = uiMoveKeyState
    elseif not uiMoveKeyState then
        lastUiMoveKeyState = false
    end
 
    -- Apply UI position change in move mode
    if ui.mouseClicked(ui.MouseButton.Left) then
        if uiMoveMode then
            uiCustomPos = ui.mousePos()
        end
    end
 
    -- Time management
    sessionTimer = math.max(0, sessionTimer - dt)
    timePassed = timePassed + dt
    speedMessageTimer = speedMessageTimer + dt
 
    -- Get player state
    local player = ac.getCarState(1)
    if player.engineLifeLeft < 1 then
        ac.console('Overtake score: ' .. totalScore)
        return
    end
 
    -- Reset car position with Delete key (when slow)
    local playerPos = player.position
    local playerDir = ac.getCameraForward()
    if ac.isKeyDown(ac.KeyIndex.Delete) and player.speedKmh < 15 then
        physics.setCarPosition(0, playerPos, playerDir)
    end
 
    -- Animation updates
    animations.pulseEffects.value = (animations.pulseEffects.value + dt * animations.pulseEffects.speed) % (math.pi * 2)
 
    -- PB beating animation
    if totalScore > personalBest then
        if not animations.pbBeating.active then
            animations.pbBeating.active = true
            animations.pbBeating.lastValue = totalScore
        end
        animations.pbBeating.intensity = math.min(1, animations.pbBeating.intensity + dt * 2)
    else
        animations.pbBeating.active = false
        animations.pbBeating.intensity = math.max(0, animations.pbBeating.intensity - dt * 2)
    end
 
    -- Combo flash animation
    if animations.comboFlash.active then
        if timePassed - animations.comboFlash.timestamp > 0.5 then
            animations.comboFlash.active = false
        end
        animations.comboFlash.intensity = math.max(0, 1 - (timePassed - animations.comboFlash.timestamp) * 2)
    end
 
    -- Combo meter decay
    local comboFadingRate = 0.5 * math.lerp(1, 0.1, math.lerpInvSat(player.speedKmh, 80, 200)) + player.wheelsOutside
    comboMeter = math.max(1, comboMeter - dt * comboFadingRate)
 
    -- Initialize car states
    local sim = ac.getSim()
    while sim.carsCount > #carsState do
        carsState[#carsState + 1] = {}
    end
 
    -- Wheels warning timeout
    if wheelsWarningTimeout > 0 then
        wheelsWarningTimeout = wheelsWarningTimeout - dt
    elseif player.wheelsOutside > 0 then
        wheelsWarningTimeout = 60
    end
 
    -- Minimum speed check
    if player.speedKmh < requiredSpeed then
        if dangerouslySlowTimer > 3 then
            ac.console('Overtake score: ' .. totalScore)
            comboMeter = 1
            totalScore = 0
        end
        dangerouslySlowTimer = dangerouslySlowTimer + dt
        if totalScore > personalBest and dangerouslySlowTimer > 3 then
            personalBest = totalScore
            if totalScore > 999 then
                overtakeScoreEnd{ Score = personalBest, Multiplier = comboMeter, Car = ac.getCarName(0) }
            end
        end
        comboMeter = 1
        return -- Return early if too slow
    else
        dangerouslySlowTimer = 0
    end
 
    -- Collision check and life system
    if player.collidedWith == 0 then
        if os.time() - livesLostTimestamp > LIFE_COOLDOWN then
            currentLives = currentLives - 1
            livesLostTimestamp = os.time()
            addMessage("Collision! Lives: " .. currentLives, "bad")
 
            if currentLives <= 0 then
                if totalScore >= personalBest then
                    personalBest = totalScore
                    if totalScore > 999 then
                        overtakeScoreEnd{ Score = personalBest, Multiplier = comboMeter, Car = ac.getCarName(0) }
                    end
                end
                addMessage("Game over! Final score: " .. totalScore, "bad")
                comboMeter = 1
                totalScore = 0
                currentLives = MAX_LIVES  -- Reset lives
                stats.comboChain = 0
            end
        end
    end
 
    -- Track closest car for multiplier
    closestDistance = 999
 
    -- Process all AI cars
    for i = 2, ac.getSim().carsCount do
        local car = ac.getCarState(i)
        local state = carsState[i]
        local distance = car.position:distance(player.position)
 
        -- Update closest distance
        if distance < closestDistance then
            closestDistance = distance
        end
 
        if car.position:closerToThan(player.position, 7) then
            local drivingAlong = math.dot(car.look, player.look) > 0.2
            if not drivingAlong then
                state.drivingAlong = false
                if not state.nearMiss and car.position:closerToThan(player.position, 3) then
                    state.nearMiss = true
                    stats.nearMisses = stats.nearMisses + 1
                    addMessage("Near Miss! +" .. math.ceil(5 * comboMeter) .. " pts", "good")
                    totalScore = totalScore + math.ceil(5 * comboMeter)
                end
            end
 
            if not state.overtaken and not state.collided and state.drivingAlong then
                local posDir = (car.position - player.position):normalize()
                local posDot = math.dot(posDir, car.look)
                state.maxPosDot = math.max(state.maxPosDot or -1, posDot)
                if posDot < -0.5 and (state.maxPosDot or 0) > 0.5 then
                    local pointsGained = math.ceil(10 * comboMeter * calculateMultipliers(player, distance))
                    totalScore = totalScore + pointsGained
                    comboMeter = comboMeter + 1
                    state.overtaken = true
                    stats.cleanOvertakes = stats.cleanOvertakes + 1
                    stats.comboChain = stats.comboChain + 1
 
                    -- Flash animation for combo
                    animations.comboFlash.active = true
                    animations.comboFlash.timestamp = timePassed
                    animations.comboFlash.intensity = 1
 
                    -- Close overtake bonus
                    if distance < 3 then
                        comboMeter = comboMeter + 2
                        addMessage("CLOSE OVERTAKE! +" .. pointsGained .. " pts (x" .. math.floor(comboMeter) .. ")", "excellent")
                    else
                        addMessage("Overtake! +" .. pointsGained .. " pts (x" .. math.floor(comboMeter) .. ")", "good")
                    end
                end
            end
        else
            state.maxPosDot = -1
            state.overtaken = false
            state.collided = false
            state.drivingAlong = true
            state.nearMiss = false
        end
    end
 
    -- Update streak progress bar animation
    animations.streakProgress.target = stats.comboChain / stats.maxComboChain
    animations.streakProgress.value = math.lerp(animations.streakProgress.value, animations.streakProgress.target, dt * 3)
 
    -- Update average speed
    stats.avgSpeed = math.lerp(stats.avgSpeed, player.speedKmh, dt * 0.5)
 
    -- Update drift points based on slip angle
    local slipAngle = math.abs(player.localAngularVelocity.y)
    if player.speedKmh > 40 and slipAngle > 0.5 then
        stats.driftPoints = stats.driftPoints + slipAngle * dt * 10
    end
 
    -- Update message age
    for i = #messages, 1, -1 do
        if messages[i] then
            messages[i].age = messages[i].age + dt
            if messages[i].age > 3 then
                table.remove(messages, i)
            end
        end
    end
 
    -- Debug print on initialization and periodically
    if timePassed == 0 or math.floor(timePassed) % 10 == 0 and math.floor(timePassed - dt) % 10 ~= 0 then
        ac.debug("Traffic UI", "Script running - Score: " .. totalScore .. ", Lives: " .. currentLives)
        ac.console("Traffic UI: Script running - Score: " .. totalScore .. ", Lives: " .. currentLives)
    end
end
 
-- Define colors
local COLOR_PANEL_BG = rgbm(0.1, 0.1, 0.12, 0.85)
local COLOR_PANEL_BORDER = rgbm(0.3, 0.3, 0.35, 0.9)
local COLOR_WHITE = rgbm(1, 1, 1, 1)
local COLOR_GOLD = rgbm(1, 0.8, 0, 1)
local COLOR_GREEN = rgbm(0, 0.8, 0.2, 1)
local COLOR_RED = rgbm(0.9, 0.1, 0.1, 1)
local COLOR_BAR_BG = rgbm(0.2, 0.2, 0.2, 0.8)
 
-- Modern tactical UI system
function script.drawUI()
    -- Skip if environment check failed
    if not isValidEnvironment then
        local screenSize = ac.getUI().windowSize
        local msgWidth = 500
        local msgHeight = 150
        local msgPos = vec2(screenSize.x / 2 - msgWidth / 2, screenSize.y / 2 - msgHeight / 2)
 
        -- Error message background
        ui.drawRectFilled(msgPos, msgPos + vec2(msgWidth, msgHeight), rgbm(0.3, 0, 0, 0.8))
        ui.drawRect(msgPos, msgPos + vec2(msgWidth, msgHeight), rgbm(1, 0, 0, 1), 2)
 
        -- Error text
        ui.pushFont(ui.Font.Big)
        ui.setCursor(msgPos + vec2(20, 20))
        ui.textColored("Traffic UI Error", rgbm(1, 0, 0, 1))
        ui.popFont()
 
        ui.setCursor(msgPos + vec2(20, 60))
        ui.text("Script not loaded in correct environment.")
        ui.setCursor(msgPos + vec2(20, 80))
        ui.text("Make sure CSP is installed and properly configured.")
        ui.setCursor(msgPos + vec2(20, 100))
        ui.text("Check console for more information.")
 
        return
    end
 
    -- Debug UI visibility
    ac.debug("Traffic UI", "Drawing UI - Toggle state: " .. tostring(UIToggle))
 
    -- Show initialization message for 10 seconds
    if showInitMessage and os.time() - scriptInitTime < 10 then
        local screenSize = ac.getUI().windowSize
        local msgWidth = 400
        local msgHeight = 100
        local msgPos = vec2(screenSize.x / 2 - msgWidth / 2, screenSize.y / 2 - msgHeight / 2)
 
        -- Background
        ui.drawRectFilled(msgPos, msgPos + vec2(msgWidth, msgHeight), rgbm(0, 0, 0, 0.8))
        ui.drawRect(msgPos, msgPos + vec2(msgWidth, msgHeight), rgbm(0, 1, 0, 1), 2)
 
        -- Text
        ui.pushFont(ui.Font.Big)
        ui.setCursor(msgPos + vec2(20, 20))
        ui.textColored("Traffic UI Script Loaded!", rgbm(0, 1, 0, 1))
        ui.popFont()
 
        ui.setCursor(msgPos + vec2(20, 50))
        ui.text("Press CTRL+D to toggle UI visibility")
        ui.setCursor(msgPos + vec2(20, 70))
        ui.text("Press B to enable UI move mode")
    end
 
    if not UIToggle then return end
 
    -- Get pulse and glow effects
    local pulseAmount = math.abs(math.sin(animations.pulseEffects.value)) * 0.3 + 0.7
    local comboLevel = getComboLevel(comboMeter)
    local comboGlow = comboLevel[3] * pulseAmount
    local comboPulseSpeed = comboLevel[4]
 
    if comboPulseSpeed > 0 then
        animations.pulseEffects.speed = 1 + comboPulseSpeed
    else
        animations.pulseEffects.speed = 1
    end
 
    -- Calculate multipliers for display
    local player = ac.getCarState(1)
    calculateMultipliers(player, closestDistance)
 
    -- Layout parameters
    local screenWidth = ac.getUI().windowSize.x
    local screenHeight = ac.getUI().windowSize.y
    local panelTopY = uiCustomPos.y
    local panelSpacing = 15
    local startX = uiCustomPos.x
    local diagonalCut = 15 -- Size of diagonal clip-path cuts
 
    -- Panel dimensions
    local scorePanelWidth = 220
    local scorePanelHeight = 100
    local multipliersPanelWidth = 220
    local multipliersPanelHeight = 120
    local statsPanelWidth = scorePanelWidth
    local statsPanelHeight = 100
    local comboPanelWidth = 150
    local comboPanelHeight = scorePanelHeight
 
    -- Colors for current state
    local pbColor = animations.pbBeating.active and 
                   lerpColor(COLOR_WHITE, COLOR_GOLD, math.abs(math.sin(timePassed * 3)) * animations.pbBeating.intensity) or 
                   COLOR_WHITE
 
    local comboColor = comboLevel[2]
    local comboTextColor = lerpColor(comboColor, COLOR_WHITE, 0.7)
    if animations.comboFlash.active then
        comboTextColor = lerpColor(comboTextColor, COLOR_WHITE, animations.comboFlash.intensity)
    end
 
    local proximityColor = getProximityLevel(closestDistance)
    local speedColor = getSpeedLevel(player.speedKmh)
 
    -- Border thickness and glow
    local borderThickness = 1 + comboGlow
 
    -- Draw primary score panel with diagonal clip-path
    local scorePanelX = startX
    local scorePanelPos = vec2(scorePanelX, panelTopY)
    drawClippedRect(scorePanelPos, vec2(scorePanelWidth, scorePanelHeight), COLOR_PANEL_BG, diagonalCut)
 
    -- PB Text with animation
    local pbText = "PB: " .. personalBest
    ui.setCursor(scorePanelPos + vec2(15, 10))
    ui.textColored(pbText, pbColor)
 
    -- Session timer
    local minutes = math.floor(sessionTimer / 60)
    local seconds = math.floor(sessionTimer % 60)
    local timerText = string.format("%02d:%02d", minutes, seconds)
    ui.setCursor(scorePanelPos + vec2(scorePanelWidth - 60, 10))
    ui.textColored(timerText, COLOR_WHITE)
 
    -- Score Text (Large, Center)
    local scoreText = totalScore .. " PTS"
    ui.setCursor(scorePanelPos + vec2(20, 40))
    ui.pushFont(ui.Font.Huge)
    ui.textColored(scoreText, animations.pbBeating.active and pbColor or COLOR_WHITE)
    ui.popFont()
 
    -- Lives display
    ui.setCursor(scorePanelPos + vec2(15, scorePanelHeight - 25))
    ui.text("LIVES: ")
 
    for i = 1, MAX_LIVES do
        local lifeColor = i <= currentLives and COLOR_GREEN or rgbm(0.3, 0.3, 0.3, 0.7)
        ui.sameLine()
        ui.rectFilled(vec2(20, 20), lifeColor)
    end
 
    -- Right Panel (Combo)
    local comboPanelX = scorePanelX + scorePanelWidth + panelSpacing
    local comboPanelPos = vec2(comboPanelX, panelTopY)
    drawClippedRect(comboPanelPos, vec2(comboPanelWidth, comboPanelHeight), COLOR_PANEL_BG, diagonalCut)
 
    -- Combo Multiplier Title
    ui.setCursor(comboPanelPos + vec2(15, 10))
    ui.textColored("COMBO", COLOR_WHITE)
 
    -- Combo Text (Large)
    local comboText = string.format("%.1fx", comboMeter)
    ui.setCursor(comboPanelPos + vec2(15, 35))
    ui.pushFont(ui.Font.Huge)
    ui.textColored(comboText, comboTextColor)
    ui.popFont()
 
    -- Combo Streak progress bar
    local barHeight = 6
    local barWidth = comboPanelWidth - 30
    local barX = comboPanelX + 15
    local barY = panelTopY + comboPanelHeight - barHeight - 15
 
    -- Draw streak text
    ui.setCursor(vec2(barX, barY - 15))
    ui.textColored(string.format("STREAK: %d/%d", stats.comboChain, stats.maxComboChain), COLOR_WHITE)
 
    -- Draw bar background
    ui.drawRectFilled(vec2(barX, barY), vec2(barX + barWidth, barY + barHeight), COLOR_BAR_BG)
 
    -- Draw filled portion with color based on progress
    if animations.streakProgress.value > 0 then
        local streakColor
        if animations.streakProgress.value < 0.3 then
            streakColor = COLOR_GREEN
        elseif animations.streakProgress.value < 0.6 then
            streakColor = rgbm(0.9, 0.6, 0, 1) -- Orange
        else
            streakColor = lerpColor(COLOR_RED, COLOR_GOLD, animations.streakProgress.value - 0.6)
        end
 
        ui.drawRectFilled(
            vec2(barX, barY), 
            vec2(barX + barWidth * animations.streakProgress.value, barY + barHeight), 
            streakColor
        )
    end
 
    -- Multipliers Panel (below score panel)
    local multipliersPanelY = panelTopY + scorePanelHeight + panelSpacing
    local multipliersPanelPos = vec2(startX, multipliersPanelY)
    drawClippedRect(multipliersPanelPos, vec2(multipliersPanelWidth, multipliersPanelHeight), COLOR_PANEL_BG, diagonalCut)
 
    -- Multipliers title
    ui.setCursor(multipliersPanelPos + vec2(15, 10))
    ui.textColored("MULTIPLIERS", COLOR_WHITE)
 
    -- Proximity multiplier
    ui.setCursor(multipliersPanelPos + vec2(15, 35))
    ui.text("PROXIMITY")
    ui.setCursor(multipliersPanelPos + vec2(multipliersPanelWidth - 60, 35))
    ui.textColored(string.format("%.1fx", proximityMultiplier), proximityColor)
 
    -- Speed multiplier
    ui.setCursor(multipliersPanelPos + vec2(15, 55))
    ui.text("SPEED")
    ui.setCursor(multipliersPanelPos + vec2(multipliersPanelWidth - 60, 55))
    ui.textColored(string.format("%.1fx", speedMultiplier), speedColor)
 
    -- Combo multiplier (repeated from above panel)
    ui.setCursor(multipliersPanelPos + vec2(15, 75))
    ui.text("COMBO")
    ui.setCursor(multipliersPanelPos + vec2(multipliersPanelWidth - 60, 75))
    ui.textColored(string.format("%.1fx", comboMeter), comboColor)
 
    -- Total multiplier
    local totalY = multipliersPanelPos.y + 95
    local totalWidth = multipliersPanelWidth - 30
    ui.drawLine(
        vec2(multipliersPanelPos.x + 15, totalY), 
        vec2(multipliersPanelPos.x + totalWidth, totalY), 
        COLOR_WHITE
    )
 
    ui.setCursor(multipliersPanelPos + vec2(15, totalY + 5))
    ui.text("TOTAL")
 
    ui.setCursor(multipliersPanelPos + vec2(multipliersPanelWidth - 60, totalY + 5))
    ui.pushFont(ui.Font.Big)
    ui.textColored(string.format("%.1fx", totalMultiplier), comboColor)
    ui.popFont()
 
    -- Stats Panel
    local statsPanelY = multipliersPanelY + multipliersPanelHeight + panelSpacing
    local statsPanelPos = vec2(startX, statsPanelY)
    drawClippedRect(statsPanelPos, vec2(statsPanelWidth, statsPanelHeight), COLOR_PANEL_BG, diagonalCut)
 
    -- Stats title
    ui.setCursor(statsPanelPos + vec2(15, 10))
    ui.textColored("STATISTICS", COLOR_WHITE)
 
    -- Stats in grid layout
    ui.setCursor(statsPanelPos + vec2(15, 35))
    ui.text("NEAR MISSES")
    ui.setCursor(statsPanelPos + vec2(statsPanelWidth - 60, 35))
    ui.textColored(tostring(stats.nearMisses), COLOR_WHITE)
 
    ui.setCursor(statsPanelPos + vec2(15, 55))
    ui.text("OVERTAKES")
    ui.setCursor(statsPanelPos + vec2(statsPanelWidth - 60, 55))
    ui.textColored(tostring(stats.cleanOvertakes), COLOR_WHITE)
 
    ui.setCursor(statsPanelPos + vec2(15, 75))
    ui.text("AVG SPEED")
    ui.setCursor(statsPanelPos + vec2(statsPanelWidth - 60, 75))
    ui.textColored(string.format("%.0f", stats.avgSpeed), COLOR_WHITE)
 
    -- Messages panel (notification area)
    if #messages > 0 then
        local messageHeight = 30
        local messageWidth = 250
        local messageX = screenWidth - messageWidth - 20
        local messageStartY = 100
 
        for i, msg in ipairs(messages) do
            local msgColor
            if msg.mood == "good" then
                msgColor = COLOR_GREEN
            elseif msg.mood == "bad" then
                msgColor = COLOR_RED
            elseif msg.mood == "excellent" then
                msgColor = COLOR_GOLD
            else
                msgColor = COLOR_WHITE
            end
 
            local alpha = math.saturate(1 - (msg.age / 3))
            local msgY = messageStartY + (i-1) * (messageHeight + 5)
            local msgBgColor = rgbm(COLOR_PANEL_BG.r, COLOR_PANEL_BG.g, COLOR_PANEL_BG.b, COLOR_PANEL_BG.a * alpha)
 
            drawClippedRect(vec2(messageX, msgY), vec2(messageWidth, messageHeight), msgBgColor, diagonalCut)
 
            ui.setCursor(vec2(messageX + 10, msgY + 7))
            ui.textColored(msg.text, rgbm(msgColor.r, msgColor.g, msgColor.b, msgColor.a * alpha))
        end
    end
 
    -- UI Move Mode indicator
    if uiMoveMode then
        ui.setCursor(vec2(10, 10))
        ui.textColored("UI MOVE MODE: Click to reposition", COLOR_GREEN)
    end
end
 
--[[
  Modern Traffic Server UI System for Assetto Corsa
  Based on original script by JBoondock, modified by Jonfinity
  Complete UI Overhaul implementing clip-path elements, multipliers, and visual effects as specified
  MIT License applies as per original code
]]
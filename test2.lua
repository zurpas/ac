-- Dood Gang HUD with Server Leaderboard
-- Exact replica of the reference design with persistent leaderboard functionality
-- For use with AssettoServer and CSP

-- Configuration
local CONFIG = {
    requiredSpeed = 80,          -- Minimum speed required in km/h
    leaderboardFile = "server/leaderboard_data.json", -- Path to save leaderboard data
    maxLeaderboardEntries = 1000, -- Maximum number of entries to track
    autosaveInterval = 60        -- How often to save leaderboard (seconds)
}

-- UI Colors (matching exact Dood Gang HUD style)
local COLOR = {
    ACCENT_BLACK = rgbm(0.05, 0.05, 0.05, 0.92),
    ACCENT_WHITE = rgbm(1, 1, 1, 1),
    POINT_WHITE = rgbm(1, 1, 1, 0.9),
    SPEEDOMETER_RED = rgbm(1, 0.2, 0.2, 1),
    SPEEDOMETER_GREEN = rgbm(0.2, 1, 0.4, 1),
    WARNING_RED = rgbm(1, 0, 0, 1)
}

-- State variables
local state = {
    timePassed = 0,
    totalScore = 0,
    comboMeter = 1,
    highestScore = 0,
    lastScore = 0,
    dangerouslySlowTimer = 0,
    carsState = {},
    wheelsWarningTimeout = 0,
    playerPosition = 0,
    sessionTime = 0,
    animationTimer = 0,
    scoreChangeFade = 0,
    lastSaveTime = 0,
    leaderboard = {},
    playerName = "",
    speedWarningTimer = 0
}

-- Load leaderboard from file
local function loadLeaderboard()
    local content = ac.load(CONFIG.leaderboardFile)
    if content then
        state.leaderboard = json.decode(content)
        ac.debug("Leaderboard loaded with " .. #state.leaderboard .. " entries")
    else
        state.leaderboard = {}
        ac.debug("No leaderboard file found, created new leaderboard")
    end
end

-- Save leaderboard to file
local function saveLeaderboard()
    local content = json.encode(state.leaderboard)
    if ac.store(CONFIG.leaderboardFile, content) then
        ac.debug("Leaderboard saved with " .. #state.leaderboard .. " entries")
        state.lastSaveTime = state.sessionTime
    else
        ac.debug("Failed to save leaderboard!")
    end
end

-- Add player to leaderboard
local function updateLeaderboard(playerName, score)
    if not playerName or playerName == "" then 
        playerName = "Unknown_" .. tostring(math.floor(math.random() * 10000))
    end
    
    -- Check if player already exists
    local playerFound = false
    for i, entry in ipairs(state.leaderboard) do
        if entry.name == playerName then
            if score > entry.score then
                entry.score = score
                entry.timestamp = os.time()
                table.sort(state.leaderboard, function(a, b) return a.score > b.score end)
            end
            playerFound = true
            break
        end
    end
    
    -- Add new player to leaderboard
    if not playerFound then
        table.insert(state.leaderboard, {
            name = playerName,
            score = score,
            timestamp = os.time()
        })
        table.sort(state.leaderboard, function(a, b) return a.score > b.score end)
        
        -- Trim leaderboard if too large
        while #state.leaderboard > CONFIG.maxLeaderboardEntries do
            table.remove(state.leaderboard)
        end
    end
    
    -- Update player position
    for i, entry in ipairs(state.leaderboard) do
        if entry.name == playerName then
            state.playerPosition = i
            break
        end
    end
    
    saveLeaderboard()
    return state.playerPosition
end

-- Find player position in leaderboard
local function getPlayerPosition(playerName)
    if not playerName or playerName == "" then return #state.leaderboard + 1 end
    
    for i, entry in ipairs(state.leaderboard) do
        if entry.name == playerName then
            return i
        end
    end
    
    return #state.leaderboard + 1
end

-- Format large numbers with commas
local function formatWithCommas(number)
    local formatted = tostring(number)
    local k
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
        if k == 0 then break end
    end
    return formatted
end

-- This function is called before event activates
function script.prepare(dt)
    -- Get player name from session
    state.playerName = ac.getCarState(1).playerName or "Driver_" .. tostring(math.floor(math.random() * 10000))
    
    -- Load leaderboard data
    loadLeaderboard()
    
    -- Get player's last best score and position
    state.playerPosition = getPlayerPosition(state.playerName)
    
    -- If player exists in leaderboard, get their high score
    for i, entry in ipairs(state.leaderboard) do
        if entry.name == state.playerName then
            state.highestScore = entry.score
            break
        end
    end
    
    return ac.getCarState(1).speedKmh > 60
end

-- Initialize car state
function initCarState()
    return {
        maxPosDot = -1,
        overtaken = false,
        collided = false,
        drivingAlong = true,
        nearMiss = false
    }
end

function script.update(dt)
    state.sessionTime = state.sessionTime + dt
    state.animationTimer = state.animationTimer + dt
    
    if state.timePassed == 0 then
        ac.sendChatMessage("Dood Gang mode activated. Let's go!")
    end

    local player = ac.getCarState(1)
    state.timePassed = state.timePassed + dt
    
    -- Auto-save leaderboard periodically
    if state.sessionTime - state.lastSaveTime > CONFIG.autosaveInterval then
        saveLeaderboard()
    end
    
    -- Check if car is destroyed
    if player.engineLifeLeft < 1 then
        if state.totalScore > state.highestScore then
            state.highestScore = math.floor(state.totalScore)
            -- Update leaderboard with new high score
            updateLeaderboard(state.playerName, state.highestScore)
            ac.sendChatMessage("New personal best: " .. state.totalScore .. " points!")
        end
        if state.totalScore > 0 then
            state.lastScore = state.totalScore
        end
        state.totalScore = 0
        state.comboMeter = 1
        return
    end

    -- Combo decay rate based on speed and wheels outside
    local comboFadingRate = 0.4 * math.lerp(1, 0.1, math.lerpInvSat(player.speedKmh, 80, 200)) + player.wheelsOutside
    state.comboMeter = math.max(1, state.comboMeter - dt * comboFadingRate)

    -- Initialize car states as needed
    local sim = ac.getSimState()
    while sim.carsCount > #state.carsState do
        state.carsState[#state.carsState + 1] = initCarState()
    end

    -- Handle speed warning
    if player.speedKmh < CONFIG.requiredSpeed then
        state.speedWarningTimer = state.speedWarningTimer + dt
        if state.speedWarningTimer > 3 then
            if state.totalScore > state.highestScore then
                state.highestScore = math.floor(state.totalScore)                
                updateLeaderboard(state.playerName, state.highestScore)
                ac.sendChatMessage("New personal best: " .. state.totalScore .. " points!")
            end
            if state.totalScore > 0 then
                state.lastScore = state.totalScore
            end
            state.totalScore = 0
            state.comboMeter = 1
        end
        state.dangerouslySlowTimer = state.dangerouslySlowTimer + dt
        return
    else
        state.speedWarningTimer = 0
        state.dangerouslySlowTimer = 0
    end

    -- Process car interactions (overtakes, near misses, collisions)
    for i = 1, sim.carsCount do
        local car = ac.getCarState(i)
        local carState = state.carsState[i]

        if car.pos:closerToThan(player.pos, 10) then
            local drivingAlong = math.dot(car.look, player.look) > 0.2
            if not drivingAlong then
                carState.drivingAlong = false

                -- Near miss detection
                if not carState.nearMiss and car.pos:closerToThan(player.pos, 3) then
                    carState.nearMiss = true
                    if car.pos:closerToThan(player.pos, 2.5) then
                        state.comboMeter = state.comboMeter + 2
                    else
                        state.comboMeter = state.comboMeter + 1
                    end
                end
            end

            -- Collision detection
            if car.collidedWith == 0 then
                carState.collided = true
                if state.totalScore > state.highestScore then
                    state.highestScore = math.floor(state.totalScore)
                    updateLeaderboard(state.playerName, state.highestScore)                    
                end
                if state.totalScore > 10 then
                    state.lastScore = state.totalScore
                end
                state.totalScore = 0
                state.comboMeter = 1
            end

            -- Overtake detection and scoring
            if not carState.overtaken and not carState.collided and carState.drivingAlong then
                local posDir = (car.pos - player.pos):normalize()
                local posDot = math.dot(posDir, car.look)
                carState.maxPosDot = math.max(carState.maxPosDot, posDot)
                if posDot < -0.5 and carState.maxPosDot > 0.5 then
                    local points = math.ceil(10 * state.comboMeter)
                    state.totalScore = state.totalScore + points
                    state.comboMeter = state.comboMeter + 1
                    state.scoreChangeFade = 1.0
                    carState.overtaken = true
                end
            end
        else
            carState.maxPosDot = -1
            carState.overtaken = false
            carState.collided = false
            carState.drivingAlong = true
            carState.nearMiss = false
        end
    end
    
    -- Update fade effects
    if state.scoreChangeFade > 0 then
        state.scoreChangeFade = state.scoreChangeFade - dt * 2
    end
end

function script.drawUI()
    local uiState = ac.getUiState()
    local screenWidth = ac.getUI().windowSize.x
    local screenHeight = ac.getUI().windowSize.y
    
    -- Timer in top right (88h51m format)
    local timeHours = math.floor(state.sessionTime / 3600)
    local timeMinutes = math.floor((state.sessionTime % 3600) / 60)
    local timeString = string.format("%02dh%02dm", timeHours, timeMinutes)
    
    ui.beginTransparentWindow("timeDisplay", vec2(screenWidth - 150, 10), vec2(140, 30))
    ui.pushFont(ui.Font.Main)
    ui.setCursor(vec2(0, 5))
    ui.textColored(timeString, COLOR.ACCENT_WHITE)
    ui.popFont()
    ui.endTransparentWindow()
    
    -- Speed indicator circle (left side)
    local speedCircleRadius = 25
    local currentSpeed = math.floor(ac.getCarState(1).speedKmh)
    local speedColor = currentSpeed < CONFIG.requiredSpeed and COLOR.SPEEDOMETER_RED or COLOR.SPEEDOMETER_GREEN
    
    ui.beginTransparentWindow("speedIndicator", vec2(50 - speedCircleRadius, 50 - speedCircleRadius), 
                              vec2(speedCircleRadius * 2, speedCircleRadius * 2))
    ui.drawCircle(vec2(speedCircleRadius, speedCircleRadius), speedCircleRadius, speedColor, 2, 32)
    ui.pushFont(ui.Font.Main)
    local speedText = tostring(currentSpeed)
    local textSize = ui.measureText(speedText)
    ui.setCursor(vec2(speedCircleRadius - textSize.x/2, speedCircleRadius - textSize.y/2))
    ui.text(speedText)
    ui.popFont()
    ui.endTransparentWindow()
    
    -- Draw top "Position Banner" like in the image
    -- ------------------------------------------
    ui.beginTransparentWindow("positionBanner", vec2(50, 50), vec2(300, 90))
    
    -- PB section with arrow-like design
    ui.pathClear()
    ui.pathLineTo(vec2(0, 0))
    ui.pathLineTo(vec2(80, 0))
    ui.pathLineTo(vec2(100, 30))
    ui.pathLineTo(vec2(300, 30))
    ui.pathLineTo(vec2(300, 60))
    ui.pathLineTo(vec2(0, 60))
    ui.pathFillConvex(COLOR.ACCENT_BLACK)
    
    -- PB text
    ui.pushFont(ui.Font.Title)
    ui.setCursor(vec2(15, 15))
    ui.text("PB")
    ui.sameLine(0, 10)
    ui.textColored(formatWithCommas(state.highestScore), COLOR.ACCENT_WHITE)
    ui.popFont()
    
    -- Position display as a separate darker block
    ui.drawRectFilled(vec2(0, 60), vec2(300, 90), rgbm(0.03, 0.03, 0.03, 0.95), 0)
    
    -- Position text
    ui.pushFont(ui.Font.Main)
    ui.setCursor(vec2(15, 65))
    ui.textColored("#" .. formatWithCommas(state.playerPosition) .. " PLACE", COLOR.ACCENT_WHITE)
    ui.popFont()
    
    ui.endTransparentWindow()
    
    -- Draw right side HUD - Score and multipliers
    -- ------------------------------------------
    ui.beginTransparentWindow("scoreHUD", vec2(screenWidth - 350, screenHeight/4), vec2(300, 120))
    
    -- Multiplier section at top
    local multiWidth = 300
    local multiHeight = 40
    
    -- Create multiplier row with arrow design
    ui.drawRectFilled(vec2(0, 0), vec2(multiWidth, multiHeight), COLOR.ACCENT_BLACK, 0)
    
    -- Draw the multiplier info
    ui.pushFont(ui.Font.Small)
    
    -- Speed multiplier
    local speedMult = math.max(1.0, math.min(currentSpeed / CONFIG.requiredSpeed, 2.0))
    ui.setCursor(vec2(20, 5))
    ui.textColored(string.format("%.1fX", speedMult), COLOR.ACCENT_WHITE)
    ui.setCursor(vec2(20, 22))
    ui.text("Speed")
    
    -- Proximity multiplier
    ui.setCursor(vec2(120, 5))
    ui.textColored("1.0X", COLOR.ACCENT_WHITE)
    ui.setCursor(vec2(120, 22))
    ui.text("Proximity")
    
    -- Combo multiplier
    ui.setCursor(vec2(220, 5))
    ui.textColored(string.format("%.1fX", state.comboMeter), COLOR.ACCENT_WHITE)
    ui.setCursor(vec2(220, 22))
    ui.text("Combo")
    
    -- Draw decorative arrows
    for i = 1, 5 do
        local x = multiWidth - 35 + (i * 8)
        ui.drawLine(vec2(x, 10), vec2(x+5, 20), COLOR.ACCENT_WHITE, 1)
        ui.drawLine(vec2(x, 30), vec2(x+5, 20), COLOR.ACCENT_WHITE, 1)
    end
    
    ui.popFont()
    
    -- Main score section
    local scoreYOffset = multiHeight
    
    -- White background for the score
    ui.pathClear()
    ui.pathLineTo(vec2(0, scoreYOffset))
    ui.pathLineTo(vec2(multiWidth - 80, scoreYOffset))
    ui.pathLineTo(vec2(multiWidth - 60, scoreYOffset + 50))
    ui.pathLineTo(vec2(0, scoreYOffset + 50))
    ui.pathFillConvex(COLOR.POINT_WHITE)
    
    -- Black section for timer
    ui.pathClear()
    ui.pathLineTo(vec2(multiWidth - 80, scoreYOffset))
    ui.pathLineTo(vec2(multiWidth, scoreYOffset))
    ui.pathLineTo(vec2(multiWidth, scoreYOffset + 50))
    ui.pathLineTo(vec2(multiWidth - 60, scoreYOffset + 50))
    ui.pathFillConvex(COLOR.ACCENT_BLACK)
    
    -- Score text
    ui.pushFont(ui.Font.Title)
    ui.setCursor(vec2(20, scoreYOffset + 15))
    ui.textColored(string.format("%d PTS", state.totalScore), rgbm(0, 0, 0, 1))
    ui.popFont()
    
    -- Timer text
    ui.pushFont(ui.Font.Main)
    ui.setCursor(vec2(multiWidth - 50, scoreYOffset + 15))
    local timerText = string.format("%02d:%02d", 
                                   math.floor(state.sessionTime / 60) % 60,
                                   math.floor(state.sessionTime) % 60)
    ui.textColored(timerText, COLOR.ACCENT_WHITE)
    ui.popFont()
    
    ui.endTransparentWindow()
    
    -- Speed warning
    if currentSpeed < CONFIG.requiredSpeed then
        ui.beginTransparentWindow("speedWarning", vec2(screenWidth/2 - 200, screenHeight/2 - 25), vec2(400, 50))
        ui.pushFont(ui.Font.Title)
        local warningText = "SPEED UP: " .. CONFIG.requiredSpeed .. " KM/H MINIMUM"
        local textWidth = ui.measureText(warningText).x
        ui.setCursor(vec2((400 - textWidth)/2, 15))
        
        -- Flashing effect for warning
        local flashRate = math.sin(state.sessionTime * 5) * 0.5 + 0.5
        ui.textColored(warningText, rgbm(1, 0.2, 0.2, 0.7 + flashRate * 0.3))
        ui.popFont()
        ui.endTransparentWindow()
    end
end

-- Server command to reset leaderboard
function script.serverCommand(command, arguments)
    if command == "reset_leaderboard" and ac.isAdmin() then
        state.leaderboard = {}
        saveLeaderboard()
        ac.sendChatMessage("Leaderboard has been reset by an admin")
        return "Leaderboard reset successful"
    elseif command == "show_leaderboard" then
        local count = tonumber(arguments) or 10
        count = math.min(count, #state.leaderboard)
        local response = "Top " .. count .. " players:\n"
        
        for i = 1, count do
            if state.leaderboard[i] then
                response = response .. i .. ". " .. state.leaderboard[i].name .. ": " .. state.leaderboard[i].score .. " pts\n"
            end
        end
        
        return response
    end
    
    return "Unknown command"
end

-- Called when player connects
function script.playerConnect(index, name)
    -- Update the player name if it's the same car index
    if index == 1 then
        state.playerName = name
        state.playerPosition = getPlayerPosition(name)
        
        -- Get player's previous best score if they exist in leaderboard
        for i, entry in ipairs(state.leaderboard) do
            if entry.name == name then
                state.highestScore = entry.score
                break
            end
        end
    end
end

-- Called when script unloads
function script.unload()
    -- Make sure leaderboard is saved
    if state.totalScore > state.highestScore then
        state.highestScore = math.floor(state.totalScore)
        updateLeaderboard(state.playerName, state.highestScore)
    end
    saveLeaderboard()
    ac.debug("Dood Gang script unloaded, leaderboard saved")
end

-- Configuration
local CONFIG = {
    requiredSpeed = 95,         -- Minimum speed to maintain scoring
    minOvertakeDistance = 7,    -- Distance to detect potential overtake
    closeOvertakeDistance = 3,  -- Distance for "close" overtake bonus
    resetWarningTime = 3,       -- Seconds until score reset when below minimum speed
    initialMessageDelay = 5,    -- Seconds between speed warning messages
    wheelsPenalty = 0.5,        -- Combo meter reduction for wheels outside track
    baseScore = 10,             -- Base score per overtake
    closeMultiplier = 3,        -- Multiplier for close overtakes
    uiToggleKey = {             -- Key combination to toggle UI
        main = ac.KeyIndex.Control,
        secondary = ac.KeyIndex.D
    }
}

-- Leaderboard 
local Leaderboard = {
    scores = {},        -- Will hold player scores
    maxEntries = 10,    -- Maximum entries to display
    file = "overtake_leaderboard.json",
    isLoaded = false
}

-- Session state
local Session = {
    timePassed = 0,
    messageTimers = {
        speed = 0,
        mack = 0
    },
    totalScore = 0,
    comboMeter = 1,
    comboColor = 0,
    dangerouslySlowTimer = 0,
    carsState = {},
    wheelsWarningTimeout = 0,
    personalBest = 0,
    sessionStart = os.time(),
    lastScoreSent = 0,    -- Throttle leaderboard updates
    uiVisible = true,
    lastKeyState = false,
    speedWarning = 0
}

-- Messages
local Messages = {
    mack = { 
        'MAAAACK!!!!', 
        'Y I K E S', 
        'You Hesitated....', 
        'Ouch..', 
        'Not A Chance...', 
        'Ain\'t no way you were makin that.'
    },
    close = { 
        'WE IN THAT!!!!! 3x', 
        'WITHIN! 3x', 
        'D I V E 3x', 
        'SKRRT!!! 3x', 
        'THREADING THE NEEDLE! 3x',
        'CALCULATED! 3x',
        'PRECISION OVERTAKE! 3x'
    },
    queue = {},
    glitter = {},
    glitterCount = 0
}

-- Utility functions
local function saveLeaderboard()
    local file = io.open(Leaderboard.file, "w")
    if file then
        file:write(json.encode(Leaderboard.scores))
        file:close()
    end
end

local function loadLeaderboard()
    local file = io.open(Leaderboard.file, "r")
    if file then
        local content = file:read("*a")
        file:close()
        
        local success, decoded = pcall(function() return json.decode(content) end)
        if success and decoded then
            Leaderboard.scores = decoded
            Leaderboard.isLoaded = true
            return true
        end
    end
    
    -- Initialize empty leaderboard if loading fails
    Leaderboard.scores = {}
    Leaderboard.isLoaded = true
    return false
end

local function updateLeaderboard(playerName, score)
    if not Leaderboard.isLoaded then
        loadLeaderboard()
    end
    
    local found = false
    for i, entry in ipairs(Leaderboard.scores) do
        if entry.name == playerName then
            if score > entry.score then
                entry.score = score
                entry.timestamp = os.time()
                found = true
                table.sort(Leaderboard.scores, function(a, b) return a.score > b.score end)
            end
            break
        end
    end
    
    if not found then
        table.insert(Leaderboard.scores, {
            name = playerName,
            score = score,
            timestamp = os.time()
        })
        table.sort(Leaderboard.scores, function(a, b) return a.score > b.score end)
        
        -- Trim leaderboard to max entries
        while #Leaderboard.scores > Leaderboard.maxEntries do
            table.remove(Leaderboard.scores)
        end
    end
    
    saveLeaderboard()
end

local function formatTime(seconds)
    local minutes = math.floor(seconds / 60)
    seconds = math.floor(seconds % 60)
    return string.format("%02d:%02d", minutes, seconds)
end

local function formatTimestamp(timestamp)
    local diff = os.difftime(os.time(), timestamp)
    
    if diff < 60 then
        return "just now"
    elseif diff < 3600 then
        return math.floor(diff/60) .. " min ago"
    elseif diff < 86400 then
        return math.floor(diff/3600) .. " hrs ago"
    else
        return math.floor(diff/86400) .. " days ago"
    end
end

-- UI functions
local function addMessage(text, mood)
    for i = math.min(#Messages.queue + 1, 4), 2, -1 do
        Messages.queue[i] = Messages.queue[i - 1]
        Messages.queue[i].targetPos = i
    end
    
    Messages.queue[1] = { 
        text = text, 
        age = 0, 
        targetPos = 1, 
        currentPos = 1, 
        mood = mood 
    }
    
    -- Add particle effects for positive messages
    if mood == 1 then
        for i = 1, 60 do
            local dir = vec2(math.random() - 0.5, math.random() - 0.5)
            Messages.glitterCount = Messages.glitterCount + 1
            Messages.glitter[Messages.glitterCount] = {
                color = rgbm.new(hsv(math.random() * 360, 1, 1):rgb(), 1),
                pos = vec2(80, 140) + dir * vec2(40, 20),
                velocity = dir:normalize():scale(0.2 + math.random()),
                life = 0.5 + 0.5 * math.random()
            }
        end
    end
end

local function updateMessages(dt)
    -- Update combo color cycling
    Session.comboColor = Session.comboColor + dt * 10 * Session.comboMeter
    if Session.comboColor > 360 then 
        Session.comboColor = Session.comboColor - 360 
    end
    
    -- Update message positions
    for i = 1, #Messages.queue do
        local m = Messages.queue[i]
        m.age = m.age + dt
        m.currentPos = math.applyLag(m.currentPos, m.targetPos, 0.8, dt)
    end
    
    -- Update particle effects
    for i = Messages.glitterCount, 1, -1 do
        local g = Messages.glitter[i]
        g.pos:add(g.velocity)
        g.velocity.y = g.velocity.y + 0.02
        g.life = g.life - dt
        g.color.mult = math.saturate(g.life * 4)
        
        if g.life < 0 then
            if i < Messages.glitterCount then
                Messages.glitter[i] = Messages.glitter[Messages.glitterCount]
            end
            Messages.glitterCount = Messages.glitterCount - 1
        end
    end
    
    -- Add random particles for high combo
    if Session.comboMeter > 10 and math.random() > 0.98 then
        for i = 1, math.floor(Session.comboMeter) do
            local dir = vec2(math.random() - 0.5, math.random() - 0.5)
            Messages.glitterCount = Messages.glitterCount + 1
            Messages.glitter[Messages.glitterCount] = {
                color = rgbm.new(hsv(math.random() * 360, 1, 1):rgb(), 1),
                pos = vec2(195, 75) + dir * vec2(40, 20),
                velocity = dir:normalize():scale(0.2 + math.random()),
                life = 0.5 + 0.5 * math.random()
            }
        end
    end
end

-- Main functions
function script.prepare(dt)
    if not Leaderboard.isLoaded then
        loadLeaderboard()
    end
    
    ac.log('Player speed: ' .. ac.getCarState(1).speedKmh)
    return ac.getCarState(1).speedKmh > 60
end

function script.update(dt)
    -- Initialize session
    if Session.timePassed == 0 then
        local playerName = ac.getDriverName(0)
        addMessage('Overtake Mode by JBoondock | Modern Edition', 0)
        addMessage('Car: ' .. ac.getCarName(0), 0)
        addMessage('Driver: ' .. playerName, 0)
    end

    -- Get player state
    local player = ac.getCarState(1)
    
    -- Check if car is destroyed
    if player.engineLifeLeft < 1 then
        ac.console('Overtake score: ' .. Session.totalScore)
        
        -- Update leaderboard on car destruction
        if Session.totalScore > 0 then
            updateLeaderboard(ac.getDriverName(0), Session.totalScore)
        end
        return
    end

    -- Teleport car if Delete key is pressed while almost stopped
    local playerPos = player.position
    local playerDir = ac.getCameraPositionRelativeToCar()
    if ac.isKeyDown(ac.KeyIndex.Delete) and player.speedKmh < 15 then
        physics.setCarPosition(0, playerPos, playerDir)
    end

    -- Update timers
    Session.timePassed = Session.timePassed + dt
    Session.messageTimers.speed = Session.messageTimers.speed + dt
    Session.messageTimers.mack = Session.messageTimers.mack + dt

    -- Update combo meter
    local comboFadingRate = 0.5 * math.lerp(1, 0.1, math.lerpInvSat(player.speedKmh, 80, 200)) + player.wheelsOutside * CONFIG.wheelsPenalty
    Session.comboMeter = math.max(1, Session.comboMeter - dt * comboFadingRate)

    -- Initialize car states array
    local sim = ac.getSim()
    while sim.carsCount > #Session.carsState do
        Session.carsState[#Session.carsState + 1] = {}
    end

    -- Check if car is out of bounds
    if Session.wheelsWarningTimeout > 0 then
        Session.wheelsWarningTimeout = Session.wheelsWarningTimeout - dt
    elseif player.wheelsOutside > 0 then
        if Session.wheelsWarningTimeout == 0 then
            addMessage('Car is Out Of Zone', -1)
            Session.wheelsWarningTimeout = 60
        end
    end

    -- Handle minimum speed requirement
    if player.speedKmh < CONFIG.requiredSpeed then
        if Session.dangerouslySlowTimer > CONFIG.resetWarningTime then
            -- Reset score after warning period
            ac.console('Overtake score: ' .. Session.totalScore)
            
            -- Update personal best and leaderboard
            if Session.totalScore > Session.personalBest then
                Session.personalBest = Session.totalScore
                ac.sendChatMessage('just scored ' .. Session.personalBest .. ' points!')
                
                -- Update leaderboard only if score is significant
                if Session.totalScore >= 100 and os.time() - Session.lastScoreSent > 30 then
                    updateLeaderboard(ac.getDriverName(0), Session.totalScore)
                    Session.lastScoreSent = os.time()
                end
            end
            
            Session.comboMeter = 1
            Session.totalScore = 0
        else
            -- Show warnings
            if Session.dangerouslySlowTimer < CONFIG.resetWarningTime then
                if Session.messageTimers.speed > CONFIG.initialMessageDelay then
                    addMessage(CONFIG.resetWarningTime .. ' Seconds until score reset!', -1)
                    Session.messageTimers.speed = 0
                end
            end

            if Session.dangerouslySlowTimer == 0 then
                addMessage('Speed up!', -1)
            end
        end
        
        Session.dangerouslySlowTimer = Session.dangerouslySlowTimer + dt
        Session.comboMeter = 1
        
        return
    else
        Session.dangerouslySlowTimer = 0
    end

    -- Handle collision with player's car
    if player.collidedWith == 0 then
        -- Update personal best and leaderboard on crash
        if Session.totalScore > 0 then
            if Session.totalScore >= Session.personalBest then
                Session.personalBest = Session.totalScore
                ac.sendChatMessage('just scored ' .. Session.personalBest .. ' points!')
                
                -- Update leaderboard only if score is significant
                if Session.totalScore >= 100 and os.time() - Session.lastScoreSent > 30 then
                    updateLeaderboard(ac.getDriverName(0), Session.totalScore)
                    Session.lastScoreSent = os.time()
                end
            end
        }
        
        Session.comboMeter = 1
        Session.totalScore = 0
        
        if Session.messageTimers.mack > 1 then
            addMessage(Messages.mack[math.random(1, #Messages.mack)], -1)
            Session.messageTimers.mack = 0
        end
    end

    -- Process AI cars for overtake detection
    for i = 2, ac.getSim().carsCount do
        local car = ac.getCarState(i)
        local state = Session.carsState[i]

        -- Check if car is close enough for potential overtake
        if car.position:closerToThan(player.position, CONFIG.minOvertakeDistance) then
            local drivingAlong = math.dot(car.look, player.look) > 0.2
            
            if not drivingAlong then
                state.drivingAlong = false

                -- Detect near miss
                if not state.nearMiss and car.position:closerToThan(player.position, CONFIG.closeOvertakeDistance) then
                    state.nearMiss = true
                end
            end

            -- Detect successful overtake
            if not state.overtaken and not state.collided and state.drivingAlong then
                -- Initialize max position dot product if needed
                if not state.maxPosDot then
                    state.maxPosDot = -1
                end
                
                local posDir = (car.position - player.position):normalize()
                local posDot = math.dot(posDir, car.look)
                state.maxPosDot = math.max(state.maxPosDot or -1, posDot)
                
                if posDot < -0.5 and state.maxPosDot > 0.5 then
                    -- Calculate score based on base score and combo multiplier
                    local scoreGain = math.ceil(CONFIG.baseScore * Session.comboMeter)
                    Session.totalScore = Session.totalScore + scoreGain
                    
                    -- Increase combo meter
                    Session.comboMeter = Session.comboMeter + 1
                    Session.comboColor = Session.comboColor + 90
                    
                    -- Show message
                    addMessage('Overtake 1x', Session.comboMeter > 50 and 1 or 0)
                    state.overtaken = true

                    -- Add bonus for close overtake
                    if car.position:closerToThan(player.position, CONFIG.closeOvertakeDistance) then
                        Session.comboMeter = Session.comboMeter + CONFIG.closeMultiplier
                        Session.comboColor = Session.comboColor + math.random(1, 90)
                        addMessage(Messages.close[math.random(#Messages.close)], 2)
                    end
                end
            end
        } else {
            -- Reset car state when out of range
            state.maxPosDot = -1
            state.overtaken = false
            state.collided = false
            state.drivingAlong = true
            state.nearMiss = false
        }
    end
end

function script.drawUI()
    -- Handle UI toggle with key combination
    local keyState = ac.isKeyDown(CONFIG.uiToggleKey.main) and ac.isKeyDown(CONFIG.uiToggleKey.secondary)
    if keyState and Session.lastKeyState ~= keyState then
        Session.uiVisible = not Session.uiVisible
        Session.lastKeyState = keyState
    elseif not keyState then
        Session.lastKeyState = false
    end
    
    -- Exit if UI is hidden
    if not Session.uiVisible then
        -- Still provide minimal UI feedback
        ui.beginTransparentWindow('overtakeHidden', vec2(10, 10), vec2(300, 50), true)
        ui.text('UI Hidden (Ctrl+D to show)')
        ui.endTransparentWindow()
        return
    end
    
    local uiState = ac.getUiState()
    updateMessages(uiState.dt)

    -- Calculate speed warning indicator
    local speedRelative = math.saturate(math.floor(ac.getCarState(1).speedKmh) / CONFIG.requiredSpeed)
    Session.speedWarning = math.applyLag(Session.speedWarning, speedRelative < 1 and 1 or 0, 0.5, uiState.dt)

    -- Define UI colors
    local colorDark = rgbm(0.4, 0.4, 0.4, 1)
    local colorGrey = rgbm(0.7, 0.7, 0.7, 1)
    local colorAccent = rgbm.new(hsv(speedRelative * 120, 1, 1):rgb(), 1)
    local colorCombo = rgbm.new(hsv(Session.comboColor, math.saturate(Session.comboMeter / 10), 1):rgb(),
        math.saturate(Session.comboMeter / 4))

    -- Define speed meter drawing function
    local function speedMeter(ref)
        ui.drawRectFilled(ref + vec2(0, -4), ref + vec2(180, 5), colorDark, 1)
        ui.drawLine(ref + vec2(0, -4), ref + vec2(0, 4), colorGrey, 1)
        ui.drawLine(ref + vec2(CONFIG.requiredSpeed, -4), ref + vec2(CONFIG.requiredSpeed, 4), colorGrey, 1)

        local speed = math.min(ac.getCarState(1).speedKmh, 180)
        if speed > 1 then
            ui.drawLine(ref + vec2(0, 0), ref + vec2(speed, 0), colorAccent, 4)
        end
    end

    -- Main score display
    ui.beginTransparentWindow('overtakeScore', vec2(uiState.windowSize.x * 0.5 - 900, 25), vec2(400, 400), true)
    ui.beginOutline()

    ui.pushStyleVar(ui.StyleVar.Alpha, 1 - Session.speedWarning)
    ui.pushFont(ui.Font.Title)
    ui.text('Cut Up Points')
    ui.pushFont(ui.Font.Huge)
    ui.textColored('PB: ' .. Session.personalBest .. ' pts', colorCombo)
    ui.popFont()
    ui.popStyleVar()

    ui.pushFont(ui.Font.Huge)
    ui.text(Session.totalScore .. ' pts')
    ui.sameLine(0, 40)
    ui.beginRotation()
    ui.textColored(math.ceil(Session.comboMeter * 10) / 10 .. 'x', colorCombo)
    
    -- Add rotation effects based on combo meter
    if Session.comboMeter > 20 then
        ui.endRotation(math.sin(Session.comboMeter / 180 * 3141.5) * 3 * math.lerpInvSat(Session.comboMeter, 20, 30) + 90)
    elseif Session.comboMeter > 50 then
        ui.endRotation(math.sin(Session.comboMeter / 220 * 3141.5) * 3 * math.lerpInvSat(Session.comboMeter, 20, 30) + 90)
    elseif Session.comboMeter > 100 then
        ui.endRotation(math.sin(Session.comboMeter / 260 * 3141.5) * 3 * math.lerpInvSat(Session.comboMeter, 20, 30) + 90)
    elseif Session.comboMeter > 250 then
        ui.endRotation(math.sin(Session.comboMeter / 360 * 3141.5) * 3 * math.lerpInvSat(Session.comboMeter, 20, 30) + 90)
    end
    
    ui.popFont()
    ui.endOutline(rgbm(0, 0, 0, 0.3))

    -- Session timer display
    local sessionTime = os.difftime(os.time(), Session.sessionStart)
    ui.text('Session Time: ' .. formatTime(sessionTime))

    -- Messages display
    ui.offsetCursorY(20)
    ui.pushFont(ui.Font.Title)
    local startPos = ui.getCursor()
    
    for i = 1, #Messages.queue do
        local m = Messages.queue[i]
        local f = math.saturate(4 - m.currentPos) * math.saturate(8 - m.age)
        ui.setCursor(startPos + vec2(20 + math.saturate(1 - m.age * 10) ^ 2 * 100, (m.currentPos - 1) * 30))
        
        -- Choose color based on message mood
        local textColor
        if m.mood == 1 then
            textColor = rgbm(0, 1, 0, f)
        elseif m.mood == -1 then
            textColor = rgbm(1, 0, 0, f)
        elseif m.mood == 2 then
            textColor = rgbm(1, 0.84, 0, f)
        else
            textColor = rgbm(1, 1, 1, f)
        end
        
        ui.textColored(m.text, textColor)
    end
    
    -- Draw particle effects
    for i = 1, Messages.glitterCount do
        local g = Messages.glitter[i]
        if g ~= nil then
            ui.drawLine(g.pos, g.pos + g.velocity * 4, g.color, 2)
        end
    end
    
    ui.popFont()
    ui.setCursor(startPos + vec2(0, 4 * 30))

    -- Speed warning display
    ui.pushStyleVar(ui.StyleVar.Alpha, Session.speedWarning)
    ui.setCursorY(0)
    ui.pushFont(ui.Font.Main)
    ui.textColored('Keep speed above ' .. CONFIG.requiredSpeed .. ' km/h:', colorAccent)
    speedMeter(ui.getCursor() + vec2(-9, 4))
    ui.popFont()
    ui.popStyleVar()

    ui.endTransparentWindow()
    
    -- Leaderboard display
    ui.beginTransparentWindow('overtakeLeaderboard', vec2(uiState.windowSize.x * 0.5 + 500, 25), vec2(350, 400), true)
    ui.beginOutline()
    
    ui.pushFont(ui.Font.Title)
    ui.text('Leaderboard')
    ui.popFont()
    
    if #Leaderboard.scores > 0 then
        for i, entry in ipairs(Leaderboard.scores) do
            local rankColor = i == 1 and rgbm(1, 0.84, 0, 1) or -- Gold
                             i == 2 and rgbm(0.75, 0.75, 0.75, 1) or -- Silver
                             i == 3 and rgbm(0.8, 0.5, 0.2, 1) or -- Bronze
                             rgbm(1, 1, 1, 0.8) -- Normal
                             
            -- Highlight player's score
            local isPlayer = entry.name == ac.getDriverName(0)
            if isPlayer then
                ui.drawRectFilled(ui.getCursor(), ui.getCursor() + vec2(350, 25), rgbm(0.2, 0.4, 0.6, 0.3), 3)
            end
            
            ui.pushFont(isPlayer and ui.Font.Main or ui.Font.Small)
            ui.textColored('#' .. i, rankColor)
            ui.sameLine(30)
            ui.text(entry.name)
            ui.sameLine(220)
            ui.textColored(entry.score .. ' pts', rankColor)
            
            -- Show timestamp for non-current session scores
            if entry.timestamp then
                ui.sameLine(280)
                ui.textColored(formatTimestamp(entry.timestamp), rgbm(0.7, 0.7, 0.7, 0.8))
            end
            
            ui.popFont()
        end
    else
        ui.text('No scores recorded yet')
    end
    
    ui.endOutline(rgbm(0, 0, 0, 0.3))
    ui.endTransparentWindow()
end

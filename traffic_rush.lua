-- Traffic Rush for Assetto Corsa
-- Version: 1.0

-- Configuration
local config = {
    minimumSpeed = 60,  -- Minimum speed required (km/h)
    maxLives = 3,       -- Maximum number of lives
    penaltyFirst = 0.05, -- 5% penalty on first collision
    penaltySecond = 0.15, -- 15% penalty on second collision
    uiUpdateInterval = 0.05, -- UI update interval
}

-- State variables
local state = {
    personalBest = 0,
    currentScore = 0,
    currentRank = 0,
    multipliers = {
        speed = 1.0,
        proximity = 1.0,
        combo = 1.0,
        laneChange = 1.0
    },
    livesRemaining = config.maxLives,
    collisionCount = 0,
    laneChangeCount = 0,
    lastLaneChange = 0,
    uiPosition = vec2(900, 70),
    uiMoving = false,
    uiHidden = false,
    messages = {},
    animations = {},
    isPB = false,
    timeInLanes = {0, 0, 0, 0},
    lanesUsed = 1,
    dangerouslySlowTimer = 0,
    muteSound = false,
}

-- Sound effects
local sounds = {
    collision = 'https://cdn.discordapp.com/attachments/140183723348852736/1001011172641878016/killingSpree.mp3',
    scoreUp = 'https://cdn.discordapp.com/attachments/140183723348852736/1000988999877394512/pog_noti_sound.mp3',
    newPB = 'https://www.myinstants.com/media/sounds/holy-shit.mp3',
    laneChange = 'https://cdn.discordapp.com/attachments/140183723348852736/1000988999877394512/pog_noti_sound.mp3',
    warning = 'https://cdn.discordapp.com/attachments/140183723348852736/1001011171236782160/inconceivable.mp3',
    gameOver = 'https://cdn.discordapp.com/attachments/140183723348852736/1001011170574094376/unfriggenbelievable.mp3',
}

-- Media players
local mediaPlayers = {
    sfx = ui.MediaPlayer(),
    music = ui.MediaPlayer(),
    alerts = ui.MediaPlayer()
}

-- UI components
local ui_components = {
    mainPanel = {width = 380, height = 240},
    scorePanel = {width = 360, height = 120},
    multiplierPanel = {width = 360, height = 100},
    messageArea = {width = 360, height = 200},
}

-- Colors
local colors = {
    background = rgbm(0.1, 0.1, 0.1, 0.8),
    backgroundAlt = rgbm(0.15, 0.15, 0.15, 0.9),
    accent = rgbm(0.8, 0.2, 0.3, 1.0),
    accentAlt = rgbm(0.3, 0.8, 0.2, 1.0),
    text = rgbm(1, 1, 1, 1.0),
    textDim = rgbm(0.7, 0.7, 0.7, 1.0),
    warning = rgbm(1, 0.6, 0, 1.0),
    danger = rgbm(1, 0.2, 0.2, 1.0),
    speed = rgbm(0.2, 0.8, 0.2, 1.0),
    proximity = rgbm(0.8, 0.2, 0.8, 1.0),
    combo = rgbm(0.2, 0.6, 1.0, 1.0),
    laneChange = rgbm(1.0, 0.8, 0.2, 1.0),
    pb = rgbm(0.8, 0.8, 0.2, 1.0),
}

-- Timeouts
local timeouts = {}

-- Messages
local CloseMessages = {
    'Extremely Close!',
    'Untouchable!',
    'Godlike...',
    'Legitness!'
}

local MackMessages = {
    'L A M E',
    'Who Taught You How To Drive?!?',
    'Learn To Drive...',
    'Seriously?!?',
    'T E R R I B L E',
    'How Did You Get A License???'
}

-- Traffic cars state
local carsState = {}
local trafficCars = {}

-- Function to prepare script execution
function script.prepare(dt)
    return ac.getCarState(1).speedKmh > 0
end

-- Function to add a message
function addMessage(text, color)
    table.insert(state.messages, {
        text = text,
        color = color or colors.text,
        age = 0
    })
    
    -- Keep only the most recent messages
    if #state.messages > 5 then
        table.remove(state.messages, 1)
    end
end

-- Function to add an animation
function addAnimation(text, duration, color)
    table.insert(state.animations, {
        text = text,
        color = color or colors.accent,
        age = 0,
        duration = duration or 2,
        position = vec2(0, 0),
        scale = 1.0
    })
end

-- Set timeout helper
function setTimeout(callback, delay)
    table.insert(timeouts, {
        callback = callback,
        delay = delay,
        elapsed = 0
    })
end

-- Update timeouts
function updateTimeouts(dt)
    for i = #timeouts, 1, -1 do
        local timeout = timeouts[i]
        timeout.elapsed = timeout.elapsed + dt
        
        if timeout.elapsed >= timeout.delay then
            timeout.callback()
            table.remove(timeouts, i)
        end
    end
end

-- Initialize
local timePassed = 0
local speedMessageTimer = 0
local mackMessageTimer = 0
local wheelsWarningTimeout = 0
local comboColor = 0

function script.initialize()
    -- Initialize messages
    addMessage("Welcome to Traffic Rush!", colors.text)
    addMessage("Maintain speed above " .. config.minimumSpeed .. " km/h", colors.warning)
    addMessage("Change lanes often for bonus points!", colors.accentAlt)
    addMessage("Right-click to move UI", colors.textDim)
    addMessage("Press M to toggle UI movement", colors.textDim)
    
    -- Initialize demo values for testing
    state.personalBest = 175975
    
    ac.log("Traffic Rush initialized")
end

-- Update game state
function script.update(dt)
    local player = ac.getCarState(1)
    local sim = ac.getSim()
    
    -- Initialize car states if needed
    while sim.carsCount > #carsState do
        carsState[#carsState + 1] = {}
    end
    
    -- Update timers
    timePassed = timePassed + dt
    speedMessageTimer = speedMessageTimer + dt
    mackMessageTimer = mackMessageTimer + dt
    
    -- Handle UI movement
    if ui.mouseClicked(ui.MouseButton.Right) and state.uiMoving then
        state.uiPosition = ui.mousePos()
    end
    
    -- Toggle UI movement mode
    if ac.isKeyDown(ac.KeyIndex.M) then
        if not state.keyPressed then
            state.uiMoving = not state.uiMoving
            addMessage(state.uiMoving and "UI Move Mode Enabled" or "UI Move Mode Disabled", colors.textDim)
            state.keyPressed = true
        end
    else
        state.keyPressed = false
    end
    
    -- Toggle sound mute
    if ac.isKeyDown(ac.KeyIndex.N) then
        if not state.keyPressedN then
            state.muteSound = not state.muteSound
            addMessage(state.muteSound and "Sound Off" or "Sound On", colors.textDim)
            state.keyPressedN = true
        end
    else
        state.keyPressedN = false
    end
    
    -- Toggle UI visibility
    if ac.isKeyDown(ac.KeyIndex.H) then
        if not state.keyPressedH then
            state.uiHidden = not state.uiHidden
            state.keyPressedH = true
        end
    else
        state.keyPressedH = false
    end
    
    -- Wheel out warning
    if wheelsWarningTimeout > 0 then
        wheelsWarningTimeout = wheelsWarningTimeout - dt
    elseif player.wheelsOutside > 0 then
        if wheelsWarningTimeout == 0 then
            addMessage("Car is Out Of Zone", colors.warning)
            wheelsWarningTimeout = 60
        end
    end
    
    -- Update combo meter
    local comboFadingRate = 0.5 * math.lerp(1, 0.1, math.lerpInvSat(player.speedKmh, 80, 200)) + player.wheelsOutside
    state.multipliers.combo = math.max(1, state.multipliers.combo - dt * comboFadingRate)
    
    -- Check minimum speed
    if player.speedKmh < config.minimumSpeed then
        if state.dangerouslySlowTimer > 3 then
            -- Reset score after 3 seconds of slow speed
            ac.console('Traffic Rush: ' .. state.currentScore)
            
            -- Update personal best if needed
            if state.currentScore > state.personalBest then
                state.personalBest = state.currentScore
                if not state.muteSound then
                    mediaPlayers.sfx:setSource(sounds.newPB)
                    mediaPlayers.sfx:setVolume(0.5)
                    mediaPlayers.sfx:play()
                end
                ac.sendChatMessage('Traffic Rush: New PB! ' .. state.personalBest)
            end
            
            -- Reset state
            state.multipliers.combo = 1
            state.currentScore = 0
            state.isPB = false
        else
            if state.dangerouslySlowTimer < 3 then
                if speedMessageTimer > 5 and timePassed > 1 then
                    addMessage('3 Seconds until score reset!', colors.warning)
                    speedMessageTimer = 0
                end
            end
            
            if state.dangerouslySlowTimer == 0 and timePassed > 1 then
                addMessage('Speed up!', colors.warning)
            end
        end
        
        state.dangerouslySlowTimer = state.dangerouslySlowTimer + dt
        state.multipliers.combo = 1
        return
    else
        state.dangerouslySlowTimer = 0
    end
    
    -- Check for collision with other cars
    if player.collidedWith > 0 then
        -- Handle collision
        state.collisionCount = state.collisionCount + 1
        state.livesRemaining = config.maxLives - state.collisionCount
        
        -- Apply penalties based on collision count
        if state.collisionCount == 1 then
            -- First collision: 5% penalty
            local penalty = math.floor(state.currentScore * config.penaltyFirst)
            state.currentScore = state.currentScore - penalty
            
            -- Notify player
            addMessage("Collision! -5% score penalty", colors.danger)
            
            -- Play sound
            if not state.muteSound then
                mediaPlayers.sfx:setSource(sounds.collision)
                mediaPlayers.sfx:setVolume(0.8)
                mediaPlayers.sfx:play()
            end
        elseif state.collisionCount == 2 then
            -- Second collision: 15% penalty
            local penalty = math.floor(state.currentScore * config.penaltySecond)
            state.currentScore = state.currentScore - penalty
            
            -- Notify player
            addMessage("Collision! -15% score penalty", colors.danger)
            
            -- Play sound
            if not state.muteSound then
                mediaPlayers.sfx:setSource(sounds.collision)
                mediaPlayers.sfx:setVolume(0.8)
                mediaPlayers.sfx:play()
            end
        else
            -- Third collision: Reset score
            addMessage("Game Over! Score reset after 3 collisions", colors.danger)
            addAnimation("GAME OVER", 3, colors.danger)
            
            -- Update personal best if needed
            if state.currentScore > state.personalBest then
                state.personalBest = state.currentScore
                if not state.muteSound then
                    mediaPlayers.alerts:setSource(sounds.newPB)
                    mediaPlayers.alerts:setVolume(0.8)
                    mediaPlayers.alerts:play()
                end
                ac.sendChatMessage('Traffic Rush: New PB! ' .. state.personalBest)
            end
            
            -- Reset state
            state.currentScore = 0
            state.collisionCount = 0
            state.livesRemaining = config.maxLives
            state.multipliers.speed = 1.0
            state.multipliers.proximity = 1.0
            state.multipliers.combo = 1.0
            state.multipliers.laneChange = 1.0
            
            -- Play game over sound
            if not state.muteSound then
                mediaPlayers.sfx:setSource(sounds.gameOver)
                mediaPlayers.sfx:setVolume(0.8)
                mediaPlayers.sfx:play()
            end
        end
        
        return
    end
    
    -- Process other cars (traffic and overtakes)
    for i = 2, sim.carsCount do
        local car = ac.getCarState(i)
        local state = carsState[i]
        
        if not car.active then
            state.overtaken = false
            state.collided = false
            state.drivingAlong = false
            state.nearMiss = false
            state.maxPosDot = -1
        elseif car.pos:closerToThan(player.position, 100) then
            -- Car is within range to process
            
            -- Check for collisions
            if car.collidedWith == 1 then
                state.collided = true
                addMessage("COLLISION!", colors.danger)
            end
            
            if not state.overtaken and not state.collided and state.drivingAlong then
                local posDir = (car.position - player.position):normalize()
                local posDot = math.dot(posDir, car.look)
                state.maxPosDot = math.max(state.maxPosDot, posDot)
                
                if posDot < -0.5 and state.maxPosDot > 0.5 then
                    -- Overtake detected!
                    state.currentScore = state.currentScore + math.ceil(player.speedKmh/10 * state.multipliers.combo)
                    state.multipliers.combo = state.multipliers.combo + 1
                    comboColor = comboColor + 90
                    
                    if not state.muteSound then
                        mediaPlayers.sfx:setSource(sounds.scoreUp)
                        mediaPlayers.sfx:setVolume(1)
                        mediaPlayers.sfx:play()
                    end
                    
                    addMessage('Overtake 1x', state.multipliers.combo > 50 and 1 or 0)
                    state.overtaken = true
                    
                    -- Check for close pass (near miss)
                    if car.position:closerToThan(player.position, 3) then
                        state.multipliers.combo = state.multipliers.combo + 3
                        state.multipliers.proximity = state.multipliers.proximity + 0.2
                        comboColor = comboColor + math.random(1, 90)
                        
                        if not state.muteSound then
                            mediaPlayers.sfx:setSource(sounds.scoreUp)
                            mediaPlayers.sfx:setVolume(1)
                            mediaPlayers.sfx:play()
                        end
                        
                        addMessage(CloseMessages[math.random(#CloseMessages)], colors.accent)
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
    
    -- Detect lane changes
    local currentLane = 0
    if player.position.x < -6 then
        currentLane = 1
    elseif player.position.x < -2 then
        currentLane = 2
    elseif player.position.x < 2 then
        currentLane = 3
    else
        currentLane = 4
    end
    
    if currentLane > 0 and not state.timeInLanes[currentLane] then
        state.timeInLanes[currentLane] = true
        
        -- Count lanes used
        local lanesUsed = 0
        for i = 1, 4 do
            if state.timeInLanes[i] then
                lanesUsed = lanesUsed + 1
            end
        end
        
        state.lanesUsed = lanesUsed
        
        -- Update lane change multiplier
        state.multipliers.laneChange = 1.0 + (state.lanesUsed * 0.1)
        
        -- Add message
        addMessage("Lane " .. currentLane .. " Bonus!", colors.laneChange)
        
        -- Play sound
        if not state.muteSound then
            mediaPlayers.sfx:setSource(sounds.laneChange)
            mediaPlayers.sfx:setVolume(0.8)
            mediaPlayers.sfx:play()
        end
    end
    
    -- Update speed multiplier based on current speed
    state.multipliers.speed = 1.0 + (player.speedKmh / 100)
    
    -- Simulate score increase for testing
    if timePassed % 1 < dt and state.currentScore < state.personalBest then
        state.currentScore = state.currentScore + math.ceil(player.speedKmh/10 * state.multipliers.combo)
    end
    
    -- Update messages
    for i = #state.messages, 1, -1 do
        local msg = state.messages[i]
        msg.age = msg.age + dt
        
        -- Remove old messages
        if msg.age > 5 then
            table.remove(state.messages, i)
        end
    end
    
    -- Update animations
    for i = #state.animations, 1, -1 do
        local anim = state.animations[i]
        anim.age = anim.age + dt
        
        -- Remove old animations
        if anim.age > anim.duration then
            table.remove(state.animations, i)
        end
    end
    
    -- Check for new personal best
    if state.currentScore > state.personalBest then
        if not state.isPB then
            state.personalBest = state.currentScore
            state.isPB = true
            addMessage("NEW PERSONAL BEST!", colors.pb)
            addAnimation("NEW PB", 3, colors.pb)
            
            -- Play sound
            if not state.muteSound then
                mediaPlayers.alerts:setSource(sounds.newPB)
                mediaPlayers.alerts:setVolume(0.8)
                mediaPlayers.alerts:play()
            end
            
            ac.sendChatMessage("Traffic Rush: New PB! " .. state.personalBest)
        else
            state.personalBest = state.currentScore
        end
    end
    
    -- Update combo color rotation
    comboColor = comboColor + dt * 10 * state.multipliers.combo
    if comboColor > 360 then 
        comboColor = comboColor - 360
    end
end

-- Draw UI function
function script.drawUI()
    if state.uiHidden then return end
    
    local uiState = ac.getUiState()
    updateTimeouts(uiState.dt)
    
    -- Begin main window
    ui.beginTransparentWindow("trafficScoreUI", state.uiPosition, vec2(ui_components.mainPanel.width, ui_components.mainPanel.height), true)
    
    -- Draw top bar with multipliers
    ui.pushStyleColor(ui.StyleColor.WindowBg, colors.background)
    ui.pushStyleColor(ui.StyleColor.Border, colors.accent)
    
    -- Draw the main header
    drawMultiplierHeader()
    
    ui.offsetCursorY(5)
    
    -- Draw current score
    drawScorePanel()
    
    -- Draw lives
    drawLivesPanel()
    
    -- Draw messages
    drawMessages()
    
    -- Draw animations
    drawAnimations()
    
    ui.popStyleColor(2)
    ui.endTransparentWindow()
    
    -- Draw rank/PB window
    ui.beginTransparentWindow("trafficRankUI", state.uiPosition + vec2(0, ui_components.mainPanel.height + 10), vec2(ui_components.mainPanel.width, 60), true)
    
    ui.pushStyleColor(ui.StyleColor.WindowBg, colors.background)
    ui.pushStyleColor(ui.StyleColor.Border, colors.pb)
    
    drawPBPanel()
    
    ui.popStyleColor(2)
    ui.endTransparentWindow()
end

-- Draw multiplier header
function drawMultiplierHeader()
    local headerHeight = 40
    
    -- Background
    ui.drawRectFilled(vec2(0, 0), vec2(ui_components.mainPanel.width, headerHeight), colors.backgroundAlt, 4)
    
    -- Draw each multiplier box
    local boxWidth = 80
    local boxSpacing = 10
    local startX = 10
    
    -- Speed multiplier
    drawMultiplierBox(vec2(startX, 5), boxWidth, 30, "Speed", state.multipliers.speed, colors.speed)
    
    -- Proximity multiplier
    drawMultiplierBox(vec2(startX + boxWidth + boxSpacing, 5), boxWidth, 30, "Proximity", state.multipliers.proximity, colors.proximity)
    
    -- Combo multiplier
    drawMultiplierBox(vec2(startX + (boxWidth + boxSpacing) * 2, 5), boxWidth, 30, "Combo", state.multipliers.combo, colors.combo)
    
    -- Total multiplier
    local totalMultiplier = state.multipliers.speed * state.multipliers.proximity * state.multipliers.combo * state.multipliers.laneChange
    ui.drawRectFilled(vec2(startX + (boxWidth + boxSpacing) * 3, 5), vec2(startX + (boxWidth + boxSpacing) * 4 - boxSpacing, 35), colors.accent, 4)
    
    -- Draw total multiplier text
    ui.setCursor(vec2(startX + (boxWidth + boxSpacing) * 3 + 5, 8))
    ui.pushFont(ui.Font.Small)
    ui.text(string.format("%.1fX", totalMultiplier))
    ui.popFont()
    
    -- Current time
    ui.setCursor(vec2(startX + (boxWidth + boxSpacing) * 3 + 40, 8))
    ui.pushFont(ui.Font.Small)
    ui.text(string.format("%02d:%02d", math.floor(timePassed / 60), math.floor(timePassed % 60)))
    ui.popFont()
end

-- Draw multiplier box
function drawMultiplierBox(pos, width, height, label, value, color)
    ui.drawRectFilled(pos, pos + vec2(width, height), color, 4)
    
    ui.setCursor(pos + vec2(5, 2))
    ui.pushFont(ui.Font.Small)
    ui.text(label)
    
    ui.setCursor(pos + vec2(5, 15))
    ui.pushFont(ui.Font.Normal)
    ui.text(string.format("%.1fX", value))
    ui.popFont()
end

-- Draw score panel
function drawScorePanel()
    local panelHeight = 80
    
    -- Background
    ui.drawRectFilled(vec2(10, ui.getCursorY()), vec2(ui_components.scorePanel.width, ui.getCursorY() + panelHeight), colors.backgroundAlt, 4)
    
    -- Score label
    ui.setCursor(vec2(20, ui.getCursorY() + 10))
    ui.pushFont(ui.Font.Normal)
    ui.text("SCORE")
    ui.popFont()
    
    -- Current score with animated scale if it's a new PB
    ui.setCursor(vec2(20, ui.getCursorY() + 5))
    ui.pushFont(ui.Font.Huge)
    
    -- Apply animation if it's a new personal best
    if state.isPB then
        local pulseFactor = 1.0 + math.sin(timePassed * 10) * 0.1
        ui.pushStyleVar(ui.StyleVar.Alpha, 0.8 + math.sin(timePassed * 5) * 0.2)
        ui.textColored(string.format("%d", state.currentScore), colors.pb)
        ui.popStyleVar()
    else
        ui.text(string.format("%d", state.currentScore))
    end
    ui.popFont()
    
    -- Lane bonus info
    ui.setCursor(vec2(20, ui.getCursorY() + 5))
    ui.pushFont(ui.Font.Small)
    ui.textColored(string.format("Lanes Used: %d/4 (%.1fX bonus)", state.lanesUsed, state.multipliers.laneChange), colors.laneChange)
    ui.popFont()
end

-- Draw lives panel
function drawLivesPanel()
    local lifeSize = 20
    local spacing = 5
    
    ui.setCursor(vec2(ui_components.mainPanel.width - (lifeSize + spacing) * config.maxLives - spacing, 50))
    
    -- Lives label
    ui.pushFont(ui.Font.Small)
    ui.setCursor(vec2(ui_components.mainPanel.width - (lifeSize + spacing) * config.maxLives - spacing - 40, 50))
    ui.text("LIVES")
    ui.popFont()
    
    -- Draw life icons
    for i = 1, config.maxLives do
        local pos = vec2(ui_components.mainPanel.width - (lifeSize + spacing) * (config.maxLives - i + 1), 50)
        local lifeColor = i <= state.livesRemaining and colors.accentAlt or colors.textDim
        
        ui.drawRectFilled(pos, pos + vec2(lifeSize, lifeSize), lifeColor, 4)
    end
end

-- Draw messages
function drawMessages()
    ui.setCursor(vec2(10, 160))
    
    for i = 1, #state.messages do
        local msg = state.messages[i]
        local alpha = 1.0
        
        -- Fade out old messages
        if msg.age > 3 then
            alpha = 1.0 - ((msg.age - 3) / 2)
        end
        
        -- Fade in new messages
        if msg.age < 0.3 then
            alpha = msg.age / 0.3
        end
        
        if alpha > 0 then
            local msgColor = rgbm(msg.color.r, msg.color.g, msg.color.b, msg.color.mult * alpha)
            ui.pushStyleVar(ui.StyleVar.Alpha, alpha)
            ui.textColored(msg.text, msgColor)
            ui.popStyleVar()
            ui.offsetCursorY(5)
        end
    end
end

-- Draw animations
function drawAnimations()
    for i = 1, #state.animations do
        local anim = state.animations[i]
        local progress = anim.age / anim.duration
        local alpha = 1.0
        
        -- Fade in/out
        if progress < 0.2 then
            alpha = progress / 0.2
        elseif progress > 0.8 then
            alpha = (1.0 - progress) / 0.2
        end
        
        -- Calculate position
        local centerX = ui_components.mainPanel.width / 2
        local centerY = ui_components.mainPanel.height / 2
        local offsetY = math.sin(progress * math.pi) * 30
        
        -- Calculate scale
        local scale = 1.0 + math.sin(progress * math.pi) * 0.3
        
        ui.pushFont(ui.Font.Huge)
        local textSize = ui.measureText(anim.text)
        local pos = vec2(centerX - textSize.x * scale / 2, centerY - offsetY - textSize.y * scale / 2)
        
        -- Draw shadow
        ui.pushStyleVar(ui.StyleVar.Alpha, alpha * 0.5)
        ui.setCursor(pos + vec2(2, 2))
        ui.textColored(anim.text, rgbm(0, 0, 0, anim.color.mult))
        ui.popStyleVar()
        
        -- Draw text
        ui.pushStyleVar(ui.StyleVar.Alpha, alpha)
        ui.setCursor(pos)
        ui.textColored(anim.text, rgbm(anim.color.r, anim.color.g, anim.color.b, anim.color.mult))
        ui.popStyleVar()
        ui.popFont()
    end
end

-- Draw PB panel
function drawPBPanel()
    -- Background
    ui.drawRectFilled(vec2(0, 0), vec2(ui_components.mainPanel.width, 60), colors.backgroundAlt, 4)
    
    -- PB label
    ui.setCursor(vec2(10, 10))
    ui.pushFont(ui.Font.Normal)
    ui.text("PB")
    ui.popFont()
    
    -- PB score
    ui.setCursor(vec2(50, 10))
    ui.pushFont(ui.Font.Title)
    ui.textColored(string.format("%d", state.personalBest), colors.pb)
    ui.popFont()
    
    -- Rank label
    ui.setCursor(vec2(ui_components.mainPanel.width - 100, 10))
    ui.pushFont(ui.Font.Normal)
    ui.text("#0 PLACE")
    ui.popFont()
end 

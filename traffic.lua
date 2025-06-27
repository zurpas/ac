-- traffic_complete.lua
-- Complete traffic scoring system with integrated animations
-- Author: Enhanced with AI assistance
-- Version: 2.0

-- ========== CONFIGURATION ==========

local requiredSpeed = 95
local scoreThreshold = 100  -- Score change threshold to trigger animation

-- Sound URLs (replace with your own)
local PBlink = 'https://www.myinstants.com/media/sounds/holy-shit.mp3'
local killingSpree = 'https://cdn.discordapp.com/attachments/140183723348852736/1001011172641878016/killingSpree.mp3'
local killingFrenzy = 'https://cdn.discordapp.com/attachments/140183723348852736/1001011172335702096/KillingFrenzy.mp3'
local runningRiot = 'https://cdn.discordapp.com/attachments/140183723348852736/1001011170272100352/RunningRiot.mp3'
local rampage = 'https://cdn.discordapp.com/attachments/140183723348852736/1001011169944932453/Rampage.mp3'
local untouchable = 'https://cdn.discordapp.com/attachments/140183723348852736/1001011170959954060/untouchable.mp3'
local invincible = 'https://cdn.discordapp.com/attachments/140183723348852736/1001011171974983710/invincible.mp3'
local inconcievable = 'https://cdn.discordapp.com/attachments/140183723348852736/1001011171236782160/inconceivable.mp3'
local unfriggenbelievable = 'https://cdn.discordapp.com/attachments/140183723348852736/1001011170574094376/unfriggenbelievable.mp3'
local noti = 'https://cdn.discordapp.com/attachments/140183723348852736/1000988999877394512/pog_noti_sound.mp3'

-- ========== CENTRALIZED COLOR PALETTE ==========
-- All colors sourced from this central table for easy theme tweaks

local colors = {
    -- Base colors
    background = rgbm(0.1, 0.1, 0.1, 0.95),
    dark = rgbm(0.4, 0.4, 0.4, 1),
    grey = rgbm(0.7, 0.7, 0.7, 1),
    
    -- Status colors
    success = rgbm(0.2, 0.8, 0.2, 1.0),
    warning = rgbm(1.0, 0.6, 0.0, 1.0),
    error = rgbm(1.0, 0.2, 0.2, 1.0),
    info = rgbm(0.4, 0.7, 1.0, 1.0),
    
    -- Text colors
    text = rgbm(1.0, 1.0, 1.0, 1.0),
    textDim = rgbm(0.7, 0.7, 0.7, 1.0),
    textBright = rgbm(1.2, 1.2, 1.2, 1.0),
    
    -- PB flash colors
    pbNormal = rgbm(0.7, 0.7, 0.7, 1.0),
    pbFlash = rgbm(1.0, 0.8, 0.2, 1.0),
    pbFlashBright = rgbm(1.2, 1.0, 0.4, 1.0),
    
    -- Combo colors (dynamic based on combo level)
    comboLow = rgbm(0.8, 0.8, 0.8, 1.0),
    comboMed = rgbm(0.2, 0.8, 1.0, 1.0),
    comboHigh = rgbm(1.0, 0.4, 0.8, 1.0),
    comboInsane = rgbm(1.0, 0.2, 0.2, 1.0),
    
    -- Score animation colors
    scoreNormal = rgbm(0.0, 0.8, 1.0, 1.0),
    scoreAnimating = rgbm(0.4, 1.0, 0.6, 1.0),
    
    -- Message colors
    messageDefault = rgbm(1, 1, 1, 1),
    messageSuccess = rgbm(0, 1, 0, 1),
    messageError = rgbm(1, 0, 0, 1),
    messageSpecial = rgbm(1, 0.84, 0, 1)
}

-- ========== EASING FUNCTIONS ==========

local Easing = {}

function Easing.linear(t)
    return t
end

function Easing.quadOut(t)
    return 1 - (1 - t) * (1 - t)
end

function Easing.cubicInOut(t)
    return t < 0.5 and 4 * t * t * t or 1 - math.pow(-2 * t + 2, 3) / 2
end

function Easing.quartOut(t)
    return 1 - math.pow(1 - t, 4)
end

function Easing.sineInOut(t)
    return -(math.cos(math.pi * t) - 1) / 2
end

-- ========== ANIMATION CLASSES ==========

-- Tween class for number interpolation
local Tween = {}
Tween.__index = Tween

function Tween:number(start, goal, duration, easingFn)
    local tween = {
        startValue = start,
        goalValue = goal,
        duration = duration,
        easingFunction = easingFn or Easing.linear,
        startTime = os.clock(),
        isComplete = false,
        currentValue = start
    }
    setmetatable(tween, Tween)
    return tween
end

function Tween:getValue()
    if self.isComplete then
        return self.goalValue
    end
    
    local currentTime = os.clock()
    local elapsed = currentTime - self.startTime
    local progress = math.min(elapsed / self.duration, 1.0)
    
    if progress >= 1.0 then
        self.isComplete = true
        self.currentValue = self.goalValue
        return self.goalValue
    end
    
    local easedProgress = self.easingFunction(progress)
    self.currentValue = self.startValue + (self.goalValue - self.startValue) * easedProgress
    return self.currentValue
end

function Tween:isFinished()
    return self.isComplete
end

-- AnimatedNumber class for score counters
local AnimatedNumber = {}
AnimatedNumber.__index = AnimatedNumber

function AnimatedNumber:new(initialValue, animationDuration, easingFn)
    local animNum = {
        targetValue = initialValue or 0,
        displayValue = initialValue or 0,
        animationDuration = animationDuration or 1.0,
        easingFunction = easingFn or Easing.quadOut,
        tween = nil,
        isAnimating = false,
        useCommaFormatting = true
    }
    setmetatable(animNum, AnimatedNumber)
    return animNum
end

function AnimatedNumber:setTarget(newValue)
    if newValue == self.targetValue then
        return -- No change needed
    end
    
    -- Start new tween from current display value to new target
    self.tween = Tween:number(self.displayValue, newValue, self.animationDuration, self.easingFunction)
    self.targetValue = newValue
    self.isAnimating = true
end

function AnimatedNumber:update(dt)
    if self.isAnimating and self.tween then
        self.displayValue = self.tween:getValue()
        
        if self.tween:isFinished() then
            self.isAnimating = false
            self.displayValue = self.targetValue
            self.tween = nil
        end
    end
end

function AnimatedNumber:getValue()
    return self.displayValue
end

function AnimatedNumber:getFormattedValue()
    if not self.useCommaFormatting then
        return tostring(math.floor(self.displayValue))
    end
    
    local scoreInt = math.floor(self.displayValue)
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

function AnimatedNumber:isAnimatingValue()
    return self.isAnimating
end

-- ========== GAME STATE VARIABLES ==========

-- Media players
local mediaPlayer = ui.MediaPlayer()
local mediaPlayer2 = ui.MediaPlayer()
local mediaPlayer3 = ui.MediaPlayer()

-- Audio state flags
local hasPlayedSpree = false
local hasPlayedFrenzy = false
local hasPlayedRiot = false
local hasPlayedRampage = false
local hasPlayedUntouchable = false
local hasPlayedInvincible = false
local hasPlayedInconcievable = false
local hasPlayedUnfriggenbelievable = false

-- Game state
local timePassed = 0
local speedMessageTimer = 0
local mackMessageTimer = 0
local totalScore = 0
local animatedScore = AnimatedNumber:new(0, 1.5, Easing.quartOut)
local lastScore = 0

local comboMeter = 1
local comboColor = 0
local animatedCombo = AnimatedNumber:new(1, 0.8, Easing.cubicInOut)

local dangerouslySlowTimer = 0
local carsState = {}
local wheelsWarningTimeout = 0
local personalBest = 0
local animatedPB = AnimatedNumber:new(0, 1.0, Easing.quadOut)
local lastPB = 0

-- PB Flash animation state
local pbFlashAnimation = {
    active = false,
    startTime = 0,
    duration = 2.0,
    scale = 1.0,
    colorPhase = 0
}

-- UI state
local uiCustomPos = vec2(900, 70)
local uiMoveMode = false
local lastUiMoveKeyState = false
local muteToggle = false
local lastMuteKeyState = false
local messageState = false

-- Speed warning state
local speedWarning = 0
local UIToggle = true
local LastKeyState = false

-- Messages and effects
local messages = {}
local glitter = {}
local glitterCount = 0

local MackMessages = { 'L A M E', 'Who Taught You How To Drive?!?', 'Learn To Drive...', 'Seriously?!?', 'T E R R I B L E', 'How Did You Get A License???' }
local CloseMessages = { 'Extremely Close...', 'Untouchable :o', 'Godlike...', 'Legitnessss' }

-- ========== HELPER FUNCTIONS ==========

function script.prepare(dt)
    return ac.getCarState(1).speedKmh > 60
end

-- Trigger PB Flash animation
local function triggerPBFlash()
    pbFlashAnimation.active = true
    pbFlashAnimation.startTime = os.clock()
    pbFlashAnimation.scale = 1.0
    pbFlashAnimation.colorPhase = 0
end

-- Get combo color based on combo value
local function getComboColor(combo)
    if combo < 10 then
        return colors.comboLow
    elseif combo < 50 then
        return colors.comboMed
    elseif combo < 100 then
        return colors.comboHigh
    else
        return colors.comboInsane
    end
end

-- Get combo color with HSV animation
local function getAnimatedComboColor(combo, time)
    local baseHue = comboColor + time * 10 * combo
    while baseHue > 360 do baseHue = baseHue - 360 end
    
    local saturation = math.saturate(combo / 10)
    local value = 1.0
    local alpha = math.saturate(combo / 4)
    
    return rgbm.new(hsv(baseHue, saturation, value):rgb(), alpha)
end

-- Add message to the message queue (refactored to use color palette)
function addMessage(text, mood)
    for i = math.min(#messages + 1, 4), 2, -1 do
        messages[i] = messages[i - 1]
        messages[i].targetPos = i
    end
    messages[1] = { text = text, age = 0, targetPos = 1, currentPos = 1, mood = mood }
    
    if mood == 1 then
        for i = 1, 60 do
            local dir = vec2(math.random() - 0.5, math.random() - 0.5)
            glitterCount = glitterCount + 1
            glitter[glitterCount] = {
                color = rgbm.new(hsv(math.random() * 360, 1, 1):rgb(), 1),
                pos = vec2(80, 140) + dir * vec2(40, 20),
                velocity = dir:normalize():scale(0.2 + math.random()),
                life = 0.5 + 0.5 * math.random()
            }
        end
    end
end

-- Update messages and effects
local function updateMessages(dt)
    comboColor = comboColor + dt * 10 * comboMeter
    if comboColor > 360 then comboColor = comboColor - 360 end
    
    for i = 1, #messages do
        local m = messages[i]
        m.age = m.age + dt
        m.currentPos = math.applyLag(m.currentPos, m.targetPos, 0.8, dt)
    end
    
    for i = glitterCount, 1, -1 do
        local g = glitter[i]
        g.pos:add(g.velocity)
        g.velocity.y = g.velocity.y + 0.02
        g.life = g.life - dt
        g.color.mult = math.saturate(g.life * 4)
        if g.life < 0 then
            if i < glitterCount then
                glitter[i] = glitter[glitterCount]
            end
            glitterCount = glitterCount - 1
        end
    end
    
    if comboMeter > 10 and math.random() > 0.98 then
        for i = 1, math.floor(comboMeter) do
            local dir = vec2(math.random() - 0.5, math.random() - 0.5)
            glitterCount = glitterCount + 1
            glitter[glitterCount] = {
                color = rgbm.new(hsv(math.random() * 360, 1, 1):rgb(), 1),
                pos = vec2(195, 75) + dir * vec2(40, 20),
                velocity = dir:normalize():scale(0.2 + math.random()),
                life = 0.5 + 0.5 * math.random()
            }
        end
    end
end

-- Update all animations
local function updateAnimations(dt)
    -- Update animated numbers
    animatedScore:update(dt)
    animatedPB:update(dt)
    animatedCombo:update(dt)
    
    -- Update PB flash animation
    if pbFlashAnimation.active then
        local currentTime = os.clock()
        local elapsed = currentTime - pbFlashAnimation.startTime
        local progress = elapsed / pbFlashAnimation.duration
        
        if progress >= 1.0 then
            pbFlashAnimation.active = false
            pbFlashAnimation.scale = 1.0
            pbFlashAnimation.colorPhase = 0
        else
            -- Scale animation with bounce effect
            local scaleCurve = math.sin(progress * math.pi)
            pbFlashAnimation.scale = 1.0 + scaleCurve * 0.4
            
            -- Color phase for flashing
            pbFlashAnimation.colorPhase = progress * 4  -- 4 cycles during animation
        end
    end
end

-- ========== MAIN UPDATE FUNCTION ==========

function script.update(dt)
    -- UI movement controls
    local uiMoveKeyState = ac.isKeyDown(ac.KeyIndex.B)
    if uiMoveKeyState and lastUiMoveKeyState ~= uiMoveKeyState then
        uiMoveMode = not uiMoveMode
        lastUiMoveKeyState = uiMoveKeyState
        if messageState then
            addMessage('UI Move mode Disabled', -1)
            messageState = false
        else
            addMessage('UI Move mode Enabled', -1)
            messageState = true
        end
    elseif not uiMoveKeyState then
        lastUiMoveKeyState = false
    end

    if ui.mouseClicked(ui.MouseButton.Right) then
        if uiMoveMode then
            uiCustomPos = ui.mousePos()
        end
    end

    -- Mute toggle
    local muteKeyState = ac.isKeyDown(ac.KeyIndex.M)
    if muteKeyState and lastMuteKeyState ~= muteKeyState then
        muteToggle = not muteToggle
        if messageState then
            addMessage('Sounds off', -1)
            messageState = false
        else
            addMessage('Sounds on', -1)
            messageState = true
        end
        lastMuteKeyState = muteKeyState
    elseif not muteKeyState then
        lastMuteKeyState = false
    end

    -- Initial messages
    if timePassed == 0 then
        addMessage(ac.getCarName(0), 0)
        addMessage('Made by Boon (Enhanced)', 2)
        addMessage('(Right-click to move the UI)', -1)
        addMessage('Driving Fast = More Points', -1)
        addMessage('We wish you a safe journey :)', -1)
    end

    local player = ac.getCarState(1)
    if player.engineLifeLeft < 1 then
        ac.console('Overtake: ' .. totalScore)
        return
    end

    local playerPos = player.position
    local playerDir = ac.getCameraForward()
    if ac.isKeyDown(ac.KeyIndex.Delete) and player.speedKmh < 15 then
        physics.setCarPosition(0, playerPos, playerDir)
    end

    timePassed = timePassed + dt
    speedMessageTimer = speedMessageTimer + dt
    mackMessageTimer = mackMessageTimer + dt

    -- Update animations
    updateAnimations(dt)

    -- Trigger score animation when score changes significantly
    if totalScore ~= lastScore then
        local scoreDiff = math.abs(totalScore - lastScore)
        if scoreDiff >= scoreThreshold then
            animatedScore:setTarget(totalScore)
        end
        lastScore = totalScore
    end

    -- Trigger PB animation when personal best changes
    if personalBest ~= lastPB and personalBest > lastPB then
        animatedPB:setTarget(personalBest)
        triggerPBFlash()
        lastPB = personalBest
    end

    -- Update combo animation
    animatedCombo:setTarget(comboMeter)

    local comboFadingRate = 0.5 * math.lerp(1, 0.1, math.lerpInvSat(player.speedKmh, 80, 200)) + player.wheelsOutside
    comboMeter = math.max(1, comboMeter - dt * comboFadingRate)

    local sim = ac.getSim()
    while sim.carsCount > #carsState do
        carsState[#carsState + 1] = {}
    end

    -- Wheels outside warning
    if wheelsWarningTimeout > 0 then
        wheelsWarningTimeout = wheelsWarningTimeout - dt
    elseif player.wheelsOutside > 0 then
        if wheelsWarningTimeout == 0 then
        end
        addMessage('Car is Out Of Zone', -1)
        wheelsWarningTimeout = 60
    end

    -- Speed check and score reset logic
    if player.speedKmh < requiredSpeed then
        if dangerouslySlowTimer > 3 then
            ac.console('Overtake: ' .. totalScore)
            comboMeter = 1
            totalScore = 0

            -- Reset audio flags
            hasPlayedSpree = false
            hasPlayedFrenzy = false
            hasPlayedRiot = false
            hasPlayedRampage = false
            hasPlayedUntouchable = false
            hasPlayedInvincible = false
            hasPlayedInconcievable = false
            hasPlayedUnfriggenbelievable = false
        else
            if dangerouslySlowTimer < 3 then
                if speedMessageTimer > 5 and not timePassed == 0 then
                    addMessage('3 Seconds until score reset!', -1)
                    speedMessageTimer = 0
                end
            end

            if dangerouslySlowTimer == 0 and not timePassed == 0 then
                addMessage('Speed up!', -1)
            end
        end
        
        dangerouslySlowTimer = dangerouslySlowTimer + dt
        comboMeter = 1
        
        if totalScore > personalBest and dangerouslySlowTimer > 3 then
            personalBest = totalScore
            if muteToggle then
                mediaPlayer:setSource(PBlink)
                mediaPlayer:setVolume(.5)
                mediaPlayer:play()
            else
                mediaPlayer:setSource(PBlink)
                mediaPlayer:setVolume(0)
                mediaPlayer:pause()
            end
            ac.sendChatMessage('Overtake: ' .. personalBest)
        end
        return
    else
        dangerouslySlowTimer = 0
    end

    -- Collision check
    if player.collidedWith == 0 then
        if totalScore >= personalBest then
            personalBest = totalScore
            if muteToggle then
                mediaPlayer:setSource(PBlink)
                mediaPlayer:setVolume(.5)
                mediaPlayer:play()
            else
                mediaPlayer:setSource(PBlink)
                mediaPlayer:setVolume(0)
                mediaPlayer:pause()
            end
            ac.sendChatMessage('Overtake: ' .. personalBest)
        end
        comboMeter = 1
        totalScore = 0

        -- Reset audio flags
        hasPlayedSpree = false
        hasPlayedFrenzy = false
        hasPlayedRiot = false
        hasPlayedRampage = false
        hasPlayedUntouchable = false
        hasPlayedInvincible = false
        hasPlayedInconcievable = false
        hasPlayedUnfriggenbelievable = false

        if mackMessageTimer > 1 then
            addMessage(MackMessages[math.random(1, #MackMessages)], -1)
            mackMessageTimer = 0
        end
    end

    -- Combo-based audio triggers
    if comboMeter >= 25 then
        if muteToggle then
            if not hasPlayedSpree then
                mediaPlayer2:setSource(killingSpree)
                mediaPlayer2:setVolume(.5)
                mediaPlayer2:play()
                hasPlayedSpree = true
            end
        else
            mediaPlayer2:setVolume(0)
            mediaPlayer2:pause()
        end
    end

    if comboMeter >= 50 and comboMeter <= 51 then
        if not hasPlayedFrenzy then
            if muteToggle then
                mediaPlayer2:setSource(killingFrenzy)
                mediaPlayer2:setVolume(.5)
                mediaPlayer2:play()
                hasPlayedFrenzy = true
            else
                mediaPlayer2:setVolume(0)
                mediaPlayer2:pause()
            end
        end
    end

    if comboMeter >= 75 and comboMeter <= 76 then
        if not hasPlayedRiot then
            if muteToggle then
                mediaPlayer2:setSource(runningRiot)
                mediaPlayer2:setVolume(.5)
                mediaPlayer2:play()
                hasPlayedRiot = true
            else
                mediaPlayer2:setVolume(0)
                mediaPlayer2:pause()
            end
        end
    end

    if comboMeter >= 100 and comboMeter <= 101 then
        if not hasPlayedRampage then
            if muteToggle then
                mediaPlayer2:setSource(rampage)
                mediaPlayer2:setVolume(.5)
                mediaPlayer2:play()
                hasPlayedRampage = true
            else
                mediaPlayer2:setVolume(0)
                mediaPlayer2:pause()
            end
        end
    end

    if comboMeter >= 150 and comboMeter <= 151 then
        if not hasPlayedUntouchable then
            if muteToggle then
                mediaPlayer2:setSource(untouchable)
                mediaPlayer2:setVolume(.5)
                mediaPlayer2:play()
                hasPlayedUntouchable = true
            else
                mediaPlayer2:setVolume(0)
                mediaPlayer2:pause()
            end
        end
    end

    if comboMeter >= 200 and comboMeter <= 201 then
        if not hasPlayedInvincible then
            if muteToggle then
                mediaPlayer2:setSource(invincible)
                mediaPlayer2:setVolume(.5)
                mediaPlayer2:play()
                hasPlayedInvincible = true
            else
                mediaPlayer2:setVolume(0)
                mediaPlayer2:pause()
            end
        end
    end

    if comboMeter >= 250 and comboMeter <= 251 then
        if not hasPlayedInconcievable then
            if muteToggle then
                mediaPlayer2:setSource(inconcievable)
                mediaPlayer2:setVolume(.5)
                mediaPlayer2:play()
                hasPlayedInconcievable = true
            else
                mediaPlayer2:setVolume(0)
                mediaPlayer2:pause()
            end
        end
    end

    if comboMeter >= 300 and comboMeter <= 301 then
        if not hasPlayedUnfriggenbelievable then
            if muteToggle then
                mediaPlayer2:setSource(unfriggenbelievable)
                mediaPlayer2:setVolume(.5)
                mediaPlayer2:play()
                hasPlayedUnfriggenbelievable = true
            else
                mediaPlayer2:setVolume(0)
                mediaPlayer2:pause()
            end
        end
    end

    -- Traffic detection and scoring
    for i = 2, ac.getSim().carsCount do
        local car = ac.getCarState(i)
        local state = carsState[i]

        if car.position:closerToThan(player.position, 7) then
            local drivingAlong = math.dot(car.look, player.look) > 0.2
            if not drivingAlong then
                state.drivingAlong = false

                if not state.nearMiss and car.position:closerToThan(player.position, 3) then
                    state.nearMiss = true
                end
            end

            if not state.overtaken and not state.collided and state.drivingAlong then
                local posDir = (car.position - player.position):normalize()
                local posDot = math.dot(posDir, car.look)
                state.maxPosDot = math.max(state.maxPosDot, posDot)
                if posDot < -0.5 and state.maxPosDot > 0.5 then
                    totalScore = totalScore + math.ceil(player.speedKmh/10 * comboMeter)
                    comboMeter = comboMeter + 1
                    comboColor = comboColor + 90
                    
                    if muteToggle then
                        mediaPlayer3:setSource(noti)
                        mediaPlayer3:setVolume(1)
                        mediaPlayer3:play()
                    else
                        mediaPlayer3:setSource(noti)
                        mediaPlayer3:setVolume(0)
                        mediaPlayer3:pause()
                    end

                    addMessage('Overtake 1x', comboMeter > 50 and 1 or 0)
                    state.overtaken = true

                    if car.position:closerToThan(player.position, 3) then
                        comboMeter = comboMeter + 3
                        comboColor = comboColor + math.random(1, 90)
                        comboColor = comboColor + 90
                        if muteToggle then
                            mediaPlayer3:setSource(noti)
                            mediaPlayer3:setVolume(1)
                            mediaPlayer3:play()
                        else
                            mediaPlayer3:setSource(noti)
                            mediaPlayer3:setVolume(0)
                            mediaPlayer3:pause()
                        end

                        addMessage(CloseMessages[math.random(#CloseMessages)], 2)
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
end

-- ========== UI RENDERING ==========

function script.drawUI()
    -- UI toggle
    local keyState = ac.isKeyDown(ac.KeyIndex.Control) and ac.isKeyDown(ac.KeyIndex.D)
    if keyState and LastKeyState ~= keyState then
        UIToggle = not UIToggle
        LastKeyState = keyState
    elseif not keyState then
        LastKeyState = false
    end

    if UIToggle then
        local uiState = ac.getUiState()
        updateMessages(uiState.dt)

        local speedRelative = math.saturate(math.floor(ac.getCarState(1).speedKmh) / requiredSpeed)
        speedWarning = math.applyLag(speedWarning, speedRelative < 1 and 1 or 0, 0.5, uiState.dt)

        -- Dynamic color calculation using the centralized palette
        local colorAccent = rgbm.new(hsv(speedRelative * 120, 1, 1):rgb(), 1)
        local colorCombo = getAnimatedComboColor(comboMeter, timePassed)

        local function speedMeter(ref)
            ui.drawRectFilled(ref + vec2(0, -4), ref + vec2(300, 5), colors.dark, 1)
            ui.drawLine(ref + vec2(0, -4), ref + vec2(0, 4), colors.grey, 1)
            ui.drawLine(ref + vec2(requiredSpeed, -4), ref + vec2(requiredSpeed, 4), colors.grey, 1)

            local speed = math.min(ac.getCarState(1).speedKmh, 300)
            if speed > 1 then
                ui.drawLine(ref + vec2(0, 0), ref + vec2(speed, 0), colorAccent, 4)
            end
        end

        ui.beginTransparentWindow('overtakeScore', uiCustomPos, vec2(1400, 1400), true)
        ui.beginOutline()

        ui.pushStyleVar(ui.StyleVar.Alpha, 1 - speedWarning)
        ui.pushFont(ui.Font.Title)
        ui.text('Driving Fast = More Points')
        ui.pushFont(ui.Font.Huge)
        
        -- PB display with flash animation
        local pbText = 'PB:' .. (animatedPB:isAnimatingValue() and animatedPB:getFormattedValue() or personalBest) .. ' pts'
        if pbFlashAnimation.active then
            -- Apply scale effect (visual emphasis)
            local flashColor = colors.pbFlash
            if math.sin(pbFlashAnimation.colorPhase * math.pi) > 0 then
                flashColor = colors.pbFlashBright
            end
            
            if pbFlashAnimation.scale > 1.1 then
                ui.textColored('★ ' .. pbText .. ' ★', flashColor)
            else
                ui.textColored(pbText, flashColor)
            end
        else
            ui.textColored(pbText, colors.pbNormal)
        end
        
        ui.popFont()
        ui.popStyleVar()

        speedMeter(ui.getCursor() + vec2(-9, 4))

        ui.pushFont(ui.Font.Huge)
        
        -- Score display with animation
        local scoreText = (animatedScore:isAnimatingValue() and animatedScore:getFormattedValue() or totalScore) .. ' pts'
        local scoreColor = animatedScore:isAnimatingValue() and colors.scoreAnimating or colors.scoreNormal
        ui.textColored(scoreText, scoreColor)
        
        ui.sameLine(0, 40)
        ui.beginRotation()
        
        -- Combo text with sine-based rotation
        local comboDisplayValue = animatedCombo:isAnimatingValue() and animatedCombo:getValue() or comboMeter
        local comboText = math.ceil(comboDisplayValue * 10) / 10 .. 'x'
        ui.textColored(comboText, colorCombo)
        
        -- Enhanced combo rotation based on sine of time & combo value
        local rotationAngle = 0
        if comboMeter > 20 then
            local timeComponent = math.sin(timePassed * 2) * 2
            local comboComponent = math.sin(comboMeter / 100 * math.pi) * 3
            rotationAngle = timeComponent + comboComponent
            ui.endRotation(rotationAngle)
        elseif comboMeter > 50 then
            local timeComponent = math.sin(timePassed * 3) * 3
            local comboComponent = math.sin(comboMeter / 150 * math.pi) * 4
            rotationAngle = timeComponent + comboComponent
            ui.endRotation(rotationAngle)
        elseif comboMeter > 100 then
            local timeComponent = math.sin(timePassed * 4) * 4
            local comboComponent = math.sin(comboMeter / 200 * math.pi) * 5
            rotationAngle = timeComponent + comboComponent
            ui.endRotation(rotationAngle)
        elseif comboMeter > 250 then
            local timeComponent = math.sin(timePassed * 5) * 5
            local comboComponent = math.sin(comboMeter / 300 * math.pi) * 6
            rotationAngle = timeComponent + comboComponent
            ui.endRotation(rotationAngle)
        end

        ui.popFont()
        ui.endOutline(rgbm(0, 0, 0, 0.3))

        ui.offsetCursorY(20)
        ui.pushFont(ui.Font.Title)
        local startPos = ui.getCursor()
        
        -- Message system using centralized color palette
        for i = 1, #messages do
            local m = messages[i]
            local f = math.saturate(4 - m.currentPos) * math.saturate(8 - m.age)
            ui.setCursor(startPos + vec2(20 + math.saturate(1 - m.age * 10) ^ 2 * 100, (m.currentPos - 1) * 30))
            
            local messageColor = colors.messageDefault
            if m.mood == 1 then
                messageColor = colors.messageSuccess
            elseif m.mood == -1 then
                messageColor = colors.messageError
            elseif m.mood == 2 then
                messageColor = colors.messageSpecial
            end
            
            ui.textColored(m.text, rgbm(messageColor.r, messageColor.g, messageColor.b, f))
        end
        
        -- Glitter effects
        for i = 1, glitterCount do
            local g = glitter[i]
            if g ~= nil then
                ui.drawLine(g.pos, g.pos + g.velocity * 4, g.color, 2)
            end
        end
        
        ui.popFont()
        ui.setCursor(startPos + vec2(0, 4 * 10))

        ui.pushStyleVar(ui.StyleVar.Alpha, speedWarning)
        ui.setCursorY(75)
        ui.pushFont(ui.Font.Main)
        ui.textColored('Keep speed above ' .. requiredSpeed .. ' km/h:', colorAccent)
        ui.popFont()
        ui.popStyleVar()

        ui.endTransparentWindow()
    else
        ui.text('')
    end
end

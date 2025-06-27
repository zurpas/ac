-- Author: Zurpy (Based on JBoondock's script)
-- Version: 1.0


local requiredSpeed = 95
local PBlink = 'http' .. 's://www.myinstants.com/media/sounds/holy-shit.mp3'

local killingSpree = 'http' ..
    's://cdn.discordapp.com/attachments/140183723348852736/1001011172641878016/killingSpree.mp3'

local killingFrenzy = 'http' ..
    's://cdn.discordapp.com/attachments/140183723348852736/1001011172335702096/KillingFrenzy.mp3'

local runningRiot = 'http' .. 's://cdn.discordapp.com/attachments/140183723348852736/1001011170272100352/RunningRiot.mp3'
local rampage = 'http' .. 's://cdn.discordapp.com/attachments/140183723348852736/1001011169944932453/Rampage.mp3'
local untouchable = 'http' .. 's://cdn.discordapp.com/attachments/140183723348852736/1001011170959954060/untouchable.mp3'
local invincible = 'http' .. 's://cdn.discordapp.com/attachments/140183723348852736/1001011171974983710/invincible.mp3'
local inconcievable = 'http' ..
    's://cdn.discordapp.com/attachments/140183723348852736/1001011171236782160/inconceivable.mp3'
local unfriggenbelievable = 'http' ..
    's://cdn.discordapp.com/attachments/140183723348852736/1001011170574094376/unfriggenbelievable.mp3'


local noti = 'http' .. 's://cdn.discordapp.com/attachments/140183723348852736/1000988999877394512/pog_noti_sound.mp3'
local mediaPlayer = ui.MediaPlayer()
local mediaPlayer2 = ui.MediaPlayer()
local mediaPlayer3 = ui.MediaPlayer()

local hasPlayedSpree = false
local hasPlayedFrenzy = false
local hasPlayedRiot = false
local hasPlayedRampage = false
local hasPlayedUntouchable = false
local hasPlayedInvincible = false
local hasPlayedInconcievable = false
local hasPlayedUnfriggenbelievable = false



function script.prepare(dt)
    return ac.getCarState(1).speedKmh > 60
end

local timePassed = 0
local speedMessageTimer = 0
local mackMessageTimer = 0
local totalScore = 0
local comboMeter = 1
local comboColor = 0
local dangerouslySlowTimer = 0
local carsState = {}
local wheelsWarningTimeout = 0
local personalBest = 0
local MackMessages = { 'L A M E', 'Who Taught You How To Drive?!?', 'Learn To Drive...', 'Seriously?!?', 'T E R R I B L E', 'How Did You Get A License???' }
local CloseMessages = { 'Extremely Close...', 'Untouchable :o', 'Godlike...', 'Legitnessss' }

-- UI positions for separate UI elements
local scoreUIPos = vec2(900, 70)  -- Position for main score display
local pbUIPos = vec2(50, 70)      -- Position for personal best display
local moveScoreUI = false
local movePBUI = false
local lastScoreMoveKeyState = false
local lastPBMoveKeyState = false
local playerRank = '#0 PLACE'     -- Player ranking
local showNewPB = false
local newPBTimer = 0


local muteToggle = false
local lastMuteKeyState = false
local messageState = false
function script.update(dt)

    -- UI move controls for Score UI
    local scoreMoveKeyState = ac.isKeyDown(ac.KeyIndex.B)
    if scoreMoveKeyState and lastScoreMoveKeyState ~= scoreMoveKeyState then
        moveScoreUI = not moveScoreUI
        lastScoreMoveKeyState = scoreMoveKeyState
        if moveScoreUI then
            addMessage('Score UI Move mode Enabled', -1)
        else
            addMessage('Score UI Move mode Disabled', -1)
        end
    elseif not scoreMoveKeyState then
        lastScoreMoveKeyState = false
    end

    -- UI move controls for PB UI
    local pbMoveKeyState = ac.isKeyDown(ac.KeyIndex.N)
    if pbMoveKeyState and lastPBMoveKeyState ~= pbMoveKeyState then
        movePBUI = not movePBUI
        lastPBMoveKeyState = pbMoveKeyState
        if movePBUI then
            addMessage('PB UI Move mode Enabled', -1)
        else
            addMessage('PB UI Move mode Disabled', -1)
        end
    elseif not pbMoveKeyState then
        lastPBMoveKeyState = false
    end

    -- Handle UI movement
    if ui.mouseClicked(ui.MouseButton.Right) then
        if moveScoreUI then
            scoreUIPos = ui.mousePos()
        elseif movePBUI then
            pbUIPos = ui.mousePos()
        end
    end




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


    -- Update PB display timer
    if showNewPB then
        newPBTimer = newPBTimer + dt
        if newPBTimer > 5 then
            showNewPB = false
            newPBTimer = 0
        end
    end
    
    if timePassed == 0 then
        addMessage('Welcome to ' .. ac.getCarName(0), 0)
        addMessage('Press B to move Score UI', -1)
        addMessage('Press N to move PB UI', -1)
        addMessage('Driving Fast = More Points', -1)
        addMessage('We wish you a safe journey :)', -1)
    end




    local player = ac.getCarState(0) -- Changed from 1 to 0 for player car
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



    local comboFadingRate = 0.5 * math.lerp(1, 0.1, math.lerpInvSat(player.speedKmh, 80, 200)) + player.wheelsOutside
    comboMeter = math.max(1, comboMeter - dt * comboFadingRate)

    local sim = ac.getSim()
    while sim.carsCount > #carsState do
        carsState[#carsState + 1] = {}
    end

    if wheelsWarningTimeout > 0 then
        wheelsWarningTimeout = wheelsWarningTimeout - dt
    elseif player.wheelsOutside > 0 then
        if wheelsWarningTimeout == 0 then
        end
        addMessage('Car is Out Of Zone', -1)
        wheelsWarningTimeout = 60
    end

    if player.speedKmh < requiredSpeed then

        if dangerouslySlowTimer > 3 then
            ac.console('Overtake: ' .. totalScore)
            comboMeter = 1
            totalScore = 0

            hasPlayedSpree = false
            hasPlayedFrenzy = false
            hasPlayedRiot = false
            hasPlayedRampage = false
            hasPlayedUntouchable = false
            hasPlayedInvincible = false
            hasPlayedInconcievable = false
            hasPlayedUnfriggenbelievable = false
            -- if totalScore > personalBest then
            --     personalBest = totalScore
            --     ac.sendChatMessage('Overtake: ' .. personalBest)
            -- end
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
            showNewPB = true
            newPBTimer = 0
            
            if muteToggle then
                mediaPlayer:setSource(PBlink)
                mediaPlayer:setVolume(.5)
                mediaPlayer:play()
            else
                mediaPlayer:setSource(PBlink)
                mediaPlayer:setVolume(0)
                mediaPlayer:pause()
            end
            
            -- Update rank based on score
            if personalBest > 100000 then
                playerRank = '#1 PLACE'
            elseif personalBest > 50000 then
                playerRank = '#2 PLACE'
            elseif personalBest > 10000 then
                playerRank = '#3 PLACE'
            else
                playerRank = '#4 PLACE'
            end

            ac.sendChatMessage('Overtake: ' .. personalBest)
        end

        return
    else
        dangerouslySlowTimer = 0
    end

    if player.collidedWith > 0 then  -- Changed from == 0 to > 0
        if totalScore >= personalBest then
            personalBest = totalScore
            showNewPB = true
            newPBTimer = 0
            
            if muteToggle then
                mediaPlayer:setSource(PBlink)
                mediaPlayer:setVolume(.5)
                mediaPlayer:play()
            else
                mediaPlayer:setSource(PBlink)
                mediaPlayer:setVolume(0)
                mediaPlayer:pause()
            end
            
            -- Update rank based on score
            if personalBest > 100000 then
                playerRank = '#1 PLACE'
            elseif personalBest > 50000 then
                playerRank = '#2 PLACE'
            elseif personalBest > 10000 then
                playerRank = '#3 PLACE'
            else
                playerRank = '#4 PLACE'
            end
            
            ac.sendChatMessage('Overtake: ' .. personalBest)
        end
        
        comboMeter = 1
        totalScore = 0

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







    -- local car = ac.getCarState(1)
    -- if car.pos:closerToThan(player.pos,2.5) then

    -- end

    for i = 2, ac.getSim().carsCount do
        local car = ac.getCarState(i)
        local state = carsState[i]


        -- ac.debug(car.collidedWith .. " COLLISION")

        if car.position:closerToThan(player.position, 7) then
            local drivingAlong = math.dot(car.look, player.look) > 0.2
            if not drivingAlong then
                state.drivingAlong = false

                if not state.nearMiss and car.position:closerToThan(player.position, 3) then
                    state.nearMiss = true


                end
            end

            -- if car.collidedWith == 0 and not state.collided then
            --     comboMeter = 1
            --     totalScore = 0
            --     addMessage('NOOOO!!!', 1)
            --     state.collided = true
            -- end

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

local messages = {}
local glitter = {}
local glitterCount = 0

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

local speedWarning = 0
local UIToggle = true
local LastKeyState = false
function script.drawUI()
    local keyState = ac.isKeyDown(ac.KeyIndex.Control) and ac.isKeyDown(ac.KeyIndex.D)
    if keyState and LastKeyState ~= keyState then
        UIToggle = not UIToggle
        LastKeyState = keyState
    elseif not keyState then
        LastKeyState = false
    end

    if not UIToggle then return end
    
    local uiState = ac.getUiState()
    updateMessages(uiState.dt)
    
    -- Update colors and visual elements
    local speedRelative = math.saturate(math.floor(ac.getCarState(0).speedKmh) / requiredSpeed)
    speedWarning = math.applyLag(speedWarning, speedRelative < 1 and 1 or 0, 0.5, uiState.dt)
    comboColor = comboColor + uiState.dt * 10 * comboMeter
    if comboColor > 360 then comboColor = comboColor - 360 end
    
    -- Define colors
    local purpleAccent = rgbm(0.5, 0.2, 0.8, 1)
    local darkPanel = rgbm(0.1, 0.1, 0.1, 0.9)
    local brightText = rgbm(1, 1, 1, 1)
    local redWarning = rgbm(1, 0.2, 0.2, 1)
    local goldSpecial = rgbm(1, 0.84, 0, 1)
    local colorCombo = rgbm.new(hsv(comboColor, math.saturate(comboMeter / 10), 1):rgb(),
        math.saturate(comboMeter / 4))
    
    -- Draw Score UI (main window like in image 2)
    ui.beginTransparentWindow('overtakeScore', scoreUIPos, vec2(350, 200))
    
    -- Top bar with multipliers (like in image 1)
    ui.drawRectFilled(vec2(0, 0), vec2(350, 40), darkPanel)
    
    -- Draw speed multiplier
    local speedMultiplier = math.min(math.max(math.floor(ac.getCarState(0).speedKmh / 50), 1), 3)
    ui.drawRectFilled(vec2(0, 0), vec2(80, 40), darkPanel)
    ui.setCursor(vec2(10, 10))
    ui.text(string.format("%.1fX", speedMultiplier))
    ui.setCursor(vec2(10, 25))
    ui.pushFont(ui.Font.Small)
    ui.text("Speed")
    ui.popFont()
    
    -- Draw proximity multiplier
    ui.drawRectFilled(vec2(85, 0), vec2(165, 40), darkPanel)
    ui.setCursor(vec2(95, 10))
    ui.text("1.0X")
    ui.setCursor(vec2(95, 25))
    ui.pushFont(ui.Font.Small)
    ui.text("Proximity")
    ui.popFont()
    
    -- Draw combo multiplier
    ui.drawRectFilled(vec2(170, 0), vec2(270, 40), darkPanel)
    ui.setCursor(vec2(180, 10))
    ui.textColored(string.format("%.1fX", comboMeter), colorCombo)
    ui.setCursor(vec2(180, 25))
    ui.pushFont(ui.Font.Small)
    ui.text("Combo")
    ui.popFont()
    
    -- Draw total multiplier
    local totalMultiplier = speedMultiplier * comboMeter
    ui.drawRectFilled(vec2(275, 0), vec2(350, 40), purpleAccent)
    ui.setCursor(vec2(285, 10))
    ui.text(string.format("%.1fX", totalMultiplier))
    
    -- Main score display
    ui.drawRectFilled(vec2(0, 45), vec2(350, 110), darkPanel)
    ui.setCursor(vec2(10, 55))
    
    -- Draw score with large font
    ui.pushFont(ui.Font.Huge)
    ui.text(totalScore .. " PTS")
    ui.popFont()
    
    -- Draw timer
    ui.setCursor(vec2(250, 80))
    ui.text(string.format("%02d:%02d", math.floor(timePassed / 60), math.floor(timePassed % 60)))
    
    -- Speed requirement warning
    if speedWarning > 0.1 then
        ui.drawRectFilled(vec2(0, 115), vec2(350, 150), redWarning)
        ui.setCursor(vec2(10, 125))
        ui.text('Keep speed above ' .. requiredSpeed .. ' km/h!')
    end
    
    ui.endTransparentWindow()
    
    -- Draw PB UI (like in image 3)
    ui.beginTransparentWindow('personalBestScore', pbUIPos, vec2(220, 80))
    
    -- PB Display
    ui.drawRectFilled(vec2(0, 0), vec2(220, 40), darkPanel)
    ui.setCursor(vec2(10, 10))
    ui.text("PB")
    ui.sameLine(40)
    ui.text(personalBest)
    
    -- Rank display
    ui.drawRectFilled(vec2(0, 45), vec2(220, 80), darkPanel)
    ui.setCursor(vec2(10, 52))
    ui.text(playerRank)
    
    ui.endTransparentWindow()
    
    -- Draw New PB notification if needed (like in image 1)
    if showNewPB then
        local alertX = math.floor(ui.windowSize().x / 2) - 150
        ui.beginTransparentWindow('newPBAlert', vec2(alertX, 50), vec2(300, 60))
        ui.drawRectFilled(vec2(0, 0), vec2(300, 60), purpleAccent)
        ui.setCursor(vec2(110, 20))
        ui.pushFont(ui.Font.Title)
        ui.text("NEW PB")
        ui.popFont()
        ui.endTransparentWindow()
    end
    
    -- Draw messages/alerts
    ui.pushFont(ui.Font.Title)
    local startPos = vec2(math.floor(ui.windowSize().x / 2) - 150, 120)
    for i = 1, #messages do
        local m = messages[i]
        local f = math.saturate(4 - m.currentPos) * math.saturate(8 - m.age)
        
        local messageColor
        if m.mood == 1 then
            messageColor = rgbm(0, 1, 0, f)
        elseif m.mood == -1 then
            messageColor = rgbm(1, 0, 0, f)
        elseif m.mood == 2 then
            messageColor = goldSpecial:clone()
            messageColor.mult = f
        else
            messageColor = rgbm(1, 1, 1, f)
        end
        
        ui.beginTransparentWindow('message'..i, startPos + vec2(0, (i-1)*30), vec2(300, 30))
        ui.setCursor(vec2(150 - ui.measureText(m.text).x/2, 0))
        ui.textColored(m.text, messageColor)
        ui.endTransparentWindow()
    end
    ui.popFont()
    
    -- Draw glitter effects
    for i = 1, glitterCount do
        local g = glitter[i]
        if g ~= nil then
            ui.drawLine(g.pos, g.pos + g.velocity * 4, g.color, 2)
        end
    end
end

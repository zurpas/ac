-- Traffic UI Script for Assetto Corsa
-- Author: Claude
-- Version: 1.0

-- Sound Effects (using popular free sound effect URLs as examples)
local pbSound = 'http' .. 's://cdn.freesound.org/previews/320/320181_5260872-lq.mp3' -- Achievement sound
local overtakeSound = 'http' .. 's://cdn.freesound.org/previews/446/446127_9159316-lq.mp3' -- Swoosh sound
local crashSound = 'http' .. 's://cdn.freesound.org/previews/331/331621_5548100-lq.mp3' -- Crash sound
local closeCallSound = 'http' .. 's://cdn.freesound.org/previews/554/554658_12512502-lq.mp3' -- Alert sound

-- Achievement sounds
local achievement1 = 'http' .. 's://cdn.freesound.org/previews/320/320775_5260872-lq.mp3'
local achievement2 = 'http' .. 's://cdn.freesound.org/previews/270/270402_5123851-lq.mp3' 
local achievement3 = 'http' .. 's://cdn.freesound.org/previews/270/270403_5123851-lq.mp3'
local achievement4 = 'http' .. 's://cdn.freesound.org/previews/270/270404_5123851-lq.mp3'
local achievement5 = 'http' .. 's://cdn.freesound.org/previews/513/513535_2554732-lq.mp3'

-- Media players for various sounds
local mediaPlayer = ui.MediaPlayer()
local mediaPlayer2 = ui.MediaPlayer()
local mediaPlayer3 = ui.MediaPlayer()

-- Constants
local MIN_SPEED = 80            -- Minimum speed required in km/h
local LANE_CHECK_INTERVAL = 5   -- How often to check lane changes (in seconds)
local NEAR_MISS_DISTANCE = 2.0  -- Distance in meters to count as a near miss
local COLLISION_PENALTY_1 = 0.05 -- 5% score penalty for first collision
local COLLISION_PENALTY_2 = 0.15 -- 15% score penalty for second collision
local UI_ANIMATION_SPEED = 0.8  -- UI animation smoothing factor (0-1)

-- Player state
local playerState = {}
local playersData = {}
local lanesData = {}

-- Animation and UI state
local messages = {}
local glitter = {}
local glitterCount = 0
local animations = {}
local animationId = 0

-- Default UI position
local uiCustomPos = vec2(900, 70)
local uiMoveMode = false
local lastUiMoveKeyState = false
local uiScale = 1.0
local uiToggle = true
local lastUiToggleKeyState = false

-- Sound toggle
local muteToggle = true -- Changed to true by default to enable sounds
local lastMuteKeyState = false

-- Function to initialize player state
local function initPlayerState(carIndex)
    if not playersData[carIndex] then
        playersData[carIndex] = {
            currentScore = 0,
            personalBest = 0,
            multiplier = 1.0,
            comboMeter = 1.0,
            lives = 3,
            collisions = 0,
            lastCollisionTime = 0,
            lanesUsed = {},
            lastLaneCheck = 0,
            laneDiversityBonus = 1.0,
            lastPosition = vec3(0, 0, 0),
            lastLane = 0,
            animationColor = 0,
            notifications = {},
            achievementFlags = {},
            overtaken = false,
            belowSpeedWarned = false
        }
    end
end

-- Function to determine which lane the player is in
local function getLaneIndex(x, z, track)
    -- This function would be customized for each track
    -- Basic implementation - divide track into 3 lanes based on x position
    -- Real implementation would use track boundaries and road width
    return math.floor((x + 10) / 5) % 3 + 1
end

-- Function to reset player stats after 3rd collision
local function resetPlayerStats(carIndex)
    if playersData[carIndex] then
        local data = playersData[carIndex]
        data.currentScore = 0
        data.multiplier = 1.0
        data.comboMeter = 1.0
        data.lives = 3
        data.collisions = 0
        data.lanesUsed = {}
        data.laneDiversityBonus = 1.0
        
        addMessage('Lives Reset!', carIndex, -1)
    end
end

-- Function to add a message to the UI
function addMessage(text, carIndex, mood)
    -- Only process for existing players
    if not playersData[carIndex] then return end

    -- Add message to this player's queue
    local playerMessages = playersData[carIndex].notifications
    
    -- Shift existing messages
    for i = math.min(#playerMessages + 1, 4), 2, -1 do
        playerMessages[i] = playerMessages[i - 1]
        if playerMessages[i] then -- Make sure it's not nil before accessing
            playerMessages[i].targetPos = i
        end
    end
    
    -- Add new message
    playerMessages[1] = { text = text, age = 0, targetPos = 1, currentPos = 1, mood = mood }
    
    -- Add glitter/particle effect for positive messages
    if mood == 1 then
        createGlitterEffect(carIndex, 60, vec2(80, 140))
    end
end

-- Create glitter/particle effect
function createGlitterEffect(carIndex, count, position)
    if not playersData[carIndex] then return end
    
    -- Create particles
    for i = 1, count do
        local dir = vec2(math.random() - 0.5, math.random() - 0.5)
        glitterCount = glitterCount + 1
        glitter[glitterCount] = {
            carIndex = carIndex,
            color = rgbm.new(hsv(math.random() * 360, 1, 1):rgb(), 1),
            pos = position + dir * vec2(40, 20),
            velocity = dir:normalize():scale(0.2 + math.random()),
            life = 0.5 + 0.5 * math.random()
        }
    end
end

-- Create score popup animation
function createScorePopup(carIndex, score, position)
    if not playersData[carIndex] then return end
    
    animationId = animationId + 1
    table.insert(animations, {
        id = animationId,
        carIndex = carIndex,
        text = "+" .. tostring(score),
        position = position,
        age = 0,
        maxAge = 1.5,
        startSize = 1.0,
        endSize = 2.0,
        color = rgbm.new(hsv(math.random(100, 150), 0.8, 1):rgb(), 1)
    })
end

-- Update messages and animations
local function updateAnimations(dt, carIndex)
    if not playersData[carIndex] then return end
    
    local data = playersData[carIndex]
    
    -- Update color cycling for combo multiplier
    data.animationColor = data.animationColor + dt * 10 * data.comboMeter
    if data.animationColor > 360 then 
        data.animationColor = data.animationColor - 360 
    end
    
    -- Update messages
    for i, msg in ipairs(data.notifications) do
        if msg then -- Check if message exists
            msg.age = msg.age + dt
            msg.currentPos = math.applyLag(msg.currentPos, msg.targetPos, UI_ANIMATION_SPEED, dt)
        end
    end
    
    -- Update glitter/particles
    for i = glitterCount, 1, -1 do
        local g = glitter[i]
        if g and g.carIndex == carIndex then
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
    end
    
    -- Random glitter effect for high combo meter
    if data.comboMeter > 10 and math.random() > 0.98 then
        createGlitterEffect(carIndex, math.floor(data.comboMeter), vec2(195, 75))
    end
    
    -- Update score popup animations
    for i = #animations, 1, -1 do
        local anim = animations[i]
        if anim and anim.carIndex == carIndex then
            anim.age = anim.age + dt
            if anim.age > anim.maxAge then
                table.remove(animations, i)
            end
        end
    end
end

-- Check lane diversity and update bonus
local function updateLaneDiversity(carIndex, currentTime)
    if not playersData[carIndex] then return end
    
    local data = playersData[carIndex]
    
    -- Only check lane diversity every LANE_CHECK_INTERVAL seconds
    if currentTime - data.lastLaneCheck < LANE_CHECK_INTERVAL then
        return
    end
    
    data.lastLaneCheck = currentTime
    
    -- Count number of different lanes used
    local laneCount = 0
    for _ in pairs(data.lanesUsed) do
        laneCount = laneCount + 1
    end
    
    -- Update lane diversity bonus
    if laneCount >= 3 then
        -- Significant bonus for using 3+ lanes
        data.laneDiversityBonus = 2.0
        addMessage("Lane Diversity Bonus x2!", carIndex, 1)
    elseif laneCount == 2 then
        -- Small bonus for using 2 lanes
        data.laneDiversityBonus = 1.2
    else
        -- No bonus for staying in one lane
        data.laneDiversityBonus = 1.0
    end
end

-- Handle collision events
local function handleCollision(carIndex, otherCarIndex)
    if not playersData[carIndex] then return end
    
    local data = playersData[carIndex]
    local currentTime = ac.getSim().timeMS / 1000
    
    -- Prevent multiple collisions from being counted in quick succession
    if currentTime - data.lastCollisionTime < 1.0 then
        return
    end
    
    data.lastCollisionTime = currentTime
    data.collisions = data.collisions + 1
    data.comboMeter = 1.0
    
    -- Play crash sound
    if muteToggle then
        mediaPlayer2:setSource(crashSound)
        mediaPlayer2:setVolume(0.7)
        mediaPlayer2:play()
    end
    
    -- Apply penalties based on collision count
    if data.collisions == 1 then
        -- First collision: lose 5% of score
        local penalty = math.floor(data.currentScore * COLLISION_PENALTY_1)
        data.currentScore = data.currentScore - penalty
        addMessage("Collision! -" .. tostring(penalty) .. " pts (2 lives left)", carIndex, -1)
        data.lives = 2
        
    elseif data.collisions == 2 then
        -- Second collision: lose 15% of score
        local penalty = math.floor(data.currentScore * COLLISION_PENALTY_2)
        data.currentScore = data.currentScore - penalty
        addMessage("Collision! -" .. tostring(penalty) .. " pts (1 life left)", carIndex, -1)
        data.lives = 1
        
    else
        -- Third collision: reset score to zero and reset lives
        addMessage("Game Over! Score reset", carIndex, -1)
        resetPlayerStats(carIndex)
    end
end

-- Calculate score for overtaking
local function calculateOvertakeScore(carIndex, car, otherCar)
    if not playersData[carIndex] then return 0 end
    
    local data = playersData[carIndex]
    local baseScore = math.ceil(car.speedKmh / 10)
    
    -- Apply multipliers
    local speedMultiplier = math.max(1.0, car.speedKmh / 100)
    local proximityMultiplier = 1.0
    
    -- Check proximity for near miss bonus
    local distance = car.position:distance(otherCar.position)
    if distance < NEAR_MISS_DISTANCE then
        proximityMultiplier = 2.0
        addMessage("Near miss! x2 Points", carIndex, 1)
        
        if muteToggle then
            mediaPlayer3:setSource(closeCallSound)
            mediaPlayer3:setVolume(1.0)
            mediaPlayer3:play()
        end
    end
    
    -- Calculate final score with all multipliers
    local finalMultiplier = data.comboMeter * speedMultiplier * proximityMultiplier * data.laneDiversityBonus
    local score = math.floor(baseScore * finalMultiplier)
    
    return score
end

-- Required function that runs before the script starts
function script.prepare(dt)
    -- This script should run when at least one car is present
    return true
end

-- Main update function called each frame
function script.update(dt)
    local sim = ac.getSim()
    local currentTime = sim.timeMS / 1000
    
    -- Check UI move key (B key)
    local uiMoveKeyState = ac.isKeyDown(ac.KeyIndex.B)
    if uiMoveKeyState and lastUiMoveKeyState ~= uiMoveKeyState then
        uiMoveMode = not uiMoveMode
        lastUiMoveKeyState = uiMoveKeyState
        
        if uiMoveMode then
            ac.setMessage("UI Control", "Move mode enabled (right-click to position)")
        else
            ac.setMessage("UI Control", "Move mode disabled")
        end
    elseif not uiMoveKeyState then
        lastUiMoveKeyState = false
    end
    
    -- Check for right-click to move UI
    if ui.mouseClicked(ui.MouseButton.Right) then
        if uiMoveMode then
            uiCustomPos = ui.mousePos()
        end
    end
    
    -- Check mute key (M key)
    local muteKeyState = ac.isKeyDown(ac.KeyIndex.M)
    if muteKeyState and lastMuteKeyState ~= muteKeyState then
        muteToggle = not muteToggle
        lastMuteKeyState = muteKeyState
        
        local msg = muteToggle and "Sounds on" or "Sounds off"
        ac.setMessage("Sound", msg)
    elseif not muteKeyState then
        lastMuteKeyState = false
    end
    
    -- Check UI toggle key (Ctrl+D)
    local uiToggleKeyState = ac.isKeyDown(ac.KeyIndex.Control) and ac.isKeyDown(ac.KeyIndex.D)
    if uiToggleKeyState and lastUiToggleKeyState ~= uiToggleKeyState then
        uiToggle = not uiToggle
        lastUiToggleKeyState = uiToggleKeyState
    elseif not uiToggleKeyState then
        lastUiToggleKeyState = false
    end
    
    -- Process all cars
    for carIndex = 0, sim.carsCount - 1 do
        local car = ac.getCarState(carIndex)
        
        -- Initialize player data if needed
        initPlayerState(carIndex)
        local data = playersData[carIndex]
        
        -- Skip processing if car is damaged beyond use
        if car.engineLifeLeft < 0.1 then
            data.currentScore = 0
            -- Using if instead of continue (which doesn't exist in Lua 5.1)
            goto continue_cars
        end
        
        -- Update lane data
        local currentLane = getLaneIndex(car.position.x, car.position.z, sim.track)
        if currentLane ~= data.lastLane then
            data.lanesUsed[currentLane] = true
            data.lastLane = currentLane
        end
        
        -- Check lane diversity periodically
        updateLaneDiversity(carIndex, currentTime)
        
        -- Check minimum speed requirement
        if car.speedKmh < MIN_SPEED then
            if not data.belowSpeedWarned and data.currentScore > 0 then
                addMessage("Speed too low! Maintain " .. MIN_SPEED .. "+ km/h", carIndex, -1)
                data.belowSpeedWarned = true
            end
            
            -- Gradually reduce combo meter when speed is too low
            data.comboMeter = math.max(1.0, data.comboMeter - dt * 0.5)
        else
            data.belowSpeedWarned = false
            
            -- Process interactions with other cars
            for otherCarIndex = 0, sim.carsCount - 1 do
                if otherCarIndex ~= carIndex then
                    local otherCar = ac.getCarState(otherCarIndex)
                    
                    -- Check for collisions
                    if car.collidedWith == otherCarIndex then
                        handleCollision(carIndex, otherCarIndex)
                    end
                    
                    -- Check for overtakes (only when cars are close enough)
                    if otherCar.position:closerToThan(car.position, 10) then
                        local drivingAlong = math.dot(car.look, otherCar.look) > 0.2
                        
                        if drivingAlong then
                            -- This is simplified overtake detection logic
                            local relPos = otherCar.position - car.position
                            local posDir = relPos:normalize()
                            local posDot = math.dot(posDir, otherCar.look)
                            
                            -- Car was in front, now is behind
                            if posDot < -0.5 and not data.overtaken then
                                -- Calculate score
                                local score = calculateOvertakeScore(carIndex, car, otherCar)
                                data.currentScore = data.currentScore + score
                                data.comboMeter = data.comboMeter + 0.2
                                
                                -- Create score animation
                                createScorePopup(carIndex, score, vec2(200, 100))
                                
                                -- Play overtake sound
                                if muteToggle then
                                    mediaPlayer3:setSource(overtakeSound)
                                    mediaPlayer3:setVolume(0.8)
                                    mediaPlayer3:play()
                                end
                                
                                -- Add message
                                addMessage("Overtake! +" .. score .. " pts", carIndex, 1)
                                data.overtaken = true
                                
                                -- Check for new personal best
                                if data.currentScore > data.personalBest then
                                    data.personalBest = data.currentScore
                                    
                                    -- Play personal best sound
                                    if muteToggle then
                                        mediaPlayer:setSource(pbSound)
                                        mediaPlayer:setVolume(0.6)
                                        mediaPlayer:play()
                                    end
                                    
                                    -- Broadcast achievement to chat
                                    ac.sendChatMessage("New Personal Best: " .. data.personalBest .. " pts by " .. ac.getDriverName(carIndex))
                                end
                            end
                        else
                            -- Reset overtaken flag when cars are no longer aligned
                            data.overtaken = false
                        end
                    else
                        -- Reset overtaken flag when cars are far apart
                        data.overtaken = false
                    end
                end
            end
        end
        
        -- Update animations
        updateAnimations(dt, carIndex)
        
        ::continue_cars::
    end
end

-- Draw the user interface
function script.drawUI()
    -- Skip if UI is toggled off
    if not uiToggle then return end
    
    -- Get current car index (player's car) - fixed to use car index 0
    local currentCarIndex = 0
    local car = ac.getCarState(currentCarIndex)
    
    -- Initialize this player if needed
    initPlayerState(currentCarIndex)
    
    if not playersData[currentCarIndex] then return end
    
    local data = playersData[currentCarIndex]
    local uiState = ac.getUiState()
    
    -- Start transparent window
    ui.beginTransparentWindow('trafficScore', uiCustomPos, vec2(1400, 1400), true)
    ui.beginOutline()
    
    -- Main heading
    ui.pushFont(ui.Font.Title)
    ui.text("TRAFFIC CHALLENGE")
    ui.popFont()
    
    -- Personal Best
    ui.pushFont(ui.Font.Huge)
    local pbColor = rgbm.new(hsv(data.animationColor, 0.8, 1):rgb(), 1)
    ui.textColored("PB: " .. data.personalBest .. " pts", pbColor)
    ui.popFont()
    
    -- Speed bar
    local speedRelative = math.saturate(car.speedKmh / MIN_SPEED)
    local colorSpeed = rgbm.new(hsv(speedRelative * 120, 1, 1):rgb(), 1)
    
    -- Draw speed bar background
    ui.drawRectFilled(
        ui.getCursor() + vec2(0, 5), 
        ui.getCursor() + vec2(300, 15), 
        rgbm(0.15, 0.15, 0.15, 0.8), 
        3
    )
    
    -- Draw speed bar fill
    if car.speedKmh > 1 then
        ui.drawRectFilled(
            ui.getCursor() + vec2(0, 5), 
            ui.getCursor() + vec2(math.min(car.speedKmh / MIN_SPEED * 300, 300), 15), 
            colorSpeed, 
            3
        )
    end
    
    -- Speed text
    ui.setCursor(ui.getCursor() + vec2(0, 20))
    ui.pushFont(ui.Font.Main)
    ui.textColored(math.floor(car.speedKmh) .. " km/h", colorSpeed)
    
    -- Draw minimum speed marker
    ui.setCursor(ui.getCursor() + vec2(0, -45))
    ui.drawLine(
        ui.getCursor() + vec2(MIN_SPEED / MIN_SPEED * 300, 0), 
        ui.getCursor() + vec2(MIN_SPEED / MIN_SPEED * 300, 15), 
        rgbm(1, 1, 1, 0.7), 
        2
    )
    ui.setCursor(ui.getCursor() + vec2(0, 25))
    
    -- Current score and multiplier
    ui.setCursor(ui.getCursor() + vec2(0, 10))
    ui.pushFont(ui.Font.Huge)
    ui.text(data.currentScore .. " pts")
    ui.sameLine(0, 40)
    
    -- Animated multiplier text
    ui.beginRotation()
    local comboColor = rgbm.new(hsv(data.animationColor, math.saturate(data.comboMeter / 10), 1):rgb(), math.saturate(data.comboMeter / 4))
    ui.textColored(string.format("%.1fx", data.comboMeter), comboColor)
    
    -- Rotate text based on combo meter
    local angle = 0
    if data.comboMeter > 5 then
        angle = math.sin(data.comboMeter / 180 * 3141.5) * 3 * math.min(data.comboMeter / 20, 1) + 90
    end
    ui.endRotation(angle)
    ui.popFont()
    
    -- End main UI outline
    ui.endOutline(rgbm(0, 0, 0, 0.5))
    
    -- Lives indicator
    ui.setCursor(ui.getCursor() + vec2(0, 20))
    ui.text("Lives: ")
    ui.sameLine()
    
    for i = 1, 3 do
        local lifeColor = i <= data.lives and rgbm(0, 1, 0, 1) or rgbm(0.5, 0.5, 0.5, 0.5)
        ui.drawCircleFilled(ui.getCursor() + vec2(15 * i, 0), 8, lifeColor)
        ui.sameLine()
    end
    
    -- Lane diversity indicator
    ui.setCursor(ui.getCursor() + vec2(100, 0))
    ui.text("Lane Bonus: " .. string.format("%.1fx", data.laneDiversityBonus))
    
    -- Display messages
    ui.setCursor(ui.getCursor() + vec2(0, 30))
    ui.pushFont(ui.Font.Title)
    local startPos = ui.getCursor()
    
    for i, msg in ipairs(data.notifications) do
        if msg then
            -- Calculate message opacity based on age and position
            local opacity = math.saturate(4 - msg.currentPos) * math.saturate(8 - msg.age)
            
            -- Choose color based on message mood (-1: negative, 0: neutral, 1: positive, 2: special)
            local msgColor = rgbm(1, 1, 1, opacity)
            if msg.mood == -1 then 
                msgColor = rgbm(1, 0, 0, opacity)
            elseif msg.mood == 1 then 
                msgColor = rgbm(0, 1, 0, opacity)
            elseif msg.mood == 2 then 
                msgColor = rgbm(1, 0.84, 0, opacity)
            end
            
            -- Position and animate message
            local xOffset = 20 + math.saturate(1 - msg.age * 10) ^ 2 * 100
            local yOffset = (msg.currentPos - 1) * 30
            ui.setCursor(startPos + vec2(xOffset, yOffset))
            
            -- Display message
            ui.textColored(msg.text, msgColor)
        end
    end
    ui.popFont()
    
    -- Draw glitter particles
    for i = 1, glitterCount do
        local g = glitter[i]
        if g and g.carIndex == currentCarIndex then
            ui.drawLine(g.pos, g.pos + g.velocity * 4, g.color, 2)
        end
    end
    
    -- Draw score popup animations
    for _, anim in ipairs(animations) do
        if anim and anim.carIndex == currentCarIndex then
            -- Calculate animation properties
            local progress = anim.age / anim.maxAge
            local size = math.lerp(anim.startSize, anim.endSize, progress)
            local opacity = 1 - progress
            local color = rgbm(anim.color.r, anim.color.g, anim.color.b, opacity)
            
            -- Position text with rising animation
            local pos = anim.position + vec2(0, -80 * progress)
            
            -- Draw text with scale (fixed scaling function)
            ui.pushFont(ui.Font.Huge)
            local textSize = ui.measureText(anim.text)
            ui.setCursor(pos - textSize * 0.5 * size)
            -- Use pushStyleVar instead of scaleSize which may not exist
            ui.pushStyleVar(ui.StyleVar.Scale, size)
            ui.textColored(anim.text, color)
            ui.popStyleVar()
            ui.popFont()
        end
    end
    
    -- End UI window
    ui.endTransparentWindow()
end

-- Welcome message when script loads
ac.setMessage("Traffic Challenge", "Script loaded! Press M to toggle sound, B to move UI, Ctrl+D to hide UI") 

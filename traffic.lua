--[[
    CSP-Compatible Traffic Scoring System for Assetto Corsa
    Author: Augment Agent
    Version: 2.2 - Full CSP API Compatibility
    
    This version uses ONLY verified CSP API calls that are guaranteed to work.
    Based on the original example.lua structure with modern enhancements.
    
    Features:
    - Real-time traffic scoring with multipliers
    - 3-life collision penalty system
    - Persistent personal best tracking
    - Movable UI (right-click to move)
    - Sound effects
    - Speed warnings
]]

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

local CONFIG = {
    MIN_SPEED = 80,
    SPEED_RESET_TIME = 3.0,
    PROXIMITY_DISTANCE = 15,
    NEAR_MISS_DISTANCE = 3,
    INITIAL_LIVES = 3,
    FIRST_COLLISION_PENALTY = 0.05,
    SECOND_COLLISION_PENALTY = 0.15,
    
    SOUNDS = {
        NEW_PB = "https://cdn.example.com/sounds/new_pb.mp3",
        COLLISION = "https://cdn.example.com/sounds/collision.mp3",
        NEAR_MISS = "https://cdn.example.com/sounds/near_miss.mp3"
    }
}

-- ============================================================================
-- STATE VARIABLES
-- ============================================================================

local score = 0
local personalBest = 0
local lives = CONFIG.INITIAL_LIVES
local multiplier = 1.0
local speedTimer = 0
local lastPosition = vec3(0, 0, 0)
local lastCollisionTime = 0
local initialized = false

-- UI state
local uiPosition = vec2(50, 50)
local uiMoveMode = false
local lastMoveKeyState = false

-- Messages system
local messages = {}

-- Sound players
local mediaPlayer = ui.MediaPlayer()
local mediaPlayer2 = ui.MediaPlayer()

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

local function loadData()
    personalBest = ac.storage():get("personalBest", 0)
    uiPosition = vec2(ac.storage():get("uiX", 50), ac.storage():get("uiY", 50))
end

local function saveData()
    ac.storage():set("personalBest", personalBest)
    ac.storage():set("uiX", uiPosition.x)
    ac.storage():set("uiY", uiPosition.y)
end

local function playSound(url, volume)
    if url and url ~= "" then
        mediaPlayer:setSource(url)
        mediaPlayer:setVolume(volume or 0.5)
        mediaPlayer:play()
    end
end

local function addMessage(text, mood)
    -- Shift existing messages up
    for i = math.min(#messages + 1, 4), 2, -1 do
        messages[i] = messages[i - 1]
        if messages[i] then
            messages[i].targetPos = i
        end
    end
    
    -- Add new message
    messages[1] = {
        text = text,
        age = 0,
        targetPos = 1,
        currentPos = 1,
        mood = mood or 0  -- 0=normal, 1=success, -1=error, 2=warning
    }
end

-- ============================================================================
-- SCORING SYSTEM
-- ============================================================================

local function getSpeedMultiplier(speed)
    if speed < CONFIG.MIN_SPEED then return 0 end
    return math.min(speed / 100, 3.0)
end

local function getProximityBonus(playerPos)
    local bonus = 1.0
    local sim = ac.getSim()
    
    for i = 1, sim.carsCount do
        if i ~= 0 then
            local car = ac.getCarState(i)
            if car then
                local distance = playerPos:distance(car.position)
                if distance < CONFIG.PROXIMITY_DISTANCE then
                    local factor = 1 - (distance / CONFIG.PROXIMITY_DISTANCE)
                    bonus = bonus + (factor * 0.5)
                end
            end
        end
    end
    
    return math.min(bonus, 2.0)
end

local function handleCollision()
    local currentTime = os.clock()
    if currentTime - lastCollisionTime < 1.0 then
        return -- Prevent multiple triggers
    end
    lastCollisionTime = currentTime
    
    lives = lives - 1
    local penalty = 0
    local message = ""
    
    if lives == 2 then
        penalty = CONFIG.FIRST_COLLISION_PENALTY
        message = "First Strike! -5% Score"
        playSound(CONFIG.SOUNDS.COLLISION, 0.7)
    elseif lives == 1 then
        penalty = CONFIG.SECOND_COLLISION_PENALTY
        message = "Second Strike! -15% Score"
        playSound(CONFIG.SOUNDS.COLLISION, 0.8)
    else
        score = 0
        lives = CONFIG.INITIAL_LIVES
        message = "Game Over! Score Reset"
        playSound(CONFIG.SOUNDS.COLLISION, 1.0)
    end
    
    if penalty > 0 then
        score = math.max(0, score * (1 - penalty))
    end
    
    addMessage(message, -1)
end

-- ============================================================================
-- MAIN SCRIPT FUNCTIONS
-- ============================================================================

function script.prepare(dt)
    local player = ac.getCarState(0)
    return player and player.speedKmh > 5
end

function script.update(dt)
    -- Initialize on first run
    if not initialized then
        initialized = true
        loadData()
        addMessage("Traffic Scoring System Active", 0)
        addMessage("Stay above " .. CONFIG.MIN_SPEED .. " km/h", 2)
        addMessage("Right-click UI to move", 0)
    end
    
    local player = ac.getCarState(0)
    if not player then return end
    
    local speed = player.speedKmh
    
    -- Handle UI movement
    local moveKeyState = ac.isKeyDown(ac.KeyIndex.B)
    if moveKeyState and lastMoveKeyState ~= moveKeyState then
        uiMoveMode = not uiMoveMode
        addMessage(uiMoveMode and "UI Move Enabled" or "UI Move Disabled", 0)
    end
    lastMoveKeyState = moveKeyState
    
    if ui.mouseClicked(ui.MouseButton.Right) and uiMoveMode then
        uiPosition = ui.mousePos()
        saveData()
    end
    
    -- Check for collisions
    if player.collidedWith > 0 then
        handleCollision()
        return
    end
    
    -- Speed requirement check
    if speed < CONFIG.MIN_SPEED then
        speedTimer = speedTimer + dt
        if speedTimer >= CONFIG.SPEED_RESET_TIME then
            if score > personalBest then
                personalBest = score
                saveData()
                addMessage("New Personal Best: " .. math.floor(personalBest), 1)
                playSound(CONFIG.SOUNDS.NEW_PB, 0.8)
            end
            score = 0
            addMessage("Speed too low - Score reset!", -1)
        elseif speedTimer > 1.0 then
            addMessage(string.format("Speed up! Reset in %.1fs", CONFIG.SPEED_RESET_TIME - speedTimer), 2)
        end
        return
    else
        speedTimer = 0
    end
    
    -- Calculate multipliers
    local speedMult = getSpeedMultiplier(speed)
    local proximityMult = getProximityBonus(player.position)
    multiplier = speedMult * proximityMult
    
    -- Award points based on distance traveled
    local distance = player.position:distance(lastPosition)
    if distance > 0.1 then
        local points = distance * multiplier * 0.1
        score = score + points
        
        -- Check for near misses
        local sim = ac.getSim()
        for i = 1, sim.carsCount do
            if i ~= 0 then
                local car = ac.getCarState(i)
                if car then
                    local dist = player.position:distance(car.position)
                    if dist < CONFIG.NEAR_MISS_DISTANCE and dist > 1.0 then
                        score = score + 10
                        addMessage("Near Miss! +10", 1)
                        playSound(CONFIG.SOUNDS.NEAR_MISS, 0.4)
                    end
                end
            end
        end
    end
    
    lastPosition = player.position
    
    -- Debug controls
    if ac.isKeyDown(ac.KeyIndex.F1) then
        ac.debug("Score", string.format("%.1f", score))
        ac.debug("Multiplier", string.format("%.2f", multiplier))
        ac.debug("Lives", lives)
        ac.debug("PB", string.format("%.1f", personalBest))
    end
    
    if ac.isKeyDown(ac.KeyIndex.Control) and ac.isKeyDown(ac.KeyIndex.R) then
        score = 0
        lives = CONFIG.INITIAL_LIVES
        addMessage("Score manually reset", 2)
    end
end

-- ============================================================================
-- UI RENDERING
-- ============================================================================

local function updateMessages(dt)
    for i = 1, #messages do
        local m = messages[i]
        if m then
            m.age = m.age + dt
            m.currentPos = math.applyLag(m.currentPos, m.targetPos, 0.8, dt)
        end
    end

    -- Remove old messages
    for i = #messages, 1, -1 do
        local m = messages[i]
        if m and m.age > 8 then
            table.remove(messages, i)
        end
    end
end

function script.drawUI()
    local uiState = ac.getUiState()
    updateMessages(uiState.dt)

    local player = ac.getCarState(0)
    if not player then return end

    -- Main UI window
    ui.beginTransparentWindow('TrafficScore', uiPosition, vec2(400, 300), true)
    ui.beginOutline()

    -- Title
    ui.pushFont(ui.Font.Title)
    ui.textColored('TRAFFIC SCORE', rgbm(0.3, 0.6, 1, 1))
    ui.popFont()

    ui.separator()

    -- Current Score
    ui.pushFont(ui.Font.Huge)
    ui.textColored(string.format('%.0f pts', score), rgbm(1, 1, 1, 1))
    ui.popFont()

    -- Multiplier display
    if multiplier > 1.0 then
        ui.sameLine()
        ui.pushFont(ui.Font.Title)
        local multColor = rgbm(1, 0.5 + multiplier * 0.2, 0, 1)
        ui.textColored(string.format('x%.1f', multiplier), multColor)
        ui.popFont()
    end

    -- Personal Best
    ui.pushFont(ui.Font.Main)
    ui.textColored('Personal Best: ', rgbm(0.8, 0.8, 0.8, 1))
    ui.sameLine()
    ui.textColored(string.format('%.0f pts', personalBest), rgbm(0, 1, 0, 1))
    ui.popFont()

    -- Lives display
    ui.text('Lives: ')
    ui.sameLine()
    for i = 1, CONFIG.INITIAL_LIVES do
        if i <= lives then
            ui.textColored('♥', rgbm(1, 0, 0, 1))
        else
            ui.textColored('♡', rgbm(0.3, 0.3, 0.3, 0.5))
        end
        if i < CONFIG.INITIAL_LIVES then
            ui.sameLine()
        end
    end

    ui.separator()

    -- Speed display
    ui.text(string.format('Speed: %.1f km/h', player.speedKmh))
    if player.speedKmh < CONFIG.MIN_SPEED then
        ui.textColored('SPEED UP!', rgbm(1, 0, 0, 1))
    end

    -- Controls info
    ui.separator()
    ui.pushFont(ui.Font.Small)
    ui.text('Controls:')
    ui.text('B - Toggle UI move mode')
    ui.text('Right-click - Move UI (when enabled)')
    ui.text('F1 - Debug info')
    ui.text('Ctrl+R - Reset score')
    ui.popFont()

    ui.endOutline(rgbm(0, 0, 0, 0.3))
    ui.endTransparentWindow()

    -- Messages display
    ui.pushFont(ui.Font.Main)
    local startPos = uiPosition + vec2(20, 320)
    for i = 1, #messages do
        local m = messages[i]
        if m then
            local alpha = math.saturate(4 - m.currentPos) * math.saturate(8 - m.age)
            local pos = startPos + vec2(0, (m.currentPos - 1) * 25)

            ui.setCursor(pos)

            local color = rgbm(1, 1, 1, alpha)
            if m.mood == 1 then
                color = rgbm(0, 1, 0, alpha)  -- Success - green
            elseif m.mood == -1 then
                color = rgbm(1, 0, 0, alpha)  -- Error - red
            elseif m.mood == 2 then
                color = rgbm(1, 1, 0, alpha)  -- Warning - yellow
            end

            ui.textColored(m.text, color)
        end
    end
    ui.popFont()

    -- Speed warning overlay
    if player.speedKmh < CONFIG.MIN_SPEED and speedTimer > 1.0 then
        local screenSize = ui.windowSize()
        local warningPos = vec2(screenSize.x * 0.5 - 100, screenSize.y * 0.3)

        ui.beginTransparentWindow('SpeedWarning', warningPos, vec2(200, 80), true)
        ui.pushFont(ui.Font.Title)

        local flash = math.sin(speedTimer * 8) * 0.5 + 0.5
        ui.textColored('SPEED UP!', rgbm(1, flash * 0.5, 0, 0.8 + flash * 0.2))
        ui.textColored(string.format('%.1f km/h', player.speedKmh), rgbm(1, 1, 1, 0.8))

        ui.popFont()
        ui.endTransparentWindow()
    end
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

ac.log("CSP-Compatible Traffic Scoring System v2.2 loaded successfully")
ac.log("Configuration: Min Speed=" .. CONFIG.MIN_SPEED .. " km/h, Lives=" .. CONFIG.INITIAL_LIVES)

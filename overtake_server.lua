--[[
Overtake Challenge for Assetto Corsa Traffic Server
Version 1.0.0

This script is designed to be loaded via csp_extra_options.ini on an Assetto Corsa server
with traffic. It tracks overtakes, near misses, and provides a scoring system.

To use:
1. Host this file on GitHub or another accessible URL
2. Add the URL to your csp_extra_options.ini under [SCRIPT_X] section
]]

-- Configuration
local config = {
    -- Game Settings
    difficultyMultiplier = 1.0,
    saveInterval = 10,  -- seconds
    
    -- Points and Multipliers
    basePoints = {
        overtake = 50,
        nearMiss = 100,
        laneChange = 20
    },
    
    maxMultipliers = {
        speed = 3.0,
        proximity = 2.0,
        nearMiss = 2.0,
        laneChange = 2.0
    },
    
    multiplierDecay = {
        speed = 0.01,
        proximity = 0.01,
        nearMiss = 0.01,
        laneChange = 0.01
    },
    
    -- Penalty settings
    penalties = {
        firstHit = 0.95,  -- 5% reduction
        secondHit = 0.85, -- 15% reduction
        thirdHit = 0.0    -- Reset score
    },
    
    -- Traffic Detection
    proximityThreshold = 5.0,  -- meters
    nearMissThreshold = 2.0,   -- meters
    collisionThreshold = 0.5,  -- meters
    minimumSpeed = 20.0,       -- km/h
    carTrackingRange = 100.0,  -- meters
    
    -- Debug
    debugMode = false
}

-- Player data storage (indexed by car ID)
local players = {}

-- Get or create player data
local function getPlayerData(carId)
    if not players[carId] then
        players[carId] = {
            score = 0,
            personalBest = 0,
            lives = 3,
            multipliers = {
                speed = 1.0,
                proximity = 1.0,
                nearMiss = 1.0,
                laneChange = 1.0
            },
            lastLane = 0,
            overtakenCars = {},
            lastScoreMessage = 0
        }
    end
    return players[carId]
end

-- Chat message functions
local function sendChatToPlayer(carId, message)
    ac.sendChatToPlayer(carId, message)
end

local function broadcastChat(message)
    ac.sendChat(message)
end

-- Score notification (throttled to prevent spam)
local function notifyScore(carId, points, reason)
    local playerData = getPlayerData(carId)
    local currentTime = os.time()
    
    -- Limit notifications to once per second
    if currentTime - playerData.lastScoreMessage >= 1 then
        local car = ac.getCar(carId)
        local playerName = car.driver.name
        
        -- Format message
        local pointsText = points > 0 and "+" .. points or points
        local message = playerName .. ": " .. pointsText .. " points"
        
        if reason then
            message = message .. " (" .. reason .. ")"
        end
        
        -- Personal best notification
        if playerData.score > playerData.personalBest then
            playerData.personalBest = playerData.score
            message = message .. " - NEW PERSONAL BEST: " .. playerData.score
        end
        
        -- Send to player
        sendChatToPlayer(carId, message)
        playerData.lastScoreMessage = currentTime
    end
end

-- Add points with multipliers
local function addPoints(carId, basePoints, reason)
    local playerData = getPlayerData(carId)
    
    local totalMultiplier = playerData.multipliers.speed * 
                          playerData.multipliers.proximity * 
                          playerData.multipliers.nearMiss * 
                          playerData.multipliers.laneChange
                          
    local points = math.floor(basePoints * totalMultiplier * config.difficultyMultiplier)
    playerData.score = playerData.score + points
    
    -- Notify player
    notifyScore(carId, points, reason)
    
    return points
end

-- Apply penalty
local function applyPenalty(carId, severity)
    local playerData = getPlayerData(carId)
    local oldScore = playerData.score
    
    if severity == 1 then
        -- First hit: 5% penalty
        playerData.score = math.floor(playerData.score * config.penalties.firstHit)
        playerData.lives = 2
    elseif severity == 2 then
        -- Second hit: 15% penalty
        playerData.score = math.floor(playerData.score * config.penalties.secondHit)
        playerData.lives = 1
    else
        -- Third hit: Reset score
        playerData.score = 0
        playerData.lives = 3
    end
    
    -- Calculate points lost
    local pointsLost = playerData.score - oldScore
    
    -- Notify player
    local car = ac.getCar(carId)
    local playerName = car.driver.name
    local message = playerName .. ": " .. pointsLost .. " points (Collision"
    
    if severity == 1 then
        message = message .. " - 2 lives remaining)"
    elseif severity == 2 then
        message = message .. " - 1 life remaining)"
    else
        message = message .. " - Game Over)"
    end
    
    sendChatToPlayer(carId, message)
end

-- Determine current lane (simplified - would need to be adapted to your track)
local function getCurrentLane(car)
    -- This is a very basic example - you would need to implement proper lane detection
    -- based on your track data or use data from your traffic system
    local trackPos = car.worldPosition
    local trackWidth = 12  -- Typical track width in meters with multiple lanes
    
    -- Simple calculation based on position relative to track center
    local distanceFromMiddle = trackPos.x
    
    if distanceFromMiddle < -trackWidth/4 then
        return 1  -- Left lane
    elseif distanceFromMiddle > trackWidth/4 then
        return 3  -- Right lane
    else
        return 2  -- Middle lane
    end
end

-- Check if a lane change occurred
local function checkLaneChange(carId)
    local car = ac.getCar(carId)
    local playerData = getPlayerData(carId)
    local currentLane = getCurrentLane(car)
    
    if playerData.lastLane == 0 then
        playerData.lastLane = currentLane
        return false
    end
    
    if currentLane ~= playerData.lastLane then
        -- Lane change detected
        playerData.lastLane = currentLane
        
        -- Update multiplier
        playerData.multipliers.laneChange = math.min(
            config.maxMultipliers.laneChange, 
            playerData.multipliers.laneChange + 0.1
        )
        
        -- Add points
        local points = addPoints(carId, config.basePoints.laneChange, "Lane Change")
        
        if config.debugMode then
            ac.log("Lane change detected for car " .. carId .. "! Points: " .. points)
        end
        
        return true
    end
    
    return false
end

-- Check for near misses with other cars
local function checkNearMiss(playerCarId, otherCarId)
    local playerCar = ac.getCar(playerCarId)
    local otherCar = ac.getCar(otherCarId)
    local playerData = getPlayerData(playerCarId)
    
    -- Skip if either car doesn't exist
    if not playerCar or not otherCar then
        return false
    end
    
    local playerPos = playerCar.worldPosition
    local carPos = otherCar.worldPosition
    
    -- Calculate distance
    local distance = math.sqrt((playerPos.x - carPos.x)^2 + (playerPos.z - carPos.z)^2)
    
    -- Get relative speed
    local playerSpeed = playerCar.speedKmh
    local carSpeed = otherCar.speedKmh
    local relativeSpeed = math.abs(playerSpeed - carSpeed)
    
    -- Skip if cars are too far apart or speed is too low
    if distance > config.proximityThreshold or relativeSpeed < config.minimumSpeed then
        return false
    end
    
    -- Check for collision
    if distance < config.collisionThreshold then
        -- Determine collision severity based on relative speed
        local severity = 1  -- Default: first hit
        
        if relativeSpeed > 50 then
            severity = 3    -- Major collision
        elseif relativeSpeed > 30 then
            severity = 2    -- Medium collision
        end
        
        -- Apply penalty
        applyPenalty(playerCarId, severity)
        
        if config.debugMode then
            ac.log("Collision detected between car " .. playerCarId .. 
                  " and car " .. otherCarId .. " (severity: " .. severity .. ")")
        end
        
        return true
    
    -- Check for near miss
    elseif distance < config.nearMissThreshold and 
           distance >= config.collisionThreshold and
           relativeSpeed > config.minimumSpeed then
        
        -- Calculate points based on distance and speed
        local distancePoints = math.max(0, config.basePoints.nearMiss - distance * 10)  -- Closer = more points
        local speedPoints = relativeSpeed * 0.5                  -- Faster = more points
        
        -- Update multiplier (temporary boost)
        playerData.multipliers.nearMiss = math.min(
            config.maxMultipliers.nearMiss, 
            playerData.multipliers.nearMiss + 0.1
        )
        
        -- Add points
        local points = addPoints(playerCarId, distancePoints + speedPoints, "Near Miss")
        
        if config.debugMode then
            ac.log("Near miss between car " .. playerCarId .. 
                  " and car " .. otherCarId .. "! Distance: " .. 
                  distance .. "m, Relative speed: " .. relativeSpeed .. 
                  " km/h, Points: " .. points)
        end
        
        return true
    end
    
    return false
end

-- Check for overtakes
local function checkOvertake(playerCarId, otherCarId)
    local playerCar = ac.getCar(playerCarId)
    local otherCar = ac.getCar(otherCarId)
    local playerData = getPlayerData(playerCarId)
    
    -- Skip if either car doesn't exist
    if not playerCar or not otherCar then
        return false
    end
    
    local playerPos = playerCar.worldPosition
    local carPos = otherCar.worldPosition
    
    -- Calculate longitudinal distance (along track direction)
    local playerForward = playerCar.look
    local relativePos = vec3(carPos.x - playerPos.x, carPos.y - playerPos.y, carPos.z - playerPos.z)
    local forwardDot = playerForward.x * relativePos.x + playerForward.z * relativePos.z
    
    -- Check if car is in front or behind
    local isInFront = forwardDot > 0
    
    -- Initialize tracking data for this car if not exists
    if not playerData.overtakenCars[otherCarId] then
        playerData.overtakenCars[otherCarId] = {
            lastInFront = isInFront,
            overtaken = false,
            lastSeen = os.clock()
        }
    end
    
    local carData = playerData.overtakenCars[otherCarId]
    carData.lastSeen = os.clock()  -- Update last seen time
    
    -- Detect overtake: car was in front, now it's behind
    if carData.lastInFront and not isInFront and not carData.overtaken then
        carData.overtaken = true
        
        -- Calculate difficulty based on distance and relative speed
        local distance = math.sqrt((playerPos.x - carPos.x)^2 + (playerPos.z - carPos.z)^2)
        local difficulty = math.max(1.0, 3.0 - distance / 5.0)  -- Closer = more difficult = higher score
        
        -- Update multipliers
        playerData.multipliers.speed = math.min(
            config.maxMultipliers.speed, 
            playerData.multipliers.speed + 0.05
        )
        
        -- Add points
        local points = addPoints(playerCarId, config.basePoints.overtake * difficulty, "Overtake")
        
        if config.debugMode then
            ac.log("Overtake completed by car " .. playerCarId .. 
                  " of car " .. otherCarId .. "! Difficulty: " .. 
                  difficulty .. ", Points: " .. points)
        end
        
        return true
    
    -- Reset overtaken status if the car is in front again (for multiple overtakes)
    elseif isInFront and carData.overtaken then
        carData.overtaken = false
    end
    
    -- Update tracking
    carData.lastInFront = isInFront
    
    return false
end

-- Clean up old car data
local function cleanupCarData(carId)
    local playerData = getPlayerData(carId)
    local currentTime = os.clock()
    
    for otherCarId, data in pairs(playerData.overtakenCars) do
        if currentTime - data.lastSeen > 10.0 then
            playerData.overtakenCars[otherCarId] = nil
            
            if config.debugMode then
                ac.log("Removed tracking data for car " .. otherCarId .. " (timeout)")
            end
        end
    end
end

-- Update multipliers (decay over time)
local function updateMultipliers(carId, dt)
    local playerData = getPlayerData(carId)
    
    playerData.multipliers.speed = math.max(1.0, 
        playerData.multipliers.speed - config.multiplierDecay.speed * dt)
        
    playerData.multipliers.proximity = math.max(1.0, 
        playerData.multipliers.proximity - config.multiplierDecay.proximity * dt)
        
    playerData.multipliers.nearMiss = math.max(1.0, 
        playerData.multipliers.nearMiss - config.multiplierDecay.nearMiss * dt)
        
    playerData.multipliers.laneChange = math.max(1.0, 
        playerData.multipliers.laneChange - config.multiplierDecay.laneChange * dt)
end

-- Check if a car is a traffic car
local function isTrafficCar(carId)
    -- This is a placeholder function - implement based on your traffic system
    -- For example, traffic cars might have a specific prefix in their names
    -- or use specific car models, or be controlled by AI
    
    local car = ac.getCar(carId)
    
    -- Skip if car doesn't exist
    if not car then return false end
    
    -- Check if it's AI controlled (traffic)
    if car.isAIControlled then
        return true
    end
    
    -- You might need additional checks based on your traffic system
    -- For example, if traffic cars use specific models:
    -- if car.model == "traffic_car_1" or car.model == "traffic_car_2" then
    --     return true
    -- end
    
    return false
end

-- Process interactions between players and traffic
local function processPlayerTrafficInteractions()
    local carsCount = ac.getSim().carsCount
    
    -- Check each player car
    for playerCarId = 0, carsCount - 1 do
        local playerCar = ac.getCar(playerCarId)
        
        -- Skip if car doesn't exist or isn't a player
        if not playerCar or playerCar.isAIControlled then
            goto continue_player
        end
        
        -- Update player data
        local playerData = getPlayerData(playerCarId)
        
        -- Check lane changes
        checkLaneChange(playerCarId)
        
        -- Check interactions with other cars
        for otherCarId = 0, carsCount - 1 do
            -- Skip self
            if otherCarId == playerCarId then
                goto continue_other
            end
            
            local otherCar = ac.getCar(otherCarId)
            
            -- Skip if car doesn't exist or isn't traffic
            if not otherCar or not isTrafficCar(otherCarId) then
                goto continue_other
            end
            
            -- Skip if car is too far
            if otherCar.distanceToPlayer > config.carTrackingRange then
                goto continue_other
            end
            
            -- Check for overtakes and near misses
            checkOvertake(playerCarId, otherCarId)
            checkNearMiss(playerCarId, otherCarId)
            
            ::continue_other::
        end
        
        -- Clean up old car data
        cleanupCarData(playerCarId)
        
        ::continue_player::
    end
end

-- Command handler
local function onChatMessage(message, senderCarId)
    -- Simple commands
    if message == "/score" then
        local playerData = getPlayerData(senderCarId)
        local car = ac.getCar(senderCarId)
        local playerName = car.driver.name
        
        sendChatToPlayer(senderCarId, playerName .. "'s score: " .. playerData.score .. 
                        " (Best: " .. playerData.personalBest .. ")")
        return 1
    elseif message == "/reset" then
        local playerData = getPlayerData(senderCarId)
        playerData.score = 0
        playerData.lives = 3
        
        -- Reset multipliers
        playerData.multipliers.speed = 1.0
        playerData.multipliers.proximity = 1.0
        playerData.multipliers.nearMiss = 1.0
        playerData.multipliers.laneChange = 1.0
        
        sendChatToPlayer(senderCarId, "Score reset to 0. Good luck!")
        return 1
    elseif message == "/help" then
        sendChatToPlayer(senderCarId, "Overtake Challenge Commands:")
        sendChatToPlayer(senderCarId, "/score - Show current score")
        sendChatToPlayer(senderCarId, "/reset - Reset your score")
        sendChatToPlayer(senderCarId, "/help - Show this help")
        return 1
    end
    
    return 0
end

-- Main update loop
function script.update(dt)
    -- Process player-traffic interactions
    processPlayerTrafficInteractions()
    
    -- Update multipliers for all players
    for carId, playerData in pairs(players) do
        updateMultipliers(carId, dt)
    end
end

-- Event handler for chat messages
function script.onChatMessage(message, senderCarId)
    return onChatMessage(message, senderCarId)
end

-- Initialize
function script.initialize()
    if config.debugMode then
        ac.log("Overtake Challenge initialized")
    end
    
    -- Broadcast server message
    broadcastChat("Overtake Challenge activated! Type /help for commands.")
end

ac.log("Overtake Challenge loaded. Version 1.0.0") 

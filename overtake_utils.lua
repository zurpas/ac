--[[
Overtake Challenge Utils for Assetto Corsa Traffic Server
Version 1.0.0

Utility functions for the overtake challenge script.
]]

local utils = {}

-- Calculate distance between two positions
function utils.distance(pos1, pos2)
    return math.sqrt((pos1.x - pos2.x)^2 + (pos1.z - pos2.z)^2)
end

-- Calculate relative speed in km/h
function utils.relativeSpeed(car1, car2)
    return math.abs(car1.speedKmh - car2.speedKmh)
end

-- Format time as MM:SS.mmm
function utils.formatTime(seconds)
    local minutes = math.floor(seconds / 60)
    local secs = seconds % 60
    return string.format("%02d:%05.2f", minutes, secs)
end

-- Format score with thousands separators
function utils.formatScore(score)
    local formatted = tostring(score)
    local k
    
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    
    return formatted
end

-- Get the side of the car another car is on (left, right, front, behind)
function utils.getRelativeSide(carRef, carTarget)
    if not carRef or not carTarget then
        return "unknown"
    end
    
    local refPos = carRef.position
    local targetPos = carTarget.position
    
    -- Get reference car's forward and right vectors
    local forward = carRef.look
    local right = vec3(forward.z, 0, -forward.x) -- Right is perpendicular to forward
    
    -- Calculate relative position
    local relPos = vec3(
        targetPos.x - refPos.x,
        targetPos.y - refPos.y,
        targetPos.z - refPos.z
    )
    
    -- Project onto forward and right axes
    local forwardProj = forward.x * relPos.x + forward.z * relPos.z
    local rightProj = right.x * relPos.x + right.z * relPos.z
    
    -- Determine relative position
    if math.abs(forwardProj) > math.abs(rightProj) then
        -- More along the forward axis
        if forwardProj > 0 then
            return "front"
        else
            return "behind"
        end
    else
        -- More along the right axis
        if rightProj > 0 then
            return "right"
        else
            return "left"
        end
    end
end

-- Calculate speed multiplier based on car speed
function utils.calculateSpeedMultiplier(car)
    local speed = car.speedKmh
    
    if speed < 50 then
        return 1.0
    elseif speed < 80 then
        return 1.2
    elseif speed < 120 then
        return 1.5
    elseif speed < 180 then
        return 2.0
    else
        return 3.0
    end
end

-- Calculate proximity multiplier based on distance
function utils.calculateProximityMultiplier(distance)
    if distance > 3.0 then
        return 1.0
    elseif distance > 2.0 then
        return 1.2
    elseif distance > 1.5 then
        return 1.5
    elseif distance > 1.0 then
        return 1.8
    else
        return 2.0
    end
end

-- Get lane name from lane number
function utils.getLaneName(lane)
    if lane == 1 then
        return "left"
    elseif lane == 2 then
        return "middle"
    elseif lane == 3 then
        return "right"
    else
        return "unknown"
    end
end

-- Check if car is on the road
function utils.isOnRoad(car)
    -- This is a simple implementation
    -- For more accurate results, you would need track-specific data
    return true
end

-- Calculate difficulty multiplier for scoring
function utils.calculateDifficulty(speed, proximity)
    -- Higher speed and closer proximity = higher difficulty = more points
    local speedFactor = math.max(1.0, speed / 100)
    local proximityFactor = math.max(1.0, 5.0 / proximity)
    
    return speedFactor * proximityFactor
end

return utils 

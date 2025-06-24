--[[
Overtake Challenge Utilities
Version 1.0.0

Utility functions for the Assetto Corsa Overtake Challenge
This file contains helper functions to keep the main script cleaner.
]]

local utils = {}

-- Constants for physics calculations
utils.GRAVITY = 9.81 -- m/s²

-- Format score as string with commas as thousand separators
function utils.formatScore(score)
    local formatted = tostring(score)
    local k = #formatted % 3
    
    if k == 0 then k = 3 end
    
    local result = string.sub(formatted, 1, k)
    
    for i = k + 1, #formatted, 3 do
        result = result .. "," .. string.sub(formatted, i, i + 2)
    end
    
    return result
end

-- Calculate relative speed between two cars (considering direction)
function utils.getRelativeSpeed(car1, car2)
    if not car1 or not car2 then
        return 0
    end
    
    -- Get velocity vectors
    local vel1 = car1.velocity
    local vel2 = car2.velocity
    
    -- Calculate relative velocity magnitude
    local relVelX = vel1.x - vel2.x
    local relVelY = vel1.y - vel2.y
    local relVelZ = vel1.z - vel2.z
    
    -- Convert to km/h
    local relSpeed = math.sqrt(relVelX^2 + relVelY^2 + relVelZ^2) * 3.6
    
    return relSpeed
end

-- Get the side of the car another car is on (left, right, front, behind)
function utils.getRelativeSide(carRef, carTarget)
    if not carRef or not carTarget then
        return "unknown"
    end
    
    local refPos = carRef.worldPosition
    local targetPos = carTarget.worldPosition
    
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

-- Calculate the G-forces a car is experiencing
function utils.getGForces(car)
    if not car then
        return { lateral = 0, longitudinal = 0, vertical = 0 }
    end
    
    local acceleration = car.acceleration -- in m/s²
    
    -- Convert to G (divide by standard gravity)
    local gForces = {
        lateral = acceleration.x / utils.GRAVITY,
        longitudinal = acceleration.z / utils.GRAVITY,
        vertical = acceleration.y / utils.GRAVITY
    }
    
    return gForces
end

-- Check if a car is within lane boundaries
function utils.isInLane(car, laneWidth, laneOffset)
    if not car then
        return false
    end
    
    -- Default values if not provided
    laneWidth = laneWidth or 3.5 -- meters
    laneOffset = laneOffset or 0  -- center offset
    
    -- Get car's position relative to track
    local trackPos = car.trackPosition
    
    -- Check if within lane boundaries
    -- This is a simplified version - would need to be adapted to your track
    if math.abs(trackPos.x - laneOffset) <= laneWidth / 2 then
        return true
    end
    
    return false
end

-- Determine if a player is driving in the wrong direction
function utils.isWrongWay(car)
    if not car then
        return false
    end
    
    -- Get car's forward vector and track direction
    local carForward = car.look
    local trackDir = car.trackDirection
    
    -- Calculate dot product to determine alignment
    local alignment = carForward.x * trackDir.x + carForward.z * trackDir.z
    
    -- If dot product is negative, car is going against track direction
    return alignment < 0
end

-- Calculate optimal racing line distance
function utils.racingLineDistance(car)
    if not car then
        return 0
    end
    
    -- This is a placeholder function - implement based on your track
    -- In a real implementation, you would need track-specific racing line data
    
    -- For now, just return a simplified distance from track center
    return math.abs(car.trackPosition.x)
end

-- Simple chat color coding
function utils.coloredText(text, r, g, b)
    return string.format("\\c%02X%02X%02X%s\\c", 
        math.floor(r * 255),
        math.floor(g * 255),
        math.floor(b * 255),
        text
    )
end

-- Format time in MM:SS.MS format
function utils.formatTime(timeInSeconds)
    local minutes = math.floor(timeInSeconds / 60)
    local seconds = timeInSeconds % 60
    return string.format("%02d:%05.2f", minutes, seconds)
end

-- Get car's current road surface type
function utils.getSurfaceType(car)
    if not car then
        return "unknown"
    end
    
    -- This is a simplified version - would need access to actual surface data
    -- Check if all wheels are on the same surface type
    local wheelTypes = {
        car.wheels[0].surfaceType,
        car.wheels[1].surfaceType,
        car.wheels[2].surfaceType,
        car.wheels[3].surfaceType
    }
    
    -- If all wheels are on the same surface, return that
    if wheelTypes[1] == wheelTypes[2] and wheelTypes[1] == wheelTypes[3] and wheelTypes[1] == wheelTypes[4] then
        return wheelTypes[1]
    end
    
    -- If some wheels are on different surfaces, prioritize most common
    local counts = {}
    local maxType = "unknown"
    local maxCount = 0
    
    for _, surfaceType in ipairs(wheelTypes) do
        counts[surfaceType] = (counts[surfaceType] or 0) + 1
        if counts[surfaceType] > maxCount then
            maxCount = counts[surfaceType]
            maxType = surfaceType
        end
    end
    
    return maxType
end

return utils 

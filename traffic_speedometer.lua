-- Advanced Traffic Speedometer UI for Assetto Corsa
-- Author: Claude AI
-- Version: 1.0
-- A movable speedometer with traffic information for the Within Boundaries server

-- Debug initialization
ac.debug("Traffic Speedometer", "Script loading...")
ac.console("Traffic Speedometer: Script loading...")

-- Check if we're in the correct environment
local function checkEnvironment()
    local success, result = pcall(function()
        return ac.getUI() ~= nil and ac.getCarState ~= nil
    end)
    
    if not success or not result then
        ac.console("ERROR: Traffic Speedometer script not loaded in correct environment!")
        ac.debug("Traffic Speedometer", "ERROR: Not in correct AC environment")
        return false
    end
    
    return true
end

-- Verify environment
local isValidEnvironment = checkEnvironment()
if not isValidEnvironment then
    ac.console("Traffic Speedometer: Script failed environment check. Make sure CSP is installed and properly configured.")
    ac.debug("Traffic Speedometer", "Environment check failed")
end

-- Check CSP version
local cspVersion = ac.getPatchVersionCode()
ac.debug("Traffic Speedometer", "CSP Version: " .. tostring(cspVersion))

-- UI settings
local uiPos = vec2(ac.getUI().windowSize.x * 0.75, ac.getUI().windowSize.y * 0.1)
local uiSize = vec2(200, 240)
local uiMoveMode = false
local isDragging = false
local dragOffset = vec2(0, 0)

-- Traffic detection
local MAX_TRAFFIC_DETECT_RANGE = 100  -- meters
local trafficCars = {}
local trafficAhead = 0
local trafficBehind = 0
local closestCarDistance = 999
local closestCarSpeed = 0
local closestCarRelSpeed = 0
local collisionRisk = 0
local collisionTime = 0

-- Speed data
local speedHistory = {}
local HISTORY_SIZE = 60
local avgSpeedLast30s = 0
local topSpeed = 0
local avgTrafficDensity = 0
local trafficDensityHistory = {}

-- Session data
local sessionStartTime = os.time()
local distanceTraveled = 0
local lastPos = nil
local safetyScore = 100
local nearMissCount = 0
local collisionCount = 0

-- Colors
local COLOR_BG = rgbm(0.08, 0.08, 0.1, 0.85)
local COLOR_BORDER = rgbm(0.2, 0.2, 0.25, 0.9)
local COLOR_TEXT = rgbm(0.9, 0.9, 0.9, 1)
local COLOR_HIGHLIGHT = rgbm(0.1, 0.6, 1.0, 1)
local COLOR_WARNING = rgbm(0.9, 0.5, 0, 1)
local COLOR_DANGER = rgbm(0.9, 0.1, 0.1, 1)
local COLOR_SAFE = rgbm(0.1, 0.8, 0.2, 1)

function script.prepare(dt)
    return true  -- Always run
end

-- Animation values
local warningPulse = 0
local timePassed = 0

function script.update(dt)
    -- Update timer
    timePassed = timePassed + dt
    
    -- Update position only when dragging
    if isDragging then
        local mousePos = ui.mousePos()
        uiPos = vec2(mousePos.x - dragOffset.x, mousePos.y - dragOffset.y)
    end
    
    -- Check for move mode toggle (B key)
    local moveKeyPressed = ui.keyPressed(ui.Key.B)
    if moveKeyPressed then
        uiMoveMode = not uiMoveMode
        ac.debug("Traffic Speedometer", "Move mode: " .. tostring(uiMoveMode))
    end
    
    -- Get player car state
    local player = ac.getCarState(1)
    
    -- Update speed history
    if #speedHistory >= HISTORY_SIZE then
        table.remove(speedHistory, 1)
    end
    table.insert(speedHistory, player.speedKmh)
    
    -- Calculate average speed
    local sumSpeed = 0
    for _, speed in ipairs(speedHistory) do
        sumSpeed = sumSpeed + speed
    end
    avgSpeedLast30s = sumSpeed / #speedHistory
    
    -- Update top speed
    if player.speedKmh > topSpeed then
        topSpeed = player.speedKmh
    end
    
    -- Update distance traveled
    if lastPos ~= nil then
        local dist = math.distance(lastPos, player.position)
        distanceTraveled = distanceTraveled + dist
    end
    lastPos = vec3(player.position.x, player.position.y, player.position.z)
    
    -- Scan for traffic cars
    trafficCars = {}
    trafficAhead = 0
    trafficBehind = 0
    closestCarDistance = 999
    
    for i = 2, ac.getSim().carsCount do
        local car = ac.getCarState(i)
        
        -- Skip if the car is too far
        local dist = math.distance(player.position, car.position)
        if dist <= MAX_TRAFFIC_DETECT_RANGE then
            -- Calculate if car is ahead or behind
            local relativePos = car.position - player.position
            local forwardDot = math.dot(player.look, relativePos)
            
            local trafficInfo = {
                id = i,
                distance = dist,
                speed = car.speedKmh,
                isAhead = forwardDot > 0
            }
            
            table.insert(trafficCars, trafficInfo)
            
            if forwardDot > 0 then
                trafficAhead = trafficAhead + 1
                
                -- Update closest car ahead
                if dist < closestCarDistance then
                    closestCarDistance = dist
                    closestCarSpeed = car.speedKmh
                    closestCarRelSpeed = player.speedKmh - car.speedKmh
                    
                    -- Simple collision risk calculation
                    if closestCarRelSpeed > 0 and dist < 50 then
                        -- Time to collision in seconds
                        collisionTime = dist / (closestCarRelSpeed / 3.6)
                        
                        -- Risk factor (0-1)
                        if collisionTime > 0 and collisionTime < 5 then
                            collisionRisk = 1 - (collisionTime / 5)
                            
                            -- Register near miss
                            if collisionTime < 1 and dist < 5 then
                                nearMissCount = nearMissCount + 1
                                safetyScore = math.max(0, safetyScore - 1)
                            end
                        else
                            collisionRisk = 0
                        end
                    else
                        collisionRisk = 0
                        collisionTime = 0
                    end
                end
            else
                trafficBehind = trafficBehind + 1
            end
        end
    end
    
    -- Update traffic density history
    if #trafficDensityHistory >= HISTORY_SIZE then
        table.remove(trafficDensityHistory, 1)
    end
    local currentDensity = trafficAhead + trafficBehind
    table.insert(trafficDensityHistory, currentDensity)
    
    -- Calculate average traffic density
    local sumDensity = 0
    for _, density in ipairs(trafficDensityHistory) do
        sumDensity = sumDensity + density
    end
    avgTrafficDensity = sumDensity / #trafficDensityHistory
    
    -- Update warning pulse animation
    if collisionRisk > 0 then
        warningPulse = math.abs(math.sin(timePassed * 10)) * collisionRisk
    else
        warningPulse = 0
    end
end

function script.drawUI()
    -- Skip if environment check failed
    if not isValidEnvironment then return end
    
    -- Draw UI background and border
    local borderColor = COLOR_BORDER
    local bgColor = COLOR_BG
    
    -- Apply warning pulse effect
    if collisionRisk > 0 then
        borderColor = rgbm.lerprgb(COLOR_BORDER, COLOR_DANGER, warningPulse)
        bgColor = rgbm.lerprgb(COLOR_BG, rgbm(0.2, 0.05, 0.05, 0.85), warningPulse)
    end
    
    -- Draw background
    ui.drawRectFilled(uiPos, uiPos + uiSize, bgColor)
    
    -- Draw fancy border with different thickness based on risk
    local borderThickness = 1 + math.floor(warningPulse * 2)
    ui.drawRect(uiPos, uiPos + uiSize, borderColor, borderThickness)
    
    -- Title bar with drag handle
    local titleBarHeight = 25
    local titleBarColor = rgbm.lerprgb(rgbm(0.15, 0.15, 0.2, 0.9), COLOR_DANGER, warningPulse)
    ui.drawRectFilled(uiPos, vec2(uiPos.x + uiSize.x, uiPos.y + titleBarHeight), titleBarColor)
    
    -- Title text
    ui.pushFont(ui.Font.Medium)
    local titleText = "Traffic Radar"
    local titleWidth = ui.measureText(titleText).x
    ui.setCursor(vec2(uiPos.x + (uiSize.x / 2) - (titleWidth / 2), uiPos.y + 3))
    ui.text(titleText)
    ui.popFont()
    
    -- Current speed (large display)
    local player = ac.getCarState(1)
    local speedText = string.format("%d", math.floor(player.speedKmh))
    
    ui.pushFont(ui.Font.Huge)
    local speedWidth = ui.measureText(speedText).x
    ui.setCursor(vec2(uiPos.x + (uiSize.x / 2) - (speedWidth / 2), uiPos.y + 30))
    
    -- Change color based on speed
    local speedColor = COLOR_TEXT
    if player.speedKmh > 180 then
        speedColor = COLOR_DANGER
    elseif player.speedKmh > 130 then
        speedColor = COLOR_WARNING
    elseif player.speedKmh > 80 then
        speedColor = COLOR_HIGHLIGHT
    end
    
    ui.textColored(speedText, speedColor)
    ui.popFont()
    
    -- KMH label
    ui.pushFont(ui.Font.Small)
    ui.setCursor(vec2(uiPos.x + (uiSize.x / 2) - 10, uiPos.y + 70))
    ui.text("KM/H")
    ui.popFont()
    
    -- Traffic information
    local infoY = uiPos.y + 90
    local infoX = uiPos.x + 10
    local colWidth = 90
    
    -- Traffic count indicators
    ui.setCursor(vec2(infoX, infoY))
    ui.text("Traffic Ahead:")
    ui.setCursor(vec2(infoX + colWidth, infoY))
    ui.textColored(tostring(trafficAhead), trafficAhead > 3 and COLOR_WARNING or COLOR_TEXT)
    
    ui.setCursor(vec2(infoX, infoY + 20))
    ui.text("Traffic Behind:")
    ui.setCursor(vec2(infoX + colWidth, infoY + 20))
    ui.textColored(tostring(trafficBehind), COLOR_TEXT)
    
    -- Closest car information (if any car is detected ahead)
    if closestCarDistance < 100 then
        ui.setCursor(vec2(infoX, infoY + 45))
        ui.text("Closest Car:")
        ui.setCursor(vec2(infoX + colWidth, infoY + 45))
        
        local distColor = COLOR_SAFE
        if closestCarDistance < 10 then
            distColor = COLOR_DANGER
        elseif closestCarDistance < 30 then
            distColor = COLOR_WARNING
        end
        
        ui.textColored(string.format("%.0fm", closestCarDistance), distColor)
        
        -- Relative speed
        ui.setCursor(vec2(infoX, infoY + 65))
        ui.text("Closing Speed:")
        ui.setCursor(vec2(infoX + colWidth, infoY + 65))
        
        local relSpeedColor = COLOR_TEXT
        if closestCarRelSpeed > 50 then
            relSpeedColor = COLOR_DANGER
        elseif closestCarRelSpeed > 20 then
            relSpeedColor = COLOR_WARNING
        elseif closestCarRelSpeed < 0 then
            relSpeedColor = COLOR_SAFE
        end
        
        ui.textColored(string.format("%+.0f", closestCarRelSpeed), relSpeedColor)
        
        -- Collision warning
        if collisionRisk > 0 then
            local warningText = "SLOW DOWN!"
            if collisionTime < 1.5 then
                warningText = "BRAKE NOW!"
            end
            
            ui.pushFont(ui.Font.Medium)
            local warnWidth = ui.measureText(warningText).x
            ui.setCursor(vec2(uiPos.x + (uiSize.x / 2) - (warnWidth / 2), infoY + 85))
            
            -- Pulsing warning color
            local warningColor = rgbm.lerprgb(COLOR_WARNING, COLOR_DANGER, warningPulse)
            ui.textColored(warningText, warningColor)
            ui.popFont()
        end
    end
    
    -- Session stats (bottom section)
    local statsY = infoY + 110
    
    -- Draw divider line
    ui.drawLine(
        vec2(uiPos.x + 10, statsY),
        vec2(uiPos.x + uiSize.x - 10, statsY),
        rgbm(0.3, 0.3, 0.4, 0.8)
    )
    
    -- Session stats title
    ui.pushFont(ui.Font.Small)
    ui.setCursor(vec2(uiPos.x + 10, statsY + 5))
    ui.text("SESSION STATS")
    ui.popFont()
    
    -- Stats data
    ui.setCursor(vec2(infoX, statsY + 20))
    ui.text("Distance:")
    ui.setCursor(vec2(infoX + colWidth, statsY + 20))
    ui.textColored(string.format("%.1f km", distanceTraveled / 1000), COLOR_HIGHLIGHT)
    
    ui.setCursor(vec2(infoX, statsY + 35))
    ui.text("Top Speed:")
    ui.setCursor(vec2(infoX + colWidth, statsY + 35))
    ui.textColored(string.format("%d km/h", math.floor(topSpeed)), 
                  topSpeed > 180 and COLOR_DANGER or COLOR_HIGHLIGHT)
    
    ui.setCursor(vec2(infoX, statsY + 50))
    ui.text("Safety Score:")
    ui.setCursor(vec2(infoX + colWidth, statsY + 50))
    
    local safetyColor = COLOR_SAFE
    if safetyScore < 70 then
        safetyColor = COLOR_DANGER
    elseif safetyScore < 90 then
        safetyColor = COLOR_WARNING
    end
    
    ui.textColored(string.format("%d", safetyScore), safetyColor)
    
    -- Move mode indicator / instructions
    if uiMoveMode then
        ui.setCursor(vec2(uiPos.x + 5, uiPos.y + uiSize.y - 15))
        ui.pushFont(ui.Font.Small)
        ui.textColored("CLICK & DRAG TO MOVE - PRESS B TO EXIT", COLOR_HIGHLIGHT)
        ui.popFont()
    end
    
    -- Handle mouse interactions
    if uiMoveMode then
        local mousePos = ui.mousePos()
        local isHovered = mousePos.x >= uiPos.x and mousePos.x <= uiPos.x + uiSize.x and
                          mousePos.y >= uiPos.y and mousePos.y <= uiPos.y + uiSize.y
        
        -- Handle drag start
        if isHovered and ui.mouseClicked(ui.MouseButton.Left) and not isDragging then
            isDragging = true
            dragOffset = vec2(mousePos.x - uiPos.x, mousePos.y - uiPos.y)
        end
        
        -- Handle drag end
        if not ui.mouseDown(ui.MouseButton.Left) and isDragging then
            isDragging = false
        end
    end
end 
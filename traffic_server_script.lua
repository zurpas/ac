-- Server-side companion script for Traffic Server
-- This handles server-side logic and multiplayer synchronization

-- Server data storage
local serverData = {
    playerScores = {},
    leaderboard = {},
    serverStats = {
        totalPlayers = 0,
        activeSession = true,
        sessionStartTime = 0
    }
}

-- Initialize server
function script.prepare()
    serverData.serverStats.sessionStartTime = os.time()
    ac.log("Traffic Server: Server-side script initialized")
end

-- Handle player connections
function script.carConnected(carID)
    local car = ac.getCar(carID)
    if car then
        serverData.playerScores[carID] = {
            playerName = ac.getDriverName(carID),
            currentScore = 0,
            personalBest = 0,
            lives = 3,
            collisions = 0,
            sessionTime = 0,
            connected = true
        }
        
        serverData.serverStats.totalPlayers = serverData.serverStats.totalPlayers + 1
        
        -- Send welcome message to player
        local welcomeData = {
            type = "welcome",
            message = "Welcome to Traffic Server!",
            serverTime = os.time() - serverData.serverStats.sessionStartTime
        }
        
        ac.sendChatMessage(carID, "Traffic Server: Welcome! Press F7 to toggle UI, F8 to reset score.")
        
        ac.log("Traffic Server: Player " .. ac.getDriverName(carID) .. " connected")
    end
end

-- Handle player disconnections
function script.carDisconnected(carID)
    if serverData.playerScores[carID] then
        serverData.playerScores[carID].connected = false
        ac.log("Traffic Server: Player " .. ac.getDriverName(carID) .. " disconnected")
    end
end

-- Main server update loop
function script.update(dt)
    updateServerLogic(dt)
    updateLeaderboard()
    handleServerMessages()
end

-- Update server-side logic
function updateServerLogic(dt)
    -- Update session time for all connected players
    for carID, playerData in pairs(serverData.playerScores) do
        if playerData.connected then
            playerData.sessionTime = playerData.sessionTime + dt
        end
    end
    
    -- Clean up disconnected players after 5 minutes
    local currentTime = os.time()
    for carID, playerData in pairs(serverData.playerScores) do
        if not playerData.connected and (currentTime - playerData.disconnectTime or 0) > 300 then
            serverData.playerScores[carID] = nil
        end
    end
end

-- Update and maintain leaderboard
function updateLeaderboard()
    local leaderboard = {}
    
    for carID, playerData in pairs(serverData.playerScores) do
        if playerData.connected and playerData.personalBest > 0 then
            table.insert(leaderboard, {
                carID = carID,
                name = playerData.playerName,
                score = playerData.personalBest,
                currentScore = playerData.currentScore,
                lives = playerData.lives
            })
        end
    end
    
    -- Sort by personal best score
    table.sort(leaderboard, function(a, b)
        return a.score > b.score
    end)
    
    serverData.leaderboard = leaderboard
end

-- Handle messages from clients
function script.clientMessage(carID, data)
    if not serverData.playerScores[carID] then return end
    
    local messageData = ac.parseJSON(data)
    if not messageData then return end
    
    if messageData.type == "scoreUpdate" then
        handleScoreUpdate(carID, messageData)
    elseif messageData.type == "collision" then
        handleCollision(carID, messageData)
    elseif messageData.type == "requestLeaderboard" then
        sendLeaderboard(carID)
    end
end

-- Handle score updates from clients
function handleScoreUpdate(carID, data)
    local playerData = serverData.playerScores[carID]
    if not playerData then return end
    
    playerData.currentScore = data.currentScore or 0
    playerData.lives = data.lives or 3
    
    -- Update personal best
    if playerData.currentScore > playerData.personalBest then
        playerData.personalBest = playerData.currentScore
        
        -- Broadcast new personal best to all players
        local broadcastData = {
            type = "personalBest",
            playerName = playerData.playerName,
            score = playerData.personalBest
        }
        
        broadcastToAllPlayers(broadcastData)
        
        ac.log("Traffic Server: " .. playerData.playerName .. " achieved new personal best: " .. playerData.personalBest)
    end
end

-- Handle collision events
function handleCollision(carID, data)
    local playerData = serverData.playerScores[carID]
    if not playerData then return end
    
    playerData.collisions = playerData.collisions + 1
    
    -- Log collision for server statistics
    ac.log("Traffic Server: Player " .. playerData.playerName .. " collision #" .. playerData.collisions)
end

-- Send leaderboard to specific player
function sendLeaderboard(carID)
    local leaderboardData = {
        type = "leaderboard",
        data = {}
    }
    
    for i = 1, math.min(10, #serverData.leaderboard) do
        local entry = serverData.leaderboard[i]
        table.insert(leaderboardData.data, {
            position = i,
            name = entry.name,
            score = entry.score,
            isActive = entry.lives > 0
        })
    end
    
    ac.sendClientMessage(carID, ac.formatJSON(leaderboardData))
end

-- Broadcast message to all connected players
function broadcastToAllPlayers(data)
    local jsonData = ac.formatJSON(data)
    
    for carID, playerData in pairs(serverData.playerScores) do
        if playerData.connected then
            ac.sendClientMessage(carID, jsonData)
        end
    end
end

-- Handle server commands (admin functions)
function script.serverCommand(command, args)
    if command == "traffic_stats" then
        local stats = string.format(
            "Traffic Server Stats:\n" ..
            "- Total Players: %d\n" ..
            "- Active Players: %d\n" ..
            "- Session Time: %d minutes\n" ..
            "- Top Score: %.0f",
            serverData.serverStats.totalPlayers,
            countActivePlayers(),
            math.floor((os.time() - serverData.serverStats.sessionStartTime) / 60),
            getTopScore()
        )
        
        ac.log(stats)
        return stats
        
    elseif command == "traffic_reset" then
        -- Reset all player scores (admin command)
        for carID, playerData in pairs(serverData.playerScores) do
            if playerData.connected then
                local resetData = {
                    type = "serverReset",
                    message = "Server admin has reset all scores"
                }
                ac.sendClientMessage(carID, ac.formatJSON(resetData))
            end
        end
        
        -- Reset server data
        for carID, playerData in pairs(serverData.playerScores) do
            playerData.currentScore = 0
            playerData.personalBest = 0
            playerData.lives = 3
            playerData.collisions = 0
        end
        
        return "All player scores have been reset"
        
    elseif command == "traffic_kick_idle" then
        -- Kick players with 0 score after 10 minutes (admin command)
        local kickedCount = 0
        local currentTime = os.time()
        
        for carID, playerData in pairs(serverData.playerScores) do
            if playerData.connected and 
               playerData.personalBest == 0 and 
               playerData.sessionTime > 600 then
                
                ac.kickUser(carID)
                kickedCount = kickedCount + 1
            end
        end
        
        return "Kicked " .. kickedCount .. " idle players"
    end
end

-- Helper function to count active players
function countActivePlayers()
    local count = 0
    for carID, playerData in pairs(serverData.playerScores) do
        if playerData.connected and playerData.lives > 0 then
            count = count + 1
        end
    end
    return count
end

-- Helper function to get top score
function getTopScore()
    local topScore = 0
    for carID, playerData in pairs(serverData.playerScores) do
        if playerData.personalBest > topScore then
            topScore = playerData.personalBest
        end
    end
    return topScore
end

-- Periodic announcements
local lastAnnouncement = 0
function script.update(dt)
    updateServerLogic(dt)
    updateLeaderboard()
    
    -- Send periodic leaderboard updates every 30 seconds
    local currentTime = os.time()
    if currentTime - lastAnnouncement > 30 then
        broadcastLeaderboardUpdate()
        lastAnnouncement = currentTime
    end
end

-- Broadcast leaderboard update to all players
function broadcastLeaderboardUpdate()
    if #serverData.leaderboard > 0 then
        local updateData = {
            type = "leaderboardUpdate",
            topPlayer = serverData.leaderboard[1].name,
            topScore = serverData.leaderboard[1].score,
            totalPlayers = countActivePlayers()
        }
        
        broadcastToAllPlayers(updateData)
    end
end

-- Traffic Management Server Script for CSP
-- This script handles server-side traffic logic and synchronization

-- Script information
local scriptName = "Traffic Server Manager"
local scriptVersion = "1.0.0"

-- Server state
local server_state = {
    initialized = false,
    traffic_enabled = false,
    active_sessions = {},
    traffic_data = {
        global_density = 50,
        speed_multiplier = 1.0,
        max_cars = 20,
        spawn_distance = 500,
        despawn_distance = 200
    },
    update_interval = 1.0,
    last_update = 0
}

-- Traffic synchronization data
local sync_data = {
    traffic_cars = {},
    last_sync = 0,
    sync_interval = 2.0
}

-- Utility functions
local function log_server(message)
    ac.log("[SERVER] " .. message)
end

local function broadcast_to_clients(event, data)
    -- Broadcast event to all connected clients
    for session_id, session in pairs(server_state.active_sessions) do
        if session.connected then
            ac.sendChatMessage(session_id, "[TRAFFIC] " .. event .. ": " .. (data or ""))
        end
    end
end

-- Session management
local function register_session(session_id)
    server_state.active_sessions[session_id] = {
        connected = true,
        join_time = os.time(),
        traffic_enabled = false,
        last_activity = os.time()
    }
    log_server("Session registered: " .. session_id)
end

local function unregister_session(session_id)
    if server_state.active_sessions[session_id] then
        server_state.active_sessions[session_id] = nil
        log_server("Session unregistered: " .. session_id)
    end
end

-- Traffic management functions
local traffic_server = {
    -- Initialize server traffic system
    init = function(self)
        server_state.initialized = true
        log_server("Traffic server system initialized")
        
        -- Set up default traffic rules
        self:setup_traffic_rules()
    end,
    
    -- Setup traffic rules and AI behavior
    setup_traffic_rules = function(self)
        -- Configure AI behavior for traffic
        ac.setAILevel(0.7) -- Moderate AI skill
        ac.setAIAggression(0.3) -- Low aggression for traffic cars
        
        log_server("Traffic rules configured")
    end,
    
    -- Update server traffic state
    update = function(self, dt)
        if not server_state.initialized then
            self:init()
        end
        
        server_state.last_update = server_state.last_update + dt
        
        -- Periodic updates
        if server_state.last_update >= server_state.update_interval then
            self:update_traffic_data()
            self:cleanup_inactive_sessions()
            server_state.last_update = 0
        end
        
        -- Sync traffic data
        sync_data.last_sync = sync_data.last_sync + dt
        if sync_data.last_sync >= sync_data.sync_interval then
            self:sync_traffic_data()
            sync_data.last_sync = 0
        end
    end,
    
    -- Update traffic data based on active sessions
    update_traffic_data = function(self)
        local active_count = 0
        local total_density = 0
        
        for session_id, session in pairs(server_state.active_sessions) do
            if session.connected and session.traffic_enabled then
                active_count = active_count + 1
                total_density = total_density + (session.traffic_density or 50)
            end
        end
        
        if active_count > 0 then
            server_state.traffic_data.global_density = total_density / active_count
            server_state.traffic_enabled = true
        else
            server_state.traffic_enabled = false
        end
    end,
    
    -- Sync traffic data to clients
    sync_traffic_data = function(self)
        if not server_state.traffic_enabled then return end
        
        local sync_message = string.format(
            "SYNC|density:%.0f|speed:%.1f|cars:%d",
            server_state.traffic_data.global_density,
            server_state.traffic_data.speed_multiplier,
            #sync_data.traffic_cars
        )
        
        broadcast_to_clients("TRAFFIC_SYNC", sync_message)
    end,
    
    -- Clean up inactive sessions
    cleanup_inactive_sessions = function(self)
        local current_time = os.time()
        local timeout = 300 -- 5 minutes timeout
        
        for session_id, session in pairs(server_state.active_sessions) do
            if current_time - session.last_activity > timeout then
                unregister_session(session_id)
            end
        end
    end,
    
    -- Handle client requests
    handle_client_request = function(self, session_id, request_type, data)
        local session = server_state.active_sessions[session_id]
        if not session then
            register_session(session_id)
            session = server_state.active_sessions[session_id]
        end
        
        session.last_activity = os.time()
        
        if request_type == "ENABLE_TRAFFIC" then
            session.traffic_enabled = true
            session.traffic_density = tonumber(data) or 50
            log_server("Traffic enabled for session " .. session_id .. " with density " .. session.traffic_density)
            
        elseif request_type == "DISABLE_TRAFFIC" then
            session.traffic_enabled = false
            log_server("Traffic disabled for session " .. session_id)
            
        elseif request_type == "UPDATE_SETTINGS" then
            local settings = self:parse_settings(data)
            for key, value in pairs(settings) do
                session[key] = value
            end
            log_server("Settings updated for session " .. session_id)
            
        elseif request_type == "SPAWN_CAR" then
            self:handle_spawn_request(session_id, data)
            
        elseif request_type == "CLEAR_TRAFFIC" then
            self:clear_session_traffic(session_id)
        end
    end,
    
    -- Parse settings from client data
    parse_settings = function(self, data)
        local settings = {}
        if not data then return settings end
        
        for setting in string.gmatch(data, "([^|]+)") do
            local key, value = string.match(setting, "([^:]+):([^:]+)")
            if key and value then
                settings[key] = tonumber(value) or value
            end
        end
        
        return settings
    end,
    
    -- Handle spawn car request
    handle_spawn_request = function(self, session_id, data)
        local session = server_state.active_sessions[session_id]
        if not session or not session.traffic_enabled then return end
        
        if #sync_data.traffic_cars >= server_state.traffic_data.max_cars then
            ac.sendChatMessage(session_id, "[TRAFFIC] Maximum traffic cars reached")
            return
        end
        
        -- Add new traffic car to sync data
        local car_id = "traffic_" .. session_id .. "_" .. os.time()
        table.insert(sync_data.traffic_cars, {
            id = car_id,
            session_id = session_id,
            spawn_time = os.time(),
            position = data or "0,0,0"
        })
        
        log_server("Spawned traffic car " .. car_id .. " for session " .. session_id)
        broadcast_to_clients("CAR_SPAWNED", car_id)
    end,
    
    -- Clear traffic for specific session
    clear_session_traffic = function(self, session_id)
        for i = #sync_data.traffic_cars, 1, -1 do
            if sync_data.traffic_cars[i].session_id == session_id then
                table.remove(sync_data.traffic_cars, i)
            end
        end
        
        log_server("Cleared traffic for session " .. session_id)
        broadcast_to_clients("TRAFFIC_CLEARED", session_id)
    end,
    
    -- Get server statistics
    get_stats = function(self)
        local active_sessions = 0
        local traffic_sessions = 0
        
        for _, session in pairs(server_state.active_sessions) do
            if session.connected then
                active_sessions = active_sessions + 1
                if session.traffic_enabled then
                    traffic_sessions = traffic_sessions + 1
                end
            end
        end
        
        return {
            active_sessions = active_sessions,
            traffic_sessions = traffic_sessions,
            total_traffic_cars = #sync_data.traffic_cars,
            server_uptime = os.time() - (server_state.start_time or os.time()),
            traffic_enabled = server_state.traffic_enabled
        }
    end
}

-- Event handlers
function script.init()
    server_state.start_time = os.time()
    traffic_server:init()
    log_server(scriptName .. " v" .. scriptVersion .. " initialized")
end

function script.update(dt)
    traffic_server:update(dt)
end

-- Handle player connections
function script.onClientConnect(sessionId)
    register_session(sessionId)
    
    -- Send welcome message and current traffic state
    local stats = traffic_server:get_stats()
    local welcome_msg = string.format(
        "Traffic System Active | Sessions: %d | Traffic Cars: %d",
        stats.active_sessions,
        stats.total_traffic_cars
    )
    
    ac.sendChatMessage(sessionId, "[TRAFFIC] " .. welcome_msg)
end

function script.onClientDisconnect(sessionId)
    traffic_server:clear_session_traffic(sessionId)
    unregister_session(sessionId)
end

-- Handle chat commands
function script.onChatMessage(sessionId, message)
    -- Check if message is a traffic command
    if string.sub(message, 1, 9) == "[TRAFFIC]" then
        local command = string.sub(message, 11)
        local cmd_parts = {}
        
        for part in string.gmatch(command, "([^|]+)") do
            table.insert(cmd_parts, part)
        end
        
        if #cmd_parts >= 2 then
            local request_type = cmd_parts[1]
            local data = cmd_parts[2]
            traffic_server:handle_client_request(sessionId, request_type, data)
        end
    end
end

-- Periodic server announcements
local announcement_timer = 0
local announcement_interval = 300 -- 5 minutes

function script.periodicAnnouncements(dt)
    announcement_timer = announcement_timer + dt
    
    if announcement_timer >= announcement_interval then
        local stats = traffic_server:get_stats()
        
        if stats.active_sessions > 0 then
            local announcement = string.format(
                "Server Stats | Players: %d | Traffic Sessions: %d | Cars: %d | Use Ctrl+T for traffic UI",
                stats.active_sessions,
                stats.traffic_sessions,
                stats.total_traffic_cars
            )
            
            broadcast_to_clients("SERVER_STATS", announcement)
        end
        
        announcement_timer = 0
    end
end

-- Add periodic announcements to update loop
local original_update = script.update
script.update = function(dt)
    original_update(dt)
    script.periodicAnnouncements(dt)
end

-- Server command interface
function script.onServerCommand(command, args)
    if command == "traffic_status" then
        local stats = traffic_server:get_stats()
        log_server("=== Traffic Server Status ===")
        log_server("Active Sessions: " .. stats.active_sessions)
        log_server("Traffic Sessions: " .. stats.traffic_sessions)
        log_server("Total Traffic Cars: " .. stats.total_traffic_cars)
        log_server("Server Uptime: " .. stats.server_uptime .. "s")
        log_server("Traffic Enabled: " .. tostring(stats.traffic_enabled))
        return true
        
    elseif command == "traffic_clear_all" then
        sync_data.traffic_cars = {}
        broadcast_to_clients("ALL_TRAFFIC_CLEARED", "")
        log_server("All traffic cleared by server command")
        return true
        
    elseif command == "traffic_reload" then
        traffic_server:init()
        log_server("Traffic system reloaded")
        return true
    end
    
    return false
end

log_server("Traffic Server Script loaded successfully")

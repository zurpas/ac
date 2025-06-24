-- Traffic Management UI Script for CSP (Client-side)
-- This script creates a modern, draggable UI for managing traffic settings

-- Script initialization
local scriptName = "Traffic Manager UI"
local scriptVersion = "1.0.0"

-- UI State variables
local ui_state = {
    show_main_window = false,
    show_settings = false,
    traffic_enabled = false,
    traffic_density = 50,
    traffic_speed_multiplier = 1.0,
    spawn_distance = 500,
    despawn_distance = 200,
    max_traffic_cars = 20,
    window_pos = vec2(100, 100),
    window_size = vec2(400, 300),
    last_update = 0
}

-- Traffic management functions
local traffic_manager = {
    cars = {},
    spawn_timer = 0,
    spawn_interval = 5.0,
    
    -- Initialize traffic system
    init = function(self)
        ac.log("Traffic Manager initialized")
    end,
    
    -- Update traffic system
    update = function(self, dt)
        if not ui_state.traffic_enabled then return end
        
        self.spawn_timer = self.spawn_timer + dt
        
        if self.spawn_timer >= self.spawn_interval then
            self:spawn_traffic_car()
            self.spawn_timer = 0
        end
        
        self:update_traffic_cars(dt)
    end,
    
    -- Spawn a new traffic car
    spawn_traffic_car = function(self)
        if #self.cars >= ui_state.max_traffic_cars then return end
        
        local player_pos = ac.getCar(0).position
        local spawn_pos = player_pos + vec3(
            math.random(-ui_state.spawn_distance, ui_state.spawn_distance),
            0,
            math.random(-ui_state.spawn_distance, ui_state.spawn_distance)
        )
        
        -- Add traffic car data
        table.insert(self.cars, {
            position = spawn_pos,
            velocity = vec3(0, 0, math.random(20, 60) * ui_state.traffic_speed_multiplier),
            id = #self.cars + 1,
            spawn_time = os.time()
        })
        
        ac.log("Spawned traffic car at: " .. tostring(spawn_pos))
    end,
    
    -- Update existing traffic cars
    update_traffic_cars = function(self, dt)
        local player_pos = ac.getCar(0).position
        
        for i = #self.cars, 1, -1 do
            local car = self.cars[i]
            local distance = player_pos:distance(car.position)
            
            -- Remove cars that are too far away
            if distance > ui_state.despawn_distance then
                table.remove(self.cars, i)
                ac.log("Despawned traffic car " .. car.id)
            else
                -- Update car position
                car.position = car.position + car.velocity * dt
            end
        end
    end,
    
    -- Clear all traffic
    clear_all = function(self)
        self.cars = {}
        ac.log("Cleared all traffic cars")
    end
}

-- UI Drawing functions
local function draw_main_window()
    ui.pushStyleVar(ui.StyleVar.WindowRounding, 8)
    ui.pushStyleVar(ui.StyleVar.WindowPadding, vec2(16, 16))
    
    ui.setNextWindowPos(ui_state.window_pos, ui.Cond.FirstUseEver)
    ui.setNextWindowSize(ui_state.window_size, ui.Cond.FirstUseEver)
    
    local window_flags = bit.bor(
        ui.WindowFlags.None,
        ui.WindowFlags.NoCollapse
    )
    
    ui.setNextWindowBgAlpha(0.9)
    
    if ui.begin("Traffic Manager", window_flags) then
        -- Header
        ui.pushFont(ui.Font.Title)
        ui.textColoredWrapped(rgbm(0.3, 0.8, 1.0, 1.0), "🚗 Traffic Management System")
        ui.popFont()
        
        ui.separator()
        ui.spacing()
        
        -- Main controls
        ui.pushFont(ui.Font.Main)
        
        -- Traffic enable/disable
        local traffic_changed = false
        ui_state.traffic_enabled, traffic_changed = ui.checkbox("Enable Traffic", ui_state.traffic_enabled)
        
        if traffic_changed then
            if ui_state.traffic_enabled then
                traffic_manager:init()
                ac.log("Traffic system enabled")
            else
                traffic_manager:clear_all()
                ac.log("Traffic system disabled")
            end
        end
        
        ui.spacing()
        
        if ui_state.traffic_enabled then
            -- Traffic density slider
            ui.text("Traffic Density:")
            ui_state.traffic_density = ui.slider("##density", ui_state.traffic_density, 0, 100, "%.0f%%")
            
            ui.spacing()
            
            -- Speed multiplier
            ui.text("Speed Multiplier:")
            ui_state.traffic_speed_multiplier = ui.slider("##speed", ui_state.traffic_speed_multiplier, 0.1, 3.0, "%.1fx")
            
            ui.spacing()
            
            -- Max cars
            ui.text("Max Traffic Cars:")
            ui_state.max_traffic_cars = ui.slider("##maxcars", ui_state.max_traffic_cars, 1, 50, "%.0f")
            
            ui.spacing()
            
            -- Distance settings
            ui.text("Spawn Distance:")
            ui_state.spawn_distance = ui.slider("##spawndist", ui_state.spawn_distance, 100, 1000, "%.0fm")
            
            ui.text("Despawn Distance:")
            ui_state.despawn_distance = ui.slider("##despawndist", ui_state.despawn_distance, 100, 500, "%.0fm")
            
            ui.spacing()
            ui.separator()
            ui.spacing()
            
            -- Status information
            ui.text("Status Information:")
            ui.textColored(rgbm(0.7, 0.7, 0.7, 1.0), "Active Cars: " .. #traffic_manager.cars)
            ui.textColored(rgbm(0.7, 0.7, 0.7, 1.0), "Next Spawn: " .. string.format("%.1fs", traffic_manager.spawn_interval - traffic_manager.spawn_timer))
            
            ui.spacing()
            
            -- Action buttons
            if ui.button("Clear All Traffic", vec2(150, 30)) then
                traffic_manager:clear_all()
            end
            
            ui.sameLine()
            
            if ui.button("Spawn Car Now", vec2(150, 30)) then
                traffic_manager:spawn_traffic_car()
            end
        else
            ui.textColoredWrapped(rgbm(0.8, 0.8, 0.8, 0.7), "Enable traffic to access controls")
        end
        
        ui.popFont()
        
        ui.spacing()
        ui.separator()
        
        -- Footer with settings button
        if ui.button("Settings", vec2(80, 25)) then
            ui_state.show_settings = not ui_state.show_settings
        end
        
        ui.sameLine()
        ui.spring()
        ui.textColored(rgbm(0.5, 0.5, 0.5, 1.0), "v" .. scriptVersion)
    end
    ui.endWindow()
    
    ui.popStyleVar(2)
end

local function draw_settings_window()
    if not ui_state.show_settings then return end
    
    ui.pushStyleVar(ui.StyleVar.WindowRounding, 8)
    ui.pushStyleVar(ui.StyleVar.WindowPadding, vec2(12, 12))
    
    ui.setNextWindowSize(vec2(300, 200), ui.Cond.FirstUseEver)
    ui.setNextWindowBgAlpha(0.95)
    
    if ui.begin("Traffic Settings", ui.WindowFlags.NoCollapse) then
        ui.pushFont(ui.Font.Small)
        
        ui.text("Spawn Interval:")
        traffic_manager.spawn_interval = ui.slider("##interval", traffic_manager.spawn_interval, 1.0, 30.0, "%.1fs")
        
        ui.spacing()
        ui.separator()
        ui.spacing()
        
        ui.text("Keybindings:")
        ui.textColored(rgbm(0.7, 0.7, 0.7, 1.0), "Ctrl+T: Toggle Traffic UI")
        ui.textColored(rgbm(0.7, 0.7, 0.7, 1.0), "Ctrl+R: Reset All Settings")
        
        ui.spacing()
        
        if ui.button("Close Settings", vec2(-1, 25)) then
            ui_state.show_settings = false
        end
        
        ui.popFont()
    end
    ui.endWindow()
    
    ui.popStyleVar(2)
end

-- Input handling
local function handle_input()
    -- Toggle main window with Ctrl+T
    if ui.keyboardButtonPressed(ui.Key.T) and (ui.keyboardButtonDown(ui.Key.LeftCtrl) or ui.keyboardButtonDown(ui.Key.RightCtrl)) then
        ui_state.show_main_window = not ui_state.show_main_window
        ac.log("Traffic UI toggled: " .. tostring(ui_state.show_main_window))
    end
    
    -- Reset settings with Ctrl+R
    if ui.keyboardButtonPressed(ui.Key.R) and (ui.keyboardButtonDown(ui.Key.LeftCtrl) or ui.keyboardButtonDown(ui.Key.RightCtrl)) then
        ui_state.traffic_enabled = false
        ui_state.traffic_density = 50
        ui_state.traffic_speed_multiplier = 1.0
        ui_state.max_traffic_cars = 20
        traffic_manager:clear_all()
        ac.log("Traffic settings reset")
    end
end

-- Main script functions
function script.update(dt)
    -- Handle input
    handle_input()
    
    -- Update traffic manager
    traffic_manager:update(dt)
    
    -- Update UI state
    ui_state.last_update = ui_state.last_update + dt
end

function script.drawUI()
    if ui_state.show_main_window then
        draw_main_window()
        draw_settings_window()
    end
end

-- Optional: 3D rendering for traffic visualization
function script.draw3D()
    if not ui_state.traffic_enabled then return end
    
    -- Draw traffic car indicators
    for _, car in ipairs(traffic_manager.cars) do
        render.debugSphere(car.position, 2, rgbm(1, 0.5, 0, 0.8))
        render.debugArrow(car.position, car.position + car.velocity:normalize() * 10, rgbm(0, 1, 0, 1))
    end
end

-- Initialize on script load
ac.log("Traffic Manager UI Script loaded successfully")
ui_state.show_main_window = true -- Show UI on first load

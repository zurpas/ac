--[[
Traffic Score & UI Script for Assetto Corsa     
================================================
Author: ChatGPT-o3 (2024-06-27)
Version: 1.0.0

HOW TO USE
---------
• Upload this file somewhere accessible via HTTPS (e.g. https://yourcdn.com/traffic_score.lua).
• In the server's `csp_extra_options.ini` add:

  [EXTRA_RULES]
  ALLOW_WRONG_WAY = 1
  LUA_SCRIPTING   = 1
  DISABLE_RAIN_PHYSICS = 1

  [SCRIPT_1]
  SCRIPT = "https://yourcdn.com/traffic_score.lua"

No client-side installation is needed – Custom Shaders Patch will automatically download and execute this script for every joining player.

DEPENDENCIES
------------
None besides CSP v0.2.3-preview115 or newer (for ImGui & multiplayer safe storage).

------------------------------------------------------------------------------
GLOBAL GUARDED STATE (per-client)
------------------------------------------------------------------------------
`script`-table is provided by CSP and is unique to each client, so we attach our
state to it to avoid polluting the global Lua namespace in multiplayer.
]]

local ac      = ac   -- shorthand (provided by CSP)
local ui      = ui   -- ImGui helper (provided by CSP)
local vec3    = vec3 -- 3-component vector (provided by CSP)

---------------------------------------------------------------------
-- CONFIGURABLE PARAMETERS                                          --
---------------------------------------------------------------------
local CFG = {
  -- Scoring multipliers -----------------------------------------------------
  speedMultiplierFactor      = 0.02, -- how much km/h influences multiplier
  proximityBaseMultiplier    = 1.0,  -- baseline multiplier when no traffic
  proximityDistanceThreshold = 4.0,  -- [m] distance considered "near" other car
  proximityGainPerSecond     = 0.12, -- how quickly proximity multiplier grows
  proximityDecayPerSecond    = 0.25, -- how quickly it decays when alone
  comboGainPerNearMiss       = 0.25, -- extra added to combo on near miss
  comboDecayPerSecond        = 0.15, -- combo decay over time
  laneBonusValue             = 0.3,  -- flat bonus added after using 3+ lanes
  laneDiversityWindow        = 15.0, -- [s] time window to detect lane variety

  -- Collision penalty -------------------------------------------------------
  collisionPenalties = {0.05, 0.15, 1.0}, -- % score lost per collision (3 lives)

  -- Popup / animation timings ----------------------------------------------
  popupDuration      = 3.0, -- seconds
  fadeDuration       = 0.35,
  scaleInDuration    = 0.30,

  -- UI ----------------------------------------------------------------------
  uiScale            = 1.0,
  fontLargeSize      = 28,
  fontMediumSize     = 20,
  fontSmallSize      = 14,
  windowAlpha        = 0.82,

  -- Sound urls --------------------------------------------------------------
  sndCollision       = "https://pouch.jumpshare.com/preview/gqrndw4hWQJvYsX5fnCgIXxj85SeyzDMKLkN4k-LI84Hl-ybkdx1CXcS0ZgflrY137n5HCsitRoKHyZkWi1kO5xYJjLNidZFFpvY6h-EO5YCgCtgkwvdPnr5fN5G2ah6fMkGhYIJ8znZ2qIYXG39SG6yjbN-I2pg_cnoHs_AmgI.wav",
  sndNewPB           = "https://pouch.jumpshare.com/preview/DEHhvx97itAX7pI6L-IfA12UZ4zFllzWCS8OjS_qSDPXGd3QWeLoMoEJOegFQle_X51kWGLPP319wB5TgEqYa4Zq_WIsPw2UNa3RWASRAYf6KuA1krstcP9cj7RzQxM_dz-22ZNZdPkSWSvi_A90LW6yjbN-I2pg_cnoHs_AmgI.wav",
  sndPopup           = "https://pouch.jumpshare.com/preview/RDaVIczqjTNClKDaYh08oNCpMYz-CIOoGZ8R8iwsD5crDfyQhu6f-kEXrEF3UKLcZVGjD2zukj5FtJKHxerty9W8oejAs4KgWjDBHS8evYFao5Q4mmpbbJuOIKW_QsI_SzQK7xSgy9bPPpCNQwC1j26yjbN-I2pg_cnoHs_AmgI.wav",
}

---------------------------------------------------------------------
-- HELPER FUNCTIONS --------------------------------------------------
---------------------------------------------------------------------
local function clamp(x, a, b) return math.max(a, math.min(b, x)) end

-- Linear interpolation
local function lerp(a, b, t) return a + (b - a) * t end

-- Smooth animation helper (exp filter)
local function smooth(current, target, smoothness, dt)
  local k = 1.0 - math.exp(-smoothness * dt)
  return current + (target - current) * k
end

-- Check if a value is close (epsilon)
local function almostEqual(a, b, eps) return math.abs(a - b) <= (eps or 1e-3) end

-- Returns track lane index (-1, 0, 1) based on world X relative to spline
local function getLaneIndex(car)
  -- Very simplified: split road width into 3 lanes left-center-right around AI line.
  local worldPos = car.position
  local closestPoint = ac.trackClosestPoint(worldPos) -- vec3, on ideal line
  local relX = (worldPos - closestPoint):dot(ac.getTrackRight()):__len() * (worldPos.x < closestPoint.x and -1 or 1)
  local halfRoad = ac.getTrackWidth() * 0.5
  local laneWidth = halfRoad / 1.5 -- rough
  local lane = math.floor(relX / laneWidth + 0.5) -- gives ‑1,0,1 or beyond
  return clamp(lane, -1, 1)
end

---------------------------------------------------------------------
-- STATE -------------------------------------------------------------
---------------------------------------------------------------------
local S = {
  score            = 0.0,
  lives            = 3,
  personalBest     = ac.storage():get("personalBest", 0),

  -- Multipliers
  mSpeed           = 1.0,
  mProximity       = 1.0,
  mCombo           = 1.0,
  mLane            = 0.0,

  -- Animation helpers
  lastScoreChange  = 0.0,
  lastPBChange     = 0.0,
  collisionFlash   = 0.0,

  -- Lane diversity tracking
  lanesUsed        = {},   -- [laneIndex] = timestamp last used

  -- Pop-ups list
  popups           = {},   -- {text, birth}

  -- UI window state (persistent)
  uiPos            = ac.storage():get("uiPos", {x = 200, y = 60}),
  uiSize           = {x = 420, y = 120},
}

---------------------------------------------------------------------
-- STORAGE HELPERS ---------------------------------------------------
---------------------------------------------------------------------
local storage = ac.storage()
local function savePersistent()
  storage:set("personalBest", S.personalBest)
  storage:set("uiPos",       S.uiPos)
end

---------------------------------------------------------------------
-- POPUP MANAGEMENT --------------------------------------------------
---------------------------------------------------------------------
local function pushPopup(text)
  table.insert(S.popups, {text = text, birth = ac.getSim().sessionTime})
  -- Play a popup sound (protected: might fail if url missing)
  pcall(ac.playSound, CFG.sndPopup)
end

---------------------------------------------------------------------
-- COLLISION HANDLING (uses ac.flags & event callback) --------------
---------------------------------------------------------------------
-- We rely on Car.damage value spikes. CPS currently lacks explicit collision
-- event callback in Lua, so we detect by comparing `car.damage` frame-to-frame.

local damagePrev = 0.0
local function handleCollision(car, dt)
  local dmg     = car.damage
  if dmg > damagePrev + 0.01 then -- damaged >1% means collision occurred
    S.collisionFlash = 1.0    -- for UI flash
    local lifeIndex = 4 - S.lives -- 1..3
    local penalty = CFG.collisionPenalties[lifeIndex] or 1.0
    S.score = S.score * (1.0 - penalty)
    S.lives = S.lives - 1

    pushPopup(string.format("-%.0f%% SCORE (%d LIVES LEFT)", penalty * 100, math.max(S.lives,0)))
    pcall(ac.playSound, CFG.sndCollision)

    if S.lives <= 0 then
      -- reset
      S.score = 0
      S.mCombo = 1
      S.lives  = 3
      pushPopup("SCORE RESET")
    end
    S.lastScoreChange = ac.getSim().sessionTime
  end
  damagePrev = dmg
end

---------------------------------------------------------------------
-- NEAR MISS DETECTION & PROXIMITY -----------------------------------
---------------------------------------------------------------------
local nearMissCooldown = 0.0
local function updateProximityAndCombo(playerCar, dt)
  local closestDist = 999
  local carCount = ac.getCarCount()
  for i = 0, carCount-1 do
    if i ~= playerCar.index then
      local other = ac.getCar(i)
      if other and other.isConnected then
        local dist = (playerCar.position - other.position):length()
        closestDist = math.min(closestDist, dist)

        if dist < CFG.proximityDistanceThreshold and nearMissCooldown <= 0 then
          -- near miss!
          S.mCombo = S.mCombo + CFG.comboGainPerNearMiss
          pushPopup("NEAR MISS +" .. tostring(CFG.comboGainPerNearMiss))
          nearMissCooldown = 2.0 -- prevent spam
        end
      end
    end
  end

  nearMissCooldown = math.max(0, nearMissCooldown - dt)

  -- Proximity multiplier target
  local proxTarget = CFG.proximityBaseMultiplier + clamp((CFG.proximityDistanceThreshold - closestDist) / CFG.proximityDistanceThreshold, 0, 1) * 1.0
  S.mProximity = smooth(S.mProximity, proxTarget, 3.5, dt)

  -- Combo decay
  S.mCombo = math.max(1.0, S.mCombo - CFG.comboDecayPerSecond * dt)
end

---------------------------------------------------------------------
-- SPEED MULTIPLIER --------------------------------------------------
---------------------------------------------------------------------
local function updateSpeedMultiplier(playerCar, dt)
  local speedKmh = math.max(0, playerCar.speedKmh)
  local target   = 1.0 + speedKmh * CFG.speedMultiplierFactor
  S.mSpeed = smooth(S.mSpeed, target, 3.0, dt)
end

---------------------------------------------------------------------
-- LANE DIVERSITY ----------------------------------------------------
---------------------------------------------------------------------
local function updateLaneBonus(playerCar, dt)
  local now = ac.getSim().sessionTime
  local laneIndex = getLaneIndex(playerCar)
  if laneIndex then
    S.lanesUsed[laneIndex] = now
  end

  -- remove old lanes
  local active = 0
  for lane, t in pairs(S.lanesUsed) do
    if now - t > CFG.laneDiversityWindow then
      S.lanesUsed[lane] = nil
    else
      active = active + 1
    end
  end

  -- bonus applies if 3 lanes used recently
  S.mLane = active >= 3 and CFG.laneBonusValue or 0.0
end

---------------------------------------------------------------------
-- SCORE UPDATE ------------------------------------------------------
---------------------------------------------------------------------
local function updateScore(dt)
  local multiplier = S.mSpeed * S.mProximity * S.mCombo + S.mLane
  local delta = multiplier * dt * 10 -- base gain per second (10) scaled
  S.score = S.score + delta

  if S.score > S.personalBest then
    S.personalBest = S.score
    S.lastPBChange = ac.getSim().sessionTime
    pushPopup("NEW PERSONAL BEST!")
    pcall(ac.playSound, CFG.sndNewPB)
  end
end

---------------------------------------------------------------------
-- UI RENDERING ------------------------------------------------------
---------------------------------------------------------------------
ui.registerWindow("trafficScore", function()
  local simTime = ac.getSim().sessionTime

  ui.setNextWindowPos(S.uiPos.x, S.uiPos.y, ui.WindowCond.FirstUseEver)
  ui.setNextWindowSize(S.uiSize.x, S.uiSize.y, ui.WindowCond.FirstUseEver)

  ui.window("Traffic Score", function()
    -- allow moving window
    if ui.isItemActive() and ui.isMouseDown(0) then
      local delta = ui.getMouseDelta()
      S.uiPos.x = S.uiPos.x + delta.x
      S.uiPos.y = S.uiPos.y + delta.y
    end

    -- Fonts -----------------------------------------------------------
    local fontLarge   = ui.getFont(CFG.fontLargeSize * CFG.uiScale)
    local fontMedium  = ui.getFont(CFG.fontMediumSize * CFG.uiScale)
    local fontSmall   = ui.getFont(CFG.fontSmallSize * CFG.uiScale)

    -------------------------------------------------------------------
    -- Top multipliers bar                                             --
    -------------------------------------------------------------------
    ui.pushFont(fontSmall)

    local function drawMultiplier(title, value)
      ui.pushStyleColor(ui.Col.Text, ui.rgbm(1,1,1,1))
      ui.text(string.format("%.1fx", value))
      ui.sameLine()
      ui.text(title)
      ui.popStyleColor()
      ui.sameLine(0, 14 * CFG.uiScale)
    end

    drawMultiplier("Speed",      S.mSpeed)
    drawMultiplier("Proximity",  S.mProximity)
    drawMultiplier("Combo",      S.mCombo)
    drawMultiplier("Bonus",      1.0 + S.mLane)

    ui.popFont()

    -------------------------------------------------------------------
    -- Main Score display                                              --
    -------------------------------------------------------------------
    ui.pushFont(fontLarge)
    local scoreAlpha = 1.0
    if simTime - S.lastScoreChange < CFG.fadeDuration then
      scoreAlpha = lerp(0, 1, (simTime - S.lastScoreChange) / CFG.fadeDuration)
    end
    if S.collisionFlash > 0 then
      ui.pushStyleColor(ui.Col.Text, ui.rgbm(1, 0.2, 0.2, scoreAlpha))
    else
      ui.pushStyleColor(ui.Col.Text, ui.rgbm(1, 1, 1, scoreAlpha))
    end

    ui.text(string.format("%d PTS", math.floor(S.score)))
    ui.popStyleColor()
    ui.popFont()

    -------------------------------------------------------------------
    -- Personal Best / Lives                                           --
    -------------------------------------------------------------------
    ui.pushFont(fontMedium)
    ui.text(string.format("PB  %d", math.floor(S.personalBest)))
    ui.sameLine() ui.text(string.format("  Lives: %d", S.lives))
    ui.popFont()

    -------------------------------------------------------------------
    -- Popups (draw over UI)                                            --
    -------------------------------------------------------------------
    local i = 1
    while i <= #S.popups do
      local p = S.popups[i]
      local age = simTime - p.birth
      if age > CFG.popupDuration then
        table.remove(S.popups, i)
      else
        local alpha = clamp(1.0 - age / CFG.popupDuration, 0, 1)
        ui.setCursorPos( ui.getCursorPos() - ui.ImVec2(0, (i-1)*22) )
        ui.pushStyleColor(ui.Col.Text, ui.rgbm(1,1,1,alpha))
        ui.text(p.text)
        ui.popStyleColor()
        i = i + 1
      end
    end

  end, ui.WindowFlags.NoResize | ui.WindowFlags.NoCollapse | ui.WindowFlags.AlwaysAutoResize | ui.WindowFlags.NoTitleBar | ui.WindowFlags.NoSavedSettings, CFG.windowAlpha)
end)

---------------------------------------------------------------------
-- SCRIPT LIFECYCLE --------------------------------------------------
---------------------------------------------------------------------
function script.update(dt)
  local playerCar = ac.getCar(0) -- local player is always index 0 in client
  if not playerCar or not playerCar.isConnected then return end

  updateSpeedMultiplier(playerCar, dt)
  updateProximityAndCombo(playerCar, dt)
  updateLaneBonus(playerCar, dt)
  updateScore(dt)
  handleCollision(playerCar, dt)

  -- decay flash effect
  S.collisionFlash = math.max(0, S.collisionFlash - dt * 3.0)
end

function script.drawUI()
  ui.showWindow("trafficScore")
end

---------------------------------------------------------------------
-- SHUTDOWN ----------------------------------------------------------
---------------------------------------------------------------------
function script.shutdown()
  savePersistent()
end

-- Auto-save PB every minute so we don’t lose on crash ---------------
local autosaveTimer = 0
function script.tick(dt)
  autosaveTimer = autosaveTimer + dt
  if autosaveTimer > 60 then
    autosaveTimer = 0
    savePersistent()
  end
end

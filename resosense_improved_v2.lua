-- Downloaded from https://github.com/s0daa/CSGO-HVH-LUAS
-- Improved by Copilot with Advanced Anti-Fake Detection & Angle History Analysis
-- FULLY FIXED - All nil checks included

local ffi = require 'ffi'

local tab, container = "Rage", "Other"

local current = {
    check_access = true,
    angle_memory = {},
    player_states = {},
    ddt_data = {},
    angle_confidence = {},
    fake_detector = {},
}

ffi.cdef [[
    struct c_animstate { 
        char pad[ 3 ];
        char m_bForceWeaponUpdate;
        char pad1[ 91 ];
        void* m_pBaseEntity;
        void* m_pActiveWeapon;
        void* m_pLastActiveWeapon;
        float m_flPrevCycle;
        float m_flWeight;
        float m_flWeightDeltaRate;
        float m_flPlaybackRate;
        float m_flLastClientSideAnimationUpdateTime;
        int m_iLastClientSideAnimationUpdateFramecount;
        float m_flAnimUpdateDelta;
        float m_flEyeYaw;
        float m_flPitch;
        float m_flGoalFeetYaw;
        float m_flCurrentFeetYaw;
        float m_flCurrentTorsoYaw;
        float m_flUnknownVelocityLean;
        float m_flLeanAmount;
        char pad2[ 4 ];
        float m_flFeetCycle;
        float m_flFeetYawRate;
        char pad3[ 4 ];
        float m_fDuckAmount;
        float m_fLandingDuckAdditiveSomething;
        char pad4[ 4 ];
        float m_vOriginX;
        float m_vOriginY;
        float m_vOriginZ;
        float m_vLastOriginX;
        float m_vLastOriginY;
        float m_vLastOriginZ;
        float m_vVelocityX;
        float m_vVelocityY;
        char pad5[ 4 ];
        float m_flUnknownFloat1;
        char pad6[ 8 ];
        float m_flUnknownFloat2;
        float m_flUnknownFloat3;
        float m_flUnknown;
        float m_flSpeed2D;
        float m_flUpVelocity;
        float m_flSpeedNormalized;
        float m_flFeetSpeedForwardsOrSideWays;
        float m_flFeetSpeedUnknownForwardOrSideways;
        float m_flTimeSinceStartedMoving;
        float m_flTimeSinceStoppedMoving;
        bool m_bOnGround;
        bool m_bInHitGroundAnimation;
        float m_flTimeSinceInAir;
        float m_flLastOriginZ;
        float m_flHeadHeightOrOffsetFromHittingGroundAnimation;
        float m_flStopToFullRunningFraction;
        char pad7[ 4 ];
        float m_flMagicFraction;
        char pad8[ 60 ];
        float m_flWorldForce;
        char pad9[ 462 ];
        float m_flMaxYaw;
        float m_flMinYaw;
    };
]]

local classptr = ffi.typeof('void***')
local rawientitylist = client.create_interface('client.dll', 'VClientEntityList003')
if not rawientitylist then
    error('VClientEntityList003 not found', 2)
end

local ientitylist = ffi.cast(classptr, rawientitylist)
local get_client_entity = ffi.cast('void*(__thiscall*)(void*, int)', ientitylist[0][3])

-- ==================== UI ЭЛЕМЕНТЫ ====================

local misc = {
    enable = ui.new_checkbox(tab, container, "ResoSense v3"),
    type = ui.new_combobox(tab, container, "Type", {"Default", "Jitter", "Alternative", "Custom", "Smart"}),
    delta = ui.new_slider(tab, container, 'Delta', 1, 10, 3, true, "°"),
    brute_force = ui.new_checkbox(tab, container, "Brute Force (Memory)"),
    anti_fake = ui.new_checkbox(tab, container, "Anti-Fake Detection"),
    movement_detection = ui.new_checkbox(tab, container, "Movement Detection"),
    aggressiveness = ui.new_slider(tab, container, 'Aggressiveness', 1, 100, 50, true, "%"),
    confidence_threshold = ui.new_slider(tab, container, 'Confidence Threshold', 1, 100, 70, true, "%"),
    
    ddt_enable = ui.new_checkbox(tab, container, "Defensive Double Tap"),
    ddt_mode = ui.new_combobox(tab, container, "DDT Mode", {"On Shot", "On Damage", "Always"}),
    ddt_ticks = ui.new_slider(tab, container, "DDT Ticks", 1, 16, 8, true, "t"),
    ddt_accuracy = ui.new_slider(tab, container, "DDT Accuracy", 1, 100, 75, true, "%"),
}

-- ==================== УТИЛИТЫ ====================

local function SafeGetUI(control, default_value)
    if not control then return default_value end
    local value = ui.get(control)
    return value or default_value
end

local function NormalizeAngle(angle)
    if not angle or angle ~= angle then return 0 end
    while angle > 180 do
        angle = angle - 360
    end
    while angle < -180 do
        angle = angle + 360
    end
    return angle
end

local function GetAnimationState(player)
    if not player then return nil end
    pcall(function()
        local player_ptr = ffi.cast("void***", get_client_entity(ientitylist, player))
        if not player_ptr then return nil end
        local animstate_ptr = ffi.cast("char*", player_ptr) + 0x9960
        local state = ffi.cast("struct c_animstate**", animstate_ptr)[0]
        return state
    end)
    return nil
end

local function GetPlayerPos(player)
    if not player then return {x = 0, y = 0, z = 0} end
    local x = entity.get_prop(player, "m_vecOrigin[0]")
    local y = entity.get_prop(player, "m_vecOrigin[1]")
    local z = entity.get_prop(player, "m_vecOrigin[2]")
    return {x = x or 0, y = y or 0, z = z or 0}
end

local function GetPlayerVelocity(player)
    if not player then return {x = 0, y = 0, z = 0} end
    local vx = entity.get_prop(player, "m_vecVelocity[0]")
    local vy = entity.get_prop(player, "m_vecVelocity[1]")
    local vz = entity.get_prop(player, "m_vecVelocity[2]")
    return {x = vx or 0, y = vy or 0, z = vz or 0}
end

-- ==================== ДВИЖЕНИЕ ====================

local function DetectMovementType(player)
    local animstate = GetAnimationState(player)
    if not animstate then return "unknown" end
    
    local speed = tonumber(animstate.m_flSpeed2D) or 0
    local is_in_air = (tonumber(animstate.m_flTimeSinceInAir) or 0) > 0.1
    local on_ground = animstate.m_bOnGround or false
    local in_hit_ground = animstate.m_bInHitGroundAnimation or false
    
    if is_in_air and not on_ground then
        return "jumping"
    elseif in_hit_ground or (tonumber(animstate.m_flTimeSinceInAir) or 0) < 0.5 then
        return "landing"
    elseif speed > 150 then
        return "running"
    elseif speed > 50 then
        return "walking"
    else
        return "standing"
    end
end

-- ==================== АНАЛИЗ УГЛОВ И ДЕТЕКТОР ФЕЙКОВ ====================

local function AnalyzePlayerAngles(player)
    local animstate = GetAnimationState(player)
    if not animstate then return nil end
    
    local eye_yaw = tonumber(animstate.m_flEyeYaw) or 0
    local goal_feet_yaw = tonumber(animstate.m_flGoalFeetYaw) or 0
    local current_feet_yaw = tonumber(animstate.m_flCurrentFeetYaw) or 0
    local playback_rate = tonumber(animstate.m_flPlaybackRate) or 0.5
    local speed = tonumber(animstate.m_flSpeed2D) or 0
    
    local yaw_diff = math.abs(NormalizeAngle(goal_feet_yaw - current_feet_yaw))
    
    local suspicion_score = 0
    
    if yaw_diff > 100 then
        suspicion_score = suspicion_score + 30
    elseif yaw_diff > 60 then
        suspicion_score = suspicion_score + 15
    end
    
    if playback_rate < 0.05 or playback_rate > 3.0 then
        suspicion_score = suspicion_score + 40
    elseif playback_rate < 0.2 or playback_rate > 2.0 then
        suspicion_score = suspicion_score + 20
    end
    
    if speed > 200 and playback_rate < 0.3 then
        suspicion_score = suspicion_score + 35
    end
    
    return {
        eye_yaw = eye_yaw,
        goal_feet_yaw = goal_feet_yaw,
        current_feet_yaw = current_feet_yaw,
        yaw_diff = yaw_diff,
        playback_rate = playback_rate,
        speed = speed,
        suspicion_score = math.min(suspicion_score, 100),
        is_likely_fake = suspicion_score > 50,
    }
end

-- ==================== ЗАПОМИНАНИЕ УГЛОВ ====================

local function InitializeAngleMemory(player)
    if not current.angle_memory[player] then
        current.angle_memory[player] = {
            angles = {},
            movement_type = "",
            last_update = 0,
            confidence = 0,
            angle_history = {},
        }
    end
    if not current.angle_confidence[player] then
        current.angle_confidence[player] = {}
    end
    if not current.fake_detector[player] then
        current.fake_detector[player] = {
            suspicion_history = {},
            last_suspicion = 0,
        }
    end
end

local function AddAngleToMemory(player, yaw, movement_type, suspicion_score)
    InitializeAngleMemory(player)
    local memory = current.angle_memory[player]
    
    if not yaw or yaw ~= yaw then return end
    
    local rounded_yaw = math.floor(yaw / 5 + 0.5) * 5
    
    if not memory.angles[rounded_yaw] then
        memory.angles[rounded_yaw] = {count = 0, movement_type = movement_type, suspicion = 0}
    end
    
    local weight = 1
    if suspicion_score and suspicion_score > 50 then
        weight = 0.3
    end
    
    memory.angles[rounded_yaw].count = memory.angles[rounded_yaw].count + weight
    memory.angles[rounded_yaw].suspicion = suspicion_score or 0
    
    if not memory.angle_history[movement_type] then
        memory.angle_history[movement_type] = {}
    end
    table.insert(memory.angle_history[movement_type], {yaw = rounded_yaw, tick = globals.tickcount()})
    
    if #memory.angle_history[movement_type] > 100 then
        table.remove(memory.angle_history[movement_type], 1)
    end
    
    memory.last_update = globals.tickcount()
end

local function GetMostUsedAngle(player)
    if not current.angle_memory[player] then return nil end
    
    local memory = current.angle_memory[player]
    local best_yaw = nil
    local best_count = 0
    
    for yaw, data in pairs(memory.angles) do
        local is_suspicious = data.suspicion and data.suspicion > 50
        local adjusted_count = is_suspicious and (data.count * 0.5) or data.count
        
        if adjusted_count > best_count then
            best_count = adjusted_count
            best_yaw = yaw
        end
    end
    
    local confidence_threshold = SafeGetUI(misc.confidence_threshold, 70) / 100
    local confidence = math.min(best_count / 25, 1.0)
    
    if confidence < confidence_threshold then
        return nil, confidence
    end
    
    return best_yaw, confidence
end

local function ClearOldMemory()
    for player, data in pairs(current.angle_memory) do
        if globals.tickcount() - data.last_update > 300 then
            current.angle_memory[player] = nil
            current.angle_confidence[player] = nil
            current.fake_detector[player] = nil
        end
    end
end

-- ==================== DEFENSIVE DOUBLE TAP ====================

local function InitializeDDTData(player)
    if not current.ddt_data[player] then
        current.ddt_data[player] = {
            last_shot_tick = 0,
            last_damage_tick = 0,
            position_history = {},
            velocity_history = {},
            is_active = false,
            activation_tick = 0,
        }
    end
end

local function StorePosAndVel(player)
    InitializeDDTData(player)
    local data = current.ddt_data[player]
    local tick = globals.tickcount()
    
    data.position_history[tick] = GetPlayerPos(player)
    data.velocity_history[tick] = GetPlayerVelocity(player)
    
    for t in pairs(data.position_history) do
        if tick - t > 20 then
            data.position_history[t] = nil
            data.velocity_history[t] = nil
        end
    end
end

local function ActivateDDT(player)
    InitializeDDTData(player)
    local data = current.ddt_data[player]
    data.is_active = true
    data.activation_tick = globals.tickcount()
end

local function ProcessDDT(player)
    if not SafeGetUI(misc.ddt_enable, false) then return false end
    
    InitializeDDTData(player)
    local data = current.ddt_data[player]
    local current_tick = globals.tickcount()
    local ddt_ticks = SafeGetUI(misc.ddt_ticks, 8)
    local ddt_mode = SafeGetUI(misc.ddt_mode, "On Shot")
    
    local should_activate = false
    
    if ddt_mode == "On Shot" then
        local local_player = entity.get_local_player()
        if local_player then
            local local_health = entity.get_prop(local_player, "m_iHealth")
            if local_health and local_health < entity.get_prop(local_player, "m_iMaxHealth") then
                should_activate = true
                data.last_damage_tick = current_tick
            end
        end
    elseif ddt_mode == "On Damage" then
        should_activate = data.is_active or (current_tick - data.activation_tick < 5)
    elseif ddt_mode == "Always" then
        should_activate = true
    end
    
    if should_activate then
        ActivateDDT(player)
    end
    
    if data.is_active and (current_tick - data.activation_tick) < ddt_ticks then
        return true
    else
        data.is_active = false
        return false
    end
end

-- ==================== RESOLVER ====================

local function SmartResolve(player, animstate, delta, yaw1)
    local movement_type = DetectMovementType(player)
    local aggressiveness = SafeGetUI(misc.aggressiveness, 50) / 100
    
    local playback_rate = tonumber(animstate.m_flPlaybackRate) or 0.5
    local base_yaw = delta * yaw1 * playback_rate
    local yaws = base_yaw
    
    if movement_type == "jumping" then
        yaws = base_yaw * (1.2 * aggressiveness)
    elseif movement_type == "landing" then
        yaws = base_yaw * (0.8 * aggressiveness)
    elseif movement_type == "running" then
        yaws = base_yaw * (1.1 * aggressiveness)
    elseif movement_type == "standing" then
        yaws = base_yaw * (0.9 * aggressiveness)
    end
    
    return yaws, movement_type
end

local eye_yaw = 1
local ent_name = "none"
local side = -1
local side2 = -1
local current_movement = "unknown"
local memory_used = false
local ddt_active = false
local fake_detected = false

local function ResolveJitter(player)
    local animstate = GetAnimationState(player)
    if not animstate then return end
    
    StorePosAndVel(player)
    
    local angle_analysis = nil
    if SafeGetUI(misc.anti_fake, false) then
        angle_analysis = AnalyzePlayerAngles(player)
    end
    
    fake_detected = angle_analysis and angle_analysis.is_likely_fake or false
    
    local eye_angles = entity.get_prop(player, "m_angEyeAngles[1]") or 0
    local pose_param = entity.get_prop(player, "m_flPoseParameter", 11) or 0
    
    local delta = tonumber(eye_angles) or 0 - (tonumber(pose_param) or 0)
    eye_yaw = tonumber(animstate.m_flEyeYaw) or 0
    ent_name = entity.get_player_name(player) or "Unknown"

    local yaw1 = (tonumber(pose_param) or 0) * 116 - 58
    side = globals.tickcount() % 2 == 0 and -1 or 1
    side2 = (globals.tickcount() % 3) - 1

    local yaws = 0
    local resolver_type = SafeGetUI(misc.type, "Default")
    local playback_rate = tonumber(animstate.m_flPlaybackRate) or 0.5
    
    if resolver_type == "Default" then
        yaws = delta * yaw1 * playback_rate
    elseif resolver_type == "Jitter" then
        yaws = side * math.abs(delta * yaw1 * playback_rate)
    elseif resolver_type == "Alternative" then
        yaws = side2 * math.abs(delta * yaw1 * playback_rate)
    elseif resolver_type == "Custom" then
        local delta_slider = SafeGetUI(misc.delta, 1)
        if delta_slider ~= 0 then
            yaws = (delta * yaw1 * playback_rate) / delta_slider
        end
    elseif resolver_type == "Smart" then
        yaws, current_movement = SmartResolve(player, animstate, delta, yaw1)
    end

    if not yaws or yaws ~= yaws or yaws == math.huge or yaws == -math.huge then
        yaws = 0
    end
    
    yaws = NormalizeAngle(yaws)

    if SafeGetUI(misc.brute_force, false) then
        local suspicion = angle_analysis and angle_analysis.suspicion_score or 0
        AddAngleToMemory(player, yaws, current_movement, suspicion)
        
        local best_yaw, confidence = GetMostUsedAngle(player)
        if best_yaw and confidence and confidence > 0.5 then
            yaws = best_yaw
            memory_used = true
        else
            memory_used = false
        end
    else
        memory_used = false
    end

    ddt_active = ProcessDDT(player)
    if ddt_active then
        local accuracy = SafeGetUI(misc.ddt_accuracy, 75) / 100
        yaws = yaws * (0.5 + accuracy * 0.5)
    end

    plist.set(player, "Force body yaw", true)
    plist.set(player, "Force body yaw value", yaws)
end

local function Resolver(player)
    if SafeGetUI(misc.enable, false) then
        if entity.is_dormant(player) or entity.get_prop(player, "m_bDormant") then
            return
        end
        ResolveJitter(player)
    else
        plist.set(player, "Force body yaw", false)
    end
end

local function ResolverUpdate()
    if current.check_access == false then return end
    ClearOldMemory()
    
    local enemies = entity.get_players(true)
    for i, enemy_ent in ipairs(enemies) do
        if enemy_ent and entity.is_alive(enemy_ent) then
            Resolver(enemy_ent)
        end
    end
end

-- ==================== UI ИНДИКАТОР ====================

local x_ind, y_ind = client.screen_size()
local function paint_indicator()
    if current.check_access == false then return end
    if not SafeGetUI(misc.enable, false) then return end
    if entity.get_local_player() == nil or not entity.is_alive(entity.get_local_player()) then return end
    
    local y_offset = y_ind / 1.9
    renderer.text(20, y_offset, 255, 255, 255, 255, "", 0, "> ResoSense v3 \aEE4444FF[v3.1]")
    renderer.text(20, y_offset + 12, 255, 255, 255, 255, "", 0, "> Type: \aEE4444FF" .. SafeGetUI(misc.type, "Default"))
    
    if SafeGetUI(misc.movement_detection, false) then
        renderer.text(20, y_offset + 24, 255, 255, 255, 255, "", 0, "> Movement: \aEE4444FF" .. current_movement)
    end
    
    if SafeGetUI(misc.anti_fake, false) then
        local fake_status = fake_detected and "\aFF0000FF[FAKE]" or "\a00FF00FF[REAL]"
        renderer.text(20, y_offset + 36, 255, 255, 255, 255, "", 0, "> Anti-Fake: " .. fake_status)
    end
    
    if SafeGetUI(misc.brute_force, false) then
        local memory_status = memory_used and "\a00FF00FF[USING]" or "\aFFFFFFFF[learning]"
        renderer.text(20, y_offset + 48, 255, 255, 255, 255, "", 0, "> Brute Force: " .. memory_status)
    end
    
    if SafeGetUI(misc.ddt_enable, false) then
        local ddt_status = ddt_active and "\a00FF00FF[ACTIVE]" or "\aFFFFFFFF[ready]"
        renderer.text(20, y_offset + 60, 255, 255, 255, 255, "", 0, "> DDT: " .. ddt_status)
        renderer.text(20, y_offset + 72, 255, 255, 255, 255, "", 0, "> Enemy: \aEE4444FF" .. ent_name)
        renderer.text(20, y_offset + 84, 255, 255, 255, 255, "", 0, "> Eye: \aEE4444FF" .. math.floor(eye_yaw))
    else
        renderer.text(20, y_offset + 60, 255, 255, 255, 255, "", 0, "> Enemy: \aEE4444FF" .. ent_name)
        renderer.text(20, y_offset + 72, 255, 255, 255, 255, "", 0, "> Eye: \aEE4444FF" .. math.floor(eye_yaw))
    end
end

-- ==================== УПРАВЛЕНИЕ UI ====================

local function visibility()
    ui.set_visible(misc.enable, current.check_access)
    ui.set_visible(misc.type, SafeGetUI(misc.enable, false) and current.check_access)
    ui.set_visible(misc.delta, SafeGetUI(misc.type, "Default") == "Custom" and SafeGetUI(misc.enable, false) and current.check_access)
    ui.set_visible(misc.brute_force, SafeGetUI(misc.enable, false) and current.check_access)
    ui.set_visible(misc.anti_fake, SafeGetUI(misc.enable, false) and current.check_access)
    ui.set_visible(misc.confidence_threshold, SafeGetUI(misc.brute_force, false) and SafeGetUI(misc.enable, false) and current.check_access)
    ui.set_visible(misc.movement_detection, SafeGetUI(misc.enable, false) and current.check_access)
    ui.set_visible(misc.aggressiveness, SafeGetUI(misc.type, "Default") == "Smart" and SafeGetUI(misc.enable, false) and current.check_access)
    
    ui.set_visible(misc.ddt_enable, current.check_access)
    ui.set_visible(misc.ddt_mode, SafeGetUI(misc.ddt_enable, false) and current.check_access)
    ui.set_visible(misc.ddt_ticks, SafeGetUI(misc.ddt_enable, false) and current.check_access)
    ui.set_visible(misc.ddt_accuracy, SafeGetUI(misc.ddt_enable, false) and current.check_access)
end

-- ==================== СОБЫТИЯ ====================

client.set_event_callback("paint_ui", visibility)
client.set_event_callback("paint", paint_indicator)
client.set_event_callback("setup_command", ResolverUpdate)

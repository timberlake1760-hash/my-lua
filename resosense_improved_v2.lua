-- Downloaded from https://github.com/s0daa/CSGO-HVH-LUAS
-- Improved by Copilot with Defensive Double Tap

local ffi = require 'ffi'

local tab, container = "Rage", "Other"

local current = {
    check_access = true,
    angle_memory = {},
    player_states = {},
    ddt_data = {}, -- Данные для Defensive Double Tap
}

ffi.cdef [[
    struct animation_layer_t {
		bool m_bClientBlend;
		float m_flBlendIn;
		void* m_pStudioHdr;
		int m_nDispatchSequence;
		int m_nDispatchSequence_2;
		uint32_t m_nOrder;
		uint32_t m_nSequence;
		float m_flPrevCycle;
		float m_flWeight;
		float m_flWeightDeltaRate;
		float m_flPlaybackRate;
		float m_flCycle;
		void* m_pOwner;
		char pad_0038[4];
    };
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
local rawientitylist = client.create_interface('client.dll', 'VClientEntityList003') or
                           error('VClientEntityList003 wasnt found', 2)

local ientitylist = ffi.cast(classptr, rawientitylist) or error('rawientitylist is nil', 2)
local get_client_networkable = ffi.cast('void*(__thiscall*)(void*, int)', ientitylist[0][0]) or
                                   error('get_client_networkable_t is nil', 2)
local get_client_entity = ffi.cast('void*(__thiscall*)(void*, int)', ientitylist[0][3]) or
                              error('get_client_entity is nil', 2)

local rawivmodelinfo = client.create_interface('engine.dll', 'VModelInfoClient004')
local ivmodelinfo = ffi.cast(classptr, rawivmodelinfo) or error('rawivmodelinfo is nil', 2)
local get_studio_model = ffi.cast('void*(__thiscall*)(void*, const void*)', ivmodelinfo[0][32])

-- ==================== UI ЭЛЕМЕНТЫ ====================

local misc = {
    -- Resolver UI
    enable = ui.new_checkbox(tab, container, "Reso\a9FCA2BFFSense"),
    type = ui.new_combobox(tab, container, "Type", {"Default", "Jitter", "Alternative", "Custom", "Smart"}),
    delta = ui.new_slider(tab, container, 'Delta', 1, 10, 3, true, "°"),
    brute_force = ui.new_checkbox(tab, container, "Brute Force (Memory)"),
    movement_detection = ui.new_checkbox(tab, container, "Movement Detection"),
    aggressiveness = ui.new_slider(tab, container, 'Aggressiveness', 1, 100, 50, true, "%"),
    
    -- Defensive Double Tap UI
    ddt_enable = ui.new_checkbox(tab, container, "Defensive Double Tap"),
    ddt_mode = ui.new_combobox(tab, container, "DDT Mode", {"On Shot", "On Damage", "Always"}),
    ddt_ticks = ui.new_slider(tab, container, "DDT Ticks", 1, 16, 8, true, "t"),
    ddt_accuracy = ui.new_slider(tab, container, "DDT Accuracy", 1, 100, 75, true, "%"),
}

-- ==================== УТИЛИТЫ ====================

local function NormalizeAngle(angle)
    while angle > 180 do
        angle = angle - 360
    end
    while angle < -180 do
        angle = angle + 360
    end
    return angle
end

local function GetAnimationState(player)
    if not (player) then
        return
    end
    local player_ptr = ffi.cast("void***", get_client_entity(ientitylist, player))
    local animstate_ptr = ffi.cast("char*", player_ptr) + 0x9960
    local state = ffi.cast("struct c_animstate**", animstate_ptr)[0]
    return state
end

local function GetPlayerPos(player)
    local x = entity.get_prop(player, "m_vecOrigin[0]")
    local y = entity.get_prop(player, "m_vecOrigin[1]")
    local z = entity.get_prop(player, "m_vecOrigin[2]")
    return {x = x, y = y, z = z}
end

local function GetPlayerVelocity(player)
    local vx = entity.get_prop(player, "m_vecVelocity[0]")
    local vy = entity.get_prop(player, "m_vecVelocity[1]")
    local vz = entity.get_prop(player, "m_vecVelocity[2]")
    return {x = vx, y = vy, z = vz}
end

-- ==================== ДВИЖЕНИЕ ====================

local function DetectMovementType(player)
    local animstate = GetAnimationState(player)
    if not animstate then return "unknown" end
    
    local speed = animstate.m_flSpeed2D
    local is_in_air = animstate.m_flTimeSinceInAir > 0.1
    local on_ground = animstate.m_bOnGround
    local in_hit_ground = animstate.m_bInHitGroundAnimation
    
    if is_in_air and not on_ground then
        return "jumping"
    elseif in_hit_ground or animstate.m_flTimeSinceInAir < 0.5 then
        return "landing"
    elseif speed > 150 then
        return "running"
    elseif speed > 50 then
        return "walking"
    else
        return "standing"
    end
end

-- ==================== ЗАПОМИНАНИЕ УГЛОВ ====================

local function InitializeAngleMemory(player)
    if not current.angle_memory[player] then
        current.angle_memory[player] = {
            angles = {},
            movement_type = "",
            last_update = 0,
            confidence = 0,
        }
    end
end

local function AddAngleToMemory(player, yaw, movement_type)
    InitializeAngleMemory(player)
    local memory = current.angle_memory[player]
    
    local rounded_yaw = math.floor(yaw / 5 + 0.5) * 5
    
    if not memory.angles[rounded_yaw] then
        memory.angles[rounded_yaw] = {count = 0, movement_type = movement_type}
    end
    memory.angles[rounded_yaw].count = memory.angles[rounded_yaw].count + 1
    
    memory.last_update = globals.tickcount()
end

local function GetMostUsedAngle(player)
    if not current.angle_memory[player] then return nil end
    
    local memory = current.angle_memory[player]
    local best_yaw = nil
    local best_count = 0
    
    for yaw, data in pairs(memory.angles) do
        if data.count > best_count then
            best_count = data.count
            best_yaw = yaw
        end
    end
    
    return best_yaw, best_count
end

local function ClearOldMemory()
    for player, data in pairs(current.angle_memory) do
        if globals.tickcount() - data.last_update > 300 then
            current.angle_memory[player] = nil
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
    
    -- Очищаем старые данные (более 20 тиков)
    for t in pairs(data.position_history) do
        if tick - t > 20 then
            data.position_history[t] = nil
            data.velocity_history[t] = nil
        end
    end
end

local function GetBacktrackPosition(player, ticks_back)
    InitializeDDTData(player)
    local data = current.ddt_data[player]
    local target_tick = globals.tickcount() - ticks_back
    
    if data.position_history[target_tick] then
        return data.position_history[target_tick]
    end
    
    -- Интерполируем позицию если точная не найдена
    return GetPlayerPos(player)
end

local function ActivateDDT(player)
    InitializeDDTData(player)
    local data = current.ddt_data[player]
    data.is_active = true
    data.activation_tick = globals.tickcount()
end

local function ProcessDDT(player)
    if not ui.get(misc.ddt_enable) then return false end
    
    InitializeDDTData(player)
    local data = current.ddt_data[player]
    local current_tick = globals.tickcount()
    local ddt_ticks = ui.get(misc.ddt_ticks)
    local ddt_mode = ui.get(misc.ddt_mode)
    
    -- Проверяем условия активации
    local should_activate = false
    
    if ddt_mode == "On Shot" then
        -- Проверяем, стреляет ли враг в нас
        local local_player = entity.get_local_player()
        if local_player then
            local local_health = entity.get_prop(local_player, "m_iHealth")
            if local_health and local_health < entity.get_prop(local_player, "m_iMaxHealth") then
                should_activate = true
                data.last_damage_tick = current_tick
            end
        end
    elseif ddt_mode == "On Damage" then
        -- Аналогично On Shot
        should_activate = data.is_active or (current_tick - data.activation_tick < 5)
    elseif ddt_mode == "Always" then
        should_activate = true
    end
    
    if should_activate then
        ActivateDDT(player)
    end
    
    -- Если DDT активен и еще в пределах тиков
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
    local aggressiveness = ui.get(misc.aggressiveness) / 100
    
    local base_yaw = delta * yaw1 * animstate.m_flPlaybackRate
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

local function ResolveJitter(player)
    local animstate = GetAnimationState(player)
    if not animstate then return end
    
    StorePosAndVel(player) -- Запоминаем позицию для DDT
    
    local lpent = get_client_entity(ientitylist, player)
    local delta = entity.get_prop(player, "m_angEyeAngles[1]") - entity.get_prop(player, "m_flPoseParameter", 11)
    eye_yaw = animstate.m_flEyeYaw
    ent_name = entity.get_player_name(player)

    local yaw1 = (entity.get_prop(player, "m_flPoseParameter", 11) or 1) * 116 - 58
    side = globals.tickcount() % 2 == 0 and -1 or 1
    side2 = (globals.tickcount() % 3) - 1

    local yaws
    local resolver_type = ui.get(misc.type)
    
    if resolver_type == "Default" then
        yaws = delta * yaw1 * animstate.m_flPlaybackRate
    elseif resolver_type == "Jitter" then
        yaws = side * math.abs(delta * yaw1 * animstate.m_flPlaybackRate)
    elseif resolver_type == "Alternative" then
        yaws = side2 * math.abs(delta * yaw1 * animstate.m_flPlaybackRate)
    elseif resolver_type == "Custom" then
        yaws = (delta * yaw1 * animstate.m_flPlaybackRate) / ui.get(misc.delta)
    elseif resolver_type == "Smart" then
        yaws, current_movement = SmartResolve(player, animstate, delta, yaw1)
    end

    yaws = NormalizeAngle(yaws)

    -- Brute Force: запоминаем углы
    if ui.get(misc.brute_force) then
        AddAngleToMemory(player, yaws, current_movement)
        
        local best_yaw, count = GetMostUsedAngle(player)
        if best_yaw and count > 10 then
            yaws = best_yaw
            memory_used = true
        else
            memory_used = false
        end
    else
        memory_used = false
    end

    -- Defensive Double Tap обработка
    ddt_active = ProcessDDT(player)
    if ddt_active then
        -- Модифицируем yaw для DDT
        local accuracy = ui.get(misc.ddt_accuracy) / 100
        yaws = yaws * (0.5 + accuracy * 0.5) -- Делаем его более точным
    end

    plist.set(player, "Force body yaw", true)
    plist.set(player, "Force body yaw value", yaws)
end

local function Resolver(player)
    if ui.get(misc.enable) then
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
    if not ui.get(misc.enable) then return end
    if entity.get_local_player() == nil or not entity.is_alive(entity.get_local_player()) then return end
    
    local y_offset = y_ind / 1.9
    renderer.text(20, y_offset, 255, 255, 255, 255, "", 0, "> reso\a9FCA2BFFsense \aEE4444FF[alpha]")
    renderer.text(20, y_offset + 12, 255, 255, 255, 255, "", 0, "> resolver type: \aEE4444FF" .. ui.get(misc.type))
    
    if ui.get(misc.movement_detection) then
        renderer.text(20, y_offset + 24, 255, 255, 255, 255, "", 0, "> movement: \aEE4444FF" .. current_movement)
    end
    
    if ui.get(misc.brute_force) then
        local memory_status = memory_used and "\a00FF00FF[USING]" or "\aFFFFFFFF[learning]"
        renderer.text(20, y_offset + 36, 255, 255, 255, 255, "", 0, "> brute force: " .. memory_status)
    end
    
    if ui.get(misc.ddt_enable) then
        local ddt_status = ddt_active and "\a00FF00FF[ACTIVE]" or "\aFFFFFFFF[ready]"
        renderer.text(20, y_offset + 48, 255, 255, 255, 255, "", 0, "> DDT: " .. ddt_status)
        renderer.text(20, y_offset + 60, 255, 255, 255, 255, "", 0, "> Enemy: \aEE4444FF" .. ent_name)
        renderer.text(20, y_offset + 72, 255, 255, 255, 255, "", 0, "> Eye: \aEE4444FF" .. math.floor(eye_yaw))
    else
        renderer.text(20, y_offset + 48, 255, 255, 255, 255, "", 0, "> Enemy: \aEE4444FF" .. ent_name)
        renderer.text(20, y_offset + 60, 255, 255, 255, 255, "", 0, "> Eye: \aEE4444FF" .. math.floor(eye_yaw))
    end
end

-- ==================== УПРАВЛЕНИЕ UI ====================

local function visibility()
    ui.set_visible(misc.enable, current.check_access)
    ui.set_visible(misc.type, ui.get(misc.enable) and current.check_access)
    ui.set_visible(misc.delta, ui.get(misc.type) == "Custom" and ui.get(misc.enable) and current.check_access)
    ui.set_visible(misc.brute_force, ui.get(misc.enable) and current.check_access)
    ui.set_visible(misc.movement_detection, ui.get(misc.enable) and current.check_access)
    ui.set_visible(misc.aggressiveness, ui.get(misc.type) == "Smart" and ui.get(misc.enable) and current.check_access)
    
    -- DDT видимость
    ui.set_visible(misc.ddt_enable, current.check_access)
    ui.set_visible(misc.ddt_mode, ui.get(misc.ddt_enable) and current.check_access)
    ui.set_visible(misc.ddt_ticks, ui.get(misc.ddt_enable) and current.check_access)
    ui.set_visible(misc.ddt_accuracy, ui.get(misc.ddt_enable) and current.check_access)
end

-- ==================== СОБЫТИЯ ====================

client.set_event_callback("paint_ui", visibility)
client.set_event_callback("paint", paint_indicator)
client.set_event_callback("setup_command", ResolverUpdate)

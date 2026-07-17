-- GameSense Lua Aimbot with Logging
-- Custom aimbot script with prediction, target filtering and detailed logs

local ffi = require 'ffi'

local tab, container = "Rage", "Aimbot"

local aimbot_config = {
    check_access = true,
    target_data = {},
    shot_log = {}, -- Логи выстрелов
    max_log_entries = 100,
}

ffi.cdef [[
    struct vector_t {
        float x, y, z;
    };
]]

local classptr = ffi.typeof('void***')
local rawientitylist = client.create_interface('client.dll', 'VClientEntityList003') or
                           error('VClientEntityList003 wasnt found', 2)

local ientitylist = ffi.cast(classptr, rawientitylist) or error('rawientitylist is nil', 2)
local get_client_entity = ffi.cast('void*(__thiscall*)(void*, int)', ientitylist[0][3]) or
                              error('get_client_entity is nil', 2)

-- ==================== UI ЭЛЕМЕНТЫ ====================

local aimbot_ui = {
    -- Основные опции
    enable = ui.new_checkbox(tab, container, "Enable Aimbot"),
    mode = ui.new_combobox(tab, container, "Mode", {"Silent", "Smooth", "Flick"}),
    fov = ui.new_slider(tab, container, "FOV", 1, 180, 45, true, "°"),
    smoothness = ui.new_slider(tab, container, "Smoothness", 1, 100, 35, true, "%"),
    
    -- Целеполагание
    target_bone = ui.new_combobox(tab, container, "Target Bone", {"Head", "Neck", "Chest", "Best"}),
    prediction = ui.new_checkbox(tab, container, "Enable Prediction"),
    prediction_strength = ui.new_slider(tab, container, "Prediction Strength", 1, 100, 60, true, "%"),
    
    -- Фильтрация
    only_visible = ui.new_checkbox(tab, container, "Only Visible"),
    only_alive = ui.new_checkbox(tab, container, "Only Alive"),
    skip_teammates = ui.new_checkbox(tab, container, "Skip Teammates"),
    min_health = ui.new_slider(tab, container, "Min Enemy Health", 1, 100, 1, true, "HP"),
    
    -- Расширенные опции
    dynamic_smoothness = ui.new_checkbox(tab, container, "Dynamic Smoothness"),
    distance_smoothing = ui.new_checkbox(tab, container, "Distance Smoothing"),
    recoil_control = ui.new_slider(tab, container, "Recoil Control", 0, 100, 50, true, "%"),
    
    -- Логирование
    enable_logging = ui.new_checkbox(tab, container, "Enable Aimbot Logging"),
    log_detail_level = ui.new_combobox(tab, container, "Log Detail", {"Brief", "Normal", "Detailed"}),
    show_log_panel = ui.new_checkbox(tab, container, "Show Log Panel"),
}

-- ==================== ЛОГИРОВАНИЕ ====================

local function AddShotLog(log_data)
    if not ui.get(aimbot_ui.enable_logging) then return end
    
    table.insert(aimbot_config.shot_log, {
        tick = globals.tickcount(),
        timestamp = os.time(),
        target = log_data.target or "Unknown",
        distance = log_data.distance or 0,
        fov_angle = log_data.fov_angle or 0,
        predicted_angles = log_data.predicted_angles or {pitch = 0, yaw = 0},
        final_angles = log_data.final_angles or {pitch = 0, yaw = 0},
        mode = log_data.mode or "Unknown",
        bone = log_data.bone or "Unknown",
        hit = log_data.hit or false,
        reason = log_data.reason or "Normal shot",
        prediction_used = log_data.prediction_used or false,
        smoothness_applied = log_data.smoothness_applied or 0,
    })
    
    -- Удаляем старые логи
    if #aimbot_config.shot_log > aimbot_config.max_log_entries then
        table.remove(aimbot_config.shot_log, 1)
    end
end

local function GetLogString(log_entry)
    local detail_level = ui.get(aimbot_ui.log_detail_level)
    
    if detail_level == "Brief" then
        return string.format("[%d] %s | %.0fu | Hit: %s", 
            log_entry.tick,
            log_entry.target,
            log_entry.distance,
            log_entry.hit and "✓" or "✗"
        )
    elseif detail_level == "Normal" then
        return string.format("[%d] %s | %.0fu | FOV: %.1f° | Pitch: %.1f° | Yaw: %.1f° | Hit: %s",
            log_entry.tick,
            log_entry.target,
            log_entry.distance,
            log_entry.fov_angle,
            log_entry.final_angles.pitch,
            log_entry.final_angles.yaw,
            log_entry.hit and "✓" or "✗"
        )
    else -- Detailed
        return string.format("[%d] %s | %.0fu | FOV: %.1f° | Mode: %s | Bone: %s\n    Predicted: P:%.1f° Y:%.1f° | Final: P:%.1f° Y:%.1f°\n    Pred: %s | Smooth: %.0f%% | Hit: %s | Reason: %s",
            log_entry.tick,
            log_entry.target,
            log_entry.distance,
            log_entry.fov_angle,
            log_entry.mode,
            log_entry.bone,
            log_entry.predicted_angles.pitch,
            log_entry.predicted_angles.yaw,
            log_entry.final_angles.pitch,
            log_entry.final_angles.yaw,
            log_entry.prediction_used and "✓" or "✗",
            log_entry.smoothness_applied,
            log_entry.hit and "✓" or "✗",
            log_entry.reason
        )
    end
end

-- ==================== УТИЛИТЫ ====================

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

local function GetBonePos(player, bone)
    local bones = {
        Head = 8,
        Neck = 1,
        Chest = 6,
    }
    
    if bone == "Best" then
        local dist = GetDistance(entity.get_local_player(), player)
        if dist < 1000 then
            return entity.get_player_weapon_offset(player, 8)
        else
            return entity.get_player_weapon_offset(player, 6)
        end
    end
    
    local bone_id = bones[bone] or 8
    return entity.get_player_weapon_offset(player, bone_id)
end

local function GetDistance(player1, player2)
    local pos1 = GetPlayerPos(player1)
    local pos2 = GetPlayerPos(player2)
    
    local dx = pos1.x - pos2.x
    local dy = pos1.y - pos2.y
    local dz = pos1.z - pos2.z
    
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

local function GetAnglesToPos(from_pos, to_pos)
    local dx = to_pos.x - from_pos.x
    local dy = to_pos.y - from_pos.y
    local dz = to_pos.z - from_pos.z
    
    local distance = math.sqrt(dx*dx + dy*dy + dz*dz)
    
    local pitch = -math.deg(math.atan(dz / math.sqrt(dx*dx + dy*dy)))
    local yaw = math.deg(math.atan2(dy, dx))
    
    return {pitch = pitch, yaw = yaw, distance = distance}
end

local function NormalizeAngle(angle)
    while angle > 180 do
        angle = angle - 360
    end
    while angle < -180 do
        angle = angle + 360
    end
    return angle
end

-- ==================== ПРЕДСКАЗАНИЕ ====================

local function PredictPlayerPos(player, ticks_ahead)
    local pos = GetPlayerPos(player)
    local vel = GetPlayerVelocity(player)
    local tick_time = globals.tickinterval()
    
    local prediction_time = ticks_ahead * tick_time
    
    return {
        x = pos.x + vel.x * prediction_time,
        y = pos.y + vel.y * prediction_time,
        z = pos.z + vel.z * prediction_time,
    }
end

local function CalculatePrediction(player, strength)
    local strength_normalized = strength / 100
    local ticks_ahead = math.floor(1 + strength_normalized * 15)
    
    return PredictPlayerPos(player, ticks_ahead)
end

-- ==================== ФИЛЬТРАЦИЯ ЦЕЛЕЙ ====================

local function IsValidTarget(player)
    if not player or player == entity.get_local_player() then
        return false
    end
    
    if ui.get(aimbot_ui.only_alive) and not entity.is_alive(player) then
        return false
    end
    
    if ui.get(aimbot_ui.only_visible) and not entity.is_visible(player) then
        return false
    end
    
    local player_health = entity.get_prop(player, "m_iHealth")
    if player_health < ui.get(aimbot_ui.min_health) then
        return false
    end
    
    if ui.get(aimbot_ui.skip_teammates) then
        if entity.get_prop(player, "m_iTeamNum") == entity.get_prop(entity.get_local_player(), "m_iTeamNum") then
            return false
        end
    end
    
    if entity.is_dormant(player) or entity.get_prop(player, "m_bDormant") then
        return false
    end
    
    return true
end

-- ==================== ВЫБОР ЦЕЛИ ====================

local current_target = nil

local function FindBestTarget()
    local local_player = entity.get_local_player()
    if not local_player or not entity.is_alive(local_player) then
        return nil
    end
    
    local best_target = nil
    local best_score = math.huge
    local fov_range = ui.get(aimbot_ui.fov)
    local local_pos = GetPlayerPos(local_player)
    local local_angles = entity.get_local_player_view_angles()
    
    local enemies = entity.get_players(true)
    
    for i, enemy in ipairs(enemies) do
        if IsValidTarget(enemy) then
            local enemy_pos = GetPlayerPos(enemy)
            local angles_to_enemy = GetAnglesToPos(local_pos, enemy_pos)
            
            local yaw_diff = NormalizeAngle(angles_to_enemy.yaw - local_angles[2])
            local pitch_diff = NormalizeAngle(angles_to_enemy.pitch - local_angles[1])
            
            local angle_diff = math.sqrt(yaw_diff*yaw_diff + pitch_diff*pitch_diff)
            
            if angle_diff <= fov_range then
                local distance = GetDistance(local_player, enemy)
                local score = angle_diff + (distance / 1000)
                
                if score < best_score then
                    best_score = score
                    best_target = enemy
                end
            end
        end
    end
    
    return best_target
end

-- ==================== ПЛАВНОСТЬ ====================

local function ApplySmoothing(from_angle, to_angle, smoothness)
    local smooth_factor = (100 - smoothness) / 100
    
    local yaw_diff = NormalizeAngle(to_angle.yaw - from_angle.yaw)
    local pitch_diff = NormalizeAngle(to_angle.pitch - from_angle.pitch)
    
    return {
        pitch = from_angle.pitch + pitch_diff * smooth_factor,
        yaw = from_angle.yaw + yaw_diff * smooth_factor,
    }
end

local function GetDynamicSmoothness(distance, base_smoothness)
    local distance_factor = math.min(distance / 3000, 1)
    return base_smoothness + (distance_factor * 30)
end

-- ==================== ГЛАВНЫЙ AIMBOT ====================

local last_angles = {pitch = 0, yaw = 0}
local last_shot_target = nil

local function AimbotThink()
    if not ui.get(aimbot_ui.enable) then
        return
    end
    
    if aimbot_config.check_access == false then
        return
    end
    
    local local_player = entity.get_local_player()
    if not local_player or not entity.is_alive(local_player) then
        current_target = nil
        return
    end
    
    local target = FindBestTarget()
    
    if not target then
        current_target = nil
        return
    end
    
    current_target = target
    
    local local_pos = GetPlayerPos(local_player)
    local local_angles = entity.get_local_player_view_angles()
    
    local target_pos = GetPlayerPos(target)
    local prediction_used = false
    
    if ui.get(aimbot_ui.prediction) then
        target_pos = CalculatePrediction(target, ui.get(aimbot_ui.prediction_strength))
        prediction_used = true
    end
    
    local bone = ui.get(aimbot_ui.target_bone)
    local bone_offset = GetBonePos(target, bone)
    
    if bone_offset then
        target_pos.x = target_pos.x + bone_offset.x
        target_pos.y = target_pos.y + bone_offset.y
        target_pos.z = target_pos.z + bone_offset.z
    end
    
    local target_angles = GetAnglesToPos(local_pos, target_pos)
    
    local smoothness = ui.get(aimbot_ui.smoothness)
    
    if ui.get(aimbot_ui.dynamic_smoothness) then
        smoothness = GetDynamicSmoothness(target_angles.distance, smoothness)
    end
    
    local final_angles = ApplySmoothing(last_angles, target_angles, smoothness)
    
    local recoil_control = ui.get(aimbot_ui.recoil_control) / 100
    local punch_angles = entity.get_prop(local_player, "m_aimPunchAngle")
    
    if punch_angles then
        final_angles.pitch = final_angles.pitch - (punch_angles[1] * recoil_control)
        final_angles.yaw = final_angles.yaw - (punch_angles[2] * recoil_control)
    end
    
    last_angles = final_angles
    
    -- Рассчитываем угол от центра экрана до цели
    local yaw_diff = NormalizeAngle(target_angles.yaw - local_angles[2])
    local pitch_diff = NormalizeAngle(target_angles.pitch - local_angles[1])
    local fov_angle = math.sqrt(yaw_diff*yaw_diff + pitch_diff*pitch_diff)
    
    local mode = ui.get(aimbot_ui.mode)
    
    if mode == "Silent" then
        plist.set(current_target, "Force body yaw", true)
        plist.set(current_target, "Force body yaw value", final_angles.yaw)
    elseif mode == "Smooth" or mode == "Flick" then
        local cmd = user_cmd.get()
        if cmd then
            cmd.viewangles = {final_angles.pitch, final_angles.yaw, 0}
        end
    end
    
    last_shot_target = target
    
    -- Логируем выстрел
    AddShotLog({
        target = entity.get_player_name(target),
        distance = target_angles.distance,
        fov_angle = fov_angle,
        predicted_angles = target_angles,
        final_angles = final_angles,
        mode = mode,
        bone = bone,
        prediction_used = prediction_used,
        smoothness_applied = smoothness,
    })
end

-- ==================== UI ИНДИКАТОР И ЛОГИ ====================

local x_ind, y_ind = client.screen_size()

local function paint_aimbot()
    if not ui.get(aimbot_ui.enable) then return end
    
    local y_offset = y_ind / 2
    
    if current_target then
        local target_name = entity.get_player_name(current_target)
        local distance = GetDistance(entity.get_local_player(), current_target)
        
        renderer.text(20, y_offset, 0, 255, 0, 255, "", 0, "> Aimbot: \a00FF00FF[ACTIVE]")
        renderer.text(20, y_offset + 12, 255, 255, 255, 255, "", 0, "> Target: \aEE4444FF" .. target_name)
        renderer.text(20, y_offset + 24, 255, 255, 255, 255, "", 0, "> Distance: \aEE4444FF" .. math.floor(distance) .. "u")
        renderer.text(20, y_offset + 36, 255, 255, 255, 255, "", 0, "> Mode: \aEE4444FF" .. ui.get(aimbot_ui.mode))
    else
        renderer.text(20, y_offset, 255, 100, 100, 255, "", 0, "> Aimbot: \aFFFFFFFF[No target]")
    end
    
    -- Отображаем логи
    if ui.get(aimbot_ui.show_log_panel) and ui.get(aimbot_ui.enable_logging) then
        local log_x = 20
        local log_y = y_ind - 300
        
        renderer.text(log_x, log_y, 200, 200, 255, 255, "", 0, "=== AIMBOT LOG ===")
        
        local start_index = math.max(1, #aimbot_config.shot_log - 10)
        local y_pos = log_y + 15
        
        for i = start_index, #aimbot_config.shot_log do
            local log_entry = aimbot_config.shot_log[i]
            local log_string = GetLogString(log_entry)
            
            -- Выбираем цвет в зависимости от попадания
            local r, g, b = 255, 100, 100 -- Красный для промаха
            if log_entry.hit then
                r, g, b = 100, 255, 100 -- Зелёный для попадания
            end
            
            renderer.text(log_x, y_pos, r, g, b, 255, "", 0, log_string)
            y_pos = y_pos + 12
        end
        
        renderer.text(log_x, y_pos + 5, 150, 150, 150, 255, "", 0, string.format("Total shots: %d", #aimbot_config.shot_log))
    end
end

-- ==================== УПРАВЛЕНИЕ UI ====================

local function visibility()
    ui.set_visible(aimbot_ui.enable, true)
    ui.set_visible(aimbot_ui.mode, ui.get(aimbot_ui.enable))
    ui.set_visible(aimbot_ui.fov, ui.get(aimbot_ui.enable))
    ui.set_visible(aimbot_ui.smoothness, ui.get(aimbot_ui.enable))
    ui.set_visible(aimbot_ui.target_bone, ui.get(aimbot_ui.enable))
    ui.set_visible(aimbot_ui.prediction, ui.get(aimbot_ui.enable))
    ui.set_visible(aimbot_ui.prediction_strength, ui.get(aimbot_ui.enable) and ui.get(aimbot_ui.prediction))
    ui.set_visible(aimbot_ui.only_visible, ui.get(aimbot_ui.enable))
    ui.set_visible(aimbot_ui.only_alive, ui.get(aimbot_ui.enable))
    ui.set_visible(aimbot_ui.skip_teammates, ui.get(aimbot_ui.enable))
    ui.set_visible(aimbot_ui.min_health, ui.get(aimbot_ui.enable))
    ui.set_visible(aimbot_ui.dynamic_smoothness, ui.get(aimbot_ui.enable))
    ui.set_visible(aimbot_ui.distance_smoothing, ui.get(aimbot_ui.enable))
    ui.set_visible(aimbot_ui.recoil_control, ui.get(aimbot_ui.enable))
    
    ui.set_visible(aimbot_ui.enable_logging, ui.get(aimbot_ui.enable))
    ui.set_visible(aimbot_ui.log_detail_level, ui.get(aimbot_ui.enable_logging) and ui.get(aimbot_ui.enable))
    ui.set_visible(aimbot_ui.show_log_panel, ui.get(aimbot_ui.enable_logging) and ui.get(aimbot_ui.enable))
end

-- ==================== СОБЫТИЯ ====================

client.set_event_callback("paint_ui", visibility)
client.set_event_callback("paint", paint_aimbot)
client.set_event_callback("setup_command", AimbotThink)

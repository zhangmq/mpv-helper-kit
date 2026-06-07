-- 着色器快捷键（Ctrl+Alt 前缀兼容 Celluloid）
-- 手动设置的状态在视频切换时保持
local system_dir = "/usr/share/mpv-shim-default-shaders/shaders/"

local fsrcnnx_path = system_dir .. "FSRCNNX_x2_8-0-4-1.glsl"

local anime4k = {
    { path = system_dir .. "Anime4K_Restore_CNN_L.glsl",   name = "Anime4K L" },
    { path = system_dir .. "Anime4K_Restore_CNN_M.glsl",   name = "Anime4K M" },
    { path = system_dir .. "Anime4K_Restore_CNN_S.glsl",   name = "Anime4K S" },
}
local a4k_index = 0
local a4k_paths = {}
for _, a in ipairs(anime4k) do a4k_paths[a.path] = true end

local cas_path = system_dir .. "CAS-scaled.glsl"
local cas_levels = { 0.0, 0.5, 1.0 }
local cas_index = 0

local function log(level, msg) mp.msg.log(level, "[shader-keys] " .. msg) end

-- 读当前 mpv 状态，同步脚本内部索引
local function sync_indexes(list, opts)
    a4k_index, cas_index = 0, 0
    for _, s in ipairs(list) do
        if a4k_paths[s] then
            for i, a in ipairs(anime4k) do if s == a.path then a4k_index = i; break end end
        end
        if s == cas_path then
            local val = opts:match("SHARPENING=([%d.]+)")
            if val then
                for i, lvl in ipairs(cas_levels) do
                    if math.abs(lvl - tonumber(val)) < 0.05 then cas_index = i; break end
                end
            else
                cas_index = 1  -- CAS loaded but no opts → default SHARPENING=0.0
            end
        end
    end
end

-- 保存当前 mpv 状态
local function save_state()
    return {
        shaders = mp.get_property_native("glsl-shaders", {}),
        opts    = mp.get_property("glsl-shader-opts", ""),
    }
end

-- 恢复状态到 mpv（先 opts 再 shaders，确保 CAS 编译时拿到正确的 SHARPENING）
local function apply_state(state)
    if state.opts ~= "" then
        mp.set_property("glsl-shader-opts", state.opts)
    end
    mp.set_property_native("glsl-shaders", state.shaders)
    sync_indexes(state.shaders, state.opts)
    log("info", "applied: " .. #state.shaders .. " shaders, opts=" .. state.opts)
end

local saved_state = nil

-- 视频切换：观察 shader 列表变化，检测到 profile 覆盖后恢复
local restoring = false
mp.observe_property("glsl-shaders", "native", function()
    if restoring then return end  -- 防止递归
    if not saved_state then
        -- 首次记录（等 profile 设完后再抓）
        mp.add_timeout(0.1, function()
            saved_state = save_state()
            sync_indexes(saved_state.shaders, saved_state.opts)
            log("info", "init: " .. #saved_state.shaders .. " shaders, opts=" .. saved_state.opts)
        end)
        return
    end
    -- 检查当前是否与保存的状态一致
    local current = mp.get_property_native("glsl-shaders", {})
    local current_opts = mp.get_property("glsl-shader-opts", "")
    if #current ~= #saved_state.shaders or current_opts ~= saved_state.opts then
        restoring = true
        apply_state(saved_state)
        restoring = false
        return
    end
    for i = 1, #current do
        if current[i] ~= saved_state.shaders[i] then
            restoring = true
            apply_state(saved_state)
            restoring = false
            return
        end
    end
    -- 一致，同步索引
    sync_indexes(current, current_opts)
end)

-- 构建 OSD 标签
local function shader_label(s, opts)
    local base = s:match("([^/]+)%.glsl$") or s
    if base:find("FSRCNNX") then return "FSRCNNX"
    elseif base:find("Anime4K_Restore_CNN") then
        return "Anime4K " .. (base:match("Restore_CNN_(.+)$") or "?")
    elseif base:find("CAS") then
        local val = opts:match("SHARPENING=([%d.]+)") or "0.0"
        return "CAS " .. val
    else return base
    end
end

-- Ctrl+Alt+i：显示 mpv 真实状态
mp.add_key_binding("Ctrl+Alt+i", "shader-status", function()
    local list = mp.get_property_native("glsl-shaders", {})
    local opts = mp.get_property("glsl-shader-opts", "")
    local parts = {}
    for _, s in ipairs(list) do
        table.insert(parts, shader_label(s, opts))
    end
    local msg = #parts > 0 and table.concat(parts, " + ") or "着色器: 无"
    log("info", msg)
    mp.osd_message(msg, 3)
end)

-- 便捷包装：操作后保存
local function commit(fn)
    return function()
        fn()
        saved_state = save_state()
        sync_indexes(saved_state.shaders, saved_state.opts)
    end
end

-- Ctrl+Alt+f：FSRCNNX toggle
mp.add_key_binding("Ctrl+Alt+f", "fsrcnnx", commit(function()
    local list = mp.get_property_native("glsl-shaders", {})
    local found, keep = false, {}
    for _, s in ipairs(list) do
        if s == fsrcnnx_path then found = true else table.insert(keep, s) end
    end
    if found then
        mp.set_property_native("glsl-shaders", keep)
        log("info", "FSRCNNX 关")
        mp.osd_message("FSRCNNX 关")
    else
        table.insert(keep, fsrcnnx_path)
        mp.set_property_native("glsl-shaders", keep)
        log("info", "FSRCNNX 开")
        mp.osd_message("FSRCNNX 开")
    end
end))

-- Ctrl+Alt+a：Anime4K 循环
mp.add_key_binding("Ctrl+Alt+a", "anime4k-cycle", commit(function()
    local list = mp.get_property_native("glsl-shaders", {})
    local keep, current = {}, 0
    for _, s in ipairs(list) do
        if a4k_paths[s] then
            for i, a in ipairs(anime4k) do if s == a.path then current = i; break end end
        else table.insert(keep, s) end
    end
    if current > 0 then
        a4k_index = current + 1
        if a4k_index > #anime4k then
            a4k_index = 0
            mp.set_property_native("glsl-shaders", keep)
            log("info", "Anime4K 关")
            mp.osd_message("Anime4K 关")
            return
        end
    else
        a4k_index = 1
    end
    table.insert(keep, anime4k[a4k_index].path)
    mp.set_property_native("glsl-shaders", keep)
    log("info", anime4k[a4k_index].name)
    mp.osd_message(anime4k[a4k_index].name)
end))

-- Ctrl+Alt+c：CAS 循环
mp.add_key_binding("Ctrl+Alt+c", "cas-cycle", commit(function()
    local list = mp.get_property_native("glsl-shaders", {})
    local keep, active = {}, false
    for _, s in ipairs(list) do
        if s == cas_path then active = true else table.insert(keep, s) end
    end
    if active then
        cas_index = cas_index + 1
        if cas_index > #cas_levels then
            cas_index = 0
            mp.set_property_native("glsl-shaders", keep)
            mp.set_property("glsl-shader-opts", "")
            log("info", "CAS 关")
            mp.osd_message("CAS 关")
            return
        end
    else
        cas_index = 1
    end
    mp.set_property("glsl-shader-opts", "SHARPENING=" .. string.format("%.1f", cas_levels[cas_index]))
    table.insert(keep, cas_path)
    mp.set_property_native("glsl-shaders", keep)
    log("info", "CAS " .. cas_levels[cas_index])
    mp.osd_message("CAS " .. string.format("%.1f", cas_levels[cas_index]))
end))

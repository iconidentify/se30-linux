-- Remote control for MAME: polls /work/ctl/cmd for commands, runs them in
-- emulated time, and writes /work/ctl/status ("busy"/"idle <time>").
local CMD, STATUS = "/work/ctl/cmd", "/work/ctl/status"
local queue, keys = {}, nil
local mouse_acc = {0, 0}
local cur = nil          -- current action state
local function now() return manager.machine.time:as_double() end
local function port(tag) return manager.machine.ioport.ports[tag] end
local function mfield(axis) return port(":macadb:MOUSE" .. axis).fields[axis == 1 and "Mouse X" or "Mouse Y"] end
local function button() return port(":macadb:MOUSE0").fields["Mouse Button 0"] end

local function build_keys()
    keys = {}
    for tag, p in pairs(manager.machine.ioport.ports) do
        if tag:find(":macadb:KEY") then
            for name, f in pairs(p.fields) do
                local k = name:match("^(%S)  %S$") or name:lower()
                keys[k] = f
            end
        end
    end
    keys["cmd"] = keys["command / open apple"]
    keys["option"] = keys["option / solid apple"]
    keys["return"] = keys["return"]
    keys["."] = keys["."]
end

local function status(s)
    local f = io.open(STATUS, "w"); if f then f:write(s .. "\n"); f:close() end
end

local function poll()
    local f = io.open(CMD, "r")
    if not f then return end
    for line in f:lines() do
        if line:match("%S") then queue[#queue + 1] = line end
    end
    f:close(); os.remove(CMD)
    status("busy")
end

local function start(line)
    local a = {}
    for w in line:gmatch("%S+") do a[#a + 1] = w end
    local op = a[1]
    if op == "mouse" then
        cur = {op = "mouse", dx = tonumber(a[2]), dy = tonumber(a[3]), step = tonumber(a[4] or 4)}
    elseif op == "down" or op == "up" then
        button():set_value(op == "down" and 1 or 0)
        cur = {op = "wait", t = now() + 0.15}
    elseif op == "click" then
        button():set_value(1)
        cur = {op = "release", t = now() + 0.15, f = {button()}}
    elseif op == "key" then
        -- key <k> [mod ...]: hold mods + key briefly
        local fs = {}
        for i = 3, #a do fs[#fs + 1] = keys[a[i]] end
        fs[#fs + 1] = keys[a[2]]
        for _, f in ipairs(fs) do f:set_value(1) end
        cur = {op = "release", t = now() + 0.2, f = fs}
    elseif op == "type" then
        manager.machine.natkeyboard:post(line:sub(6))
        cur = {op = "typing"}
    elseif op == "wait" then
        cur = {op = "wait", t = now() + tonumber(a[2])}
    elseif op == "snap" then
        manager.machine.screens[":screen"]:snapshot(a[2] .. ".png")
        cur = nil
    elseif op == "quit" then
        manager.machine:exit()
    else
        print("remote: unknown command " .. line); cur = nil
    end
end

sub = emu.add_machine_frame_notifier(function()
    if not keys then build_keys(); status("idle 0") end
    poll()
    if cur then
        if cur.op == "mouse" then
            -- move a few units per frame so the Mac sees small, steady deltas
            local sx = math.max(-cur.step, math.min(cur.step, cur.dx))
            local sy = math.max(-cur.step, math.min(cur.step, cur.dy))
            mouse_acc[1] = mouse_acc[1] + sx; mouse_acc[2] = mouse_acc[2] + sy
            mfield(1):set_value(mouse_acc[1] % 256); mfield(2):set_value(mouse_acc[2] % 256)
            cur.dx = cur.dx - sx; cur.dy = cur.dy - sy
            if cur.dx == 0 and cur.dy == 0 then cur = {op = "wait", t = now() + 0.1} end
        elseif cur.op == "release" then
            if now() >= cur.t then
                for _, f in ipairs(cur.f) do f:set_value(0) end
                cur = {op = "wait", t = now() + 0.15}
            end
        elseif cur.op == "wait" then
            if now() >= cur.t then cur = nil end
        elseif cur.op == "typing" then
            if manager.machine.natkeyboard.empty then cur = {op = "wait", t = now() + 0.3} end
        end
        return
    end
    if #queue > 0 then
        start(table.remove(queue, 1))
    elseif cur == nil then
        status(string.format("idle %.1f", now()))
    end
end)

_addon.name = 'ImpossibleGauge'
_addon.version = '1.2'
_addon.author = 'Garrett'
_addon.commands = {'ig', 'impossiblegauge'}

require('logger')
packets = require('packets')
config  = require('config')
texts   = require('texts')

local defaults = {
    enabled = false,
    range = 50,
    delay = 2.0,
    scan_interval = 5.0,
    recheck_time = 120,
    sound = true,
    sound_file = '',
    chat_color = 200,
    suppress = true,
    suppress_window = 3.0,
    hud = {
        visible = true,
        max_confirmed_shown = 8,
        pos  = {x = 10, y = 300},
        bg   = {red = 0, green = 0, blue = 0, alpha = 160, visible = true},
        text = {font = 'Consolas', size = 11, red = 255, green = 255, blue = 255, alpha = 255},
        flags = {draggable = true, bold = false, italic = false},
        padding = 4,
    },
}

local settings = config.load(defaults)

-- state
local checked = {}            -- [mob_id] = os.time() last /check sent
local confirmed = {}           -- [mob_id] = name
local confirmed_order = {}     -- insertion order list of mob_ids
local pending = {}             -- [mob_id] = {id, index, name}
local pending_count = 0
local last_check_time = 0
local last_scan_time = 0
local last_hud_update = 0
local current_checking = nil   -- name of mob we most recently /check'd
local current_checking_until = 0
local total_checks_sent = 0
local alert_until = 0          -- os.clock() timestamp; flash HUD while > now
local recent_check_names = {}  -- [mob_name] = os.clock() of most recent auto-check
local last_suppress_gc = 0

-- HUD
local hud = texts.new('', settings.hud, settings)
hud:visible(settings.hud.visible)

local function chat(msg)
    windower.add_to_chat(settings.chat_color, '[IG] ' .. msg)
end

local function notify(name)
    windower.add_to_chat(settings.chat_color, ('[IG] >>> IMPOSSIBLE TO GAUGE: %s <<<'):format(name))
    if settings.sound and settings.sound_file ~= '' then
        windower.play_sound(settings.sound_file)
    end
    alert_until = os.clock() + 5.0
end

local function update_hud()
    if not settings.hud.visible then
        hud:hide()
        return
    end

    local now = os.clock()
    local flashing = now < alert_until
    local status_color = settings.enabled and '|cFF80FF80|ON|r' or '|cFFFF8080|OFF|r'
    -- texts lib doesn't do color codes — simulate with plain markers
    local state_tag = settings.enabled and '[ON]' or '[OFF]'

    local lines = {}
    table.insert(lines, ('ImpossibleGauge %s  range=%dy  delay=%.1fs')
        :format(state_tag, settings.range, settings.delay))
    table.insert(lines, ('Queue: %-3d  Sent: %-4d  Confirmed: %d')
        :format(pending_count, total_checks_sent, #confirmed_order))

    if current_checking and now < current_checking_until then
        table.insert(lines, 'Checking: ' .. current_checking)
    else
        table.insert(lines, 'Checking: --')
    end

    if #confirmed_order > 0 then
        table.insert(lines, '--- Impossible to Gauge ---')
        local start = math.max(1, #confirmed_order - settings.hud.max_confirmed_shown + 1)
        for i = start, #confirmed_order do
            local id = confirmed_order[i]
            local name = confirmed[id] or ('ID ' .. tostring(id))
            local prefix = (i == #confirmed_order and flashing) and ' >> ' or '  - '
            table.insert(lines, prefix .. name)
        end
    end

    hud:text(table.concat(lines, '\n'))

    if flashing then
        hud:bg_color(120, 0, 0)
        hud:bg_alpha(220)
    else
        hud:bg_color(settings.hud.bg.red, settings.hud.bg.green, settings.hud.bg.blue)
        hud:bg_alpha(settings.hud.bg.alpha)
    end

    hud:show()
end

local function scan()
    local self_info = windower.ffxi.get_info()
    if not self_info or not self_info.logged_in then return end
    local player_mob = windower.ffxi.get_mob_by_target('me')
    if not player_mob then return end

    local mobs = windower.ffxi.get_mob_array()
    if not mobs then return end

    local now = os.time()
    local range_sq = settings.range * settings.range

    for _, mob in pairs(mobs) do
        if mob
            and mob.id and mob.id > 0
            and mob.spawn_type == 16
            and mob.valid_target
            and mob.hpp and mob.hpp > 0
            and not confirmed[mob.id]
            and not pending[mob.id]
        then
            local last = checked[mob.id]
            if not last or (now - last) > settings.recheck_time then
                local dx = mob.x - player_mob.x
                local dy = mob.y - player_mob.y
                local dz = (mob.z or 0) - (player_mob.z or 0)
                if (dx*dx + dy*dy + dz*dz) <= range_sq then
                    pending[mob.id] = {id = mob.id, index = mob.index, name = mob.name}
                    pending_count = pending_count + 1
                end
            end
        end
    end
end

local function send_check(target)
    local p = packets.new('outgoing', 0x0DD, {
        ['Target'] = target.id,
        ['Target Index'] = target.index,
        ['Check Type'] = 0,
    })
    packets.inject(p)
end

windower.register_event('prerender', function()
    local now = os.clock()

    if settings.enabled then
        if now - last_scan_time >= settings.scan_interval then
            last_scan_time = now
            scan()
        end

        if now - last_check_time >= settings.delay and pending_count > 0 then
            local id, target = next(pending)
            if id then
                pending[id] = nil
                pending_count = pending_count - 1
                local mob = windower.ffxi.get_mob_by_id(id)
                if mob and mob.spawn_type == 16 and mob.valid_target and mob.hpp and mob.hpp > 0 then
                    send_check(target)
                    checked[id] = os.time()
                    last_check_time = now
                    current_checking = target.name
                    current_checking_until = now + settings.delay + 1.0
                    total_checks_sent = total_checks_sent + 1
                    if target.name and target.name ~= '' then
                        recent_check_names[target.name] = now
                    end
                end
            end
        end
    end

    if now - last_hud_update >= 0.2 then
        last_hud_update = now
        update_hud()
    end
end)

windower.register_event('incoming text', function(original, modified, mode)
    if not settings.suppress then return end
    if not original or original == '' then return end
    if original:sub(1, 4) == '[IG]' then return end

    local now = os.clock()
    if now - last_suppress_gc > 1.0 then
        last_suppress_gc = now
        for name, t in pairs(recent_check_names) do
            if now - t > settings.suppress_window then
                recent_check_names[name] = nil
            end
        end
    end

    for name, t in pairs(recent_check_names) do
        if now - t <= settings.suppress_window and original:find(name, 1, true) then
            return true
        end
    end
end)

windower.register_event('incoming chunk', function(id, data)
    if id ~= 0x029 then return end
    local p = packets.parse('incoming', data)
    if not p then return end
    if p['Message'] ~= 249 then return end

    local target_id = p['Target']
    if not target_id or confirmed[target_id] then return end

    local mob = windower.ffxi.get_mob_by_id(target_id)
    local name = (mob and mob.name) or ('ID ' .. tostring(target_id))
    confirmed[target_id] = name
    table.insert(confirmed_order, target_id)
    notify(name)
end)

windower.register_event('zone change', function()
    checked = {}
    confirmed = {}
    confirmed_order = {}
    pending = {}
    pending_count = 0
    current_checking = nil
    total_checks_sent = 0
    alert_until = 0
    recent_check_names = {}
end)

windower.register_event('unload', function()
    hud:hide()
end)

local function show_status()
    chat(('enabled=%s  range=%d  delay=%.1fs  scan=%.1fs  sound=%s  hud=%s  suppress=%s')
        :format(tostring(settings.enabled), settings.range, settings.delay,
                settings.scan_interval, tostring(settings.sound),
                tostring(settings.hud.visible), tostring(settings.suppress)))
end

windower.register_event('addon command', function(cmd, ...)
    cmd = (cmd or 'toggle'):lower()
    local args = {...}

    if cmd == 'on' then
        settings.enabled = true
        config.save(settings)
        chat('enabled')
    elseif cmd == 'off' then
        settings.enabled = false
        config.save(settings)
        chat('disabled')
    elseif cmd == 'toggle' then
        settings.enabled = not settings.enabled
        config.save(settings)
        chat(settings.enabled and 'enabled' or 'disabled')
    elseif cmd == 'range' and args[1] then
        local v = tonumber(args[1])
        if v and v > 0 then
            settings.range = v
            config.save(settings)
            chat(('range = %d yalms'):format(settings.range))
        end
    elseif cmd == 'delay' and args[1] then
        local v = tonumber(args[1])
        if v and v >= 0.5 then
            settings.delay = v
            config.save(settings)
            chat(('delay = %.2fs'):format(settings.delay))
        else
            chat('delay must be >= 0.5s')
        end
    elseif cmd == 'scan' and args[1] then
        local v = tonumber(args[1])
        if v and v >= 1 then
            settings.scan_interval = v
            config.save(settings)
            chat(('scan interval = %.1fs'):format(settings.scan_interval))
        end
    elseif cmd == 'sound' then
        settings.sound = not settings.sound
        config.save(settings)
        chat('sound ' .. (settings.sound and 'on' or 'off'))
    elseif cmd == 'suppress' then
        local sub = (args[1] or 'toggle'):lower()
        if sub == 'on' then
            settings.suppress = true
        elseif sub == 'off' then
            settings.suppress = false
        else
            settings.suppress = not settings.suppress
        end
        config.save(settings)
        chat('chat suppression ' .. (settings.suppress and 'on' or 'off'))
    elseif cmd == 'soundfile' and args[1] then
        settings.sound_file = table.concat(args, ' ')
        config.save(settings)
        chat('sound file = ' .. settings.sound_file)
    elseif cmd == 'hud' then
        local sub = (args[1] or 'toggle'):lower()
        if sub == 'show' or sub == 'on' then
            settings.hud.visible = true
        elseif sub == 'hide' or sub == 'off' then
            settings.hud.visible = false
        else
            settings.hud.visible = not settings.hud.visible
        end
        config.save(settings)
        chat('hud ' .. (settings.hud.visible and 'shown' or 'hidden'))
    elseif cmd == 'test' then
        local name = table.concat(args, ' ')
        if name == '' then name = 'Test NM' end
        local fake_id = -1 * math.random(1000, 9999)
        if not confirmed[fake_id] then
            confirmed[fake_id] = name
            table.insert(confirmed_order, fake_id)
        end
        notify(name)
    elseif cmd == 'clear' then
        checked = {}
        confirmed = {}
        confirmed_order = {}
        pending = {}
        pending_count = 0
        current_checking = nil
        total_checks_sent = 0
        alert_until = 0
        recent_check_names = {}
        chat('tracking cleared')
    elseif cmd == 'list' then
        if #confirmed_order > 0 then
            chat('confirmed impossible-to-gauge:')
            for _, id in ipairs(confirmed_order) do
                windower.add_to_chat(settings.chat_color, '   - ' .. confirmed[id])
            end
        else
            chat('no confirmations yet')
        end
    elseif cmd == 'status' then
        show_status()
    elseif cmd == 'help' then
        chat('commands:')
        local c = settings.chat_color
        windower.add_to_chat(c, '  //ig on | off | toggle')
        windower.add_to_chat(c, '  //ig range <yalms>     (default 50)')
        windower.add_to_chat(c, '  //ig delay <seconds>   (default 2.0)')
        windower.add_to_chat(c, '  //ig scan <seconds>    (default 5.0)')
        windower.add_to_chat(c, '  //ig sound             toggle sound alert')
        windower.add_to_chat(c, '  //ig soundfile <path>  set .wav path')
        windower.add_to_chat(c, '  //ig suppress [on|off] hide auto-check chat spam')
        windower.add_to_chat(c, '  //ig hud [on|off]      show/hide HUD')
        windower.add_to_chat(c, '  //ig test [name]       fire a fake alert')
        windower.add_to_chat(c, '  //ig clear             reset tracking')
        windower.add_to_chat(c, '  //ig list              list confirmed mobs')
        windower.add_to_chat(c, '  //ig status')
    else
        chat('unknown command - type //ig help')
    end
end)

chat(('loaded v%s - type //ig help'):format(_addon.version))

local module_path = (...):match ("(.+/)[^/]+$") or ""

local ipairs = ipairs
local tonumber = tonumber
local io = require("io")
local math = require("math")
local os = require("os")
local string = require("string")

module("pomodoro.impl")

return function(wibox, awful, naughty, beautiful, timer, awesome, base)
    -- pomodoro timer widget
    pomodoro = wibox.widget.base.make_widget()
    -- tweak these values in seconds to your liking
    pomodoro.short_pause_duration = 5 * 60
    pomodoro.long_pause_duration = 15 * 60
    pomodoro.work_duration = 25 * 60
    pomodoro.npomodoros = 0
    pomodoro.pause_duration = pomodoro.short_pause_duration

    pomodoro.change = 60
    pomodoro.module_path = module_path
    pomodoro.changed = false
    pomodoro.changed_timer = timer({timeout = 3})
    pomodoro.changed_timer:connect_signal("timeout", function ()
        pomodoro.changed=false
        pomodoro.changed_timer:again()
        pomodoro.changed_timer:stop()
        pomodoro.widget:set_markup(pomodoro.format(pomodoro.work_duration))
        pomodoro.icon_widget:set_markup(pomodoro.format_icon(pomodoro.work_duration))
    end)

    pomodoro.format = function (t)
        if pomodoro.changed or pomodoro.timer.started then
            return string.format("<span font='%s'>%s</span>", beautiful.font, t)
        else
            return ""
        end
    end

    pomodoro.format_icon = function (t)
        return pomodoro.pomodoro_icon()
    end

    pomodoro.pause_title = "Pause finished."
    pomodoro.pause_text = "Get back to work!"
    pomodoro.work_title = "Pomodoro finished."
    pomodoro.work_text = "Time for a pause!"
    pomodoro.is_running = false
    pomodoro.working = true
    pomodoro.auto_start_pomodoro = true
    pomodoro.widget = wibox.widget.textbox()
    pomodoro.icon_widget = wibox.widget.textbox()
    pomodoro.timer = timer { timeout = 1 }

    function pomodoro.pomodoro_icon()
        local color
        local red   = beautiful.pomodoro_work or "#FF0000"
        local green = beautiful.pomodoro_pause  or "#00FF00"

        if not pomodoro.is_running then
            -- Color for when the timer has not yet started
            color = beautiful.pomodoro_inactive or "#C0C0C0"
        elseif pomodoro.left > 0 then
            -- Color for when the timer has been started
            color = pomodoro.fade_color(green, red)
        else
            -- Color for when the timer has expired
            color = red
        end

        color = string.format("fgcolor='%s'", color)
        local font = "font='Noto Emoji 12'"
        local markup = "<span %s %s>&#127813;</span>"
        return markup:format(color, font)
    end

    function pomodoro.split_rgb(color)
        -- Return a table of three elements: the hex values of
        -- each of the pairs of `color`

        local r = tonumber(color:sub(2, 3), 16)
        local g = tonumber(color:sub(4, 5), 16)
        local b = tonumber(color:sub(6, 7), 16)

        return {r, g, b}
    end

    function pomodoro.fade_color(color1, color2)
        -- Return an interpolation of the color1 and color2
        -- based on the ratio of left time and pause/work time

        color1 = pomodoro.split_rgb(color1)
        color2 = pomodoro.split_rgb(color2)
        local step
        local faded_color

        if pomodoro.working then
            step = pomodoro.left / pomodoro.work_duration
            faded_color = {color1[1] - ((color1[1] - color2[1]) * step),
                           color1[2] - ((color1[2] - color2[2]) * step),
                           color1[3] - ((color1[3] - color2[3]) * step)
                          }
        else
            step = pomodoro.left / pomodoro.pause_duration
            faded_color = {color2[1] - ((color2[1] - color1[1]) * step),
                           color2[2] - ((color2[2] - color1[2]) * step),
                           color2[3] - ((color2[3] - color1[3]) * step)
                          }
        end

        for i in ipairs(faded_color) do
            local color = string.format("%x", math.floor(faded_color[i]))
            if #color == 1 then
                faded_color[i] = string.format("0%s", color)
            else
                faded_color[i] = color
            end
        end

        return string.format("#%s%s%s", faded_color[1],
                                     faded_color[2],
                                     faded_color[3])
    end

    function pomodoro:settime(t)
        s = ""
        if t < 0 then
            s = "-"
            t = -t
        end
        if t >= 3600 then
            t = os.date("!"..s.."%H:%M:%S", t)
        else
            t = os.date("!"..s.."%M:%S", t)
        end
        self.widget:set_markup(pomodoro.format(t))
    end

    function pomodoro:start()
        self.last_time = os.time()
        self.is_running = true
        self.timer:again()
        if self.working then
            self:emit_signal("work_start")
        else
            self:emit_signal("pause_start")
        end
    end

    function pomodoro:toggle()
        if pomodoro.left <= 0 then
            self:stop()
            if self.auto_start_pomodoro then
                self:start()
            end
        else
            if pomodoro.is_running then
                self:pause()
            else
                self:start()
            end
        end
    end

    function pomodoro:pause()
        -- TODO: Fix the showed remaining text
        pomodoro.is_running = false
        pomodoro.timer:stop()
        pomodoro.icon_widget:set_markup(pomodoro.format_icon())
    end

    function pomodoro:stop()
        pomodoro.is_running = false
        pomodoro.timer:stop()

        if self.working then
            self:emit_signal("work_stop", self.left)
            self.npomodoros = self.npomodoros + 1
            self.working = false
            if self.npomodoros % 4 == 0 then
                self.pause_duration = self.long_pause_duration
            else
                self.pause_duration = self.short_pause_duration
            end
            self.left = self.pause_duration
        else
            self:emit_signal("pause_stop", self.left)
            self.working = true
            self.left = self.work_duration
        end
        self:settime(self.left)
        self.icon_widget:set_markup(pomodoro.format_icon())
    end

    function pomodoro:increase_time()
        pomodoro.changed = true
        pomodoro.timer:stop()
        pomodoro:settime(pomodoro.work_duration+pomodoro.change)
        pomodoro.work_duration = pomodoro.work_duration+pomodoro.change
        pomodoro.left = pomodoro.work_duration
        pomodoro.changed_timer:again()
        pomodoro.changed_timer:start()
    end

    function pomodoro:decrease_time()
        pomodoro.changed = true
        pomodoro.timer:stop()
        if pomodoro.work_duration > pomodoro.change then
            pomodoro:settime(pomodoro.work_duration-pomodoro.change)
            pomodoro.work_duration = pomodoro.work_duration-pomodoro.change
            pomodoro.left = pomodoro.work_duration
        end
        pomodoro.changed_timer:again()
        pomodoro.changed_timer:start()
    end

    function get_buttons()
        return awful.util.table.join(
        awful.button({ }, 1, function()
            pomodoro:start()
        end),
        awful.button({ }, 2, function()
            pomodoro:pause()
        end),
        awful.button({ }, 3, function()
            pomodoro:stop()
        end),
        awful.button({ }, 4, function()
            pomodoro:increase_time()
        end),
        awful.button({ }, 5, function()
            pomodoro:decrease_time()
        end)
        )
    end

    function pomodoro:ticking_time()
        if pomodoro.left == 0 then
            if pomodoro.working then
                self:emit_signal("work_elapsed")
            else
                self:emit_signal("pause_elapsed")
            end
        end
        pomodoro:settime(pomodoro.left)
        pomodoro.icon_widget:set_markup(pomodoro.format_icon())
    end

    -- Function that keeps the logic for ticking
    function pomodoro:ticking()
        local now = os.time()
        pomodoro.left = pomodoro.left - (now - pomodoro.last_time)
        pomodoro.last_time = now
        pomodoro:ticking_time()
    end

    function pomodoro:spawn_sync(cmd)
        local fh = io.popen(cmd, 'r')
        local stdout = fh:read('*all')
        fh:close()
        io.write('spawn_orig')
        return stdout
    end

    function pomodoro:init()
        local xresources = pomodoro:spawn_sync('xrdb -query')

        local time_from_last_run       = xresources:match('awesome.Pomodoro.time:%s+%d+')
        local started_from_last_run    = xresources:match('awesome.Pomodoro.started:%s+%w+')
        local working_from_last_run    = xresources:match('awesome.Pomodoro.working:%s+%w+')
        local npomodoros_from_last_run = xresources:match('awesome.Pomodoro.npomodoros:%s+%d+')

        pomodoro.icon_widget:set_markup(pomodoro.format_icon())

        -- Timer configuration
        pomodoro.timer:connect_signal("timeout", pomodoro.ticking)

        -- Notifications
        pomodoro:connect_signal("work_elapsed", function()
            naughty.notify {
                bg = beautiful.bg_urgent,
                fg = beautiful.fg_urgent,
                title = pomodoro.work_title,
                text  = pomodoro.work_text,
                timeout = 10
            }
        end)
        pomodoro:connect_signal("pause_elapsed", function()
            naughty.notify {
                bg = beautiful.bg_urgent,
                fg = beautiful.fg_urgent,
                title = pomodoro.pause_title,
                text  = pomodoro.pause_text,
                timeout = 10
            }
        end)


        awesome.connect_signal("exit", function(restarting)
            -- Save current state in xrdb.
            -- run this synchronously cause otherwise it is not saved properly -.-
            if restarting then
                started_as_number = pomodoro.timer.started and 1 or 0
                working_as_number = pomodoro.working and 1 or 0
                pomodoro:spawn_sync('echo "awesome.Pomodoro.time: ' .. pomodoro.left
                .. '\nawesome.Pomodoro.started: ' .. started_as_number
                .. '\nawesome.Pomodoro.working: ' .. working_as_number
                .. '\nawesome.Pomodoro.npomodoros: ' .. pomodoro.npomodoros
                .. '" | xrdb -merge')
                fh:close()
            end
        end)

        pomodoro.widget:buttons(get_buttons())
        pomodoro.icon_widget:buttons(get_buttons())

        if time_from_last_run then
            time_from_last_run = tonumber(time_from_last_run:match('%d+'))
            if working_from_last_run then
                pomodoro.working = (tonumber(working_from_last_run:match('%d+')) == 1)
            end
            -- Use `math.min` to get the lower value for `pomodoro.left`, in
            -- case the config/setting has been changed.
            if pomodoro.working then
                pomodoro.left = math.min(time_from_last_run, pomodoro.work_duration)
            else
                pomodoro.left = math.min(time_from_last_run, pomodoro.pause_duration)
            end

            if npomodoros_from_last_run then
                pomodoro.npomodoros = tonumber(npomodoros_from_last_run:match('%d+'))
            end

            if started_from_last_run then
                started_from_last_run = tonumber(started_from_last_run:match('%d+'))
                if started_from_last_run == 1 then
                    pomodoro:start()
                end
            end
        else
            -- Initial value depends on the one set by the user
            pomodoro.left = pomodoro.work_duration
        end
        pomodoro:settime(pomodoro.left)

        awful.tooltip({
            objects = { pomodoro.widget, pomodoro.icon_widget},
            timer_function = function()
                local collected = 'Collected ' .. pomodoro.npomodoros .. ' pomodoros so far.\n'

                local settings = "Settings:\n * work: %d min\n * short pause: %d min\n * long pause: %d min"
                settings = settings:format( pomodoro.work_duration / 60,
                                            pomodoro.pause_duration / 60,
                                            pomodoro.long_pause_duration / 60)

                if pomodoro.timer.started then
                    if pomodoro.working then
                        return collected .. 'Work ending in ' .. os.date("%M:%S", pomodoro.left)
                    else
                        return collected .. 'Rest ending in ' .. os.date("%M:%S", pomodoro.left)
                    end
                else
                    return string.format("%s\nPomodoro not started\n\n%s",
                    collected,
                    settings)
                end
            end,
        })

    end

    return pomodoro
end

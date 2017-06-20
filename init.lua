local awful = require("awful")
local beautiful = require("beautiful")
local naughty = require("naughty")
local timer = require("gears.timer")
local wibox = require("wibox")


local function format_time(seconds)
    if seconds >= 3600 then
	return os.date("!%H:%M:%S", seconds)
    else
	return os.date("!%M:%S", seconds)
    end
end


local function split_rgb(color)
    -- Return a table of three elements: the hex values of
    -- each of the pairs of `color`

    local r = tonumber(color:sub(2, 3), 16)
    local g = tonumber(color:sub(4, 5), 16)
    local b = tonumber(color:sub(6, 7), 16)

    return {r, g, b}
end


-- The Pomodoro module
local Pomodoro = {}

Pomodoro.config = {
    pause_title = "Pause finished.",
    pause_text = "Get back to work!",

    work_title = "Pomodoro finished.",
    work_text = "Time for a pause!",

    collected_text = 'Collected %d pomodoros so far.\n',

    auto_start_pomodoro = true,

    allow_timer_over_duration = true,

    always_show_timer = true;

    change_step = 60,

    short_pause_duration = 5 * 60,
    long_pause_duration = 15 * 60,
    work_duration = 25 * 60,
    pause_duration = 5 * 60,
}


-- Helper functions

function Pomodoro.spawn_sync(cmd)
    local fh = io.popen(cmd, 'r')
    local stdout = fh:read('*all')
    fh:close()
    return stdout
end


function Pomodoro.notify(title, text)
    naughty.notify({
	bg = beautiful.bg_urgent,
	fg = beautiful.fg_urgent,
	title = title,
	text  = text,
	timeout = 10})
end


function Pomodoro:load_xresources_values()
    local xresources = self.spawn_sync('xrdb -query')
    local last_run = {
	time = tonumber(xresources:match('awesome.Pomodoro.time:%s+(-?%d+)')),
	started = tonumber(xresources:match('awesome.Pomodoro.started:%s+([01])')),
	working = tonumber(xresources:match('awesome.Pomodoro.working:%s+([01])')),
	pomodoros = tonumber(xresources:match('awesome.Pomodoro.npomodoros:%s+(%d+)'))
    }
    return last_run
end


function Pomodoro.fade_color(color1, color2, amount)
    -- Return an interpolation of the color1 and color2
    -- based on amount

    color1 = split_rgb(color1)
    color2 = split_rgb(color2)

    local r = math.floor(color1[1] - ((color1[1] - color2[1]) * amount))
    local g = math.floor(color1[2] - ((color1[2] - color2[2]) * amount))
    local b = math.floor(color1[3] - ((color1[3] - color2[3]) * amount))

    return string.format("#%02x%02x%02x", r, g, b)
end


function Pomodoro:make_tooltip()
   local collected = self.config.collected_text:format(self.npomodoros)

   local settings = "Settings:\n * work: %s\n * short pause: %s\n * long pause: %s"
   settings = settings:format(format_time(self.config.work_duration),
			      format_time(self.config.pause_duration),
			      format_time(self.config.long_pause_duration))

   if self.timer.started then
      if self.working then
	 return collected .. 'Work ending in ' .. os.date("%M:%S", self.time_left)
      else
	 return collected .. 'Rest ending in ' .. os.date("%M:%S", self.time_left)
      end
   else
      return string.format("%s\nPomodoro not started\n\n%s",
			   collected,
			   settings)
   end
end


function Pomodoro:update_icon_widget()
    local color
    local work_color  = beautiful.pomodoro_work   or "#FF0000"
    local pause_color = beautiful.pomodoro_pause  or "#00FF00"

    if not self.is_running then
	-- Color for when the timer has not yet started
	color = beautiful.pomodoro_inactive or "#C0C0C0"
    elseif self.working then
	local amount = 1 - math.max(self.time_left / self.config.work_duration, 0)
	color = Pomodoro.fade_color(pause_color, work_color, amount)
    else
	local amount = 1 - math.max(self.time_left / self.config.pause_duration, 0)
	color = Pomodoro.fade_color(work_color, pause_color, amount)
    end

    local markup = "<span fgcolor='%s'>&#127813;</span>"
    self.icon_widget:set_markup(markup:format(color))
end


function Pomodoro:update_timer_widget(t)
    local markup, s

    if t < 0 then
	s = "-"
	t = -t
    else
	s = ""
    end

    if self.config.always_show_timer or self.changed or self.timer.started then
	markup = s .. format_time(t)
    else
	markup = ""
    end

    self.timer_widget:set_markup(markup)
end


function Pomodoro:start()
    self.last_time = os.time()
    self.is_running = true
    self.timer:again()
    if self.working then
	self.icon_widget:emit_signal("work_start")
    else
	self.icon_widget:emit_signal("pause_start")
    end
end


function Pomodoro:toggle()
    if self.time_left <= 0 then
	self:stop()
	if self.auto_start_pomodoro then
	    self:start()
	end
    else
	if self.is_running then
	    self:pause()
	else
	    self:start()
	end
    end
end


function Pomodoro:pause()
    -- TODO: Fix the showed remaining text
    self.is_running = false

    if self.timer.started then
	self.timer:stop()
    end

    self:update_icon_widget()
end


function Pomodoro:stop()
    if self.timer.started then
	self.timer:stop()
    end

    if self.working then
	self.icon_widget:emit_signal("work_stop", self.time_left)
	self.working = false

	self.npomodoros = self.npomodoros + 1

	if self.npomodoros % 4 == 0 then
	    self.time_left = self.config.long_pause_duration
	else
	    self.time_left = self.config.short_pause_duration
	end

    else
	self.icon_widget:emit_signal("pause_stop", self.time_left)
	self.working = true
	self.time_left = self.config.work_duration
    end
    self:update_timer_widget(self.time_left)
    self:update_icon_widget()
end


function Pomodoro:modify_time(add)
    -- Add self.config.change_step minutes to self.config.work duration if add == true,
    -- otherwise subtract.

    self.changed = true

    if add then
	self:update_timer_widget(self.config.work_duration + self.config.change_step)
	self.config.work_duration = self.config.work_duration + self.config.change_step
	self.time_left = self.config.work_duration
    else
	if self.config.work_duration > self.config.change_step then
	    self:update_timer_widget(self.config.work_duration - self.config.change_step)
	    self.config.work_duration = self.config.work_duration - self.config.change_step
	    self.time_left = self.config.work_duration
	end
    end
    self.changed_timer:again()
end


function Pomodoro:get_buttons()
    return awful.util.table.join(
    awful.button({ }, 1, function() self:start() end),
    awful.button({ }, 2, function() self:pause() end),
    awful.button({ }, 3, function() self:stop() end),
    awful.button({ }, 4, function() self:modify_time(true) end),
    awful.button({ }, 5, function() self:modify_time(false) end)
    )
end


-- Table that will contain signal handlers
Pomodoro.handlers = {}


function Pomodoro.handlers.changed_timer(self)
   self.changed = false
   self.changed_timer:again()
   self.changed_timer:stop()
   self.timer_widget:set_markup(format_time(self.config.work_duration))
end


function Pomodoro.handlers.exit(self, restarting)
   -- Save current state in xrdb.
   -- run this synchronously cause otherwise it is not saved properly -.-
   if restarting then
      local started_as_number = self.timer.started and 1 or 0
      local working_as_number = self.working and 1 or 0
      self.spawn_sync('echo "awesome.Pomodoro.time: ' .. self.time_left
			 .. '\nawesome.Pomodoro.started: ' .. started_as_number
			 .. '\nawesome.Pomodoro.working: ' .. working_as_number
			 .. '\nawesome.Pomodoro.npomodoros: ' .. self.npomodoros
			 .. '" | xrdb -merge')
   end
end


function Pomodoro.handlers.ticking(self)
    -- Function that keeps the logic for ticking

    local now = os.time()
    self.time_left = self.time_left - (now - self.last_time)
    self.last_time = now

    if self.time_left == 0 then
	if not self.config.allow_timer_beyond_duration then
	    self.timer:stop()
	end

	if self.working then
	    self.icon_widget:emit_signal("work_elapsed")
	else
	    self.icon_widget:emit_signal("pause_elapsed")
	end
    end

    self:update_timer_widget(self.time_left)
    self:update_icon_widget()
end


function Pomodoro.init(config)
    -- Return a new Pomodoro object

    local self = setmetatable({}, Pomodoro)

    if config and type(config) == "table" then
       for k, v in pairs(config) do
	  if self.config[k] ~= nil then
	     self.config[k] = v
	  end
       end
    end

    -- We'll try to grab the values from the last pomodoro session
    local last_run = self:load_xresources_values()

    self.is_running = false
    self.npomodoros = last_run.pomodoros or 0

    if last_run.working then
       self.working = last_run.working
    else
       self.working = true
    end

    if last_run.started ~= nil then
	self.time_left = last_run.time
    else
	if last_run.working then
	    self.time_left = self.config.work_duration
	else
	    if last_run.npomodoros and last_run.npomodoros % 4 then
		self.time_left = self.config.long_pause_duration
	    else
		self.time_left = self.config.short_pause_duration
	    end
	end
    end

    self.changed = false
    self.changed_timer = timer({timeout = 3})
    self.changed_timer:connect_signal("timeout", function ()
					 self.handlers.changed_timer(self) end)

    self.timer_widget = wibox.widget.textbox()
    self.icon_widget = wibox.widget.textbox()
    self:update_icon_widget()

    -- Timer configuration
    self.timer = timer {timeout = 1}
    self.timer:connect_signal("timeout", function() self.handlers.ticking(self) end)

    -- Notifications
    self.icon_widget:connect_signal("work_elapsed", function()
					self.notify(self.config.work_title,
						    self.config.work_text) end)

    self.icon_widget:connect_signal("pause_elapsed", function()
					self.notify(self.config.pause_title,
						    self.config.pause_text) end)

    self.icon_widget:connect_signal("exit", function(restart)
					self.handlers.exit(self, restart) end)

    self.timer_widget:buttons(self:get_buttons())
    self.icon_widget:buttons(self:get_buttons())

    self:update_timer_widget(self.time_left)

    -- Attach the tooltip to both widgets with the make_tooltip timer funciton
    awful.tooltip({objects = {self.timer_widget, self.icon_widget},
		   timer_function = function() return self:make_tooltip() end})

    if last_run.started then
	self:start()
    end

    return self
end

Pomodoro.__index = Pomodoro
setmetatable(Pomodoro, {__call = function(cls, config) return cls.init(config) end})
return Pomodoro

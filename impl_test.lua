local createPomodoro = require('impl')

local wibox = {
    widget = {
        textbox = function() 
            return {
                set_markup = function(self, s) return nil end,
                buttons = function(self, bs) return nil end,
            }
        end,
        imagebox = function()
            return {
                set_image = function(self, image_path) return nil end,
                buttons = function(self, bs) return nil end,
            }
        end,
        base = {
            make_widget = function()
                return {
                    emit_signal = function(self, s) return nil end,
                    connect_signal = function(self, s) return nil end
                }
            end
        }
    }
}
local awful = {
    util = {
        getdir = function(str) return '/home/cooluser/.config/awesome' end,
        table = {
            join = function(elements) return nil end
        }
    },
    spawn = {
        pread = function(cmd) return "" end,
    },
    button = function(modifier, mouseButton, f) return nil end,
    tooltip = function(table) return nil end
}
local naughty = {
    notify = function(bg, fg, title, text, timeout)
    end
}
local beautiful = {}

local timer = function(t) 
    return {
        again = function(self, f) return nil end,
        stop = function(self) return nil end,
        connect_signal = function(self, f) return nil end,
    }
end

local awesome = {
    connect_signal = function(self, f) return nil end,
}

local pomodoro = createPomodoro(wibox, awful, naughty, beautiful, timer, awesome)
-- We are only worried about the formating of `t`
pomodoro.format = function (t) return t end


describe("Should set the default values properly", function()
    it('pause duration should be 5 minutes', function()
        assert.are.equal(300, pomodoro.pause_duration)
    end)
    it('work duration should be set to 25 minutes', function()
        assert.are.equal(1500, pomodoro.work_duration)
    end)
    it('default changing value for increasing and decreasing should be one minute', function()
        assert.are.equal(60, pomodoro.change)
    end)
    it('working pomodoro should be the next state', function()
        assert.are.equal(true, pomodoro.working)
    end)
end)

describe('Set time should change the textbox appropriately', function()
    local s = spy.on(pomodoro.widget, "set_markup")
    it('more than one hour pomodoro should be formatted with an hour part', function()
        pomodoro:settime(3601)
        assert.spy(s).was_called_with(pomodoro.widget, "01:00:01")
    end)
    it('less than one hour should be set with only minutes and seconds', function()
        pomodoro:settime(1500)
        assert.spy(s).was_called_with(pomodoro.widget, "25:00")
    end)
end)

describe('Starting a pomodoro', function()
    it('should start the timer', function()
        local s = spy.on(pomodoro.timer, 'again')
        pomodoro:start()
        assert.spy(s).was_called_with(pomodoro.timer)
    end)
end)


describe('Stopping a pomodoro', function()
    it('should stop the timer', function()
        local s = spy.on(pomodoro.timer, 'stop')
        pomodoro:stop()
        assert.spy(s).was_called_with(pomodoro.timer)
    end)
    it('should set is_running to false', function()
        pomodoro:stop()
        assert.are.equal(false, pomodoro.is_running)
    end)
    it('should toggle working', function()
        working = pomodoro.working
        pomodoro:stop()
        assert.are.not_equal(working, pomodoro.working)
        pomodoro:stop()
        assert.are.equal(working, pomodoro.working)
    end)
    it('should set time left to the work duration if it was in pause', function()
        local s = spy.on(pomodoro, 'settime')
        pomodoro:stop()
        assert.are.equal(5 * 60, pomodoro.left)
        assert.spy(s).was_called_with(pomodoro, 5 * 60)
    end)
    it('should set time left to the pause duration if it was in work', function()
        local s = spy.on(pomodoro, 'settime')
        pomodoro:stop()
        assert.are.equal(25 * 60, pomodoro.left)
        assert.spy(s).was_called_with(pomodoro, 25 * 60)
    end)
end)

describe('Pausing a pomodoro', function()
    it('should stop the timer', function()
        local s = spy.on(pomodoro.timer, 'stop')
        pomodoro:stop()
        assert.spy(s).was_called_with(pomodoro.timer)
    end)
end)

describe('Preserve the pomodoro before restart if any', function()
    it('should find the last time in X resource DB', function()
        pomodoro.spawn_sync = function(s)
            return [[
            awesome.Pomodoro.time:  716
            XTerm*faceName: consolas
            xterm*.background:      grey5
            ]]
        end
        pomodoro:init()
        assert.are.equal(716, pomodoro.left)
    end)
    it('should find the last time in X resource DB even if it is negative', function()
        pomodoro.spawn_sync = function(s)
            return [[
            awesome.Pomodoro.time:  -716
            XTerm*faceName: consolas
            xterm*.background:      grey5
            ]]
        end
        pomodoro:init()
        assert.are.equal(-716, pomodoro.left)
    end)
    it('should start the pomodoro right away if the value is found in the database after a restart and it was started', function()
        local s = spy.on(pomodoro, 'start')
        pomodoro.spawn_sync = function(s)
            return [[
            awesome.Pomodoro.time:  716
            awesome.Pomodoro.started:  1
            XTerm*faceName: consolas
            xterm*.background:      grey5
            ]]
        end
        pomodoro:init()
        assert.spy(s).was_called()
    end)
    it('should use the normal duration and don\'t start a pomodoro if not found in the database', function()
        local s = spy.on(pomodoro, 'start')
        pomodoro.spawn_sync = function(s)
            return [[
            awesome.pomodoro.time:  716
            XTerm*faceName: consolas
            xterm*.background:      grey5
            ]]
        end
        pomodoro:init()
        assert.spy(s).was_not_called()
        assert.are.equal(1500, pomodoro.left)
    end)

    it('should not start the timer if it was paused or stopped', function()
        local s = spy.on(pomodoro, 'start')
        pomodoro.spawn_sync = function(s)
            return [[
            awesome.Pomodoro.time:  716
            awesome.Pomodoro.started:  0
            XTerm*faceName: consolas
            xterm*.background:      grey5
            ]]
        end
        pomodoro:init()
        assert.spy(s).was_not_called()
        assert.are.equal(716, pomodoro.left)
    end)
end)

describe('Long breaks', function()

    local pomodoro = createPomodoro(wibox, awful, naughty, beautiful, timer, awesome)
    it('should properly start a long break after 4 full pomodoros', function()
        for i=1,4,1 do
            pomodoro.working = true
            pomodoro.left = 0
            assert.are.not_equal(15 * 60, pomodoro.pause_duration)
            pomodoro:stop()
        end
        assert.are.equal(15 * 60, pomodoro.pause_duration)
    end)
end)

describe('Fade color', function()
    local color1 = '#ff0000'
    local color2 = '#00ff00'
    it('should return the first color when amount is 0', function()
        assert.are.equal(color1, pomodoro.fade_color(color1, color2, 0))
    end)
    it('should return the second color when amount is 1', function()
        assert.are.equal(color2, pomodoro.fade_color(color1, color2, 1))
    end)
    it('should interpolate between two colors', function()
        color3 = '#7f7f00'
        assert.are.equal(color3, pomodoro.fade_color(color1, color2, 0.5))
    end)
end)

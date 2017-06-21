package.path = "./spec/mocked/?.lua;" .. package.path
local Pomodoro = require "init"


describe("Should set the default", function()
    -- Override spawn_sync so that the test can pass if we are running the
    -- test suite in a desktop session with values saved in the XRDB
    function Pomodoro.spawn_sync() return "" end

    local pomodoro = Pomodoro()

    it('pause duration to 5 minutes', function()
        assert.are.equal(300, pomodoro.config.short_pause_duration)
    end)
    it('work duration to 25 minutes', function()
        assert.are.equal(1500, pomodoro.config.work_duration)
    end)
    it('time change steps to one minute', function()
        assert.are.equal(60, pomodoro.config.change_step)
    end)
    it('next state to work', function()
        assert.are.equal(true, pomodoro.working)
    end)
end)

describe('The timer widget should display', function()
    local pomodoro = Pomodoro()

    local s = spy.on(pomodoro.timer_widget, "set_markup")

    it('the time in H:M:S format when the left time is greater than an hour', function()
	pomodoro.changed = true
        pomodoro:update_timer_widget(3601)
        assert.spy(s).was_called_with(pomodoro.timer_widget, "01:00:01")
    end)
    it('the time in M:S format when the left time is less than an hour', function()
	pomodoro.changed = true
        pomodoro:update_timer_widget(1500)
        assert.spy(s).was_called_with(pomodoro.timer_widget, "25:00")
    end)
end)

describe('Starting a pomodoro', function()
    local pomodoro = Pomodoro()
    it('should start the timer', function()
        local s = spy.on(pomodoro.timer, 'again')
        pomodoro:start()
        assert.spy(s).was_called_with(pomodoro.timer)
    end)
end)


describe('Stopping a pomodoro', function()
    local pomodoro = Pomodoro()
    it('should stop the timer', function()
	pomodoro.timer.started = true
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
    it('in work mode should trigger pause mode and change time accordingly', function()
	pomodoro.working = true
        pomodoro:stop()
        assert.False(pomodoro.working)
        assert.False(pomodoro.npomodoros % 4 == 0)
        assert.are.equal(pomodoro.config.short_pause_duration, pomodoro.time_left)
    end)
    it('in pause mode should trigger work mode and change time accordingly', function()
	pomodoro.working = false
        local s = spy.on(pomodoro, 'update_timer_widget')
        pomodoro:stop()
        assert.are.equal(pomodoro.config.work_duration, pomodoro.time_left)
        assert.spy(s).was_called_with(pomodoro, pomodoro.config.work_duration)
    end)
end)

describe('Pausing a pomodoro', function()
    it('should stop the timer', function()
	local pomodoro = Pomodoro()
	pomodoro.timer.started = true
        local s = spy.on(pomodoro.timer, 'stop')
        pomodoro:pause()
        assert.spy(s).was_called_with(pomodoro.timer)
    end)
end)

describe('Preserving pomodoros between restarts', function()
    it('should preserve the last remaining time in the XRDB', function()
	Pomodoro.spawn_sync = function()
	    return [[
	    awesome.Pomodoro.time:  716
            awesome.Pomodoro.started:  0
            awesome.Pomodoro.working: 1
	    XTerm*faceName: consolas
	    xterm*.background:      grey5
	    ]]
	  end
	local pomodoro = Pomodoro()
        assert.are.equal(716, pomodoro.time_left)
    end)
    it('should preserve the last remaining time in the XRDB, even if it is negative', function()
        Pomodoro.spawn_sync = function()
            return [[
            awesome.Pomodoro.time:  -716
            awesome.Pomodoro.started:  0
            XTerm*faceName: consolas
            xterm*.background:      grey5
            ]]
        end
	local pomodoro = Pomodoro()
        assert.are.equal(-716, pomodoro.time_left)
    end)
    it('should start the pomodoro right away if it was started in the previous session', function()
        Pomodoro.spawn_sync = function()
            return [[
            awesome.Pomodoro.time:  716
            awesome.Pomodoro.started:  1
            XTerm*faceName: consolas
            xterm*.background:      grey5
            ]]
        end
	local pomodoro = Pomodoro()
        local s = spy.on(pomodoro, 'start')
    end)
    it('should use the normal duration and don\'t start a pomodoro if not found in the database', function()
        Pomodoro.spawn_sync = function()
            return [[
            awesome.Pomodoro.time:  716
            awesome.Pomodoro.working: 1
            XTerm*faceName: consolas
            xterm*.background:      grey5
            ]]
        end
	local pomodoro = Pomodoro()
        local s = spy.on(pomodoro, 'start')
        assert.spy(s).was_not_called()
        assert.are.equal(1500, pomodoro.time_left)
    end)

    it('should not start the timer if it was paused or stopped', function()
        Pomodoro.spawn_sync = function()
            return [[
            awesome.Pomodoro.time:  716
            awesome.Pomodoro.started: 0
            XTerm*faceName: consolas
            xterm*.background:      grey5
            ]]
        end
	local pomodoro = Pomodoro()
        local s = spy.on(pomodoro, 'start')
        assert.spy(s).was_not_called()
        assert.are.equal(716, pomodoro.time_left)
    end)
end)

describe('Long breaks', function()
    local pomodoro = Pomodoro()
    it('should properly start a long break after 4 full pomodoros', function()
        for i=1,4,1 do
            pomodoro.working = true
            pomodoro.left = 0
            assert.are.not_equal(15 * 60, pomodoro.config.short_pause_duration)
            pomodoro:stop()
        end
        assert.are.equal(15 * 60, pomodoro.config.long_pause_duration)
    end)
end)

describe('Fade color', function()
    local pomodoro = Pomodoro()
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

local ToTheSky = {}
local Pid = {}

function Pid.createPid(kp, ki, kd, tick, u)
    local pid = {
        u = u or 0,
        e0 = 0., -- Current error
        e1 = 0., -- Previous error
        e2 = 0.  -- Error before previous
    }

    function pid:step(err)
        -- Shift error history
        self.e2 = self.e1
        self.e1 = self.e0
        self.e0 = err

        -- Incremental PID Algorithm
        -- Calculates the CHANGE (du) needed based on the slope of the error
        local du = kp * (self.e0 - self.e1) +
                   ki * tick * self.e0 +
                   kd * (self.e0 - 2 * self.e1 + self.e2) / tick

        self.u = self.u + du
        return self.u
    end

    return pid
end

ToTheSky.pid = Pid
return ToTheSky
local ToTheSky = {}
local Pid = {}

function Pid.createPid(kp, ki, kd, tick, u)
    local pid = {
        u = u or 0,
        e0 = 0.0, -- Current error (Changed from 0. to 0.0)
        e1 = 0.0, -- Previous error (Changed from 0. to 0.0)
        e2 = 0.0  -- Error before previous (Changed from 0. to 0.0)
    }

    function pid:step(err)
        self.e2 = self.e1
        self.e1 = self.e0
        self.e0 = err

        local du = kp * (self.e0 - self.e1) +
                   ki * tick * self.e0 +
                   kd * (self.e0 - 2 * self.e1 + self.e2) / tick

        self.u = self.u + du
        self.u = math.max(-14, math.min(14, self.u))
        return self.u
    end

    return pid
end

ToTheSky.pid = Pid
return ToTheSky
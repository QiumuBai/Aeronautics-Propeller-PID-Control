-- Central Controller: reads sensor, runs PID, sends speeds via rednet

-- 1. NETWORK & PERIPHERALS
rednet.open("back")  -- change to your modem side

-- Motor computer rednet IDs -- change to match your setup
local motorIds = { fl=3, fr=5, bl=2, br=4 }

local sensor = peripheral.find("gimbal_sensor")
if not sensor then error("CRITICAL: Gimbal Sensor not found!") end

-- 2. CONFIGURATION
local targetPitch, targetRoll = 0.0, 0.0
local running      = true
local inputting    = false
local systemActive = true

-- PID gains (template-style standard form)
-- Integral winds up naturally to provide steady-state correction (hover)
local kp     = 80
local ki     = 20
local kd     = 40
local intMax = 2     -- integral clamp (same as template)
local maxSpeed = 256 -- RPM ceiling
local maxStep  = 15  -- max RPM change per cycle (rate limiter)

-- 3. PID STATE
local intP, intR           = 0, 0
local lastP, lastR         = nil, nil
local lastTime             = nil
local lastSpeeds           = { fl=0, fr=0, bl=0, br=0 }

local function clamp(x, lo, hi)
    return math.max(lo, math.min(hi, x))
end

-- 4. UI
local lastState = {
    cP=-999, cR=-999,
    fl=-999, fr=-999, bl=-999, br=-999,
    active=nil, kill=nil
}

local function drawStaticUI()
    term.clear()
    term.setCursorPos(1, 1)
    print("+----------------------------------------+")
    print("|            Balancing System            |")
    print("+----------------------------------------+")
    print("| Pitch (X):             Roll (Z):       |")
    print("| Status   : [          ]                |")
    print("| Kill Sig : [    ]                      |")
    print("+----------------------------------------+")
    print("| FL: [    ]         FR: [    ]          |")
    print("| BL: [    ]         BR: [    ]          |")
    print("+----------------------------------------+")
    print("| [C] Set Target   [S] Toggle System/Stop|")
    print("| [E] Exit Program                       |")
    print("+----------------------------------------+")
end

local function smartUpdate(cP, cR, s, killActive)
    if inputting then return end

    if math.abs(cP - lastState.cP) > 0.01 then
        term.setCursorPos(14, 4) term.write(string.format("%6.2f", cP))
        lastState.cP = cP
    end
    if math.abs(cR - lastState.cR) > 0.01 then
        term.setCursorPos(34, 4) term.write(string.format("%6.2f", cR))
        lastState.cR = cR
    end

    if systemActive ~= lastState.active then
        term.setCursorPos(15, 5)
        if systemActive then
            term.setTextColor(colors.green) term.write(" ACTIVE   ")
        else
            term.setTextColor(colors.red)   term.write(" STOPPED  ")
        end
        term.setTextColor(colors.white)
        lastState.active = systemActive
    end

    if killActive ~= lastState.kill then
        term.setCursorPos(15, 6)
        if killActive then
            term.setTextColor(colors.red)   term.write(" ON ")
        else
            term.setTextColor(colors.green) term.write("OFF ")
        end
        term.setTextColor(colors.white)
        lastState.kill = killActive
    end

    local pPos = { fl={8,8}, fr={27,8}, bl={8,9}, br={27,9} }
    for k, v in pairs(s) do
        if v ~= lastState[k] then
            term.setCursorPos(pPos[k][1], pPos[k][2])
            term.write(string.format("%4d", v))
            lastState[k] = v
        end
    end
end

-- 5. CONTROL LOOP
local function controlLoop()
    local killActive = false
    local zeroCount  = 0

    while running do
        if not inputting then
            local s = { fl=0, fr=0, bl=0, br=0 }
            local cP, cR = 0, 0

            if systemActive then
                killActive = false

                local now    = os.clock()
                local angles = sensor.getAngles()
                cP, cR = angles[1], angles[2]

                local errP = targetPitch - cP
                local errR = targetRoll  - cR

                -- Compute angular velocity and accumulate integral
                local omegaP, omegaR = 0, 0
                if lastTime then
                    local dt = math.max(now - lastTime, 0.001)
                    omegaP = (cP - lastP) / dt
                    omegaR = (cR - lastR) / dt
                    -- Integral winds up to provide steady-state correction naturally
                    intP = clamp(intP + errP * dt, -intMax, intMax)
                    intR = clamp(intR + errR * dt, -intMax, intMax)
                end
                lastP, lastR, lastTime = cP, cR, now

                local dP = clamp(kp*errP + ki*intP - kd*omegaP, -maxSpeed, maxSpeed)
                local dR = clamp(kp*errR + ki*intR - kd*omegaR, -maxSpeed, maxSpeed)

                -- Mixing:
                -- Pitch: same sign for all four (front lifts, rear pushes down = same nose-up torque)
                -- Roll:  diagonal pairs (FL&BR vs FR&BL)
                local raw = {
                    fl =  dP + dR,  -- } diagonal A
                    br =  dP + dR,  -- }
                    fr =  dP - dR,  -- } diagonal B
                    bl =  dP - dR,  -- }
                }

                -- Rate limiter: prevents sudden RPM jumps
                for k, v in pairs(raw) do
                    local step = clamp(v - lastSpeeds[k], -maxStep, maxStep)
                    s[k] = math.floor(clamp(lastSpeeds[k] + step, -maxSpeed, maxSpeed))
                end

                if s.fl==0 and s.fr==0 and s.bl==0 and s.br==0 then
                    zeroCount = zeroCount + 1
                    if zeroCount >= 5 then killActive = true end
                else
                    zeroCount = 0
                end

            else
                -- Stopped: clear PID state so integral doesn't carry over on resume
                killActive = true
                zeroCount  = 0
                intP, intR = 0, 0
                lastP, lastR, lastTime = nil, nil, nil
            end

            -- Send speed to each motor computer
            for k, id in pairs(motorIds) do
                rednet.send(id, killActive and 0 or s[k])
            end
            lastSpeeds = { fl=s.fl, fr=s.fr, bl=s.bl, br=s.br }

            smartUpdate(cP, cR, s, killActive)
        end
        sleep(0.05)  -- 20Hz, matches template
    end
end

-- 6. INPUT HANDLER
local function inputHandler()
    while running do
        local _, key = os.pullEvent("key")
        if key == keys.c then
            inputting = true
            term.setCursorPos(1, 14) term.clearLine()
            term.write("Set Pitch (X): ")
            local p = tonumber(read())
            term.setCursorPos(1, 14) term.clearLine()
            term.write("Set Roll (Z): ")
            local r = tonumber(read())
            if p then targetPitch = p end
            if r then targetRoll  = r end
            inputting = false
            drawStaticUI()
        elseif key == keys.s then
            systemActive = not systemActive
            if not systemActive then
                intP, intR = 0, 0
                lastP, lastR, lastTime = nil, nil, nil
            end
        elseif key == keys.e then
            running = false
        end
    end
end

-- START
drawStaticUI()
parallel.waitForAny(controlLoop, inputHandler)

-- CLEANUP
term.clear()
term.setCursorPos(1,1)
print("Shutting down... Sending stop to all motors.")
for k, id in pairs(motorIds) do rednet.send(id, 0) end
print("Safe for disassembly.")

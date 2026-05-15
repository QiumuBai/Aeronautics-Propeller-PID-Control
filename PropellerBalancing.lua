local tothesky = require('tothesky')
local pid = tothesky.pid

-- 1. CONFIGURATION
local targetPitch, targetRoll = 0.0, 0.0
local running = true
local inputting = false
local systemActive = true -- Master toggle

-- PID Tuning (Baseline 'u' is 0 for reactionary balancing)
local pidPitch = pid.createPid(0.35, 0.008, 1.5, 0.1, 0)
local pidRoll  = pid.createPid(0.35, 0.008, 1.5, 0.1, 0)

-- Sensor Placement Check
local sensor = peripheral.find("gimbal_sensor")
if not sensor then
error("CRITICAL: Gimbal Sensor not found! Please check the physical connection.")
end

-- Mapping propellers + Global Stop
local sides = {
    fl = "front",
    fr = "right",
    bl = "left",
    br = "back",
    kill = "bottom" -- The Master Stop Output
}

-- 2. UI & OPTIMIZATION
local lastState = { cP = -999, cR = -999, fl = -1, fr = -1, bl = -1, br = -1, active = nil }

local function drawStaticUI()
    term.clear()
    term.setCursorPos(1, 1)
    print("+----------------------------------------+")
    print("|            Balancing System            |")
    print("+----------------------------------------+")
    print("| Pitch (X):             Roll (Z):       |")
    print("| Status   : [          ]                |")
    print("+----------------------------------------+")
    print("| FL: [  ]           FR: [  ]            |")
    print("| BL: [  ]           BR: [  ]            |")
    print("+----------------------------------------+")
    print("| [C] Set Target   [S] Toggle System/Stop|")
    print("| [E] Exit Program                       |")
    print("+----------------------------------------+")
end

local function smartUpdate(cP, cR, s)
    if inputting then return end

    -- Update Angles
    if math.abs(cP - lastState.cP) > 0.1 then
        term.setCursorPos(14, 4) term.write(string.format("%5.1f", cP))
        lastState.cP = cP
    end
    if math.abs(cR - lastState.cR) > 0.1 then
        term.setCursorPos(35, 4) term.write(string.format("%5.1f", cR))
        lastState.cR = cR
    end

    -- Update System Status
    if systemActive ~= lastState.active then
        term.setCursorPos(15, 5)
        if systemActive then
            term.setTextColor(colors.green)
            term.write(" ACTIVE   ")
        else
            term.setTextColor(colors.red)
            term.write(" STOPPED  ")
        end
        term.setTextColor(colors.white)
        lastState.active = systemActive
    end

    -- Update Propeller RPM indicators
    local pPos = {fl={8,7}, fr={27,7}, bl={8,8}, br={27,8}}
    for k, v in pairs(s) do
        if v ~= lastState[k] then
            term.setCursorPos(pPos[k][1], pPos[k][2])
            term.write(string.format("%2d", v))
            lastState[k] = v
        end
    end
end

-- 3. CONTROL LOGIC
local function controlLoop()
    while running do
        if not inputting then
            local s = { fl = 15, fr = 15, bl = 15, br = 15 }
            local cP, cR = 0, 0

            if systemActive then
                -- Normal Balancing Logic
                redstone.setAnalogOutput(sides.kill, 0) -- Kill signal OFF

                local angles = sensor.getAngles()
                cP, cR = angles[1], angles[2]

                local dP = pidPitch:step(targetPitch - cP)
                local dR = pidRoll:step(targetRoll - cR)

               local function clamp(val)
                   return math.max(0, math.min(14, math.floor(val + 0.5)))
               end

                s.fl = clamp(dP + dR)
                s.fr = clamp(dP - dR)
                s.bl = clamp(-dP + dR)
                s.br = clamp(-dP - dR)

                -- IDLE STOP LOGIC: If all props calculate 0, send the Stop signal
                local zeroCount = 0
                if s.fl == 0 and s.fr == 0 and s.bl == 0 and s.br == 0 then
                    zeroCount = zeroCount + 1
                    if zeroCount >= 5 then  -- ~0.5 seconds of sustained zero
                        redstone.setAnalogOutput(sides.kill, 1)
                    end
                else
                    zeroCount = 0
                end
            else
                -- Stop Logic
                redstone.setAnalogOutput(sides.kill, 1) -- Kill signal ON
                -- All motors remain 15 (Stop)
            end

            -- Apply Output
            redstone.setAnalogOutput(sides.fl, s.fl)
            redstone.setAnalogOutput(sides.fr, s.fr)
            redstone.setAnalogOutput(sides.bl, s.bl)
            redstone.setAnalogOutput(sides.br, s.br)

            smartUpdate(cP, cR, s)
        end
        sleep(0.1)
    end
end

-- 4. INPUT HANDLING
local function inputHandler()
    while running do
        local _, key = os.pullEvent("key")
        if key == keys.c then
            inputting = true
            term.setCursorPos(1, 13) term.clearLine()
            term.write("Set Pitch (X): ")
            local p = tonumber(read())
            term.setCursorPos(1, 13) term.clearLine()
            term.write("Set Roll (Z): ")
            local r = tonumber(read())
            if p then targetPitch = p end
            if r then targetRoll = r end
            inputting = false
            drawStaticUI()
        elseif key == keys.s then
            systemActive = not systemActive
        elseif key == keys.e then
            running = false
        end
    end
end

-- START
drawStaticUI()
parallel.waitForAny(controlLoop, inputHandler)

-- FINAL CLEANUP
term.clear()
term.setCursorPos(1,1)
print("Shutting down... Sending STOP signal.")
redstone.setAnalogOutput("bottom", 1)
print("Safe for disassembly.")
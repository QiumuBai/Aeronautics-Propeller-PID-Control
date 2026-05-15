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
local lastState = { cP = -999, cR = -999, fl = -1, fr = -1, bl = -1, br = -1, active = nil, kill = nil }

local function drawStaticUI()
    term.clear()
    term.setCursorPos(1, 1)
    print("+----------------------------------------+")
    print("|            Balancing System            |")
    print("+----------------------------------------+")
    print("| Pitch (X):             Roll (Z):       |")
    print("| Status   : [          ]                |")
    print("| Kill Sig : [    ]                      |")  -- NEW
    print("+----------------------------------------+")
    print("| FL: [  ]           FR: [  ]            |")
    print("| BL: [  ]           BR: [  ]            |")
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
            term.setTextColor(colors.green)
            term.write(" ACTIVE   ")
        else
            term.setTextColor(colors.red)
            term.write(" STOPPED  ")
        end
        term.setTextColor(colors.white)
        lastState.active = systemActive
    end

    -- NEW: Kill signal indicator
    if killActive ~= lastState.kill then
        term.setCursorPos(15, 6)
        if killActive then
            term.setTextColor(colors.red)
            term.write(" ON ")
        else
            term.setTextColor(colors.green)
            term.write("OFF ")
        end
        term.setTextColor(colors.white)
        lastState.kill = killActive
    end

    local pPos = {fl={8,8}, fr={27,8}, bl={8,9}, br={27,9}}  -- shifted +1
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
    local zeroCount = 0     -- ✅ MOVE HERE: outside while, persists between cycles
    local killActive = false -- ✅ ADD HERE: same reason

    while running do
        if not inputting then
            local s = { fl = 15, fr = 15, bl = 15, br = 15 }
            local cP, cR = 0, 0

            if systemActive then
                -- Normal Balancing Logic
                redstone.setAnalogOutput(sides.kill, 0)
                killActive = false -- ✅ reset each active cycle

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

                -- IDLE STOP LOGIC
                if s.fl == 0 and s.fr == 0 and s.bl == 0 and s.br == 0 then
                    zeroCount = zeroCount + 1
                    if zeroCount >= 5 then
                        redstone.setAnalogOutput(sides.kill, 1)
                        killActive = true -- ✅ mark kill as active
                    end
                else
                    zeroCount = 0 -- ✅ reset when props are non-zero
                end

            else
                -- Stop Logic
                redstone.setAnalogOutput(sides.kill, 1)
                killActive = true  -- ✅ mark kill as active
                s = { fl = 0, fr = 0, bl = 0, br = 0 }
                zeroCount = 0     -- ✅ reset so idle logic starts fresh on resume
            end

            -- Apply Output
            redstone.setAnalogOutput(sides.fl, s.fl)
            redstone.setAnalogOutput(sides.fr, s.fr)
            redstone.setAnalogOutput(sides.bl, s.bl)
            redstone.setAnalogOutput(sides.br, s.br)

            smartUpdate(cP, cR, s, killActive) -- ✅ pass killActive as 4th argument
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
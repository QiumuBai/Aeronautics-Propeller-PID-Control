-- Motor Computer: receives speed from central and applies it

local motorSide = "top"   -- side the speed controller is attached to
local modemSide = "back"  -- side the wireless modem is on
local centralId = 1       -- rednet ID of the central controller (PropellerBalancing)

local motor = peripheral.wrap(motorSide)
if not motor then error("Speed controller not found on side: " .. motorSide) end

rednet.open(modemSide)

print("Motor computer ready.")
print("My ID : " .. os.getComputerID())
print("Central ID : " .. centralId)

while true do
    -- 0.5s timeout: if central goes silent, stop the motor (safety)
    local senderId, speed = rednet.receive(0.5)

    if senderId == nil then
        motor.setTargetSpeed(0)
    elseif senderId == centralId and type(speed) == "number" then
        motor.setTargetSpeed(speed)
    end
end
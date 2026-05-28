-- Horror Entity Setup Script
-- Place this as a Script (not LocalScript) in ServerScriptService or your admin part
-- This handles moving the horror entity part to the correct location mid-game

local Players = game:GetService("Players")
local part = script.Parent -- The part that will trigger the horror

-- Disable the LocalScript initially
if part:FindFirstChild("HorrorEntity") then
	part.HorrorEntity.Disabled = true
end

-- When a player touches the part, enable the LocalScript
part.Touched:Connect(function(hit)
	if hit.Parent:FindFirstChild("Humanoid") then
		local localScript = part:FindFirstChild("HorrorEntity")
		if localScript and localScript:IsA("LocalScript") then
			localScript.Disabled = false
		end
	end
end)

print("Horror Entity Setup loaded!")

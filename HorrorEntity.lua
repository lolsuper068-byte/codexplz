-- Horror Entity Script
-- Place this as a LocalScript inside the part that triggers the horror effect

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local part = script.Parent

-- Configuration
local CONFIG = {
	BILLBOARD_DISTANCE = 100,
	GAZE_TIME_LIMIT = 4, -- 4 seconds per stage, so 12 total (4x4)
	LOOK_TEXT = {
		"Remember?",
		"You arent at peace here",
		"I can help you",
		"Hold still",
		"Look at me Look at me",
		"You miss it dont you",
		"Dont you miss them?",
		"I can bring you to that time again"
	},
	IMAGE_IDS = {
		116182441085881,
		77579280926056,
		92677338626250,
		98149804172095
	},
	HORROR_AUDIO_ID = 70605631708391,
	SPAWN_COOLDOWN = 10,
	JUMPSCARE_IMAGE = Color3.fromRGB(244, 174, 82)
}

-- State
local isActivated = false
local entitySpawned = false
local currentEntity = nil
local gazingAtEntity = false
local gazeStartTime = nil
local totalGazeTime = 0
local isDead = false
local jumpscareActive = false
local horrorAudio = nil
local effectsGui = nil
local textSpamConnection = nil
local otherAudioVolumes = {}

-- Create effects GUI
local function createEffectsGui()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "HorrorEffectsGui"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = player:WaitForChild("PlayerGui")
	
	-- Text display
	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "GazeText"
	textLabel.Size = UDim2.new(0.3, 0, 0.3, 0)
	textLabel.Position = UDim2.new(0.35, 0, 0.35, 0)
	textLabel.BackgroundTransparency = 1
	textLabel.TextScaled = true
	textLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
	textLabel.Font = Enum.Font.GothamBold
	textLabel.Parent = screenGui
	
	-- Scribbles display
	local scribbleFrame = Instance.new("Frame")
	scribbleFrame.Name = "Scribbles"
	scribbleFrame.Size = UDim2.new(1, 0, 1, 0)
	scribbleFrame.BackgroundTransparency = 1
	scribbleFrame.Parent = screenGui
	
	-- Jumpscare image
	local jumpscareLabel = Instance.new("ImageLabel")
	jumpscareLabel.Name = "JumpscareImage"
	jumpscareLabel.Size = UDim2.new(1, 0, 1, 0)
	jumpscareLabel.Position = UDim2.new(0, 0, 0, 0)
	jumpscareLabel.BackgroundColor3 = CONFIG.JUMPSCARE_IMAGE
	jumpscareLabel.BackgroundTransparency = 1
	jumpscareLabel.Visible = false
	jumpscareLabel.Parent = screenGui
	
	return screenGui, textLabel, scribbleFrame, jumpscareLabel
end

-- Spawn the entity billboard
local function spawnEntity()
	if entitySpawned then return end
	entitySpawned = true
	
	-- Create billboard
	local billboard = Instance.new("Part")
	billboard.Name = "HorrorEntity"
	billboard.Shape = Enum.PartType.Block
	billboard.Size = Vector3.new(5, 5, 0.2)
	billboard.CanCollide = false
	billboard.CFrame = camera.CFrame + camera.CFrame.LookVector * CONFIG.BILLBOARD_DISTANCE + Vector3.new(math.random(-50, 50), math.random(-50, 50), 0)
	billboard.TopSurface = Enum.SurfaceType.Smooth
	billboard.BottomSurface = Enum.SurfaceType.Smooth
	billboard.Parent = workspace
	
	-- Add BillboardGui
	local billboardGui = Instance.new("BillboardGui")
	billboardGui.Size = UDim2.new(5, 0, 5, 0)
	billboardGui.MaxDistance = math.huge
	billboardGui.Parent = billboard
	
	local imageLabel = Instance.new("ImageLabel")
	imageLabel.Size = UDim2.new(1, 0, 1, 0)
	imageLabel.BackgroundTransparency = 1
	imageLabel.Image = "rbxassetid://" .. CONFIG.IMAGE_IDS[1]
	imageLabel.Parent = billboardGui
	
	-- Make entity always face camera
	local bodyVelocity = Instance.new("BodyVelocity")
	bodyVelocity.Velocity = Vector3.new(0, 0, 0)
	bodyVelocity.MaxForce = Vector3.new(0, 0, 0)
	bodyVelocity.Parent = billboard
	
	currentEntity = {
		part = billboard,
		imageLabel = imageLabel,
		bodyVelocity = bodyVelocity,
		spawnTime = tick()
	}
	
	-- Face camera always
	local faceConnection
	faceConnection = RunService.RenderStepped:Connect(function()
		if not currentEntity or not currentEntity.part.Parent then
			faceConnection:Disconnect()
			return
		end
		
		local lookAtCamera = CFrame.new(currentEntity.part.Position, camera.CFrame.Position)
		currentEntity.part.CFrame = lookAtCamera
	end)
end

-- Check if player is looking at entity
local function isLookingAtEntity()
	if not currentEntity or not currentEntity.part.Parent then return false end
	
	local rayOrigin = camera.CFrame.Position
	local rayDirection = camera.CFrame.LookVector * 10000
	
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
	raycastParams.FilterDescendantsInstances = {player.Character}
	
	local rayResult = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	
	if rayResult and rayResult.Instance and rayResult.Instance:IsDescendantOf(currentEntity.part) then
		return true
	end
	
	return false
end

-- Spawn green text
local function spawnGazeText(container)
	local textLabel = Instance.new("TextLabel")
	textLabel.Text = CONFIG.LOOK_TEXT[math.random(1, #CONFIG.LOOK_TEXT)]
	textLabel.Size = UDim2.new(0.2, 0, 0.1, 0)
	textLabel.Position = UDim2.new(math.random(0, 80) / 100, 0, math.random(0, 90) / 100, 0)
	textLabel.BackgroundTransparency = 1
	textLabel.TextScaled = true
	textLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
	textLabel.Font = Enum.Font.GothamBold
	textLabel.Parent = container
	
	game:GetService("Debris"):AddItem(textLabel, 0.5)
end

-- Draw scribbles
local function drawScribbles(container, intensity)
	local scribbleFrame = Instance.new("Frame")
	scribbleFrame.Size = UDim2.new(1, 0, 1, 0)
	scribbleFrame.BackgroundTransparency = 1
	scribbleFrame.Parent = container
	
	for i = 1, math.floor(intensity * 5) do
		local line = Instance.new("TextLabel")
		line.Text = "/"
		line.Size = UDim2.new(0.05, 0, 0.05, 0)
		line.Position = UDim2.new(math.random(0, 100) / 100, 0, math.random(0, 100) / 100, 0)
		line.BackgroundTransparency = 1
		line.TextScaled = true
		line.TextColor3 = Color3.fromRGB(100, 100, 100)
		line.Rotation = math.random(0, 360)
		line.TextTransparency = 1 - intensity
		line.Parent = scribbleFrame
	end
	
	game:GetService("Debris"):AddItem(scribbleFrame, 0.3)
end

-- Handle gazing
local function handleGaze()
	if not effectsGui then return end
	
	local isLooking = isLookingAtEntity()
	
	if isLooking then
		if not gazingAtEntity then
			gazingAtEntity = true
			gazeStartTime = tick()
			
			-- Start horror audio
			if not horrorAudio then
				horrorAudio = Instance.new("Sound")
				horrorAudio.SoundId = "rbxassetid://" .. CONFIG.HORROR_AUDIO_ID
				horrorAudio.Volume = 0.01
				horrorAudio.Parent = camera
				horrorAudio:Play()
			end
			
			-- Save other audio volumes
			for _, sound in pairs(workspace:FindDescendantsOfClass("Sound")) do
				if sound ~= horrorAudio then
					otherAudioVolumes[sound] = sound.Volume
				end
			end
		end
		
		-- Calculate gaze time
		local currentTime = tick() - gazeStartTime
		totalGazeTime = math.max(totalGazeTime, currentTime)
		
		-- Update image based on gaze time
		local stage = math.floor(totalGazeTime / CONFIG.GAZE_TIME_LIMIT) + 1
		if stage > #CONFIG.IMAGE_IDS then stage = #CONFIG.IMAGE_IDS end
		
		if currentEntity and currentEntity.imageLabel then
			currentEntity.imageLabel.Image = "rbxassetid://" .. CONFIG.IMAGE_IDS[stage]
		end
		
		-- Update effects
		local intensity = math.min(totalGazeTime / (CONFIG.GAZE_TIME_LIMIT * 3), 1)
		
		-- Spawn text more frequently as time increases
		if textSpamConnection then textSpamConnection:Disconnect() end
		textSpamConnection = RunService.Heartbeat:Connect(function()
			if gazingAtEntity then
				spawnGazeText(effectsGui)
			end
		end)
		
		-- Draw scribbles
		drawScribbles(effectsGui:FindFirstChild("Scribbles"), intensity)
		
		-- Update horror audio volume (0.01 to 10 over 12 seconds)
		if horrorAudio then
			local volumeProgress = totalGazeTime / (CONFIG.GAZE_TIME_LIMIT * 3)
			horrorAudio.Volume = 0.01 + (volumeProgress * 9.99)
		end
		
		-- Lower other audio volumes
		for sound, originalVolume in pairs(otherAudioVolumes) do
			if sound and sound.Parent then
				sound.Volume = originalVolume * (1 - intensity)
			end
		end
		
		-- Update jumpscare background
		local jumpscareLabel = effectsGui:FindFirstChild("JumpscareImage")
		if jumpscareLabel then
			jumpscareLabel.BackgroundTransparency = 1 - intensity
		end
		
		-- Check if time limit exceeded
		if totalGazeTime >= CONFIG.GAZE_TIME_LIMIT * 3 then
			jumpscareActive = true
			
			-- Full jumpscare effect
			if jumpscareLabel then
				jumpscareLabel.BackgroundTransparency = 0
				jumpscareLabel.Visible = true
			end
			
			if horrorAudio then
				horrorAudio.Volume = 10
			end
			
			-- Kill player
			wait(0.5)
			if player.Character and player.Character:FindFirstChild("Humanoid") then
				player.Character.Humanoid.Health = 0
			end
			
			isDead = true
		end
	else
		if gazingAtEntity then
			gazingAtEntity = false
			-- Don't reset totalGazeTime - it persists!
		end
		
		if textSpamConnection then
			textSpamConnection:Disconnect()
			textSpamConnection = nil
		end
	end
end

-- Cleanup
local function cleanup()
	if textSpamConnection then
		textSpamConnection:Disconnect()
	end
	
	if horrorAudio then
		horrorAudio:Destroy()
		horrorAudio = nil
	end
	
	if currentEntity and currentEntity.part then
		currentEntity.part:Destroy()
	end
	
	currentEntity = nil
	entitySpawned = false
	gazingAtEntity = false
	totalGazeTime = 0
	gazeStartTime = nil
	jumpscareActive = false
	isDead = false
end

-- Main initialization
local function initialize()
	if isActivated then return end
	isActivated = true
	
	-- Make part invisible, anchored, and remove collision
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	
	-- Create GUI
	effectsGui, _, _, _ = createEffectsGui()
	
	-- Spawn entity
	spawnEntity()
	
	-- Main loop
	local gazeConnection
	gazeConnection = RunService.RenderStepped:Connect(function()
		if isDead or jumpscareActive then
			gazeConnection:Disconnect()
			cleanup()
			
			-- Respawn after cooldown
			wait(CONFIG.SPAWN_COOLDOWN)
			initialize()
			return
		end
		
		handleGaze()
	end)
end

-- Wait for part to be touched
part.Touched:Connect(function(hit)
	if hit.Parent:FindFirstChild("Humanoid") then
		initialize()
	end
end)

print("Horror Entity Script loaded!")

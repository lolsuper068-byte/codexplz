--[[
╔══════════════════════════════════════════════════════════════╗
║                INDEX GUI — IndexGuiLocal.lua                 ║
║                        (LocalScript)                         ║
╠══════════════════════════════════════════════════════════════╣
║  DO NOT place this manually.                                 ║
║  MainScript.lua automatically moves it to:                   ║
║    • StarterPlayer > StarterPlayerScripts  (future joins)    ║
║    • player > PlayerScripts                (current players) ║
║                                                              ║
║  ResetOnSpawn = false on the ScreenGui means the journal     ║
║  survives player deaths without resetting.                   ║
╚══════════════════════════════════════════════════════════════╝
]]

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local TweenService       = game:GetService("TweenService")
local UserInputService   = game:GetService("UserInputService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ── Wait for the bridge RemoteEvents set up by MainScript ─────
local bridge = ReplicatedStorage:WaitForChild("IndexGuiBridge", 120)
if not bridge then
	warn("[IndexGui] IndexGuiBridge not found in ReplicatedStorage — aborting.")
	return
end

local evShow         = bridge:WaitForChild("ShowGui",       60)
local evClear        = bridge:WaitForChild("ClearAll",      60)
local evClearRequest = bridge:WaitForChild("RequestClear",  60)

-- ── Constants ─────────────────────────────────────────────────
local CORNER_IMAGE  = "rbxassetid://134950303067880"
local ENTRY_IMAGE   = "rbxassetid://98626922525505"

local ANIM_FRAMES = {
	"rbxassetid://105279532012992",
	"rbxassetid://118543446849996",
	"rbxassetid://95819697374892",
	"rbxassetid://97770512283868",
	"rbxassetid://70915561282049",
	"rbxassetid://75426597246730",
	"rbxassetid://76439551483955",   -- stays on this frame
}
local FRAME_SPEED = 0.13   -- seconds per animation frame

-- Journal dimensions (nearly full screen)
local JW, JH          = 1200, 900
local CENTER_POS      = UDim2.new(0.5, -JW/2, 0.5, -JH/2)
local CENTER_SIZE     = UDim2.new(0, JW, 0, JH)

-- Corner icon dimensions (bottom-left) - stays small
local CW, CH          = 80, 100
local CORNER_POS_UI   = UDim2.new(0, 15, 1, -115)
local CORNER_SIZE_UI  = UDim2.new(0, CW, 0, CH)

-- Creepy colour palette
local DARK_RED        = Color3.fromRGB(65, 0, 0)
local MEDIUM_RED      = Color3.fromRGB(120, 0, 0)
local INK             = Color3.fromRGB(52, 14, 10)
local PARCHMENT       = Color3.fromRGB(215, 196, 168)

-- ── Build ScreenGui ───────────────────────────────────────────
-- ZIndexBehavior.Global so every ZIndex is absolute; makes
-- stacking order predictable regardless of parent hierarchy.
local gui = Instance.new("ScreenGui")
gui.Name             = "IndexJournal"
gui.ResetOnSpawn     = false          -- survives respawns ← critical
gui.ZIndexBehavior   = Enum.ZIndexBehavior.Global
gui.DisplayOrder     = 50
gui.IgnoreGuiInset   = false
gui.Parent           = playerGui

-- ── State machine ─────────────────────────────────────────────
-- "inactive"  → waiting for server activation event
-- "corner"    → small icon in bottom-left
-- "opening"   → animating from corner to centre
-- "main"      → journal open on first page ("schizophreniav2")
-- "entry"     → journal open on schizv2 detail page
-- "closing"   → animating back to corner
local state     = "inactive"
local animating = false   -- blocks concurrent open/close tweens

-- ══════════════════════════════════════════════════════════════
--  LAYER 1 — Full-screen backdrop (ZIndex 9)
--  Captures clicks OUTSIDE the journal to close it.
-- ══════════════════════════════════════════════════════════════
local backdrop = Instance.new("TextButton")
backdrop.Name                 = "Backdrop"
backdrop.Size                 = UDim2.new(1, 0, 1, 0)
backdrop.BackgroundTransparency = 1
backdrop.Text                 = ""
backdrop.ZIndex               = 9
backdrop.Visible              = false
backdrop.Parent               = gui

-- ══════════════════════════════════════════════════════════════
--  LAYER 2 — Corner icon (ZIndex 10)
--  Small journal image in the bottom-left; pulses gently.
-- ══════════════════════════════════════════════════════════════
local cornerBtn = Instance.new("ImageButton")
cornerBtn.Name                 = "CornerJournal"
cornerBtn.Size                 = CORNER_SIZE_UI
cornerBtn.Position             = CORNER_POS_UI
cornerBtn.Image                = CORNER_IMAGE
cornerBtn.BackgroundTransparency = 1
cornerBtn.ScaleType            = Enum.ScaleType.Fit
cornerBtn.ZIndex               = 10
cornerBtn.Visible              = false
cornerBtn.Parent               = gui

-- Gentle pulse so the player notices the journal
local pulseTween
local PULSE_ON  = { Size = UDim2.new(0, CW+7, 0, CH+9),
	Position = UDim2.new(0, 11, 1, -119) }
local PULSE_OFF = { Size = CORNER_SIZE_UI,
	Position = CORNER_POS_UI }

local function startPulse()
	if pulseTween then pulseTween:Cancel() end
	pulseTween = TweenService:Create(
		cornerBtn,
		TweenInfo.new(0.95, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		PULSE_ON
	)
	pulseTween:Play()
end

local function stopPulse()
	if pulseTween then pulseTween:Cancel(); pulseTween = nil end
	cornerBtn.Size     = CORNER_SIZE_UI
	cornerBtn.Position = CORNER_POS_UI
end

-- ══════════════════════════════════════════════════════════════
--  LAYER 3 — Journal container (starts hidden)
-- ══════════════════════════════════════════════════════════════
local journalFrame = Instance.new("Frame")
journalFrame.Name                 = "JournalFrame"
journalFrame.Size                 = CENTER_SIZE
journalFrame.Position             = CENTER_POS
journalFrame.BackgroundTransparency = 1
journalFrame.Visible              = false
journalFrame.ZIndex               = 11   -- rendered; non-interactive
journalFrame.Parent               = gui

-- Animated background image (the journal page itself)
local journalBg = Instance.new("ImageLabel")
journalBg.Name              = "JournalBg"
journalBg.Size              = UDim2.new(1, 0, 1, 0)
journalBg.Image             = ANIM_FRAMES[1]
journalBg.BackgroundTransparency = 1
journalBg.ScaleType         = Enum.ScaleType.Stretch
journalBg.ZIndex            = 11          -- same layer: decorative only
journalBg.Parent            = journalFrame

-- Transparent click-blocker over the journal area (ZIndex 12).
-- Sits above the backdrop (9) so clicks INSIDE the journal
-- do NOT fall through and accidentally close it.
local journalClickBlock = Instance.new("TextButton")
journalClickBlock.Name                 = "JournalClickBlock"
journalClickBlock.Size                 = UDim2.new(1, 0, 1, 0)
journalClickBlock.BackgroundTransparency = 1
journalClickBlock.Text                 = ""
journalClickBlock.ZIndex               = 12
journalClickBlock.Parent               = journalFrame

-- ══════════════════════════════════════════════════════════════
--  PAGE A — First page ("schizophreniav2" title)  ZIndex 20+
-- ══════════════════════════════════════════════════════════════
local firstPage = Instance.new("Frame")
firstPage.Name                 = "FirstPage"
firstPage.Size                 = UDim2.new(1, 0, 1, 0)
firstPage.BackgroundTransparency = 1
firstPage.Visible              = false
firstPage.ZIndex               = 20
firstPage.Parent               = journalFrame

-- Clickable title at top of LEFT page (inside white area)
local titleBtn = Instance.new("TextButton")
titleBtn.Name              = "TitleBtn"
titleBtn.Size              = UDim2.new(0.35, 0, 0.08, 0)
titleBtn.Position          = UDim2.new(0.12, 0, 0.12, 0)
titleBtn.Text              = "schizophreniav2"
titleBtn.TextColor3        = DARK_RED
titleBtn.Font              = Enum.Font.Antique
titleBtn.TextScaled        = true
titleBtn.TextSize          = 20
titleBtn.BackgroundTransparency = 1
titleBtn.TextStrokeTransparency = 0.55
titleBtn.TextStrokeColor3  = Color3.fromRGB(0, 0, 0)
titleBtn.ZIndex            = 25
titleBtn.Parent            = firstPage

-- Hover: text brightens slightly to hint it's clickable
titleBtn.MouseEnter:Connect(function()
	TweenService:Create(titleBtn, TweenInfo.new(0.1), {TextColor3 = MEDIUM_RED}):Play()
end)
titleBtn.MouseLeave:Connect(function()
	TweenService:Create(titleBtn, TweenInfo.new(0.1), {TextColor3 = DARK_RED}):Play()
end)

-- ══════════════════════════════════════════════════════════════
--  PAGE B — Entry detail (two-panel: image | description)
-- ══════════════════════════════════════════════════════════════
local entryPage = Instance.new("Frame")
entryPage.Name                 = "EntryPage"
entryPage.Size                 = UDim2.new(1, 0, 1, 0)
entryPage.BackgroundTransparency = 1
entryPage.Visible              = false
entryPage.ZIndex               = 20
entryPage.Parent               = journalFrame

-- X button — top-right corner of the journal
local xBtn = Instance.new("TextButton")
xBtn.Name               = "CloseEntryBtn"
xBtn.Size               = UDim2.new(0, 45, 0, 45)
xBtn.Position           = UDim2.new(1, -65, 0.05, 0)
xBtn.Text               = "✕"
xBtn.TextColor3         = MEDIUM_RED
xBtn.Font               = Enum.Font.Antique
xBtn.TextSize           = 28
xBtn.BackgroundColor3   = PARCHMENT
xBtn.BorderSizePixel    = 1
xBtn.BorderColor3       = Color3.fromRGB(110, 75, 40)
xBtn.ZIndex             = 30
xBtn.Parent             = entryPage
Instance.new("UICorner", xBtn).CornerRadius = UDim.new(0, 6)

xBtn.MouseEnter:Connect(function()
	TweenService:Create(xBtn, TweenInfo.new(0.1), {BackgroundColor3 = Color3.fromRGB(180, 0, 0), TextColor3 = Color3.fromRGB(255,220,220)}):Play()
end)
xBtn.MouseLeave:Connect(function()
	TweenService:Create(xBtn, TweenInfo.new(0.1), {BackgroundColor3 = PARCHMENT, TextColor3 = MEDIUM_RED}):Play()
end)

-- ── Left panel: entity image + "Class 6/10" ───────────────────
local leftPanel = Instance.new("Frame")
leftPanel.Name                 = "LeftPanel"
leftPanel.Size                 = UDim2.new(0.38, 0, 0.70, 0)
leftPanel.Position             = UDim2.new(0.12, 0, 0.18, 0)
leftPanel.BackgroundTransparency = 1
leftPanel.ZIndex               = 22
leftPanel.Parent               = entryPage

local entryImg = Instance.new("ImageLabel")
entryImg.Size               = UDim2.new(1, 0, 0.72, 0)
entryImg.Image              = ENTRY_IMAGE
entryImg.BackgroundTransparency = 1
entryImg.ScaleType          = Enum.ScaleType.Fit
entryImg.ZIndex             = 23
entryImg.Parent             = leftPanel

local classLabel = Instance.new("TextLabel")
classLabel.Size             = UDim2.new(1, 0, 0.20, 0)
classLabel.Position         = UDim2.new(0, 0, 0.75, 0)
classLabel.Text             = "Class 6/10"
classLabel.TextColor3       = INK
classLabel.Font             = Enum.Font.Antique
classLabel.TextSize         = 16
classLabel.TextScaled       = true
classLabel.TextXAlignment   = Enum.TextXAlignment.Center
classLabel.BackgroundTransparency = 1
classLabel.TextStrokeTransparency = 0.75
classLabel.ZIndex           = 23
classLabel.Parent           = leftPanel

-- ── Right panel: description text ─────────────────────────────
local rightPanel = Instance.new("Frame")
rightPanel.Name                = "RightPanel"
rightPanel.Size                = UDim2.new(0.38, 0, 0.70, 0)
rightPanel.Position            = UDim2.new(0.50, 0, 0.18, 0)
rightPanel.BackgroundTransparency = 1
rightPanel.ZIndex              = 22
rightPanel.Parent              = entryPage

local descLabel = Instance.new("TextLabel")
descLabel.Size              = UDim2.new(1, -10, 0.98, 0)
descLabel.Position          = UDim2.new(0, 5, 0.01, 0)
descLabel.Text              = "known for his deadly encounters Schizophrenia unlike his v1 counterpart can catch up to you easier and encounters with him are almost always fatal. Your best bet is soldier's rocket or pyro's blast in terms of stunning. in terms of speed use scout's soda or demomans charge. but none of these strategies can guarantee your survival. the overall best survivor for schizophrenia v2 is demoman due to his charge and stun ( if you can land it. not recommended to try )."
descLabel.TextColor3        = INK
descLabel.Font              = Enum.Font.Antique
descLabel.TextSize          = 13
descLabel.TextScaled        = false
descLabel.TextWrapped       = true
descLabel.TextXAlignment    = Enum.TextXAlignment.Left
descLabel.TextYAlignment    = Enum.TextYAlignment.Top
descLabel.BackgroundTransparency = 1
descLabel.TextStrokeTransparency = 0.75
descLabel.ZIndex            = 23
descLabel.Parent            = rightPanel

-- ══════════════════════════════════════════════════════════════
--  CONFIRM DIALOG (only visible to CrashBoom0_0, ZIndex 200+)
-- ══════════════════════════════════════════════════════════════
local confirmFrame = Instance.new("Frame")
confirmFrame.Name             = "ConfirmDialog"
confirmFrame.Size             = UDim2.new(0, 360, 0, 170)
confirmFrame.Position         = UDim2.new(0.5, -180, 0.5, -85)
confirmFrame.BackgroundColor3 = Color3.fromRGB(20, 6, 6)
confirmFrame.BorderSizePixel  = 0
confirmFrame.Visible          = false
confirmFrame.ZIndex           = 200
confirmFrame.Parent           = gui
Instance.new("UICorner", confirmFrame).CornerRadius = UDim.new(0, 10)

local confirmStroke = Instance.new("UIStroke")
confirmStroke.Color     = Color3.fromRGB(140, 0, 0)
confirmStroke.Thickness = 2
confirmStroke.Parent    = confirmFrame

local confirmLabel = Instance.new("TextLabel")
confirmLabel.Size             = UDim2.new(1, -24, 0.52, 0)
confirmLabel.Position         = UDim2.new(0, 12, 0.06, 0)
confirmLabel.Text             = "Are you sure you want to\npermanently clear the Index GUI?"
confirmLabel.TextColor3       = Color3.fromRGB(220, 175, 175)
confirmLabel.Font             = Enum.Font.Antique
confirmLabel.TextScaled       = true
confirmLabel.BackgroundTransparency = 1
confirmLabel.ZIndex           = 201
confirmLabel.Parent           = confirmFrame

local yesBtn = Instance.new("TextButton")
yesBtn.Size               = UDim2.new(0.37, 0, 0.27, 0)
yesBtn.Position           = UDim2.new(0.07, 0, 0.66, 0)
yesBtn.Text               = "Yes"
yesBtn.BackgroundColor3   = Color3.fromRGB(145, 0, 0)
yesBtn.TextColor3         = Color3.fromRGB(255, 220, 220)
yesBtn.Font               = Enum.Font.Antique
yesBtn.TextScaled         = true
yesBtn.ZIndex             = 201
yesBtn.Parent             = confirmFrame
Instance.new("UICorner", yesBtn).CornerRadius = UDim.new(0, 6)

local noBtn = Instance.new("TextButton")
noBtn.Size                = UDim2.new(0.37, 0, 0.27, 0)
noBtn.Position            = UDim2.new(0.56, 0, 0.66, 0)
noBtn.Text                = "No"
noBtn.BackgroundColor3    = Color3.fromRGB(0, 90, 0)
noBtn.TextColor3          = Color3.fromRGB(200, 255, 200)
noBtn.Font                = Enum.Font.Antique
noBtn.TextScaled          = true
noBtn.ZIndex              = 201
noBtn.Parent              = confirmFrame
Instance.new("UICorner", noBtn).CornerRadius = UDim.new(0, 6)

-- ══════════════════════════════════════════════════════════════
--  STATE MACHINE FUNCTIONS
-- ══════════════════════════════════════════════════════════════

local function setCorner()
	state                = "corner"
	journalFrame.Visible = false
	backdrop.Visible     = false
	entryPage.Visible    = false
	firstPage.Visible    = false
	cornerBtn.Visible    = true
	startPulse()
end

-- Called with task.spawn so it can yield for tweens/animation
local function openJournal()
	if state ~= "corner" or animating then return end
	animating = true
	state     = "opening"

	stopPulse()
	cornerBtn.Visible = false
	backdrop.Visible  = true

	-- Reset journal to corner size before starting tween
	journalBg.Image      = ANIM_FRAMES[1]
	firstPage.Visible    = false
	entryPage.Visible    = false
	journalFrame.Size    = CORNER_SIZE_UI
	journalFrame.Position = CORNER_POS_UI
	journalFrame.Visible = true

	-- ── Step 1: grow & slide from corner to centre ──────────
	local growTween = TweenService:Create(
		journalFrame,
		TweenInfo.new(0.60, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Size = CENTER_SIZE, Position = CENTER_POS }
	)
	growTween:Play()
	growTween.Completed:Wait()

	-- ── Step 2: play the "gif" animation, stay on last frame ─
	for i, frameId in ipairs(ANIM_FRAMES) do
		journalBg.Image = frameId
		if i < #ANIM_FRAMES then
			task.wait(FRAME_SPEED)
		end
	end
	-- Last frame (76439551483955) remains; animation does NOT loop.

	-- ── Step 3: reveal the first page ───────────────────────
	firstPage.Visible = true
	state             = "main"
	animating         = false
end

local function showEntry()
	if state ~= "main" then return end
	firstPage.Visible = false
	entryPage.Visible = true
	state             = "entry"
end

local function backToMain()
	if state ~= "entry" then return end
	entryPage.Visible = false
	firstPage.Visible = true
	state             = "main"
end

local function closeJournal()
	if (state ~= "main" and state ~= "entry") or animating then return end
	animating = true
	state     = "closing"

	firstPage.Visible = false
	entryPage.Visible = false
	backdrop.Visible  = false

	-- ── Reverse animation: slide & shrink back to corner ─────
	local shrinkTween = TweenService:Create(
		journalFrame,
		TweenInfo.new(0.60, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
		{ Size = CORNER_SIZE_UI, Position = CORNER_POS_UI }
	)
	shrinkTween:Play()
	shrinkTween.Completed:Wait()

	journalFrame.Visible = false
	animating            = false
	setCorner()   -- restore corner icon + pulse
end

-- ══════════════════════════════════════════════════════════════
--  BUTTON CONNECTIONS
-- ══════════════════════════════════════════════════════════════

cornerBtn.MouseButton1Click:Connect(function()
	if state == "corner" then
		task.spawn(openJournal)
	end
end)

titleBtn.MouseButton1Click:Connect(function()
	showEntry()
end)

xBtn.MouseButton1Click:Connect(function()
	backToMain()
end)

-- Clicks that reach the backdrop are OUTSIDE the journal → close
backdrop.MouseButton1Click:Connect(function()
	if state == "main" or state == "entry" then
		task.spawn(closeJournal)
	end
end)

-- ══════════════════════════════════════════════════════════════
--  REMOTE EVENT HANDLERS
-- ══════════════════════════════════════════════════════════════

-- Server says "the part was touched — show the icon"
evShow.OnClientEvent:Connect(function()
	if state == "inactive" then
		setCorner()
	end
end)

-- Server says "CrashBoom0_0 cleared everything — destroy self"
evClear.OnClientEvent:Connect(function()
	gui:Destroy()
	script:Destroy()
end)

-- ══════════════════════════════════════════════════════════════
--  CrashBoom0_0 CONTROLS  (/ key → confirmation dialog)
-- ══════════════════════════════════════════════════════════════
if player.Name == "CrashBoom0_0" then

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		-- gameProcessed = true when the chat box consumed the key,
		-- so only fire when it's a genuine freeform keypress.
		if gameProcessed then return end
		if input.KeyCode == Enum.KeyCode.Slash then
			confirmFrame.Visible = not confirmFrame.Visible
		end
	end)

	yesBtn.MouseButton1Click:Connect(function()
		confirmFrame.Visible = false
		evClearRequest:FireServer()
		-- Server will send ClearAll back to all clients (including us)
		-- which destroys the GUI and script from the evClear handler above.
	end)

	noBtn.MouseButton1Click:Connect(function()
		confirmFrame.Visible = false
	end)
end

-- ══════════════════════════════════════════════════════════════
--  GUI INTEGRITY GUARD
--  Detects if an admin command re-parents or orphans the ScreenGui
--  and immediately re-anchors it to PlayerGui.
--  Note: :Destroy() cannot be undone; this only catches moves.
-- ══════════════════════════════════════════════════════════════
gui.AncestryChanged:Connect(function(_, newParent)
	if newParent == nil and state ~= "inactive" then
		-- Short delay then re-parent if the gui still exists
		task.wait(0.05)
		local ok = pcall(function()
			if gui and gui.Parent == nil then
				gui.Parent = playerGui
			end
		end)
		if not ok then
			-- GUI was destroyed externally and can't be restored;
			-- nothing further we can do without rebuilding from scratch.
		end
	end
end)

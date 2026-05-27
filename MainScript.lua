--[[
╔══════════════════════════════════════════════════════════════╗
║                  INDEX GUI — MainScript.lua                  ║
║                       (Server Script)                        ║
╠══════════════════════════════════════════════════════════════╣
║  SETUP:                                                      ║
║  1. Insert a Part into Workspace                             ║
║  2. Place THIS script (Script) as a direct child of that Part║
║  3. Place IndexGuiLocal.lua (LocalScript) as a child of THIS ║
║     script — name it exactly:  IndexGuiLocal                 ║
║  That's it. Works on mid-game insertion via Kohls Insert.    ║
╚══════════════════════════════════════════════════════════════╝

  • On touch  → part deletes itself; script moves to SSS; GUI
                appears for ALL players. One-shot, no repeat.
  • On death  → GUI persists (ResetOnSpawn = false).
  • CrashBoom0_0 presses / → confirmation → fires clear to server
                → server nukes everything.
  • Kohls :clear → workspace only; SSS + PlayerScripts are safe.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer     = game:GetService("StarterPlayer")
local ServerScriptService = game:GetService("ServerScriptService")

-- ── Safety: make sure LocalScript template exists ─────────────
local part = script.Parent

-- Wait a bit for the LocalScript to be placed (handles mid-game insertion)
local localTemplate = script:WaitForChild("IndexGuiLocal", 30)
if not localTemplate then
	warn("[IndexGui] FATAL: 'IndexGuiLocal' LocalScript not found as a child of MainScript!")
	warn("[IndexGui] Hierarchy must be: Part > MainScript > IndexGuiLocal")
	return
end

-- ── Bridge Folder (holds RemoteEvents for Client<->Server) ────
-- Destroy any leftover from a previous insertion so mid-game
-- re-inserts start clean.
local existingBridge = ReplicatedStorage:FindFirstChild("IndexGuiBridge")
if existingBridge then existingBridge:Destroy() end

local bridge = Instance.new("Folder")
bridge.Name   = "IndexGuiBridge"
bridge.Parent = ReplicatedStorage

-- Server → Client: tell everyone to show their journal icon
local evShow = Instance.new("RemoteEvent")
evShow.Name   = "ShowGui"
evShow.Parent = bridge

-- Server → Client: wipe the whole GUI (CrashBoom0_0 cleared it)
local evClear = Instance.new("RemoteEvent")
evClear.Name   = "ClearAll"
evClear.Parent = bridge

-- Client → Server: CrashBoom0_0 confirmed the clear
local evClearRequest = Instance.new("RemoteEvent")
evClearRequest.Name   = "RequestClear"
evClearRequest.Parent = bridge

-- ── Deploy LocalScript to a single player's PlayerScripts ─────
local function deployToPlayer(player)
	local ps = player:WaitForChild("PlayerScripts", 10)
	if not ps then return end
	-- Avoid duplicating on mid-game re-insert
	if ps:FindFirstChild("IndexGuiLocal") then return end
	local clone = localTemplate:Clone()
	clone.Disabled = false
	clone.Parent   = ps
end

-- Give to everyone currently in-game
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(deployToPlayer, p)
end

-- ── StarterPlayerScripts clone (for players joining later) ────
-- LocalScripts here run once per session and survive respawns.
local sps = StarterPlayer:FindFirstChild("StarterPlayerScripts")
if sps then
	local old = sps:FindFirstChild("IndexGuiLocal")
	if old then old:Destroy() end
	local clone = localTemplate:Clone()
	clone.Disabled = false
	clone.Parent   = sps
end

-- ── Activation state ──────────────────────────────────────────
-- Stored as a local variable; also mirrored into bridge so the
-- PlayerAdded handler below can check it without a global.
local activated = false

-- ── PlayerAdded: deploy & catch up late joiners ───────────────
local playerAddedConn
playerAddedConn = Players.PlayerAdded:Connect(function(player)
	task.spawn(function()
		deployToPlayer(player)
		if activated then
			-- LocalScript needs a moment to initialise before
			-- it can receive the ShowGui event.
			task.wait(2)
			evShow:FireClient(player)
		end
	end)
end)

-- ── Touch Detection (one-shot) ────────────────────────────────
-- Track if part is still valid
local partValid = true
local touchConn

-- Monitor part destruction
part.AncestryChanged:Connect(function(child, parent)
	if parent == nil then
		partValid = false
	end
end)

-- Set up touch detection
local function setupTouchDetection()
	if not partValid then return end
	
	touchConn = part.Touched:Connect(function(_hit)
		if activated or not partValid then return end
		activated = true
		if touchConn then
			touchConn:Disconnect()
		end

		-- Move THIS script to ServerScriptService BEFORE deleting the
		-- part, so the script is not parented to a deleted object.
		script.Parent = ServerScriptService

		-- Nuke the part (scripts are already safe in SSS).
		if partValid then
			part:Destroy()
			partValid = false
		end

		-- Tell every connected client to reveal the journal icon.
		evShow:FireAllClients()
	end)
end

setupTouchDetection()

-- ── Clear Request (only CrashBoom0_0 can trigger this) ────────
evClearRequest.OnServerEvent:Connect(function(sender)
	-- Hard-check on server; never trust the client alone.
	if sender.Name ~= "CrashBoom0_0" then return end

	-- 1. Tell all clients to destroy their GUIs.
	evClear:FireAllClients()

	-- 2. Give clients a moment to self-destruct cleanly.
	task.wait(1.5)

	-- 3. Pull the LocalScript from StarterPlayerScripts so
	--    future joins never get it.
	local starterScripts = StarterPlayer:FindFirstChild("StarterPlayerScripts")
	if starterScripts then
		local s = starterScripts:FindFirstChild("IndexGuiLocal")
		if s then s:Destroy() end
	end

	-- 4. Disconnect the PlayerAdded listener.
	if playerAddedConn then
		playerAddedConn:Disconnect()
	end

	-- 5. Destroy the bridge (RemoteEvents) in ReplicatedStorage.
	if bridge and bridge.Parent then
		bridge:Destroy()
	end

	-- 6. Self-destruct this server script entirely.
	script:Destroy()
end)

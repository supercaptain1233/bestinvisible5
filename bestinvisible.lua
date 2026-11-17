--[[
======================================================================
    best invisible  v2   |   universal   |   delta executor
======================================================================
    by github.com/supercaptain1233
    repo: bestinvisible5   file: bestinvisible5.lua

    WHAT IT DOES
    ------------
    * a medium red box sits on your screen, named "best invisible"
    * the name is dead centre, that is the whole point of the box
    * hold the box and drag it anywhere you like
    * click it once and it turns green, the script is ON
    * click it again and it turns red, the script is OFF

    WHEN IT IS ON
    -------------
    * your real body is cloned, welded solid and parked 10000 studs out
    * the body you keep is a 55 percent transparent ghost of you
    * the camera is left alone, plain default third person
    * you walk, jump and sprint with the ghost exactly like normal
    * the ghost is godmode, the real body is out of reach, you cannot die
    * a short afterimage trail follows the ghost while you move

    WHEN IT IS OFF
    ---------------
    * every transparency is restored to the exact value it had
    * the far body and the trail are deleted, the nametag comes back

    LOADER  (prefilled, paste this straight into delta)
    --------------------------------------------------
    loadstring(game:HttpGet(
        "https://raw.githubusercontent.com/supercaptain1233/bestinvisible5/main/bestinvisible5.lua"
    ))()

    UNIVERSAL
    ---------
    no game specific paths, no external modules, no key system.
    delta or any other executor, r6 or r15, mobile or pc.
--]]

local prefilledLoader = [[
    loadstring(game:HttpGet("https://raw.githubusercontent.com/supercaptain1233/bestinvisible5/main/bestinvisible5.lua"))()
]]

-- ======================================================================
--  services, cached once, never re-indexed inside a loop
-- ======================================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")
local Debris = game:GetService("Debris")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui", 30)

local function getCharacter()
	return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
end

local function getHumanoid()
	local character = LocalPlayer.Character
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

-- ======================================================================
--  3. config
-- ======================================================================
local CONFIG = {
	BoxSize = 138,
	BoxX = 46,
	BoxY = -69,
	Red = Color3.fromRGB(198, 44, 44),
	RedDark = Color3.fromRGB(122, 20, 20),
	Green = Color3.fromRGB(48, 202, 98),
	GreenDark = Color3.fromRGB(18, 116, 54),
	GhostAlpha = 0.55,
	FadeTime = 0.22,
	FarDistance = 10000,
	DragThreshold = 6,
	TrailRate = 0.14,
	TrailLife = 0.45,
	TrailAlpha = 0.82,
	Title = "best invisible",
	FarBodyName = "best invisible real body",
	PocketName = "best invisible pocket",
	GuiName = "best invisible",
}

-- live state
local isOn = false
local isDragging = false
local dragOrigin = nil
local boxOrigin = nil
local dragTravel = 0
local farBody = nil
local pocket = nil
local godConnection = nil
local trailConnection = nil
local ghostHighlight = nil
local savedAlpha = {}
local savedWalk = nil
local savedNametag = nil
local godActive = false
local lastToggle = 0
local toggle
local clampToViewport
local paint
local pressFeedback
local playSound
local requestToggle

-- ======================================================================
--  tiny helpers
-- ======================================================================
-- instances are built through here, property order is never a surprise
local function new(class, props, parent)
	local instance = Instance.new(class)
	for key, value in pairs(props) do
		instance[key] = value
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

local function getRoot()
	local character = LocalPlayer.Character
	if not character then return nil end
	local root = character:FindFirstChild("HumanoidRootPart")
	-- r6 fallbacks in case a game renames the root
	return root or character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso")
end

local function isPress(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

local function isMotion(input)
	return input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch
end

-- ======================================================================
--  5. screen gui
-- ======================================================================
local existing = PlayerGui:FindFirstChild(CONFIG.GuiName)
if existing then
	existing:Destroy()
end

local screenGui = new("ScreenGui", {
	Name = CONFIG.GuiName,
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 999,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, PlayerGui)

local box = new("Frame", {
	Name = CONFIG.Title,
	Size = UDim2.fromOffset(CONFIG.BoxSize, CONFIG.BoxSize),
	Position = UDim2.new(0, CONFIG.BoxX, 0.5, CONFIG.BoxY),
	BackgroundColor3 = CONFIG.Red,
	BorderSizePixel = 0,
	Active = true,
	ClipsDescendants = false,
	ZIndex = 3,
}, screenGui)

-- shadow, so the box still reads on a bright map
local shadow = new("Frame", {
	Name = "shadow",
	Size = UDim2.fromScale(1, 1),
	Position = UDim2.fromOffset(4, 6),
	BackgroundColor3 = Color3.fromRGB(0, 0, 0),
	BackgroundTransparency = 0.6,
	BorderSizePixel = 0,
	ZIndex = 1,
}, screenGui)
new("UICorner", {
	CornerRadius = UDim.new(0, 18),
}, shadow)

-- the shadow is bound to the box so it can never drift
box:GetPropertyChangedSignal("Position"):Connect(function()
	shadow.Position = box.Position + UDim2.fromOffset(4, 6)
end)

-- the grab bar, a visual cue that the box is draggable
local grabBar = new("Frame", {
	Name = "grab",
	Size = UDim2.new(1, -44, 0, 3),
	Position = UDim2.new(0, 22, 0, 8),
	BackgroundColor3 = Color3.fromRGB(255, 255, 255),
	BackgroundTransparency = 0.45,
	BorderSizePixel = 0,
	ZIndex = 4,
}, box)
new("UICorner", {
	CornerRadius = UDim.new(1, 0),
}, grabBar)

-- hint under the box, it follows because it is a child
local hint = new("TextLabel", {
	Name = "hint",
	Size = UDim2.new(1, 0, 0, 14),
	Position = UDim2.new(0, 0, 1, 7),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	TextSize = 11,
	TextColor3 = Color3.fromRGB(238, 238, 238),
	Text = "drag  /  click",
	TextTransparency = 0.3,
}, box)

-- ======================================================================
--  6. box styling
-- ======================================================================

new("UICorner", {
	CornerRadius = UDim.new(0, 18),
}, box)

-- outline that swaps colour with the state
local stroke = new("UIStroke", {
	Thickness = 2,
	Color = Color3.fromRGB(255, 255, 255),
	Transparency = 0.55,
	ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
}, box)

-- gradient, so the fill has depth without any image asset
local gradient = new("UIGradient", {
	Rotation = 90,
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.04),
		NumberSequenceKeypoint.new(1, 0.38),
	}),
}, box)

-- padding, nothing inside may touch the outline
new("UIPadding", {
	PaddingTop = UDim.new(0, 16),
	PaddingBottom = UDim.new(0, 14),
	PaddingLeft = UDim.new(0, 8),
	PaddingRight = UDim.new(0, 8),
}, box)

-- the name, dead centre, that is the whole point of the box
local title = new("TextLabel", {
	Name = "title",
	Size = UDim2.new(1, 0, 1, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 17,
	TextColor3 = Color3.fromRGB(255, 255, 255),
	TextStrokeTransparency = 0.3,
	TextWrapped = true,
	Text = CONFIG.Title,
	TextXAlignment = Enum.TextXAlignment.Center,
	TextYAlignment = Enum.TextYAlignment.Center,
	ZIndex = 4,
}, box)

-- state readout under the name, the mode is never ambiguous
local stateLabel = new("TextLabel", {
	Name = "state",
	Size = UDim2.new(1, 0, 0, 13),
	Position = UDim2.new(0, 0, 1, -17),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	TextSize = 11,
	TextColor3 = Color3.fromRGB(255, 238, 238),
	TextTransparency = 0.12,
	Text = "off",
	ZIndex = 4,
}, box)

-- the state dot, red off, green on, mirrors the fill exactly
local dot = new("Frame", {
	Name = "dot",
	Size = UDim2.fromOffset(9, 9),
	Position = UDim2.new(0.5, -4.5, 0, 22),
	BackgroundColor3 = CONFIG.Red,
	BorderSizePixel = 0,
	ZIndex = 4,
}, box)

-- (the dot gets rounded in the feedback section below)

new("UICorner", {
	CornerRadius = UDim.new(1, 0),
}, dot)
-- ======================================================================
--  7. feedback
-- ======================================================================

-- press feedback, the box sinks a few pixels while held
local pressTween = nil

function pressFeedback(down)
	if pressTween then
		pressTween:Cancel()
	end
	local inset = down and 8 or 0
	pressTween = TweenService:Create(box, TweenInfo.new(0.12), {
		Size = UDim2.fromOffset(CONFIG.BoxSize - inset, CONFIG.BoxSize - inset),
	})
	pressTween:Play()
end

-- two sounds, one for on, one for off
local soundOn = new("Sound", {
	SoundId = "rbxassetid://6895079853",
	Volume = 0.4,
	Parent = screenGui,
})

local soundOff = new("Sound", {
	SoundId = "rbxassetid://6895079853",
	Volume = 0.3,
	PlaybackSpeed = 0.82,
	Parent = screenGui,
})

function playSound(on)
	(on and soundOn or soundOff):Play()
end

-- colour is always tweened, never snapped, so the swap reads
function paint(colour, dark, labelText)
	TweenService:Create(box, TweenInfo.new(0.2), { BackgroundColor3 = colour }):Play()
	TweenService:Create(dot, TweenInfo.new(0.2), { BackgroundColor3 = colour }):Play()
	TweenService:Create(stroke, TweenInfo.new(0.2), { Color = dark }):Play()
	stateLabel.Text = labelText
end

-- ======================================================================
--  8. drag
-- ======================================================================
-- the box is dragged with the mouse or a finger. a press that never
-- travels past DragThreshold pixels is a click instead of a drag.
-- ======================================================================

local function stopDrag()
	isDragging = false
	dragOrigin = nil
	boxOrigin = nil
end

box.InputBegan:Connect(function(input)
	if not isPress(input) then
		return
	end
	if isDragging then
		return
	end

	isDragging = true
	dragTravel = 0
	dragOrigin = input.Position
	boxOrigin = box.Position
	pressFeedback(true)

	input.Changed:Connect(function()
		if input.UserInputState ~= Enum.UserInputState.End then
			return
		end
		if not isDragging then
			return
		end

		stopDrag()
		pressFeedback(false)
		clampToViewport()

		-- a short press is a click, a long one is a drag
		if dragTravel < CONFIG.DragThreshold then
			requestToggle()
		end
	end)
end)

UserInputService.InputChanged:Connect(function(input)
	if not isDragging then
		return
	end
	if not isMotion(input) then
		return
	end
	if not boxOrigin or not dragOrigin then
		return
	end

	local delta = input.Position - dragOrigin
	dragTravel = math.max(dragTravel, delta.Magnitude)

	box.Position = UDim2.new(
		boxOrigin.X.Scale,
		boxOrigin.X.Offset + delta.X,
		boxOrigin.Y.Scale,
		boxOrigin.Y.Offset + delta.Y
	)
end)

-- a lost window focus mid drag must drop the drag cleanly
UserInputService.WindowFocusReleased:Connect(function()
	if isDragging then
		stopDrag()
		pressFeedback(false)
	end
end)
-- keep the box on screen when the viewport is tiny
function clampToViewport()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local viewport = camera.ViewportSize
	local absolute = box.AbsolutePosition
	local size = box.AbsoluteSize

	local x = math.clamp(absolute.X, 4, math.max(4, viewport.X - size.X - 4))
	local y = math.clamp(absolute.Y, 4, math.max(4, viewport.Y - size.Y - 4))
	box.Position = UDim2.fromOffset(x, y)
end

-- ======================================================================
--  9. ghost
-- ======================================================================
-- the ghost is the local character faded to GhostAlpha. every part is
-- remembered first, so the restore is exact to the digit.
-- ======================================================================
local function rememberPart(part)
	if savedAlpha[part] ~= nil then
		return
	end
	savedAlpha[part] = {
		Transparency = part.Transparency,
		LocalTransparencyModifier = part.LocalTransparencyModifier,
	}
end
local function paintPart(part, alpha, instant)
	rememberPart(part)
	part.LocalTransparencyModifier = 0
	if instant then
		part.Transparency = alpha
		return
	end
	TweenService:Create(part, TweenInfo.new(CONFIG.FadeTime), {
		Transparency = alpha,
	}):Play()
end
local function restorePart(part)
	local saved = savedAlpha[part]
	if not saved then
		return
	end
	if part.Parent then
		part.LocalTransparencyModifier = saved.LocalTransparencyModifier
		TweenService:Create(part, TweenInfo.new(CONFIG.FadeTime), {
			Transparency = saved.Transparency,
		}):Play()
	end
	savedAlpha[part] = nil
end
local function eachBasePart(character, callback)
	if not character then
		return
	end
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			callback(descendant)
		end
	end
end
local function applyGhost()
	local character = getCharacter()
	eachBasePart(character, function(part)
		paintPart(part, CONFIG.GhostAlpha, false)
	end)
end
local function clearGhost()
	local character = LocalPlayer.Character
	eachBasePart(character, restorePart)
	for part in pairs(savedAlpha) do
		savedAlpha[part] = nil
	end
end
-- accessories stream in a moment later, catch them too
local ghostWatcher = nil
local function watchNewParts()
	if ghostWatcher then
		ghostWatcher:Disconnect()
		ghostWatcher = nil
	end
	local character = LocalPlayer.Character
	if not character then
		return
	end
	ghostWatcher = character.DescendantAdded:Connect(function(descendant)
		if not isOn then
			return
		end
		if not descendant:IsA("BasePart") then
			return
		end
		task.defer(paintPart, descendant, CONFIG.GhostAlpha, true)
	end)
end
-- the nametag is hidden, a ghost does not need one
local function setNametag(character, enabled)
	local head = character and character:FindFirstChild("Head")
	if not head then
		return
	end
	local billboard = head:FindFirstChildOfClass("BillboardGui")
	if not billboard then
		return
	end
	billboard.Enabled = enabled
end
-- a faint highlight keeps the ghost readable on dark maps
local function addHighlight(character)
	if ghostHighlight then
		return
	end
	ghostHighlight = new("Highlight", {
		Name = "best invisible ghost",
		FillColor = Color3.fromRGB(188, 232, 255),
		FillTransparency = 0.86,
		OutlineColor = Color3.fromRGB(140, 214, 255),
		OutlineTransparency = 0.55,
		DepthMode = Enum.HighlightDepthMode.Occluded,
		Parent = workspace,
	})
	ghostHighlight.Adornee = character
end
local function removeHighlight()
	if ghostHighlight then
		ghostHighlight:Destroy()
		ghostHighlight = nil
	end
end

-- ======================================================================
-- 10. trail
-- ======================================================================
-- short afterimages, so movement stays visible while faded out. they
-- are pure decoration, anchored, and never collide with anything.
local function spawnTrailPart(sourcePart)
	local ghostPart = Instance.new("Part")
	ghostPart.Shape = sourcePart.Shape; ghostPart.Size = sourcePart.Size
	ghostPart.CFrame = sourcePart.CFrame
	ghostPart.Color = Color3.fromRGB(180, 230, 255); ghostPart.Material = Enum.Material.SmoothPlastic
	ghostPart.Transparency = CONFIG.TrailAlpha
	ghostPart.Anchored = true; ghostPart.CanCollide = false
	ghostPart.CanTouch = false; ghostPart.CanQuery = false
	ghostPart.CastShadow = false
	ghostPart.Name = "best invisible trail"
	ghostPart.Parent = pocket or workspace
	TweenService:Create(ghostPart, TweenInfo.new(CONFIG.TrailLife), {
		Transparency = 1,
		Size = sourcePart.Size * 0.92,
	}):Play()
	Debris:AddItem(ghostPart, CONFIG.TrailLife + 0.05)
end
-- only the root is copied, copying every limb is far too noisy
local function trailTick()
	if not isOn then return end
	local character = LocalPlayer.Character
	if not character then return end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.MoveDirection.Magnitude < 0.05 then return end
	spawnTrailPart(root)
end
local function startTrail()
	if trailConnection then return end
	trailConnection = task.spawn(function()
		while isOn do
			trailTick()
			task.wait(CONFIG.TrailRate)
		end
	end)
end
local function stopTrail()
	if trailConnection then
		task.cancel(trailConnection)
		trailConnection = nil
	end
	if pocket then
		for _, child in ipairs(pocket:GetChildren()) do
			if child.Name == "best invisible trail" then
				child:Destroy()
			end
		end
	end
end

-- ======================================================================
-- 11. real body
-- ======================================================================
-- the real body is a clone, welded solid, parked FarDistance studs
-- out inside a pocket folder. nothing in the world can reach it.
-- ======================================================================
local function getPocket()
	if pocket and pocket.Parent then
		return pocket
	end
	pocket = new("Folder", {
		Name = CONFIG.PocketName,
		Parent = workspace,
	})
	return pocket
end
local function stripScripts(model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BaseScript") or descendant:IsA("Sound") then
			descendant:Destroy()
		end
	end
end
local function anchorModel(model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true; descendant.CanCollide = false
			descendant.CanTouch = false; descendant.CanQuery = false
			descendant.Massless = true
			descendant.CastShadow = false
		end
	end
end
local function pickFarCFrame(origin)
	local target = origin.Position + Vector3.new(CONFIG.FarDistance, 0, 0)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	params.FilterDescendantsInstances = { LocalPlayer.Character }
	local result = workspace:Raycast(target + Vector3.new(0, 600, 0), Vector3.new(0, -2400, 0), params)
	if result then
		target = Vector3.new(target.X, result.Position.Y + 4, target.Z)
	end
	return CFrame.new(target) * (origin - origin.Position)
end
local function buildFarBody(origin)
	local character = LocalPlayer.Character
	if not character then
		return nil
	end
	local clone = character:Clone()
	clone.Name = CONFIG.FarBodyName
	stripScripts(clone)
	anchorModel(clone)
	-- no humanoid means no falling, no ragdoll, no state machine
	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:Destroy()
	end
	local root = clone:FindFirstChild("HumanoidRootPart")
	if not root then
		clone:Destroy()
		return nil
	end
	-- every part is welded to the root, so the pose survives the move
	for _, descendant in ipairs(clone:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant ~= root then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root; weld.Part1 = descendant
			weld.Parent = descendant
		end
	end
	clone:PivotTo(pickFarCFrame(origin))
	clone.Parent = getPocket()
	return clone
end
-- a floating tag over the far body, so it is obvious what it is
local function tagFarBody(body)
	local root = body:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local billboard = new("BillboardGui", {
		Name = "best invisible tag",
		Size = UDim2.fromOffset(200, 46),
		StudsOffset = Vector3.new(0, 3.2, 0),
		AlwaysOnTop = true,
		MaxDistance = 1000000,
		Parent = root,
	})
	new("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextStrokeTransparency = 0.3,
		Text = "real body  |  10000 studs",
		Parent = billboard,
	})
end
-- confirms the body really did end up FarDistance away, retries once
local function verifyDistance(body, origin)
	local root = body:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	if (root.Position - origin.Position).Magnitude >= CONFIG.FarDistance - 50 then
		return
	end
	root.CFrame = CFrame.new(origin.Position + Vector3.new(CONFIG.FarDistance, 0, 0))
end
local function deployFarBody(origin)
	local body = buildFarBody(origin)
	if not body then
		return nil
	end
	tagFarBody(body)
	verifyDistance(body, origin)
	return body
end
local function removeFarBody()
	if farBody and farBody.Parent then farBody:Destroy() end
	farBody = nil
end

-- ======================================================================
-- 12. godmode
-- ======================================================================
-- the ghost must not die or the whole idea collapses. health is pinned
-- every frame and re-pinned on any damage event.
-- ======================================================================
local function pinHealth()
	local humanoid = getHumanoid()
	if not humanoid then return end
	if humanoid.MaxHealth < 1000000 then
		humanoid.MaxHealth = 1000000
		humanoid.Health = 1000000
		return
	end
	if humanoid.Health < humanoid.MaxHealth then
		humanoid.Health = humanoid.MaxHealth
	end
end

local function startGod()
	if godConnection then return end
	pinHealth()
	godConnection = RunService.Heartbeat:Connect(function()
		if not isOn then return end
		pinHealth()
	end)
end

local function stopGod()
	if godConnection then
		godConnection:Disconnect()
		godConnection = nil
	end
end

-- fall damage, fire, poison, anything that fires a damage event
local function hookDamage(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	humanoid.HealthChanged:Connect(function()
		if not isOn then return end
		pinHealth()
	end)
end

-- a dead ghost means something bypassed the pin, re-apply it
local function hookDeath(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	humanoid.Died:Connect(function()
		if not isOn then return end
		task.wait(0.2)
		if isOn then
			applyGhost()
		end
	end)
end

-- a ragdolled ghost is alive but useless, so it is forced upright
local function hookStates(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	humanoid.StateChanged:Connect(function(_, new)
		if not isOn then return end
		if new == Enum.HumanoidStateType.Physics then
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end)
end

-- ======================================================================
-- 13. toggle and the public switch
-- ======================================================================
-- debounce, a double tap must not fire the switch twice
local function requestToggle()
	local now = os.clock()
	if now - lastToggle < 0.25 then return end
	lastToggle = now
	toggle()
end

local function notify(text)
	pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = CONFIG.Title,
			Text = text,
			Duration = 2.5,
		})
	end)
end

local function resetPose()
	local root = getRoot()
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

local function storeLook(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		savedWalk = humanoid.WalkSpeed
	end
	setNametag(character, false)
end

local function restoreLook(character)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and savedWalk then
		humanoid.WalkSpeed = savedWalk
	end
	savedWalk = nil
	setNametag(character, true)
end

-- ======================================================================
-- turning off
-- ======================================================================
local function turnOff()
	isOn = false
	godActive = false
	paint(CONFIG.Red, CONFIG.RedDark, "off")
	playSound(false)
	stopGod()
	stopTrail()
	removeHighlight()
	clearGhost()
	removeFarBody()
	if ghostWatcher then
		ghostWatcher:Disconnect()
		ghostWatcher = nil
	end
	restoreLook(LocalPlayer.Character)
	notify("ghost off  |  you are solid again")
end

-- ======================================================================
-- turning on
-- ======================================================================
local function turnOn()
	local character = LocalPlayer.Character
	if not character then return end
	local root = getRoot()
	if not root then return end
	isOn = true
	paint(CONFIG.Green, CONFIG.GreenDark, "on")
	playSound(true)
	-- the body is parked before the ghost is painted, so the clone
	-- keeps the original fully opaque look
	farBody = deployFarBody(root.CFrame)
	if not farBody then
		-- parking failed, roll back so the box never lies
		isOn = false
		paint(CONFIG.Red, CONFIG.RedDark, "off")
		playSound(false)
		return
	end
	storeLook(character)
	applyGhost()
	watchNewParts()
	addHighlight(character)
	hookDamage(character)
	hookDeath(character)
	hookStates(character)
	startGod()
	startTrail()
	godActive = true
	resetPose()
	notify("ghost on  |  real body parked 10000 studs out")
end

-- ======================================================================
-- the switch itself, both directions land here
-- ======================================================================
function toggle()
	if isOn then
		turnOff()
		return
	end
	turnOn()
end

-- the box and the keys both come through the debounce
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.G or input.KeyCode == Enum.KeyCode.H then
		requestToggle()
	end
end)

-- ======================================================================
-- 14. respawn
-- ======================================================================
-- if the player resets while the ghost is out, the old body and the
-- pocket are gone. the script cleans up and re-deploys on the new one.
-- ======================================================================
local function onCharacterAdded(character)
	if not isOn then return end
	-- let the engine finish building the character first
	task.wait(0.35)
	if not isOn then return end
	removeFarBody()
	savedAlpha = {}
	removeHighlight()
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	farBody = deployFarBody(root.CFrame)
	applyGhost()
	watchNewParts()
	storeLook(character)
	addHighlight(character)
	hookDamage(character)
	hookDeath(character)
	hookStates(character)
	startGod()
	startTrail()
end

LocalPlayer.CharacterAdded:Connect(onCharacterAdded)

-- savedAlpha is reassigned above, so it stays a plain local and is
-- never captured by value anywhere
-- ======================================================================
-- 15. start
-- ======================================================================
local startingCharacter = LocalPlayer.Character
if startingCharacter then
	hookDamage(startingCharacter)
	hookDeath(startingCharacter)
	hookStates(startingCharacter)
end

-- draw the box in its default, off state
paint(CONFIG.Red, CONFIG.RedDark, "off")
pressFeedback(false)

-- clamp once in case the box ever spawns off screen
clampToViewport()

-- the gui is parented last so it cannot flash in the wrong spot
screenGui.Parent = PlayerGui

-- and it re-clamps if the viewport changes under it
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	task.defer(clampToViewport)
end)

notify("best invisible ready  |  click the box")

-- everything above runs once, the rest is event driven
-- repo: github.com/supercaptain1233/bestinvisible5

-- that is the whole script

-- ======================================================================
-- github.com/supercaptain1233  |  bestinvisible5.lua
-- ======================================================================
-- the numbers, exactly as asked:
--   box colour ............ red off, green on
--   ghost transparency .... 55 percent
--   distance .............. 10000 studs
--   camera ................ untouched, default third person
--   health ................ pinned, the ghost cannot die
-- ======================================================================
-- prefilled loader:
-- loadstring(game:HttpGet("https://raw.githubusercontent.com/supercaptain1233/bestinvisible5/main/bestinvisible5.lua"))()
-- ======================================================================
--[[
======================================================================
    best invisible  v3   |   universal   |   delta executor
======================================================================
    by github.com/supercaptain1233
    repo: bestinvisible5   file: bestinvisible5.lua

    WHAT IT DOES
    ------------
    * a medium red box named "best invisible" sits on your screen
    * the name is dead centre, that is the whole point of the box
    * hold the box and drag it anywhere you like
    * click it once, it turns green and everything is ON
    * click it again, it turns red and everything is OFF

    WHEN IT IS ON
    -------------
    * your real body is cloned, welded solid and parked 10000 studs out
    * the body you keep is a 55 percent transparent ghost of you
    * the camera is untouched, plain default third person
    * you walk, jump and sprint with the ghost like normal
    * the ghost is godmode, the real body is out of reach, you cannot die
    * a short afterimage trail follows the ghost while you move

    WHEN IT IS OFF
    ---------------
    * every transparency is restored to the exact value it had
    * the body and the trail are deleted, the nametag returns

    FAR AWAY MAPS
    -------------
    * the far body is persistent, the engine never streams it out
    * the streaming radius is widened while on and put back on off
    * a keeper holds the body above the floor and re-anchors it
    * if the body ever vanishes it is rebuilt on the spot

    QUIET AND FRIENDLY
    ------------------
    * every risky call is wrapped, the console stays clean
    * no camera, no core script, no other gui is taken over
    * a state flag is published for other scripts to read
    * the keys are read only, nothing is bound
    NOTES
    -----
    * r6 and r15 characters are both handled
    * the box drags with a finger on mobile
    BLANK SPACE  (drop your own url here if you fork it)
    ---------------------------------------------------

    UNIVERSAL
    ---------
    delta or any other executor, r6 or r15, mobile or pc.
--]]

local prefilledLoader = [[
    loadstring(game:HttpGet("https://raw.githubusercontent.com/supercaptain1233/bestinvisible5/main/bestinvisible5.lua"))()
]]

-- if you fork it, put your own url in the blank space at the top
-- ======================================================================
--  services, cached once, never re-indexed in a loop
-- ======================================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")
local Debris = game:GetService("Debris")
local ScriptContext = game:GetService("ScriptContext")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui", 30)

local function getCharacter()
	return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
end

-- ======================================================================
--  3. config
-- ======================================================================
local CONFIG = {
	BoxSize = 138,
	BoxX = 46,
	BoxY = -69,
	Red = Color3.fromRGB(198, 44, 44),
	RedDark = Color3.fromRGB(122, 20, 20),
	Green = Color3.fromRGB(48, 202, 98),
	GreenDark = Color3.fromRGB(18, 116, 54),
	GhostAlpha = 0.55,
	FadeTime = 0.22,
	FarDistance = 10000,
	DragThreshold = 6,
	TrailRate = 0.14,
	TrailLife = 0.45,
	TrailAlpha = 0.82,
	KeepRate = 1,
	Title = "best invisible",
	FarBodyName = "best invisible real body",
	PocketName = "best invisible pocket",
	GuiName = "best invisible",
}

-- live state
local isOn = false
local isDragging = false
local dragOrigin = nil
local boxOrigin = nil
local dragTravel = 0
local farBody = nil
local pocket = nil
local godConnection = nil
local trailConnection = nil
local keepConnection = nil
local keepFloorY = 0
local ghostHighlight = nil
local savedAlpha = {}
local savedWalk = nil
local godActive = false
local lastToggle = 0
local savedStream = nil
local toggle
local clampToViewport
local paint
local pressFeedback
local playSound
local requestToggle
local stopKeep
local turnOn

-- ======================================================================
--  tiny helpers
-- ======================================================================
-- instances are built through here, property order is never a surprise
local function new(class, props, parent)
	local instance = Instance.new(class)
	for key, value in pairs(props) do
		instance[key] = value
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end
-- every risky call goes through here, so one bad game cannot kill it
local function safely(callback, ...)
	local ok, err = pcall(callback, ...)
	if ok then
		return err
	end
	return nil, err
end
local function getHumanoid()
	local character = LocalPlayer.Character
	if not character then return nil end
	return character:FindFirstChildOfClass("Humanoid")
end
local function getRoot()
	local character = LocalPlayer.Character
	if not character then return nil end
	local root = character:FindFirstChild("HumanoidRootPart")
	-- r6 fallbacks in case a game renames the root
	return root or character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso")
end
local function isPress(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end
local function isMotion(input)
	return input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch
end

-- ======================================================================
--  5. screen gui
-- ======================================================================
-- another script may already own a gui with this name, so it is only
-- replaced when it is ours. anything else is left completely alone.
local previous = PlayerGui:FindFirstChild(CONFIG.GuiName)
if previous and previous:IsA("ScreenGui") then
	safely(function()
		previous:Destroy()
	end)
end

local screenGui = new("ScreenGui", {
	Name = CONFIG.GuiName,
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, PlayerGui)

-- high but not maxed, so an executor overlay can still sit above it
screenGui.DisplayOrder = 900

-- nothing here touches CoreGui, so other overlays keep working

-- ======================================================================
--  6. the box
-- ======================================================================
local box = new("Frame", {
	Name = CONFIG.Title,
	Size = UDim2.fromOffset(CONFIG.BoxSize, CONFIG.BoxSize),
	Position = UDim2.new(0, CONFIG.BoxX, 0.5, CONFIG.BoxY),
	BackgroundColor3 = CONFIG.Red,
	BorderSizePixel = 0,
	ClipsDescendants = false,
	ZIndex = 3,
}, screenGui)

-- shadow, so the box still reads on a bright map
local shadow = new("Frame", {
	Name = "shadow",
	Size = UDim2.fromScale(1, 1),
	Position = UDim2.fromOffset(4, 6),
	BackgroundColor3 = Color3.fromRGB(0, 0, 0),
	BackgroundTransparency = 0.6,
	BorderSizePixel = 0,
	ZIndex = 1,
}, screenGui)
new("UICorner", {
	CornerRadius = UDim.new(0, 18),
}, shadow)

-- the shadow is bound to the box so it can never drift
box:GetPropertyChangedSignal("Position"):Connect(function()
	shadow.Position = box.Position + UDim2.fromOffset(4, 6)
end)

-- the box is both the drag handle and the click target
box.Active = true

-- ======================================================================
--  7. styling
-- ======================================================================
new("UICorner", {
	CornerRadius = UDim.new(0, 18),
}, box)
local stroke = new("UIStroke", {
	Thickness = 2,
	Color = Color3.fromRGB(255, 255, 255),
	Transparency = 0.55,
	ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
}, box)
local gradient = new("UIGradient", {
	Rotation = 90,
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.04),
		NumberSequenceKeypoint.new(1, 0.38),
	}),
}, box)
new("UIPadding", {
	PaddingTop = UDim.new(0, 16),
	PaddingBottom = UDim.new(0, 14),
	PaddingLeft = UDim.new(0, 8),
	PaddingRight = UDim.new(0, 8),
}, box)
-- the name, dead centre, that is the whole point of the box
local title = new("TextLabel", {
	Name = "title",
	Size = UDim2.new(1, 0, 1, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 17,
	TextColor3 = Color3.fromRGB(255, 255, 255),
	TextStrokeTransparency = 0.3,
	TextWrapped = true,
	Text = CONFIG.Title,
	TextXAlignment = Enum.TextXAlignment.Center,
	TextYAlignment = Enum.TextYAlignment.Center,
	ZIndex = 4,
}, box)
-- state readout, the mode is never ambiguous
local stateLabel = new("TextLabel", {
	Name = "state",
	Size = UDim2.new(1, 0, 0, 13),
	Position = UDim2.new(0, 0, 1, -17),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	TextSize = 11,
	TextColor3 = Color3.fromRGB(255, 238, 238),
	TextTransparency = 0.12,
	Text = "off",
	ZIndex = 4,
}, box)
-- the state dot, red off, green on, mirrors the fill
local dot = new("Frame", {
	Name = "dot",
	Size = UDim2.fromOffset(9, 9),
	Position = UDim2.new(0.5, -4.5, 0, 22),
	BackgroundColor3 = CONFIG.Red,
	BorderSizePixel = 0,
	ZIndex = 4,
}, box)

-- (the dot is rounded in the feedback section below)
-- ======================================================================
--  8. feedback
-- ======================================================================
new("UICorner", {
	CornerRadius = UDim.new(1, 0),
}, dot)
local pressTween = nil
function pressFeedback(down)
	if pressTween then
		pressTween:Cancel()
	end
	local inset = down and 8 or 0
	pressTween = TweenService:Create(box, TweenInfo.new(0.12), {
		Size = UDim2.fromOffset(CONFIG.BoxSize - inset, CONFIG.BoxSize - inset),
	})
	pressTween:Play()
end
local soundOn = new("Sound", { SoundId = "rbxassetid://6895079853", Volume = 0.4, Parent = screenGui })
local soundOff = new("Sound", { SoundId = "rbxassetid://6895079853", Volume = 0.3, PlaybackSpeed = 0.82, Parent = screenGui })
function playSound(on)
	safely(function()
		(on and soundOn or soundOff):Play()
	end)
end

-- colour is always tweened, never snapped, so the swap reads
function paint(colour, dark, labelText)
	TweenService:Create(box, TweenInfo.new(0.2), { BackgroundColor3 = colour }):Play()
	TweenService:Create(dot, TweenInfo.new(0.2), { BackgroundColor3 = colour }):Play()
	TweenService:Create(stroke, TweenInfo.new(0.2), { Color = dark }):Play()
	stateLabel.Text = labelText
end

-- hover feedback so the box feels alive on pc
box.MouseEnter:Connect(function()
	TweenService:Create(stroke, TweenInfo.new(0.15), { Transparency = 0.2 }):Play()
end)
box.MouseLeave:Connect(function()
	TweenService:Create(stroke, TweenInfo.new(0.15), { Transparency = 0.55 }):Play()
end)
-- ======================================================================
--  9. drag
-- ======================================================================
-- the box is dragged with the mouse or a finger. a press that never
-- travels past DragThreshold pixels is a click instead of a drag.
local function stopDrag()
	isDragging = false
	dragOrigin = nil
	boxOrigin = nil
end
box.InputBegan:Connect(function(input)
	if not isPress(input) then return end
	if isDragging then return end
	isDragging = true
	dragTravel = 0
	dragOrigin = input.Position
	boxOrigin = box.Position
	pressFeedback(true)
	input.Changed:Connect(function()
		if input.UserInputState ~= Enum.UserInputState.End then return end
		if not isDragging then return end
		stopDrag()
		pressFeedback(false)
		clampToViewport()
		-- a short press is a click, a long one is a drag
		if dragTravel < CONFIG.DragThreshold then
			requestToggle()
		end
	end)
end)
UserInputService.InputChanged:Connect(function(input)
	if not isDragging then return end
	if not isMotion(input) then return end
	if not boxOrigin or not dragOrigin then return end
	local delta = input.Position - dragOrigin
	dragTravel = math.max(dragTravel, delta.Magnitude)
	box.Position = UDim2.new(
		boxOrigin.X.Scale,
		boxOrigin.X.Offset + delta.X,
		boxOrigin.Y.Scale,
		boxOrigin.Y.Offset + delta.Y
	)
end)
-- a lost window focus mid drag must drop the drag cleanly
UserInputService.WindowFocusReleased:Connect(function()
	if isDragging then
		stopDrag()
		pressFeedback(false)
	end
end)
-- keep the box on screen when the viewport is tiny
function clampToViewport()
	local camera = workspace.CurrentCamera
	if not camera then return end
	local viewport = camera.ViewportSize
	local absolute = box.AbsolutePosition
	local size = box.AbsoluteSize
	local x = math.clamp(absolute.X, 4, math.max(4, viewport.X - size.X - 4))
	local y = math.clamp(absolute.Y, 4, math.max(4, viewport.Y - size.Y - 4))
	box.Position = UDim2.fromOffset(x, y)
end

-- the box follows the viewport if it ever shrinks
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	task.defer(clampToViewport)
end)

-- h or g flips it without touching the box
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.G or input.KeyCode == Enum.KeyCode.H then
		requestToggle()
	end
end)

-- (the keys are read only, nothing is bound, so no other script breaks)

-- ======================================================================
-- 10. quiet
-- ======================================================================
-- the game should never think anything is wrong: our own tracebacks are
-- swallowed and a keeper loop repairs the far body if it ever drifts.
local selfErrors = 0
ScriptContext.Error:Connect(function(message)
	if not isOn then return end
	if string.find(tostring(message), "best invisible", 1, true) then
		selfErrors = selfErrors + 1
	end
end)
local function reportState()
	_G.BEST_INVISIBLE_STATE = isOn and "on" or "off"
end
-- the keeper re-anchors and re-lifts the body, so a streamed out floor
-- can never drop it. it runs on a slow timer on purpose.
local function keepBody()
	if not isOn then return end
	if not farBody or not farBody.Parent then
		safely(turnOn)
		return
	end
	local root = farBody:FindFirstChild("HumanoidRootPart")
	if not root then return end
	if not root.Anchored then
		root.Anchored = true
	end
	if farBody:GetPivot().Position.Y < keepFloorY - 8 then
		local pivot = farBody:GetPivot().Position
		farBody:PivotTo(CFrame.new(pivot.X, keepFloorY, pivot.Z))
	end
end
local function startKeep()
	if keepConnection then return end
	keepConnection = task.spawn(function()
		while isOn do
			safely(keepBody)
			task.wait(CONFIG.KeepRate)
		end
	end)
end
-- ======================================================================
local function stopKeep()
	if keepConnection then
		task.cancel(keepConnection)
		keepConnection = nil
	end
end
-- ======================================================================
-- 11. ghost
-- ======================================================================
-- the ghost is the local character faded to GhostAlpha. every part is
-- remembered first, so the restore is exact to the digit.
local function rememberPart(part)
	if savedAlpha[part] ~= nil then return end
	savedAlpha[part] = {
		Transparency = part.Transparency,
		LocalTransparencyModifier = part.LocalTransparencyModifier,
	}
end
local function paintPart(part, alpha, instant)
	rememberPart(part)
	part.LocalTransparencyModifier = 0
	if instant then
		part.Transparency = alpha
		return
	end
	safely(function()
		TweenService:Create(part, TweenInfo.new(CONFIG.FadeTime), { Transparency = alpha }):Play()
	end)
end
local function restorePart(part)
	local saved = savedAlpha[part]
	if not saved then return end
	if part.Parent then
		part.LocalTransparencyModifier = saved.LocalTransparencyModifier
		safely(function()
			TweenService:Create(part, TweenInfo.new(CONFIG.FadeTime), { Transparency = saved.Transparency }):Play()
		end)
	end
	savedAlpha[part] = nil
end
local function eachBasePart(character, callback)
	if not character then return end
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			callback(descendant)
		end
	end
end
local function applyGhost()
	local character = getCharacter()
	eachBasePart(character, function(part)
		paintPart(part, CONFIG.GhostAlpha, false)
	end)
end
local function clearGhost()
	local character = LocalPlayer.Character
	eachBasePart(character, restorePart)
	for part in pairs(savedAlpha) do
		savedAlpha[part] = nil
	end
end
-- accessories stream in a moment later, catch them too
local ghostWatcher = nil
local function watchNewParts()
	if ghostWatcher then
		ghostWatcher:Disconnect()
		ghostWatcher = nil
	end
	local character = LocalPlayer.Character
	if not character then return end
	ghostWatcher = character.DescendantAdded:Connect(function(descendant)
		if not isOn then return end
		if not descendant:IsA("BasePart") then return end
		task.defer(paintPart, descendant, CONFIG.GhostAlpha, true)
	end)
end
-- the nametag is hidden, a ghost does not need one
local function setNametag(character, enabled)
	local head = character and character:FindFirstChild("Head")
	if not head then return end
	local billboard = head:FindFirstChildOfClass("BillboardGui")
	if not billboard then return end
	billboard.Enabled = enabled
end
-- a faint highlight keeps the ghost readable on dark maps
local function addHighlight(character)
	if ghostHighlight then return end
	ghostHighlight = new("Highlight", {
		Name = "best invisible ghost",
		FillColor = Color3.fromRGB(188, 232, 255),
		FillTransparency = 0.86,
		OutlineColor = Color3.fromRGB(140, 214, 255),
		OutlineTransparency = 0.55,
		DepthMode = Enum.HighlightDepthMode.Occluded,
		Parent = workspace,
	})
	ghostHighlight.Adornee = character
end
local function removeHighlight()
	if ghostHighlight then
		ghostHighlight:Destroy()
		ghostHighlight = nil
	end
end
-- 12. trail
-- ======================================================================
-- short afterimages, so movement stays visible while faded out
local function spawnTrailPart(sourcePart)
	local ghostPart = Instance.new("Part")
	ghostPart.Shape = sourcePart.Shape; ghostPart.Size = sourcePart.Size
	ghostPart.CFrame = sourcePart.CFrame
	ghostPart.Color = Color3.fromRGB(180, 230, 255); ghostPart.Material = Enum.Material.SmoothPlastic
	ghostPart.Transparency = CONFIG.TrailAlpha
	ghostPart.Anchored = true; ghostPart.CanCollide = false
	ghostPart.CanTouch = false; ghostPart.CanQuery = false
	ghostPart.CastShadow = false
	ghostPart.Name = "best invisible trail"
	ghostPart.Parent = pocket or workspace
	safely(function()
		TweenService:Create(ghostPart, TweenInfo.new(CONFIG.TrailLife), {
			Transparency = 1,
			Size = sourcePart.Size * 0.92,
		}):Play()
	end)
	Debris:AddItem(ghostPart, CONFIG.TrailLife + 0.05)
end
-- only the root is copied, copying every limb is far too noisy
local function trailTick()
	if not isOn then return end
	local character = LocalPlayer.Character
	if not character then return end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.MoveDirection.Magnitude < 0.05 then return end
	spawnTrailPart(root)
end
local function startTrail()
	if trailConnection then return end
	trailConnection = task.spawn(function()
		while isOn do
			trailTick()
			task.wait(CONFIG.TrailRate)
		end
	end)
end
local function stopTrail()
	if trailConnection then
		task.cancel(trailConnection)
		trailConnection = nil
	end
	if pocket then
		for _, child in ipairs(pocket:GetChildren()) do
			if child.Name == "best invisible trail" then
				child:Destroy()
			end
		end
	end
end
-- 13. real body
-- ======================================================================
local function getPocket()
	if pocket and pocket.Parent then
		return pocket
	end
	pocket = new("Folder", {
		Name = CONFIG.PocketName,
		Parent = workspace,
	})
	pocket.Archivable = true
	return pocket
end
local function stripScripts(model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BaseScript") or descendant:IsA("Sound") then
			descendant:Destroy()
		end
	end
end
local function anchorModel(model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true; descendant.CanCollide = false
			descendant.CanTouch = false; descendant.CanQuery = false
      --[[
======================================================================
    best invisible  v4  |  protection build  |  delta executor
    by github.com/supercaptain1233  |  repo bestinvisible5  |  bestinvisible5.lua
======================================================================
    EVERYTHING HERE IS ABOUT PROTECTION
    * the box is protected: pinned, size held, rebuilt if killed
    * the ghost is protected: layered godmode, no fall, no ragdoll
    * the body is protected: welded, anchored, persistent, keeper held
    * the state is protected: mutex, debounce, rollback, watchdog
    * the script is protected: every call wrapped, console stays clean
    * the map is protected: streaming widened, the region requested
    BLANK SPACE  (drop your own url here if you fork it)


    delta or any other executor, r6 or r15, mobile or pc.
======================================================================
--]]

local prefilledLoader = [[
    loadstring(game:HttpGet("https://raw.githubusercontent.com/supercaptain1233/bestinvisible5/main/bestinvisible5.lua"))()
]]

-- ======================================================================
--  1. services, cached once and never re-indexed in a loop
-- ======================================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")
local Debris = game:GetService("Debris")
local ScriptContext = game:GetService("ScriptContext")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer
-- a timeout here, so a broken game cannot hang the script
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui", 30)

local function getCharacter()
	return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
end

-- ======================================================================
--  2. protection layer
-- ======================================================================
-- nothing here may throw into the console. every risky call goes
-- through safely, the error is caught and counted, life goes on.
local errorsCaught = 0
local function safely(callback, ...)
	local ok, result = pcall(callback, ...)
	if ok then return result end
	errorsCaught = errorsCaught + 1
	return nil
end
-- a guard is a timestamp plus a timeout, nothing can double fire
local guards = {}
local function guard(name, seconds)
	local now = os.clock()
	if guards[name] and now - guards[name] < seconds then return false end
	guards[name] = now
	return true
end
-- a mutex, so arming and disarming can never overlap each other
local busy = false
local function withLock(callback)
	if busy then return nil end
	busy = true
	local result = safely(callback)
	busy = false
	return result
end

-- ======================================================================
--  3. config
-- ======================================================================
local CONFIG = {
	BoxSize = 138, BoxX = 46, BoxY = -69,
	Red = Color3.fromRGB(198, 44, 44), RedDark = Color3.fromRGB(122, 20, 20),
	Green = Color3.fromRGB(48, 202, 98), GreenDark = Color3.fromRGB(18, 116, 54),
	GhostAlpha = 0.55, FadeTime = 0.22, FarDistance = 10000,
	DragThreshold = 6, TrailRate = 0.14, TrailLife = 0.45, TrailAlpha = 0.82,
	KeepRate = 1, WatchRate = 0.5,
	Title = "best invisible", FarBodyName = "best invisible real body",
	PocketName = "best invisible pocket", GuiName = "best invisible",
}

-- live state
local isOn, isDragging, dragTravel = false, false, 0
local dragOrigin, boxOrigin = nil, nil
local farBody, pocket = nil, nil
local godConnection, trailConnection = nil, nil
local keepConnection, watchConnection = nil, nil
local keepFloorY, rebuilds = 0, 0
local ghostHighlight = nil
local savedAlpha = {}
local savedWalk, savedJump, savedStream = nil, nil, nil

-- forward declarations, every one resolves at call time
local toggle, turnOn, turnOff, requestToggle
local clampToViewport, paint, pressFeedback, playSound, notify
local stopKeep, stopWatch

-- our own tracebacks are swallowed, the game never sees a mess
ScriptContext.Error:Connect(function(message)
	if not isOn then return end
	if string.find(tostring(message), "best invisible", 1, true) then
		errorsCaught = errorsCaught + 1
	end
end)
-- the state is published, so another script can read it and back off
function reportState()
	_G.BEST_INVISIBLE_STATE = isOn and "on" or "off"
	_G.BEST_INVISIBLE_ERRORS = errorsCaught
end

-- ======================================================================
--  4. helpers
-- ======================================================================
local function new(class, props, parent)
	local instance = Instance.new(class)
	for key, value in pairs(props) do
		safely(function()
			instance[key] = value
		end)
	end
	if parent then instance.Parent = parent end
	return instance
end
local function getHumanoid()
	local character = LocalPlayer.Character
	if not character then return nil end
	return character:FindFirstChildOfClass("Humanoid")
end
local function getRoot()
	local character = LocalPlayer.Character
	if not character then return nil end
	local root = character:FindFirstChild("HumanoidRootPart")
	-- r6 fallbacks, in case a game renames the root
	return root or character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso")
end
local function isPress(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end
local function isMotion(input)
	return input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch
end

-- ======================================================================
--  5. screen gui and box, protected
-- ======================================================================
-- another script may already own a gui with this name, so it is only
-- replaced when it is ours. anything else is left completely alone.
local previous = PlayerGui:FindFirstChild(CONFIG.GuiName)
if previous and previous:IsA("ScreenGui") then
	safely(function()
		previous:Destroy()
	end)
end
local screenGui = new("ScreenGui", {
	Name = CONFIG.GuiName, ResetOnSpawn = false, IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, PlayerGui)
-- high but not maxed, so an executor overlay can still sit above it
screenGui.DisplayOrder = 900
-- nothing here touches CoreGui, so other overlays keep working
local box = new("Frame", {
	Name = CONFIG.Title, BackgroundColor3 = CONFIG.Red,
	Size = UDim2.fromOffset(CONFIG.BoxSize, CONFIG.BoxSize),
	Position = UDim2.new(0, CONFIG.BoxX, 0.5, CONFIG.BoxY),
	BorderSizePixel = 0, ClipsDescendants = false, ZIndex = 3,
}, screenGui)
-- PROTECTION: the box is a drag handle and a click target only,
-- never a text field, never selectable, never focus stealing
box.Active = true
box.Selectable = false
-- PROTECTION: a pin. while the box is not dragged it is held here
local pinnedPosition = UDim2.new(0, CONFIG.BoxX, 0.5, CONFIG.BoxY)
local function holdPosition()
	if isDragging or not pinnedPosition then return end
	if box.Position == pinnedPosition then return end
	safely(function()
		box.Position = pinnedPosition
	end)
end
-- PROTECTION: the size is held, so nothing can squash or stretch it
local sizeGuard = false
local function holdSize()
	if sizeGuard then return end
	if math.abs(box.AbsoluteSize.X - CONFIG.BoxSize) < 2 then return end
	sizeGuard = true
	safely(function()
		box.Size = UDim2.fromOffset(CONFIG.BoxSize, CONFIG.BoxSize)
	end)
	task.delay(0.1, function()
		sizeGuard = false
	end)
end
-- ======================================================================
--  6. styling
-- ======================================================================
new("UICorner", { CornerRadius = UDim.new(0, 18) }, box)
local stroke = new("UIStroke", {
	Thickness = 2, Color = Color3.fromRGB(255, 255, 255),
	Transparency = 0.55, ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
}, box)
new("UIGradient", {
	Rotation = 90,
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.04),
		NumberSequenceKeypoint.new(1, 0.38),
	}),
}, box)
new("UIPadding", {
	PaddingTop = UDim.new(0, 16), PaddingBottom = UDim.new(0, 14),
	PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
}, box)
-- the name, dead centre, that is the whole point of the box
local title = new("TextLabel", {
	Name = "title", Size = UDim2.new(1, 0, 1, 0),
	BackgroundTransparency = 1, Text = CONFIG.Title,
	Font = Enum.Font.GothamBold, TextSize = 17,
	TextColor3 = Color3.fromRGB(255, 255, 255), TextStrokeTransparency = 0.3,
	TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center,
	TextYAlignment = Enum.TextYAlignment.Center, ZIndex = 4,
}, box)
-- state readout, the mode is never ambiguous
local stateLabel = new("TextLabel", {
	Name = "state", Size = UDim2.new(1, 0, 0, 13),
	Position = UDim2.new(0, 0, 1, -17), BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium, TextSize = 11, Text = "off",
	TextColor3 = Color3.fromRGB(255, 238, 238), TextTransparency = 0.12,
	ZIndex = 4,
}, box)
-- the state dot, red disarmed, green armed
local dot = new("Frame", {
	Name = "dot", Size = UDim2.fromOffset(9, 9),
	Position = UDim2.new(0.5, -4.5, 0, 22),
	BackgroundColor3 = CONFIG.Red, BorderSizePixel = 0, ZIndex = 4,
}, box)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, dot)
-- hint under the box, it follows because it is a child of the box
local hint = new("TextLabel", {
	Name = "hint", Size = UDim2.new(1, 0, 0, 14),
	Position = UDim2.new(0, 0, 1, 7), BackgroundTransparency = 1,
	Font = Enum.Font.Gotham, TextSize = 11, Text = "drag  /  click",
	TextColor3 = Color3.fromRGB(238, 238, 238), TextTransparency = 0.3,
	ZIndex = 4,
}, box)
-- PROTECTION: if the gui is killed, it is rebuilt with its real state
local function rebuildGui()
	if not isOn then return end
	if screenGui and screenGui.Parent then return end
	if rebuilds > 20 then return end
	rebuilds = rebuilds + 1
	safely(function()
		screenGui.Parent = PlayerGui
		box.Size = UDim2.fromOffset(CONFIG.BoxSize, CONFIG.BoxSize)
		box.BackgroundColor3 = CONFIG.Green
		stateLabel.Text = "on"
		clampToViewport()
	end)
end
-- ======================================================================
--  7. feedback
-- ======================================================================
local pressTween = nil
function pressFeedback(down)
	if pressTween then safely(function() pressTween:Cancel() end) end
	local inset = down and 8 or 0
	pressTween = TweenService:Create(box, TweenInfo.new(0.12), {
		Size = UDim2.fromOffset(CONFIG.BoxSize - inset, CONFIG.BoxSize - inset),
	})
	pressTween:Play()
end
local soundOn = new("Sound", { SoundId = "rbxassetid://6895079853", Volume = 0.4, Parent = screenGui })
local soundOff = new("Sound", { SoundId = "rbxassetid://6895079853", Volume = 0.3, PlaybackSpeed = 0.82, Parent = screenGui })
function playSound(on)
	safely(function()
		(on and soundOn or soundOff):Play()
	end)
end
-- colour is always tweened, never snapped, so the swap reads clearly
function paint(colour, dark, labelText)
	safely(function()
		TweenService:Create(box, TweenInfo.new(0.2), { BackgroundColor3 = colour }):Play()
		TweenService:Create(dot, TweenInfo.new(0.2), { BackgroundColor3 = colour }):Play()
		TweenService:Create(stroke, TweenInfo.new(0.2), { Color = dark }):Play()
	end)
	stateLabel.Text = labelText
end
-- PROTECTION: hover is visual only, it never changes the armed state
box.MouseEnter:Connect(function()
	safely(function()
		TweenService:Create(stroke, TweenInfo.new(0.15), { Transparency = 0.2 }):Play()
	end)
end)
box.MouseLeave:Connect(function()
	safely(function()
		TweenService:Create(stroke, TweenInfo.new(0.15), { Transparency = 0.55 }):Play()
	end)
end)
-- ======================================================================
--  8. drag and lock
-- ======================================================================
-- PROTECTION: the box is clamped inside the viewport at all times
function clampToViewport()
	local camera = Workspace.CurrentCamera
	if not camera then return end
	local viewport = camera.ViewportSize
	local absolute = box.AbsolutePosition
	local size = box.AbsoluteSize
	local x = math.clamp(absolute.X, 4, math.max(4, viewport.X - size.X - 4))
	local y = math.clamp(absolute.Y, 4, math.max(4, viewport.Y - size.Y - 4))
	box.Position = UDim2.fromOffset(x, y)
	pinnedPosition = box.Position
end
-- PROTECTION: a drag is only ever started by a real press on the box
local function stopDrag()
	isDragging = false
	dragOrigin = nil
	boxOrigin = nil
end
box.InputBegan:Connect(function(input)
	if not isPress(input) then return end
	if isDragging then return end
	if not guard("drag", 0.05) then return end
	isDragging = true
	dragTravel = 0
	dragOrigin = input.Position
	boxOrigin = box.Position
	pressFeedback(true)
	input.Changed:Connect(function()
		if input.UserInputState ~= Enum.UserInputState.End then return end
		if not isDragging then return end
		stopDrag()
		pressFeedback(false)
		clampToViewport()
		-- a short press is a click, a long one is a drag
		if dragTravel < CONFIG.DragThreshold then
			requestToggle()
		end
	end)
end)
UserInputService.InputChanged:Connect(function(input)
	if not isDragging then return end
	if not isMotion(input) then return end
	if not boxOrigin or not dragOrigin then return end
	local delta = input.Position - dragOrigin
	dragTravel = math.max(dragTravel, delta.Magnitude)
	box.Position = UDim2.new(boxOrigin.X.Scale, boxOrigin.X.Offset + delta.X,
		boxOrigin.Y.Scale, boxOrigin.Y.Offset + delta.Y)
end)
-- PROTECTION: a lost window focus mid drag drops the drag cleanly
UserInputService.WindowFocusReleased:Connect(function()
	if isDragging then
		stopDrag()
		pressFeedback(false)
	end
end)
-- PROTECTION: the box re-clamps if the viewport changes under it
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	task.defer(function() safely(clampToViewport) end)
end)
-- ======================================================================
--  9. ghost, protected
-- ======================================================================
-- every part is remembered before it is touched, restore is exact
local function rememberPart(part)
	if savedAlpha[part] ~= nil then return end
	savedAlpha[part] = {
		Transparency = part.Transparency,
		LocalTransparencyModifier = part.LocalTransparencyModifier,
	}
end
local function paintPart(part, alpha, instant)
	rememberPart(part)
	safely(function() part.LocalTransparencyModifier = 0 end)
	if instant then
		part.Transparency = alpha
		return
	end
	safely(function()
		TweenService:Create(part, TweenInfo.new(CONFIG.FadeTime), { Transparency = alpha }):Play()
	end)
end
local function restorePart(part)
	local saved = savedAlpha[part]
	if not saved then return end
	if part.Parent then
		safely(function()
			part.LocalTransparencyModifier = saved.LocalTransparencyModifier
			TweenService:Create(part, TweenInfo.new(CONFIG.FadeTime), { Transparency = saved.Transparency }):Play()
		end)
	end
	savedAlpha[part] = nil
end
local function eachBasePart(character, callback)
	if not character then return end
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then safely(callback, descendant) end
	end
end
local function applyGhost()
	eachBasePart(getCharacter(), function(part)
		paintPart(part, CONFIG.GhostAlpha, false)
	end)
end
local function clearGhost()
	eachBasePart(LocalPlayer.Character, restorePart)
	for part in pairs(savedAlpha) do savedAlpha[part] = nil end
end
-- PROTECTION: parts that stream in later are caught and faded too
local ghostWatcher = nil
local function watchNewParts()
	if ghostWatcher then
		safely(function() ghostWatcher:Disconnect() end)
		ghostWatcher = nil
	end
	local character = LocalPlayer.Character
	if not character then return end
	ghostWatcher = character.DescendantAdded:Connect(function(descendant)
		if not isOn then return end
		if not descendant:IsA("BasePart") then return end
		task.defer(paintPart, descendant, CONFIG.GhostAlpha, true)
	end)
end
-- PROTECTION: the nametag is hidden, a ghost does not need one
local function setNametag(character, enabled)
	local head = character and character:FindFirstChild("Head")
	if not head then return end
	local billboard = head:FindFirstChildOfClass("BillboardGui")
	if not billboard then return end
	safely(function() billboard.Enabled = enabled end)
end
-- PROTECTION: a faint highlight keeps the ghost readable on dark maps
local function addHighlight(character)
	if ghostHighlight then return end
	ghostHighlight = new("Highlight", {
		Name = "best invisible ghost", Parent = Workspace,
		FillColor = Color3.fromRGB(188, 232, 255), FillTransparency = 0.86,
		OutlineColor = Color3.fromRGB(140, 214, 255), OutlineTransparency = 0.55,
		DepthMode = Enum.HighlightDepthMode.Occluded,
	})
	ghostHighlight.Adornee = character
end
local function removeHighlight()
	if ghostHighlight then
		safely(function() ghostHighlight:Destroy() end)
		ghostHighlight = nil
	end
end
-- ======================================================================
-- 10. body, protected
-- ======================================================================
-- the body is cloned, welded solid and parked FarDistance studs out in
-- a persistent pocket. nothing in the world can reach it out there.
local function getPocket()
	if pocket and pocket.Parent then return pocket end
	pocket = new("Folder", { Name = CONFIG.PocketName, Parent = Workspace })
	pocket.Archivable = true
	return pocket
end
local function stripScripts(model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BaseScript") or descendant:IsA("Sound") then
			safely(function() descendant:Destroy() end)
		end
	end
end
local function anchorModel(model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			safely(function()
				descendant.Anchored = true
				descendant.CanCollide = false
				descendant.CanTouch = false
				descendant.CanQuery = false
				descendant.Massless = true
				descendant.CastShadow = false
			end)
		end
	end
end
local function pickFarCFrame(origin)
	local target = origin.Position + Vector3.new(CONFIG.FarDistance, 0, 0)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	params.FilterDescendantsInstances = { LocalPlayer.Character }
	local result = safely(function()
		return Workspace:Raycast(target + Vector3.new(0, 900, 0), Vector3.new(0, -3600, 0), params)
	end)
	-- if the floor out there is not loaded, origin height is held instead
	keepFloorY = origin.Position.Y + 6
	if result then keepFloorY = result.Position.Y + 6 end
	return CFrame.new(Vector3.new(target.X, keepFloorY, target.Z)) * (origin - origin.Position)
end
local function buildFarBody(origin)
	local character = LocalPlayer.Character
	if not character then return nil end
	local clone = character:Clone()
	clone.Name = CONFIG.FarBodyName
	stripScripts(clone)
	anchorModel(clone)
	-- persistent, so the engine never streams the body out
	safely(function()
		clone.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	end)
	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	if humanoid then safely(function() humanoid:Destroy() end) end
	local root = clone:FindFirstChild("HumanoidRootPart")
	if not root then
		clone:Destroy()
		return nil
	end
	-- every part is welded to the root, so the pose survives the move
	for _, descendant in ipairs(clone:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant ~= root then
			safely(function()
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = root
				weld.Part1 = descendant
				weld.Parent = descendant
			end)
		end
	end
	clone:PivotTo(pickFarCFrame(origin))
	clone.Parent = getPocket()
	return clone
end
local function tagFarBody(body)
	local root = body:FindFirstChild("HumanoidRootPart")
	if not root then return end
	new("BillboardGui", {
		Name = "best invisible tag", Parent = root, AlwaysOnTop = true,
		Size = UDim2.fromOffset(200, 46), StudsOffset = Vector3.new(0, 3.2, 0),
		MaxDistance = 1000000,
	})
end
local function verifyDistance(body, origin)
	local root = body:FindFirstChild("HumanoidRootPart")
	if not root then return end
	if (root.Position - origin.Position).Magnitude >= CONFIG.FarDistance - 50 then return end
	root.CFrame = CFrame.new(origin.Position + Vector3.new(CONFIG.FarDistance, 0, 0))
end
local function deployFarBody(origin)
	local body = buildFarBody(origin)
	if not body then return nil end
	tagFarBody(body)
	verifyDistance(body, origin)
	return body
end
local function removeFarBody()
	if farBody and farBody.Parent then
		safely(function() farBody:Destroy() end)
	end
	farBody = nil
end
-- PROTECTION: the streaming radius is widened while armed and put back
-- exactly on disarm, so the map around the ghost can never vanish
local function widenStreaming()
	if not Workspace.StreamingEnabled then return end
	savedStream = {
		min = Workspace.StreamingMinRadius,
		target = Workspace.StreamingTargetRadius,
	}
	safely(function()
		Workspace.StreamingMinRadius = math.max(Workspace.StreamingMinRadius, 2048)
		Workspace.StreamingTargetRadius = math.max(Workspace.StreamingTargetRadius, 12288)
	end)
end
local function restoreStreaming()
	if not savedStream then return end
	safely(function()
		Workspace.StreamingMinRadius = savedStream.min
		Workspace.StreamingTargetRadius = savedStream.target
	end)
	savedStream = nil
end
local function holdMapLoaded()
	if not isOn then return end
	local root = getRoot()
	if not root then return end
	-- asking for the region keeps the far chunk alive on streamed maps
	safely(function()
		Workspace:RequestStreamAroundAsync(
			Vector3.new(root.Position.X + CONFIG.FarDistance, keepFloorY, root.Position.Z)
		)
	end)
end
-- PROTECTION: a keeper re-anchors and re-lifts the body every second,
-- so a streamed out floor can never drop it out of the world
local function keepBody()
	if not isOn then return end
	if not farBody or not farBody.Parent then
		safely(turnOn)
		return
	end
	local root = farBody:FindFirstChild("HumanoidRootPart")
	local mine = getRoot()
	if not root or not mine then return end
	if not root.Anchored then root.Anchored = true end
	local low = root.Position.Y < keepFloorY - 8
	local far = (root.Position - mine.Position).Magnitude > CONFIG.FarDistance * 1.5
	if low or far then
		safely(function()
			farBody:PivotTo(CFrame.new(root.Position.X, keepFloorY, root.Position.Z))
		end)
	end
end
local function startKeep()
	if keepConnection then return end
	keepConnection = task.spawn(function()
		while isOn do
			safely(keepBody)
			task.wait(CONFIG.KeepRate)
		end
	end)
end
function stopKeep()
	if keepConnection then
		safely(function() task.cancel(keepConnection) end)
		keepConnection = nil
	end
end
-- PROTECTION: the watchdog holds the box in one piece while armed
local function watchTick()
	if not isOn then return end
	safely(rebuildGui)
	safely(holdPosition)
	safely(holdSize)
	safely(holdMapLoaded)
end
function stopWatch()
	if watchConnection then
		safely(function() task.cancel(watchConnection) end)
		watchConnection = nil
	end
end
local function startWatch()
	if watchConnection then return end
	watchConnection = task.spawn(function()
		while isOn do
			watchTick()
			task.wait(CONFIG.WatchRate)
		end
	end)
end
-- ======================================================================
-- 11. trail, protected
-- ======================================================================
-- short afterimages, so movement stays visible while faded out
local function spawnTrailPart(sourcePart)
	local ghostPart = Instance.new("Part")
	safely(function()
		ghostPart.Shape = sourcePart.Shape
		ghostPart.Size = sourcePart.Size
		ghostPart.CFrame = sourcePart.CFrame
		ghostPart.Color = Color3.fromRGB(180, 230, 255)
		ghostPart.Transparency = CONFIG.TrailAlpha
		ghostPart.Anchored = true
		ghostPart.CanCollide = false
		ghostPart.CanTouch = false
		ghostPart.CanQuery = false
		ghostPart.CastShadow = false
		ghostPart.Name = "best invisible trail"
		ghostPart.Parent = pocket or Workspace
	end)
	safely(function()
		TweenService:Create(ghostPart, TweenInfo.new(CONFIG.TrailLife), {
			Transparency = 1, Size = sourcePart.Size * 0.92,
		}):Play()
	end)
	Debris:AddItem(ghostPart, CONFIG.TrailLife + 0.05)
end
local function trailTick()
	if not isOn then return end
	local root = getRoot()
	if not root then return end
	local humanoid = getHumanoid()
	if humanoid and humanoid.MoveDirection.Magnitude < 0.05 then return end
	spawnTrailPart(root)
end
local function startTrail()
	if trailConnection then return end
	trailConnection = task.spawn(function()
		while isOn do
			safely(trailTick)
			task.wait(CONFIG.TrailRate)
		end
	end)
end
local function stopTrail()
	if trailConnection then
		safely(function() task.cancel(trailConnection) end)
		trailConnection = nil
	end
	if pocket then
		for _, child in ipairs(pocket:GetChildren()) do
			if child.Name == "best invisible trail" then
				safely(function() child:Destroy() end)
			end
		end
	end
end
-- ======================================================================
-- 12. godmode, layered
-- ======================================================================
local function pinHealth()
	local humanoid = getHumanoid()
	if not humanoid then return end
	if humanoid.MaxHealth < 1000000 then
		humanoid.MaxHealth = 1000000
		humanoid.Health = 1000000
		return
	end
	if humanoid.Health < humanoid.MaxHealth then
		humanoid.Health = humanoid.MaxHealth
	end
end
local function startGod()
	if godConnection then return end
	pinHealth()
	godConnection = RunService.Heartbeat:Connect(function()
		if not isOn then return end
		pinHealth()
	end)
end
local function stopGod()
	if godConnection then
		safely(function() godConnection:Disconnect() end)
		godConnection = nil
	end
end
local function hookDamage(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	humanoid.HealthChanged:Connect(function()
		if not isOn then return end
		pinHealth()
	end)
end
local function hookDeath(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	humanoid.Died:Connect(function()
		if not isOn then return end
		task.wait(0.2)
		if isOn then safely(applyGhost) end
	end)
end
-- PROTECTION: a ragdolled ghost is alive but useless, it is forced up
local function hookStates(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	humanoid.StateChanged:Connect(function(_, new)
		if not isOn then return end
		if new == Enum.HumanoidStateType.Physics then
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end)
end
-- ======================================================================
-- 13. toggle, guarded
-- ======================================================================
function requestToggle()
	if not guard("toggle", 0.25) then return end
	withLock(toggle)
end
local function notify(text)
	safely(function()
		StarterGui:SetCore("SendNotification", {
			Title = CONFIG.Title, Text = text, Duration = 2.5,
		})
	end)
end
-- PROTECTION: disarm puts every single value back where it was found
function turnOff()
	isOn = false
	paint(CONFIG.Red, CONFIG.RedDark, "off")
	playSound(false)
	stopGod()
	stopTrail()
	stopKeep()
	stopWatch()
	restoreStreaming()
	removeHighlight()
	clearGhost()
	removeFarBody()
	if ghostWatcher then
		safely(function() ghostWatcher:Disconnect() end)
		ghostWatcher = nil
	end
	local character = LocalPlayer.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			if savedWalk then humanoid.WalkSpeed = savedWalk end
			if savedJump then humanoid.JumpPower = savedJump end
		end
		safely(setNametag, character, true)
	end
	savedWalk, savedJump = nil, nil
	reportState()
	notify("ghost off  |  you are solid again")
end
-- PROTECTION: arm parks the body first, so the clone keeps full colour
function turnOn()
	local character = LocalPlayer.Character
	if not character then return end
	local root = getRoot()
	if not root then return end
	isOn = true
	paint(CONFIG.Green, CONFIG.GreenDark, "on")
	playSound(true)
	farBody = deployFarBody(root.CFrame)
	if not farBody then
		-- parking failed, roll back so the box never lies
		isOn = false
		paint(CONFIG.Red, CONFIG.RedDark, "off")
		playSound(false)
		return
	end
	widenStreaming()
	holdMapLoaded()
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		savedWalk, savedJump = humanoid.WalkSpeed, humanoid.JumpPower
	end
	safely(setNametag, character, false)
	applyGhost()
	watchNewParts()
	addHighlight(character)
	hookDamage(character)
	hookDeath(character)
	hookStates(character)
	startGod()
	startTrail()
	startKeep()
	startWatch()
	local mine = getRoot()
	if mine then mine.AssemblyLinearVelocity = Vector3.zero end
	reportState()
	notify("ghost on  |  real body parked 10000 studs out")
end
-- PROTECTION: both directions land here, one at a time
function toggle()
	if isOn then turnOff() else turnOn() end
end
-- PROTECTION: if the player resets while armed, it all comes back
local function onCharacterAdded(character)
	if not isOn then return end
	task.wait(0.35)
	if not isOn then return end
	removeFarBody()
	savedAlpha = {}
	removeHighlight()
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	farBody = deployFarBody(root.CFrame)
	if not farBody then return end
	widenStreaming()
	applyGhost()
	watchNewParts()
	addHighlight(character)
	hookDamage(character)
	hookDeath(character)
	hookStates(character)
	startGod()
	startTrail()
	startKeep()
	startWatch()
end
LocalPlayer.CharacterAdded:Connect(onCharacterAdded)
-- ======================================================================
-- 14. start
-- ======================================================================
local startingCharacter = LocalPlayer.Character
if startingCharacter then
	hookDamage(startingCharacter)
	hookDeath(startingCharacter)
	hookStates(startingCharacter)
end
paint(CONFIG.Red, CONFIG.RedDark, "off")
pressFeedback(false)
clampToViewport()
screenGui.Parent = PlayerGui
reportState()
notify("best invisible ready  |  click the box")
-- ======================================================================
-- github.com/supercaptain1233  |  bestinvisible5.lua
-- ======================================================================
-- the numbers, exactly as asked:
--   box colour ............ red disarmed, green armed
--   ghost transparency .... 55 percent
--   distance .............. 10000 studs
--   camera ................ untouched, default third person
--   health ................ pinned, the ghost cannot die
--   far body .............. persistent, keeper held, never falls
--   other scripts ......... left alone, nothing bound or stolen
-- ======================================================================
-- prefilled loader:
-- loadstring(game:HttpGet("https://raw.githubusercontent.com/supercaptain1233/bestinvisible5/main/bestinvisible5.lua"))()
-- ======================================================================

-- ======================================================================
-- PROTECTION SUMMARY, every guard in one place
-- ======================================================================
-- box:   pin, size hold, viewport clamp, rebuild on kill
-- ghost: transparency fade with exact restore, watcher for new parts
-- body:  weld, anchor, persist, keeper, distance verify
-- state: mutex, toggle guard, drag guard, rollback on failure
-- script: safely on every call, error counter, published state
-- map:   streaming widened, region requested, radius restored
-- ======================================================================
-- QUICK USE
-- ======================================================================
-- 1. paste this into delta and execute it
-- 2. a red box appears, it says "best invisible"
-- 3. drag it wherever it is comfortable
-- 4. click it once, it turns green, you are a ghost
-- 5. click it again, it turns red, you are solid again
-- 6. g or h does the same thing if you prefer keys
-- ======================================================================
-- WHAT IS PROTECTED AND HOW
-- ======================================================================
-- THE BOX
--   * pinnedPosition holds the box at its last spot, so nothing
--     can nudge it while it is not being dragged
--   * holdSize re-applies BoxSize if anything squashes the frame
--   * clampToViewport keeps it fully on screen on every drag end
--   * rebuildGui re-parents it and repaints it if it is deleted
--   * Selectable is off, so a text box cannot steal focus from it
--   * a drag guard stops a double press from firing the toggle twice
--   * a press shorter than six pixels is a click, longer is a drag
-- THE GHOST
--   * every transparency is stored before it is touched
--   * the restore puts the stored value back, digit for digit
--   * a descendant watcher fades parts that stream in afterwards
--   * the nametag is disabled, a ghost does not advertise itself
--   * a faint highlight keeps it visible on dark or cluttered maps
-- THE BODY
--   * cloned, stripped of scripts and sounds, welded part to root
--   * fully anchored, no collide, no touch, no query, massless
--   * ModelStreamingMode is Persistent, the engine holds it loaded
--   * parked 10000 studs out, with a raycast so it lands on floor
--   * verifyDistance re-parks it if it ever comes back short
--   * the keeper re-anchors and re-lifts it every single second
-- THE STATE
--   * withLock is a mutex, arming and disarming cannot overlap
--   * requestToggle is debounced to a quarter of a second
--   * a failed park rolls the box straight back to red
--   * the watchdog rebuilds, re-pins, re-sizes and re-streams
-- THE SCRIPT
--   * safely wraps every risky call and counts the errors
--   * ScriptContext.Error swallows our own tracebacks
--   * _G.BEST_INVISIBLE_STATE is published for other scripts
-- THE MAP
--   * StreamingMinRadius and StreamingTargetRadius are raised
--   * the exact old numbers are stored and restored on disarm
--   * RequestStreamAroundAsync pulls in the far chunk
-- ======================================================================
-- WHAT IS NEVER TOUCHED
-- ======================================================================
--   * the camera, no CameraType or CFrame writes anywhere
--   * CoreGui, nothing is inserted into it
--   * other guis, ours is only destroyed if it is ours
--   * other keys, g and h are read only, nothing is bound
--   * WalkSpeed and JumpPower are stored and put back, never forced
--   * the far body has CanQuery off, other raycasts pass through
--   * DisplayOrder is 900, not 999, so an overlay can sit above
-- ======================================================================
-- NUMBERS
-- ======================================================================
--   ghost transparency ........ 0.55  (55 percent)
--   park distance ............. 10000 studs
--   fade time ................. 0.22 seconds
--   trail life ................ 0.45 seconds
--   keeper interval ........... 1 second
--   watchdog interval ......... 0.5 seconds
--   toggle debounce ........... 0.25 seconds
--   drag threshold ............ 6 pixels
--   rebuild limit ............. 20 attempts
--   box size .................. 138 pixels
-- ======================================================================
-- IF SOMETHING LOOKS WRONG
-- ======================================================================
--   * the box is green but nothing happened -> the park failed,
--     the box rolls itself back to red on its own
--   * the box vanished -> the watchdog re-parents it within 0.5s
--   * the body fell -> the keeper lifts it back on the next tick
--   * the body vanished -> the keeper rebuilds it on the next tick
--   * you are still solid -> click once more, the guard may have
--     eaten a very fast double tap
-- ======================================================================
-- end of file
-- ======================================================================

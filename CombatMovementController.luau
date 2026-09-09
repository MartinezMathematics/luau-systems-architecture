--!strict
-- Module: CombatMovementController.luau
-- Author: Hector Martinez
-- Architecture: Client-Side Locomotion & Real-Time Combat Controller
-- Engine: Roblox Engine (Luau)
--
-- Core Subsystems:
--   1. Procedural Kinematics:
--      - Projects humanoid movement vectors into local root space (VectorToObjectSpace).
--      - Applies frame-rate-independent Lerp interpolation for procedural torso tilting.
--   2. Spatial Combat & Hit Detection:
--      - Hybrid spatial query pipeline combining directional Spherecasts with radial overlap checks.
--      - Vector dot-product calculation for directional flanking detection (backstabs/block bypasses).
--   3. Kinematic-Driven Dynamic Systems:
--      - Maps normalized speed fractions to dynamic FOV interpolation, audio pitch, and VFX emission.
--   4. State Synchronization:
--      - Dispatches RemoteEvent payloads to authoritative server services for damage and animation replication.

local runService = game:GetService("RunService")
local player = game.Players.LocalPlayer
local userInputService = game:GetService("UserInputService")
local camera = workspace.CurrentCamera
local replicatedStorage = game:GetService("ReplicatedStorage")
local root = player.Character:WaitForChild("HumanoidRootPart")
local humanoid = player.Character:WaitForChild("Humanoid")
local mouse = player:GetMouse()

local CameraShaker = require(replicatedStorage.CameraShaker)

local camShake = CameraShaker.new(Enum.RenderPriority.Camera.Value, function(shakeCFrame)
	camera.CFrame = camera.CFrame * shakeCFrame
end)
camShake:Start()

local isBlocking = false
local firstHumanoid
local knockedBack = player.Character:HasTag("KnockedBack")

local FinalHit = false

local canHit = true
local isPlaying = false -- Cooldown flag for hit
local canClickAgain = true

local combo = 1
local combo2 = 1
local comboResetTime = 1 -- Time to reset combo if no subsequent hit
local comboResetTimer = nil
local maxComboTime = 5
local lastComboTime = 0

local KnockbackAnims = {
	script.KnockbackAnimations:FindFirstChild("Hit1"),
	script.KnockbackAnimations:FindFirstChild("Hit2"),
	script.KnockbackAnimations:FindFirstChild("Hit3"),
	script.KnockbackAnimations:FindFirstChild("Hit4")
}

local animations = {
	script.HitAnimations:FindFirstChild("Hit1"),
	script.HitAnimations:FindFirstChild("Hit2"),
	script.HitAnimations:FindFirstChild("Hit3"),
	script.HitAnimations:FindFirstChild("Hit4")
}

local maxHits = (#animations*2)
local hitMarker = 1

local function isAnimationInTable(anim)
	for _, animation in ipairs(animations) do
		if animation == anim then
			return true
		end
	end
	return false
end

local function isPlayerBehindPart(player, part)
	local partPosition = part.Position
	local partLookVector = part.CFrame.LookVector
	local playerPosition = player.Character.HumanoidRootPart.Position
	local toPlayer = (playerPosition - partPosition).unit

	local dotProduct = partLookVector:Dot(toPlayer)
	return dotProduct < 0
end

local maxClones = 60 -- Hard limit for the number of clones
local clones = {} -- Table to keep track of the clones

local cloneFunction = function(newPart)
	if #clones < maxClones then
		newPart.Anchored = true
		newPart.CanCollide = false
		newPart.Transparency = 0.5
		newPart.Material = Enum.Material.Neon
		newPart.Color = Color3.new(0.533333, 0, 1)
		newPart.Size = newPart.Size + Vector3.new(0.01, 0.01, 0.01)
		newPart.Parent = workspace.IgnoreFolder

		table.insert(clones, newPart)

		spawn(function()
			wait(0.4)
			for i, clone in ipairs(clones) do
				if clone == newPart then
					table.remove(clones, i)
					break
				end
			end
			newPart:Destroy()
		end)

		local tween = game:GetService('TweenService'):Create(newPart, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {Transparency = 1, Color = Color3.new(0.576471, 1, 0.87451)})
		tween:Play()
	end
end

local hitAnim

local function playAnimation(anim)

	if anim and not knockedBack then
		-- Stop any currently playing animations
		for _, track in pairs(humanoid:GetPlayingAnimationTracks()) do
			track:Stop()
		end

		if hitAnim then
			hitAnim:Stop(0)
			hitAnim = nil
		end

		local animationTrack = humanoid:LoadAnimation(anim)
		hitAnim = animationTrack
		animationTrack:Play()

		if isAnimationInTable(anim) then
			animationTrack:AdjustSpeed(3)

			spawn(function()
				if #clones < maxClones then
					for _, part in pairs(player.Character:GetChildren()) do
						if part:IsA("BasePart") and part ~= root and part.Name ~= "HumanoidRootPart" and part.Name ~= "SpeedParticles" then
							local newPart = part:Clone()

							if newPart.Name == "Head" then
								newPart:Destroy()
								local headRep = replicatedStorage:WaitForChild("HeadReplacement"):Clone()
								headRep.CFrame = newPart.CFrame
								newPart = headRep
							end

							for _, v in pairs(newPart:GetDescendants()) do
								if not v:IsA('BasePart') then
									v:Destroy()
								end
							end

							cloneFunction(newPart)
						end
					end
				end
			end)

		end

		if not isAnimationInTable(anim) then
			animationTrack.Stopped:Connect(function()
				isPlaying = false  -- Reset cooldown flag after animation completes
				canHit = true      -- Reset canHit after animation completes
			end)

			return animationTrack
		else
			wait(0.1)
			animationTrack:Stop()
			hitAnim = nil
			isPlaying = false  -- Reset cooldown flag after animation completes
			canHit = true    

			return animationTrack
		end

	else
		warn("Animation not found or knocked back")
	end
end

local function playVictimAnimation(anim, hum)
	-- and not hum.Parent:HasTag("KnockedBack") 
	-- and firstHumanoid == hum
	if anim then
		if FinalHit == true then
			FinalHit = false
			game.SoundService.FinalHit:Play()

			game.ReplicatedStorage.Knockbacked:FireServer(hum)
		else
			game.ReplicatedStorage.Animations:FireServer(hum, anim)
		end
	else
		warn("Victim animation not found")
	end
end

local function resetCombo()
	combo = 1
	combo2 = 1
	FinalHit = false

	print("Combos reset")
end

local isRunning, isShiftPressed, isLanding, initiatedJump, canJump, canSlide, isWalking = false, false, false, false, true, false, false
local jumpAnim, fallAnim, slideAnim, runAnim, idleAnim, landingAnim, walkAnim
local lastCloneTime, baseFOV, maxFOV, landingSpeedFactor, landingDuration, landingAccelerationTime = 0, 70, 140, 2, 1, 6
local walkSpeedTarget, walkSpeedMin, walkSpeedMax, acceleration, deceleration = 16, 16, 100, 1, 6
local MaxTiltAngle, canMultSpeed = 25, false

local speedSound = Instance.new("Sound")
speedSound.SoundId = "rbxassetid://2162238374"
speedSound.Looped = true
speedSound.Parent = root
speedSound:Play()

local footstepSound = Instance.new("Sound")
footstepSound.SoundId = "rbxassetid://6563562192"
footstepSound.Volume = 0.1
footstepSound.Parent = root

local speedLinesTemplate = replicatedStorage:WaitForChild("SpeedParticles")
local speedLines

local function createSphere(position, radius, color, transparency, parent)
	local sphere = Instance.new("Part")
	sphere.Shape = Enum.PartType.Ball
	sphere.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
	sphere.Anchored = true
	sphere.CanCollide = false
	sphere.Transparency = transparency
	sphere.Color = color
	sphere.Position = position
	sphere.Parent = parent
	game:GetService("Debris"):AddItem(sphere, 0.5)
	return sphere
end

local function visualizeSphereCast(startPos, endPos, radius)
	local direction = (endPos - startPos).Unit
	local distance = (endPos - startPos).Magnitude
	local steps = math.floor(distance / (radius * 2))

	for i = 0, steps do
		local position = startPos + direction * (i * radius * 2)
		createSphere(position, radius, Color3.fromRGB(255, 0, 0), 0.5, workspace)
	end

	-- Make sure to place a sphere at the exact end position
	createSphere(endPos, radius, Color3.fromRGB(255, 0, 0), 0.5, workspace)
end

local function damageHumanoid(hum)
	local damageAmount = 2.5 -- Amount of damage to deal
	game.ReplicatedStorage.Damage:FireServer(hum, damageAmount, true, nil ,nil)
	game.SoundService.HitSFX:Play()
end

local function isHumanoidInFront()
	local character = player.Character or player.CharacterAdded:Wait()
	local rootPart = character:WaitForChild("HumanoidRootPart")
	local forwardVector = rootPart.CFrame.LookVector
	local startPos = rootPart.Position

	local radius = 3.5
	local distance = 1.25

	local endPos = startPos + forwardVector * distance
	local rayDirection = (endPos - startPos).Unit * distance

	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = {character}
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	local overlapParams = OverlapParams.new()
	overlapParams.FilterDescendantsInstances = {character}
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude

	local function handleHumanoid(human, behind, root2)
		if not behind then
			local humanRoot = human.Parent.HumanoidRootPart
			game.ReplicatedStorage.Damage:FireServer(nil,nil,false,human,root2)
		end
		damageHumanoid(human)

		local anim = KnockbackAnims[combo2]
		print("Playing animation: Knockback" .. combo2)
		playVictimAnimation(anim, human)

		camShake:ShakeOnce(4, 4, 0, 0.2)

		return true, human
	end

	local function checkHumanoid(human, root2)
		if not human then
			return false, nil
		end

		local parent = human.Parent
		if not parent:HasTag("KnockedBack") and not parent:HasTag("Blocking") then
			return handleHumanoid(human, false, root2)
		elseif parent:HasTag("Blocking") and isPlayerBehindPart(player, root2) then
			return handleHumanoid(human, true, root2)
		end

		return false, nil
	end

	local function processResult(result)
		if result then
			local hitPart = result.Instance
			local parent = hitPart.Parent
			local human = parent:FindFirstChild("Humanoid")
			if human then
				return checkHumanoid(human, parent:WaitForChild("HumanoidRootPart"))
			end
		end
		return false, nil
	end

	local raycastResult = workspace:Spherecast(startPos, radius, rayDirection, raycastParams)
	local result, human = processResult(raycastResult)
	if result then
		return true, human
	end

	local overlapParts = workspace:GetPartBoundsInRadius(startPos, radius, overlapParams)
	for _, part in ipairs(overlapParts) do
		local parent = part.Parent
		local human = parent:FindFirstChild("Humanoid")
		if human then
			local result, humanFound = checkHumanoid(human, parent:WaitForChild("HumanoidRootPart"))
			if result then
				return true, humanFound
			end
		end
	end

	return false, nil
end

local function loadAndPlayAnimation(animName)
	local anim = humanoid:LoadAnimation(script:WaitForChild(animName))
	anim:Play()
	return anim
end

local function playRunAnimation()
	if isRunning and not runAnim and not walkAnim then
		runAnim = loadAndPlayAnimation("Run")
		runAnim:GetMarkerReachedSignal("Left"):Connect(function() footstepSound:Play() end)
		runAnim:GetMarkerReachedSignal("Right"):Connect(function() footstepSound:Play() end)
	end
end

local function stopRunAnimation()
	if runAnim then
		runAnim:Stop()
		runAnim = nil
	end
end

local function playWalkAnimation()
	if not walkAnim then
		walkAnim = loadAndPlayAnimation("Walk")
		--walkAnim:GetMarkerReachedSignal("Left"):Connect(function() footstepSound:Play() end)
		--walkAnim:GetMarkerReachedSignal("Right"):Connect(function() footstepSound:Play() end)
	end
end

local function stopWalkAnimation()
	if walkAnim then
		walkAnim:Stop()
		walkAnim = nil
	end
end

local function playIdleAnimation()
	if not idleAnim and not isPlaying and not isBlocking then
		idleAnim = loadAndPlayAnimation("Idle")
		idleAnim:GetMarkerReachedSignal("Left"):Connect(function() footstepSound:Play() end)
		idleAnim:GetMarkerReachedSignal("Right"):Connect(function() footstepSound:Play() end)
	end
end

local function stopIdleAnimation()
	if idleAnim then
		idleAnim:Stop()
		idleAnim = nil
	end
end

local function enableParticles()
	if speedLines then
		for _, emitter in pairs(speedLines:GetDescendants()) do
			if emitter:IsA("ParticleEmitter") then
				emitter.Enabled = true
			end
		end
	end
end

local function disableParticles()
	if speedLines then
		for _, emitter in pairs(speedLines:GetDescendants()) do
			if emitter:IsA("ParticleEmitter") then
				emitter.Enabled = false
			end
		end
	end
end

local function playerParticles()
	for _, v in pairs(replicatedStorage.SpeedCore.VFX:GetChildren()) do
		if v:IsA('ParticleEmitter') then
			local newVFX = v:Clone()
			newVFX.Enabled = true
			newVFX.Parent = root
		end
	end
end

playerParticles()

local function adjustSpeedOnLanding(step)
	workspace.Gravity = 250
	local originalWalkSpeed = humanoid.WalkSpeed
	--humanoid.WalkSpeed = originalWalkSpeed * landingSpeedFactor
	wait(landingDuration)

	local elapsedTime = 0
	
	--Reset MaxTiltAngle after landing animation
	if isRunning then
		MaxTiltAngle = 25 
	else
		MaxTiltAngle = 10
	end

	while elapsedTime < landingAccelerationTime and canMultSpeed and not jumpAnim and not fallAnim and not runAnim do
		local timeBeforeWait = os.clock()
		--humanoid.WalkSpeed = humanoid.WalkSpeed + ((originalWalkSpeed - humanoid.WalkSpeed) * (step / landingAccelerationTime))
		elapsedTime = elapsedTime + (os.clock() - timeBeforeWait)
		wait(step)
	end

	if not runAnim and slideAnim then
		--humanoid.WalkSpeed = originalWalkSpeed
	end
end

local function updateWalkingState()
	if not isShiftPressed and not isBlocking and not slideAnim and not fallAnim and not jumpAnim and not idleAnim and not hitAnim then
		if humanoid.MoveDirection.Magnitude >= 0.1 then
			if not isWalking then
				isWalking = true
				if not slideAnim then playWalkAnimation() end
			end
		else
			if isWalking then -- Not Running
				isWalking = false
				stopWalkAnimation()
			end
		end
	else
		if isWalking then -- Not Running
			isWalking = false
			stopWalkAnimation()
		end
	end
end

local function updateRunningState()
	if isShiftPressed and not isBlocking then
		if humanoid.MoveDirection.Magnitude >= 0.1 or Jumping then
			if not isRunning then
				isRunning = true
				if not slideAnim then playRunAnimation() end
				if not speedLines then
					speedLines = speedLinesTemplate:Clone()
					speedLines.Parent = root
					local weld = Instance.new("Weld")
					weld.Part0 = root
					weld.Part1 = speedLines
					weld.C0 = CFrame.new(0, 0, -2.5)
					weld.Parent = root
				end
				enableParticles()
			end
			walkSpeedTarget = walkSpeedMax
		else
			if isRunning then
				isRunning = false
				stopRunAnimation()
				disableParticles()
				walkSpeedTarget = walkSpeedMin
			end
		end
	else
		if isRunning then
			isRunning = false
			stopRunAnimation()
			disableParticles()
			walkSpeedTarget = walkSpeedMin
		end
	end
end

runService.RenderStepped:Connect(function(step)

	if hitMarker >= maxHits and isHumanoidInFront() then -- FINAL HIT CHECK
		hitMarker = 0
		FinalHit = true
	end

	if humanoid:GetState() ~= Enum.HumanoidStateType.Freefall and fallAnim then
		fallAnim:Stop()
		fallAnim = nil
	end

	if slideAnim then
		canMultSpeed = true
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, false)
	else
		canMultSpeed = false
		if canJump then
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, true)
		end
	end

	updateWalkingState()
	updateRunningState()

	local targetSpeed = walkSpeedTarget
	local currentSpeed = humanoid.WalkSpeed

	if currentSpeed < targetSpeed then
		humanoid.WalkSpeed = currentSpeed + (targetSpeed - currentSpeed) * acceleration * step
	else
		humanoid.WalkSpeed = currentSpeed + (targetSpeed - currentSpeed) * deceleration * step
	end

	local speedFraction = (humanoid.WalkSpeed - walkSpeedMin) / (walkSpeedMax - walkSpeedMin)

	if speedLines then
		for _, emitter in pairs(speedLines:GetDescendants()) do
			if emitter:IsA("ParticleEmitter") then
				emitter.Rate = 1 + (90 * speedFraction)
			end
		end
	end

	local targetFOV = isShiftPressed and (baseFOV + (maxFOV - baseFOV) * speedFraction) or baseFOV
	camera.FieldOfView = camera.FieldOfView + (targetFOV - camera.FieldOfView) * 0.1

	speedSound.PlaybackSpeed = 0.5 + speedFraction * 1.5
	speedSound.Volume = 0.3 * speedFraction

	if runAnim then
		runAnim:AdjustSpeed(1 + speedFraction * 1.5)
	end

	if humanoid.MoveDirection.Magnitude >= 0.1 and isShiftPressed and not isBlocking then
		local cloneInterval = 0.5 + (0.05 - 0.5) * speedFraction
		if tick() - lastCloneTime >= cloneInterval then
			lastCloneTime = tick()

			if #clones < maxClones then
				for _, part in pairs(player.Character:GetChildren()) do
					if part:IsA("BasePart") and part ~= root and part.Name ~= "HumanoidRootPart" and part.Name ~= "SpeedParticles" then
						local newPart = part:Clone()

						if newPart.Name == "Head" then
							newPart:Destroy()
							local headRep = replicatedStorage:WaitForChild("HeadReplacement"):Clone()
							headRep.CFrame = newPart.CFrame
							newPart = headRep
						end

						for _, v in pairs(newPart:GetDescendants()) do
							if not v:IsA('BasePart') then
								v:Destroy()
							end
						end

						cloneFunction(newPart)
					end
				end
			end
		end
	end
end)

local RootJoint = root:WaitForChild("RootJoint")
local RootC0 = RootJoint.C0
local Jumping = false
local Tilt = CFrame.new()
local landingDebounce = false

local function onStateChanged(oldState, newState)
	if (newState == Enum.HumanoidStateType.Jumping or newState == Enum.HumanoidStateType.Freefall) and initiatedJump then
		if fallAnim == nil then
			fallAnim = loadAndPlayAnimation("Fall")
		end
		Jumping = true
	elseif newState == Enum.HumanoidStateType.Landed then
		initiatedJump = false
		Jumping = false
		if fallAnim then
			fallAnim:Stop()
			fallAnim = nil
		end
		if slideAnim == nil then
			slideAnim = loadAndPlayAnimation("Land")
		end
		landingDebounce = true
		local landingSound = Instance.new("Sound")
		landingSound.SoundId = "rbxassetid://1910795334"
		landingSound.Parent = root
		landingSound:Play()
		Jumping = false

		if slideAnim then
			MaxTiltAngle = 0
		elseif runAnim then
			MaxTiltAngle = 25
		elseif not slideAnim and not runAnim and not fallAnim then
			MaxTiltAngle = 5
		end

		spawn(function()
			adjustSpeedOnLanding(runService.RenderStepped:Wait())
			isLanding = false
		end)

		landingDebounce = false
	end
end

humanoid.StateChanged:Connect(onStateChanged)

runService.RenderStepped:Connect(function(delta)
	local MoveDirection = root.CFrame:VectorToObjectSpace(humanoid.MoveDirection)
	Tilt = Tilt:Lerp(CFrame.Angles(math.rad(-MoveDirection.Z) * MaxTiltAngle, math.rad(-MoveDirection.X) * MaxTiltAngle, 0), 0.2 ^ (1 / (delta * 60)))
	RootJoint.C0 = RootC0 * Tilt

	if Jumping then
		if runAnim then
			runAnim:Stop()
			runAnim = nil
		end
		if canJump then
			workspace.Gravity = 100
			canJump = false
			local animationWaitTime = 0.5 -- Adjust this as needed
			spawn(function()
				local startTime = os.clock()
				repeat
					task.wait()
				until slideAnim == nil or os.clock() - startTime >= animationWaitTime
				canJump = true
				workspace.Gravity = 250
				if slideAnim then
					slideAnim:Stop()
					slideAnim = nil
				end
				if isRunning then
					playRunAnimation()
				end
			end)
			MaxTiltAngle = -15
		end
	else
		if isRunning and not slideAnim then
			playRunAnimation()
		end
		if not slideAnim and isShiftPressed then
			MaxTiltAngle = 25
		end
	end

	if not Jumping and humanoid.MoveDirection.Magnitude < 0.1 and slideAnim then
		slideAnim:Stop()
		slideAnim = nil
		local landingSound2 = Instance.new("Sound")
		landingSound2.SoundId = "rbxassetid://7512928742"
		landingSound2.Parent = root
		landingSound2.Volume = 0.15
		landingSound2:Play()
	end

	if not isRunning and humanoid.MoveDirection.Magnitude < 0.1 and not Jumping and not isLanding then
		if not idleAnim then
			playIdleAnimation()
		end
	else
		if idleAnim then
			stopIdleAnimation()
		end
	end
end)

local function onLeftClick()
	if isPlaying or not canHit then
		return -- Prevent executing if an animation is already playing or canHit is false
	end

	if isHumanoidInFront() then

		local first, second = isHumanoidInFront()
		warn("isHumanoidInFront result - first: ", first, ", second: ", second)

		if first then
			local HUMAN = second

			if HUMAN == nil then
				firstHumanoid = HUMAN
			elseif HUMAN ~= firstHumanoid then
				firstHumanoid = HUMAN

				warn("First Humanoid: " .. tostring(firstHumanoid))

				hitMarker = 0
				resetCombo()
			end
		end

		hitMarker += 1

		combo = combo + 1
		if combo > #animations then
			combo = 1

			if hitMarker >= maxHits or FinalHit then -- TO FIX -- AFTER A MAX COMBO, IF YOU SPAM PUNCH, IT KNOCKS BACK EVERY HIT --
				hitMarker = 0
				spawn(function()
					canClickAgain = false
					resetCombo()
					wait(0.5)
					canClickAgain = true
				end)
			end
		end

		combo2 = combo2 + 1
		if combo2 > #KnockbackAnims then
			combo2 = 1
		end

		isPlaying = true -- Set cooldown flag
		canHit = false -- Set canHit to false when a hit is registered

		local anim = animations[combo]
		print("Playing animation: Hit" .. combo)
		playAnimation(anim)

		warn("Current combo: " .. combo)

		combo = combo + 1
		if combo > #animations then
			combo = 1

			if hitMarker >= maxHits or FinalHit then -- TO FIX -- AFTER A MAX COMBO, IF YOU SPAM PUNCH, IT KNOCKS BACK EVERY HIT --
				hitMarker = 0
				spawn(function()
					canClickAgain = false
					hitMarker = 0
					wait(0.5)
					canClickAgain = true
				end)
			end
		end

	else
		isPlaying = true -- Set cooldown flag
		canHit = false -- Set canHit to false when a hit is registered

		local anim = animations[combo]
		print("Playing animation: Hit" .. combo)
		playAnimation(anim)

		warn("Current combo: " .. combo)

		combo = combo + 1
		if combo > #animations then
			combo = 1

			if hitMarker >= maxHits  or FinalHit == true then -- TO FIX -- AFTER A MAX COMBO, IF YOU SPAM PUNCH, IT KNOCKS BACK EVERY HIT --
				hitMarker = 0
				spawn(function()
					canClickAgain = false
					hitMarker = 0
					wait(0.5)
					canClickAgain = true
				end)
			end
		end
		combo2 = combo2 + 1
		if combo2 > #KnockbackAnims then
			combo2 = 1
		end
	end

	if comboResetTimer then
		comboResetTimer:Disconnect()
	end

	comboResetTimer = runService.RenderStepped:Connect(function(_, dt)
		if tick() - lastComboTime >= comboResetTime/2 then
			comboResetTimer:Disconnect()
			resetCombo()
			hitMarker = 0
			isPlaying = false -- Reset cooldown flag

			spawn(function()
				canClickAgain = false
				wait(0.5)
				canClickAgain = true
			end)
		end
	end)
end

-- Input handling
userInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then return end

	if input.KeyCode == Enum.KeyCode.LeftShift then
		isShiftPressed = true
		return
	end

	if input.KeyCode == Enum.KeyCode.Space then
		--initiatedJump = true
	end

	-- Handle MouseButton1 for Combo System
	if input.UserInputType == Enum.UserInputType.MouseButton1 and not isBlocking and canHit and canClickAgain and not isPlaying and not player.Character:FindFirstChild("HasBeenHit") and not runAnim and not fallAnim and not slideAnim then
		lastComboTime = tick()
		onLeftClick()
		stopIdleAnimation()
	end
end)

userInputService.InputEnded:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then return end

	if input.KeyCode == Enum.KeyCode.LeftShift then
		isShiftPressed = false
	end
end)

local blockAnim = nil

runService.RenderStepped:Connect(function()

	if userInputService:IsKeyDown(Enum.KeyCode.F) and not fallAnim and not slideAnim then

		if not isBlocking then
			-- Changed to FireServer instead of connecting OnClientEvent
			game.ReplicatedStorage.BlockEvent:FireServer(false)
			stopIdleAnimation()
		end

		if not blockAnim then
			blockAnim = playAnimation(script.Block)
			blockAnim:Play()
		end

		isBlocking = true

		humanoid.JumpPower = 0
		humanoid.WalkSpeed = 8
		MaxTiltAngle = 3

	elseif isBlocking then

		-- Changed to FireServer instead of connecting OnClientEvent
		game.ReplicatedStorage.BlockEvent:FireServer(true)

		if blockAnim then
			blockAnim:Stop()
			blockAnim = nil
		end

		isBlocking = false

		humanoid.JumpPower = 50
		humanoid.WalkSpeed = 16
		MaxTiltAngle = 15
	end

end)

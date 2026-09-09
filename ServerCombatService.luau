--!strict
-- Module: ServerCombatService.luau
-- Author: Hector Martinez
-- Architecture: Authoritative Server Combat, Physics, & Replication Service
-- Engine: Roblox Engine (Luau)
--
-- Core Subsystems:
--   1. Authoritative Damage Verification:
--      - Validates Humanoid instances and applies health reductions server-side.
--      - Applies momentary stun modifiers to target walk speed and jump mechanics.
--   2. Dynamic Knockback Physics:
--      - Calculates directional impulse vectors and applies BodyVelocity constraints.
--      - Aligns victim CFrame to face the instigator along the horizontal plane.
--   3. Network State Replication:
--      - Synchronizes animation tracks across all listening clients.
--      - Manages gameplay tags ('KnockedBack', 'Blocking') for client-side state filtering.

local replicatedStorage = game:GetService("ReplicatedStorage")
local debris = game:GetService("Debris")

local damageEvent = replicatedStorage:WaitForChild("Damage")
local animationsEvent = replicatedStorage:WaitForChild("Animations")
local knockbackedEvent = replicatedStorage:WaitForChild("Knockbacked")
local blockEvent = replicatedStorage:WaitForChild("BlockEvent")

damageEvent.OnServerEvent:Connect(function(player, humanoid, damageAmount, condition, human, humanRoot)
	if humanoid and humanoid:IsA("Humanoid") and condition then
		humanoid:TakeDamage(damageAmount)

		task.spawn(function()
			local check = Instance.new("BoolValue")
			check.Name = "HasBeenHit"
			check.Parent = humanoid.Parent
			debris:AddItem(check, 0.25)

			humanoid.JumpPower = 0
			humanoid.WalkSpeed = 2
			task.wait(0.15)
			humanoid.WalkSpeed = 16
			humanoid.JumpPower = 50
		end)
	elseif human and humanRoot and player.Character and player.Character.PrimaryPart then
		local lookTarget = player.Character.PrimaryPart.Position * Vector3.new(1, 0, 1) + humanRoot.Position * Vector3.new(0, 1, 0)
		human.Parent:SetPrimaryPartCFrame(CFrame.lookAt(humanRoot.Position, lookTarget))
	end
end)

animationsEvent.OnServerEvent:Connect(function(player, hum, anim)
	for _, track in pairs(hum:GetPlayingAnimationTracks()) do
		track:Stop()
	end

	local animationTrack = hum:LoadAnimation(anim)
	animationTrack:Play()
	return animationTrack
end)

knockbackedEvent.OnServerEvent:Connect(function(player, humanoid)
	local targetParent = humanoid.Parent
	local targetRoot = targetParent:WaitForChild("HumanoidRootPart")
	local playerRoot = player.Character and player.Character.PrimaryPart

	if playerRoot then
		local lookTarget = playerRoot.Position * Vector3.new(1, 0, 1) + targetRoot.Position * Vector3.new(0, 1, 0)
		targetParent:SetPrimaryPartCFrame(CFrame.lookAt(targetRoot.Position, lookTarget))
	end

	for _, track in pairs(humanoid:GetPlayingAnimationTracks()) do
		track:Stop()
	end

	local bodyVelocity = Instance.new("BodyVelocity")
	bodyVelocity.MaxForce = Vector3.new(10000, 10000, 10000)
	bodyVelocity.P = 1250
	bodyVelocity.Velocity = player.Character.HumanoidRootPart.CFrame.LookVector * 60 + Vector3.new(0, 5, 0)
	bodyVelocity.Parent = targetRoot
	debris:AddItem(bodyVelocity, 1)

	targetParent:AddTag("KnockedBack")

	task.wait()
	local beenHitAnim = humanoid:LoadAnimation(script.Knockback)
	beenHitAnim:Play()

	task.spawn(function()
		beenHitAnim.Ended:Wait()
		targetParent:RemoveTag("KnockedBack")
	end)
end)

blockEvent.OnServerEvent:Connect(function(player, isReleasing)
	local character = player.Character
	if not character then return end

	if isReleasing then
		if character:HasTag("Blocking") then
			character:RemoveTag("Blocking")
		end
	else
		if not character:HasTag("Blocking") then
			character:AddTag("Blocking")
		end
	end
end)

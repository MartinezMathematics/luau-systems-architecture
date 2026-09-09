--!strict
-- Module: EnvironmentalFXService.luau
-- Author: Hector Martinez
-- Architecture: Procedural Environmental VFX & Spatial Geometry Generator
-- Engine: Roblox Engine (Luau)
--
-- Core Subsystems:
--   1. Polar-to-Cartesian Coordinate Ring Generation:
--      - Maps discrete angular intervals (360/n) to parametric Cartesian positions:
--        x = r * cos(theta), z = r * sin(theta) across multi-tiered radial shells.
--   2. Procedural Surface Detection:
--      - Sweeps downward vertical raycasts from height offsets to detect terrain elevation,
--        surface normals, and material/color properties.
--   3. Kinematic Tween Interpolation:
--      - Manages cubic entry/exit easing transitions for dynamically spawned environmental geometry.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local function createSoundEffect(root, pos)
	local SFX1 = Instance.new("Sound")
	SFX1.SoundId = "rbxassetid://6246215379"
	SFX1.Volume = 2
	SFX1.RollOffMaxDistance = 1000
	SFX1.RollOffMinDistance = 15
	SFX1.Parent = workspace
	SFX1:Play()
	Debris:AddItem(SFX1, 5)
end

local function handleVFX(VFX, pos, root)
	VFX.Parent = workspace.IgnoreFolder
	VFX:SetPrimaryPartCFrame(CFrame.new(pos - Vector3.new(0, 3, 0)))

	for _, v in pairs(VFX:GetDescendants()) do
		if v:IsA("ParticleEmitter") and not v.Parent:IsA("Attachment") then
			v.Enabled = false
		end
	end

	for _, v in pairs(VFX:GetDescendants()) do
		if v:IsA("ParticleEmitter") then
			if v.Name ~= "Rocks" then
				v.Enabled = true
			else
				local rayOrigin = pos + Vector3.new(0, 500, 0)
				local rayDirection = Vector3.new(0, -1000, 0)
				local raycastParams = RaycastParams.new()
				raycastParams.FilterDescendantsInstances = {root.Parent, workspace.IgnoreFolder}
				raycastParams.FilterType = Enum.RaycastFilterType.Exclude

				local raycastResult = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
				if raycastResult then
					v.Color = ColorSequence.new(raycastResult.Instance.Color, raycastResult.Instance.Color)
					v.Enabled = false
					task.spawn(function()
						task.wait()
						v:Emit(500)
					end)
				end
			end
		end
	end

	for _, v in pairs(VFX:GetDescendants()) do
		if v:IsA("ParticleEmitter") and v.Parent:IsA("Attachment") then
			task.spawn(function()
				task.wait()
				v:Emit(1)
			end)
		end
	end
end

local function createCircle(pos)
	local rows = {
		{radius = 15, parts = 15},
		{radius = 30, parts = 30},
		{radius = 45, parts = 50}
	}

	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = {workspace.IgnoreFolder}
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	for _, row in ipairs(rows) do
		for i = 1, row.parts do
			local angle = math.rad((i - 1) * (360 / row.parts))
			local offset = Vector3.new(math.random(-2, 2), 0, math.random(-2, 2))
			local x = (row.radius + offset.X) * math.cos(angle)
			local z = (row.radius + offset.Z) * math.sin(angle)
			local position = pos + Vector3.new(x, 0, z)
			local rayOrigin = position + Vector3.new(0, 500, 0)
			local rayDirection = Vector3.new(0, -1000, 0)

			local raycastResult = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
			if raycastResult then
				local floorPosition = raycastResult.Position - Vector3.new(0, 2, 0)
				local floorInstance = raycastResult.Instance

				local part = Instance.new("Part")
				part.Size = Vector3.new(math.random(6, 7), math.random(3, 5), math.random(3, 5))
				part.Anchored = true
				part.CanCollide = false
				part.BrickColor = floorInstance.BrickColor
				part.Material = floorInstance.Material
				part.Transparency = floorInstance.Transparency
				part.Parent = workspace.IgnoreFolder

				part.CFrame = CFrame.new(floorPosition - Vector3.new(0, part.Size.Y, 0), pos)
				local targetCFrame = CFrame.new(floorPosition + Vector3.new(0, part.Size.Y / 2, 0) + Vector3.new(0, 1, 0), pos + Vector3.new(0, 6, 0))
				local tweenInfo = TweenInfo.new(0.1, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out, 0, false, 0)
				local tweenOut = TweenService:Create(part, tweenInfo, {CFrame = targetCFrame})
				local tweenBackInfo = TweenInfo.new(2.5, Enum.EasingStyle.Cubic, Enum.EasingDirection.In, 0, false, 1)
				local targetBackCFrame = CFrame.new(floorPosition - Vector3.new(0, part.Size.Y, 0), pos)
				local tweenBack = TweenService:Create(part, tweenBackInfo, {CFrame = targetBackCFrame})

				local sphere = Instance.new("Part")
				sphere.Shape = Enum.PartType.Ball
				sphere.Anchored = true
				sphere.CanCollide = false
				sphere.Color = Color3.new(0.717647, 0.435294, 1)
				sphere.Material = Enum.Material.Neon
				sphere.Transparency = 0.985
				sphere.Size = Vector3.new(1, 1, 1)
				sphere.CFrame = CFrame.new(pos)
				sphere.Parent = workspace.IgnoreFolder

				local growTweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
				local shrinkTweenInfo = TweenInfo.new(2, Enum.EasingStyle.Exponential, Enum.EasingDirection.In)
				local growTween = TweenService:Create(sphere, growTweenInfo, {Size = Vector3.new(50, 50, 50)})
				local shrinkTween = TweenService:Create(sphere, shrinkTweenInfo, {Size = Vector3.new(0, 0, 0)})

				growTween:Play()
				growTween.Completed:Connect(function()
					shrinkTween:Play()
				end)
				shrinkTween.Completed:Connect(function()
					sphere:Destroy()
				end)

				tweenOut:Play()
				tweenOut.Completed:Connect(function()
					tweenBack:Play()
				end)

				Debris:AddItem(part, 12)
			end
		end
		task.wait(0.1)
	end
end

local function onTransformFired(player, root, pos)
	createSoundEffect(root, pos)

	local VFX = ReplicatedStorage.SpeedCore.VFX.ElectricBoom:Clone()
	handleVFX(VFX, pos, root)

	createCircle(pos)

	task.wait(2.25)
	for _, v in pairs(VFX:GetDescendants()) do
		if v:IsA("ParticleEmitter") then
			v.Enabled = false
		end
	end
end

ReplicatedStorage.SpeedCore.TransformEvent.OnServerEvent:Connect(onTransformFired)

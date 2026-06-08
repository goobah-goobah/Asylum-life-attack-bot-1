local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

local COME_HERE_PHRASE = "come"
local FOLLOW_PHRASE = "follow"
local STOP_PHRASE = "stop"
local JUMP_PHRASE = "jump"

local START_AUTO_DEFEND_PHRASE = "auto defend"
local STOP_AUTO_DEFEND_PHRASE = "stop auto defending"
local AUTO_DEFEND_TARGET = "Put ur user ig here"

local START_RAGE_PHRASE = "rage mode"
local STOP_RAGE_PHRASE = "stop rage"

local SPEED_COIL_NAME = "Patient Banner"
local WEAPON_PRIORITY = {"Metal Shard", "Glass Shard", "Glass Fragment", "Fists", "Door & Glass Shard"}

local DEFEND_DETECTION_RANGE = 12    
local AUTO_DEFEND_RANGE = 5          
local MAX_DEFENSE_TETHER_RANGE = 20  
local COMBAT_ENGAGE_RANGE = 12       

local ROTATION_SMOOTHNESS = 0.35 
local ATTACK_COOLDOWN = 0.55 

local isFollowing = false
local isAttacking = false
local isDefending = false          
local isAutoDefending = false 
local isRaging = false 
local currentTargetPlayer = nil    
local angle = 0 
local lastJumpTime = 0 
local orbitDirection = 1 
local lastAttackTime = 0
local lastHealth = 100
local lastTargetHealth = 100 

local currentWaypoints = {}
local currentWaypointIndex = 1
local isComputingPath = false
local lastPathTime = 0
local targetHealthConnection = nil
local nextRandomJumpTime = 0 

local function sayInChat(text)
    task.spawn(function()
        pcall(function()
            StarterGui:SetCore("ChatMakeSystemMessage", {
                Text = "[Client Bot] " .. text,
                Color = Color3.fromRGB(255, 100, 255),
                Font = Enum.Font.SourceSansBold,
                TextSize = 18
            })
        end)
    end)
end

local function getRootAndHumanoid(player)
    if not player then return nil, nil end
    local char = player.Character
    if not char then return nil, nil end
    
    local root = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChildWhichIsA("BasePart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    
    return root, hum
end

local function equipItemByName(itemName)
    local character = LocalPlayer.Character
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if not character or not backpack then return false end
    
    local _, humanoid = getRootAndHumanoid(LocalPlayer)
    if not humanoid or humanoid.Health <= 0 then return false end
    
    local equippedTool = character:FindFirstChildOfClass("Tool")
    if equippedTool and equippedTool.Name == itemName then return true end
    
    local targetTool = backpack:FindFirstChild(itemName)
    if targetTool and targetTool:IsA("Tool") then
        humanoid:EquipTool(targetTool)
        return true
    end
    return false
end

local function equipBestWeapon()
    for _, weaponName in ipairs(WEAPON_PRIORITY) do
        if equipItemByName(weaponName) then return true end
    end
    return false
end

local function forceJump()
    local _, humanoid = getRootAndHumanoid(LocalPlayer)
    if humanoid and humanoid:GetState() ~= Enum.HumanoidStateType.Jumping and humanoid:GetState() ~= Enum.HumanoidStateType.Freefall then
        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        lastJumpTime = os.clock()
    end
end

local function shouldAllowJumping(myRoot, targetRoot)
    if not myRoot or not targetRoot then return false end
    
    if myRoot.Position.Y > targetRoot.Position.Y + 2.5 then
        return false
    end
    
    local character = LocalPlayer.Character
    if character then
        local equippedTool = character:FindFirstChildOfClass("Tool")
        if equippedTool and equippedTool.Name == "Fists" then
            return false
        end
    end
    
    return true
end

local function findClosestPlayerWithinRange(range)
    local myRoot = getRootAndHumanoid(LocalPlayer)
    if not myRoot then return nil end
    local myPos = myRoot.Position
    
    local closestPlayer, shortestDistance = nil, range
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local root, hum = getRootAndHumanoid(player)
            if root and hum and hum.Health > 0 then
                local dist = (root.Position - myPos).Magnitude
                if dist < shortestDistance then
                    shortestDistance = dist
                    closestPlayer = player
                end
            end
        end
    end
    return closestPlayer
end

local function stopMovement()
    isFollowing = false
    isAttacking = false
    isDefending = false
    isRaging = false 
    currentTargetPlayer = nil
    currentWaypoints = {}
    currentWaypointIndex = 1
    
    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game)
    
    local myRoot, humanoid = getRootAndHumanoid(LocalPlayer)
    if humanoid and myRoot then 
        humanoid:MoveTo(myRoot.Position) 
    end
end

local function checkLineOfSight(startPos, endPos, characterToIgnore)
    local raycastParams = RaycastParams.new()
    raycastParams.FilterDescendantsInstances = {LocalPlayer.Character, characterToIgnore, workspace.CurrentCamera}
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    
    local direction = (endPos - startPos)
    local result = workspace:Raycast(startPos, direction, raycastParams)
    return result == nil
end

local function computeNewPath(startPos, endPos)
    if isComputingPath or (os.clock() - lastPathTime < 0.4) then return end
    isComputingPath = true
    lastPathTime = os.clock()
    
    task.spawn(function()
        local path = PathfindingService:CreatePath({
            AgentRadius = 2.0,
            AgentHeight = 5.0,
            AgentCanJump = true,
            WaypointSpacing = 4
        })
        
        local success, _ = pcall(function() path:ComputeAsync(startPos, endPos) end)
        if success and path.Status == Enum.PathStatus.Success then
            currentWaypoints = path:GetWaypoints()
            currentWaypointIndex = 1
        else
            currentWaypoints = {{Position = endPos, Action = Enum.PathWaypointAction.Walk}}
            currentWaypointIndex = 1
        end
        isComputingPath = false
    end)
end

local function executeAttackThenJumpSequence(myRoot, targetRoot)
    lastAttackTime = os.clock()
    
    local character = LocalPlayer.Character
    if character then
        local tool = character:FindFirstChildOfClass("Tool")
        if tool then
            tool:Activate()
        else
            VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
            task.wait(0.01)
            VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
        end
    end
    
    task.wait(0.03)
    if shouldAllowJumping(myRoot, targetRoot) and math.random() > 0.45 then
        forceJump()
    end
end

local function findThreatToDefendedPlayer(defendedPlayer)
    local defendedRoot = getRootAndHumanoid(defendedPlayer)
    if not defendedRoot then return nil end
    local defendedPos = defendedRoot.Position
    
    local closestThreat, shortestDistance = nil, DEFEND_DETECTION_RANGE
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player ~= defendedPlayer then
            local root, hum = getRootAndHumanoid(player)
            if root and hum and hum.Health > 0 then
                local distance = (root.Position - defendedPos).Magnitude
                if distance < shortestDistance then
                    shortestDistance = distance
                    closestThreat = player
                end
            end
        end
    end
    return closestThreat
end

local function setupSprintAutomation(humanoid)
    local isSprinting = false
    humanoid:GetPropertyChangedSignal("MoveDirection"):Connect(function()
        local isMoving = humanoid.MoveDirection.Magnitude > 0.1
        local shouldSprint = (isFollowing or isAttacking or isDefending or isRaging) and isMoving
        
        if shouldSprint and not isSprinting then
            isSprinting = true
            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.LeftShift, false, game)
        elseif not shouldSprint and isSprinting then
            isSprinting = false
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game)
        end
    end)
end

local function followPathLogic(humanoid, myPosition, targetPosition)
    if #currentWaypoints == 0 or currentWaypointIndex > #currentWaypoints then
        computeNewPath(myPosition, targetPosition)
    end

    if #currentWaypoints > 0 and currentWaypointIndex <= #currentWaypoints then
        local nextWaypoint = currentWaypoints[currentWaypointIndex]
        local wpPos = nextWaypoint.Position
        
        humanoid:MoveTo(wpPos)
        
        if nextWaypoint.Action == Enum.PathWaypointAction.Jump and os.clock() - lastJumpTime > 0.5 then
            forceJump()
        end
        
        if (myPosition - wpPos).Magnitude < 4 then
            currentWaypointIndex = currentWaypointIndex + 1
        end
    else
        humanoid:MoveTo(targetPosition)
    end
end

local function startTrackingLoop()
    task.spawn(function()
        orbitDirection = 1 
        local stuckDuration = 0
        nextRandomJumpTime = os.clock() + (math.random(4, 12) / 10)
        
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.LeftShift, false, game)
        
        while (isFollowing or isAttacking or isDefending or isRaging) and currentTargetPlayer do
            local deltaTime = task.wait(0.015)
            
            local myRoot, humanoid = getRootAndHumanoid(LocalPlayer)
            local targetRoot, targetHum = getRootAndHumanoid(currentTargetPlayer)
            
            if isAttacking and (not targetHum or targetHum.Health <= 0) then
                if isRaging then
                    local nextVictim = findClosestPlayerWithinRange(9999)
                    if nextVictim then
                        currentTargetPlayer = nextVictim
                        targetRoot, targetHum = getRootAndHumanoid(nextVictim)
                        sayInChat("Target eliminated. Next target acquired: " .. nextVictim.Name)
                    else
                        stopMovement()
                        sayInChat("Rage cycle complete. No targets left on server.")
                        break
                    end
                else
                    stopMovement()
                    sayInChat("Target neutralized.")
                    break
                end
            end

            if myRoot and humanoid and targetRoot and targetHum and targetHum.Health > 0 then
                local myPosition = myRoot.Position
                local targetPosition = targetRoot.Position
                local distanceToTarget = (myPosition - targetPosition).Magnitude
                local isReadyToAttack = (os.clock() - lastAttackTime) >= ATTACK_COOLDOWN
                local hasLineOfSight = checkLineOfSight(myPosition, targetPosition, currentTargetPlayer.Character)

                VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.LeftShift, false, game)

                if os.clock() > nextRandomJumpTime then
                    if shouldAllowJumping(myRoot, targetRoot) then
                        forceJump()
                    end
                    nextRandomJumpTime = os.clock() + (math.random(5, 16) / 10)
                end

                local strafeWeave = math.sin(os.clock() * 6.5) * 1.35

                if isDefending and not isRaging then
                    local behindOffset = -targetRoot.CFrame.LookVector * 3.5
                    local absoluteBehindPosition = targetPosition + behindOffset
                    
                    local activeThreat = findThreatToDefendedPlayer(currentTargetPlayer)
                    local threatRoot, threatHum = getRootAndHumanoid(activeThreat)
                    
                    if threatRoot and threatHum and (threatRoot.Position - targetPosition).Magnitude <= MAX_DEFENSE_TETHER_RANGE and distanceToTarget <= MAX_DEFENSE_TETHER_RANGE then
                        local threatPosition = threatRoot.Position
                        local distanceToThreat = (myPosition - threatPosition).Magnitude
                        
                        myRoot.CFrame = myRoot.CFrame:Lerp(CFrame.lookAt(myPosition, Vector3.new(threatPosition.X, myPosition.Y, threatPosition.Z)), ROTATION_SMOOTHNESS)
                        
                        if checkLineOfSight(myPosition, threatPosition, activeThreat.Character) and distanceToThreat < 12 then
                            currentWaypoints = {}
                            equipBestWeapon()
                            
                            if distanceToThreat <= 5.5 then
                                angle = angle + ((6.28 * deltaTime * 0.95) * orbitDirection)
                                local dynamicThreatTrack = threatPosition + Vector3.new(math.cos(angle) * (3.2 + strafeWeave), 0, math.sin(angle) * (3.2 + strafeWeave))
                                humanoid:MoveTo(dynamicThreatTrack)
                                
                                if isReadyToAttack then 
                                    executeAttackThenJumpSequence(myRoot, threatRoot)
                                end
                            else
                                humanoid:MoveTo(absoluteBehindPosition)
                            end
                        else
                            equipItemByName(SPEED_COIL_NAME)
                            followPathLogic(humanoid, myPosition, absoluteBehindPosition)
                        end
                    else
                        myRoot.CFrame = myRoot.CFrame:Lerp(CFrame.lookAt(myPosition, myPosition + targetRoot.CFrame.LookVector), ROTATION_SMOOTHNESS)
                        equipItemByName(SPEED_COIL_NAME)
                        
                        if (myPosition - absoluteBehindPosition).Magnitude > 2 then
                            followPathLogic(humanoid, myPosition, absoluteBehindPosition)
                        else
                            currentWaypoints = {}
                            humanoid:MoveTo(myPosition)
                        end
                    end

                elseif isAttacking or isRaging then
                    myRoot.CFrame = myRoot.CFrame:Lerp(CFrame.lookAt(myPosition, Vector3.new(targetPosition.X, myPosition.Y, targetPosition.Z)), ROTATION_SMOOTHNESS)
                    
                    local engageRange = isRaging and 9999 or COMBAT_ENGAGE_RANGE
                    
                    if hasLineOfSight and distanceToTarget < engageRange then
                        currentWaypoints = {}
                        equipBestWeapon()
                        
                        if distanceToTarget <= 6 then
                            angle = angle + ((6.28 * deltaTime * 0.95) * orbitDirection)
                            
                            local optimalDistance = distanceToTarget > 5 and 3.5 or 2.8
                            local combatOrbitPoint = targetPosition + Vector3.new(math.cos(angle) * (optimalDistance + strafeWeave), 0, math.sin(angle) * (optimalDistance + strafeWeave))
                            humanoid:MoveTo(combatOrbitPoint)
                            
                            if isReadyToAttack then
                                executeAttackThenJumpSequence(myRoot, targetRoot)
                            end
                        else
                            local rawVelocity = targetRoot.Velocity
                            local targetVelocity = Vector3.new(rawVelocity.X, 0, rawVelocity.Z)
                            local leadMultiplier = 0.2
                            
                            if targetVelocity.Magnitude < 1 then
                                leadMultiplier = 0
                            end
                            
                            local interceptPoint = targetPosition + (targetVelocity * leadMultiplier)
                            humanoid:MoveTo(interceptPoint)
                        end
                    else
                        equipItemByName(SPEED_COIL_NAME)
                        followPathLogic(humanoid, myPosition, targetPosition)
                    end

                elseif isFollowing then
                    myRoot.CFrame = myRoot.CFrame:Lerp(CFrame.lookAt(myPosition, Vector3.new(targetPosition.X, myPosition.Y, targetPosition.Z)), ROTATION_SMOOTHNESS)
                    equipItemByName(SPEED_COIL_NAME)
                    
                    if distanceToTarget > 5 then
                        if hasLineOfSight then
                            currentWaypoints = {}
                            humanoid:MoveTo(targetPosition)
                        else
                            followPathLogic(humanoid, myPosition, targetPosition)
                        end
                    else
                        currentWaypoints = {}
                        humanoid:MoveTo(myPosition)
                    end
                end

                if humanoid.MoveDirection.Magnitude > 0.1 then
                    local horizontalSpeed = Vector3.new(myRoot.AssemblyLinearVelocity.X, 0, myRoot.AssemblyLinearVelocity.Z).Magnitude
                    if horizontalSpeed < 3 then
                        stuckDuration = stuckDuration + deltaTime
                        if stuckDuration >= 0.12 then 
                            forceJump()
                            stuckDuration = 0
                            currentWaypoints = {}
                        end
                    else
                        stuckDuration = 0
                    end
                end
            else
                task.wait(0.1)
            end
        end
    end)
end

local function monitorSteveHealth(player)
    if player.Name:lower() ~= AUTO_DEFEND_TARGET:lower() then return end
    if targetHealthConnection then targetHealthConnection:Disconnect() end
    
    local function hookHumanoid(char)
        local humanoid = char:WaitForChild("Humanoid", 5)
        if humanoid then
            lastTargetHealth = humanoid.Health
            targetHealthConnection = humanoid.HealthChanged:Connect(function(currentHealth)
                if isAutoDefending and currentHealth < lastTargetHealth and not isAttacking and not isRaging then
                    local threat = findThreatToDefendedPlayer(player)
                    if threat then
                        stopMovement()
                        isAttacking = true
                        currentTargetPlayer = threat
                        sayInChat("Defending " .. player.Name .. "! Engaging threat: " .. threat.Name)
                        startTrackingLoop()
                    end
                end
                lastTargetHealth = currentHealth
            end)
        end
    end
    
    if player.Character then hookHumanoid(player.Character) end
    player.CharacterAdded:Connect(hookHumanoid)
end

local function setupCharacterConnections(character)
    local humanoid = character:WaitForChild("Humanoid", 5)
    if humanoid then
        setupSprintAutomation(humanoid)
        lastHealth = humanoid.Health
        humanoid.HealthChanged:Connect(function(currentHealth)
            if currentHealth < lastHealth and not isAttacking and not isDefending and not isRaging then
                local threat = findClosestPlayerWithinRange(AUTO_DEFEND_RANGE)
                if threat then
                    stopMovement()
                    isAttacking = true
                    currentTargetPlayer = threat
                    sayInChat("Engaging counter-measures: " .. threat.Name)
                    startTrackingLoop()
                end
            end
            lastHealth = currentHealth
        end)
    end
end

if LocalPlayer.Character then setupCharacterConnections(LocalPlayer.Character) end
LocalPlayer.CharacterAdded:Connect(setupCharacterConnections)

for _, p in ipairs(Players:GetPlayers()) do monitorSteveHealth(p) end
Players.PlayerAdded:Connect(monitorSteveHealth)

local function findPlayerByUsername(name)
    local lowerName = string.lower(name)
    for _, player in ipairs(Players:GetPlayers()) do
        if string.sub(string.lower(player.Name), 1, #lowerName) == lowerName or string.sub(string.lower(player.DisplayName), 1, #lowerName) == lowerName then
            return player
        end
    end
    return nil
end

local function processChatMessage(player, message)
    if player == LocalPlayer then return end
    local cleanedMessage = string.lower(message)
    
    if cleanedMessage == string.lower(START_RAGE_PHRASE) then
        stopMovement()
        isRaging = true
        isAttacking = true
        local initialVictim = findClosestPlayerWithinRange(9999)
        if initialVictim then
            currentTargetPlayer = initialVictim
            sayInChat("RAGE MODE ACTIVE. Lock-on: " .. initialVictim.Name)
            startTrackingLoop()
        else
            sayInChat("Rage mode initialization failed: Server empty.")
        end
    elseif cleanedMessage == string.lower(STOP_RAGE_PHRASE) then
        stopMovement()
        sayInChat("Rage mode disabled.")
    elseif cleanedMessage == string.lower(START_AUTO_DEFEND_PHRASE) then
        isAutoDefending = true
        sayInChat("Auto-Defend mode toggled ON for therealsteve777.")
    elseif cleanedMessage == string.lower(STOP_AUTO_DEFEND_PHRASE) then
        isAutoDefending = false
        stopMovement()
        sayInChat("Auto-Defend mode toggled OFF.")
    elseif cleanedMessage == string.lower(STOP_PHRASE) then
        stopMovement()
        sayInChat("Bot paused.")
    elseif cleanedMessage == string.lower(JUMP_PHRASE) then
        forceJump()
    elseif cleanedMessage == string.lower(COME_HERE_PHRASE) or cleanedMessage == string.lower(FOLLOW_PHRASE) then
        stopMovement()
        isFollowing = true
        currentTargetPlayer = player
        sayInChat("Following " .. player.Name)
        startTrackingLoop()
    else
        local defendNameMatch = string.match(cleanedMessage, "^defend%s+(.+)$")
        if defendNameMatch then
            local targetPlayer = findPlayerByUsername(defendNameMatch)
            if targetPlayer then
                stopMovement()
                isDefending = true
                currentTargetPlayer = targetPlayer
                sayInChat("Protecting " .. targetPlayer.Name)
                startTrackingLoop()
            end
        else
            local targetNameMatch = string.match(cleanedMessage, "^attack%s+(.+)$")
            if targetNameMatch then
                local targetPlayer = findPlayerByUsername(targetNameMatch)
                if targetPlayer and targetPlayer ~= LocalPlayer then
                    stopMovement()
                    isAttacking = true
                    currentTargetPlayer = targetPlayer
                    sayInChat("Hunting down: " .. targetPlayer.Name)
                    startTrackingLoop()
                end
            end
        end
    end
end

local function hookChannel(channel)
    if channel:IsA("TextChannel") then
        channel.MessageReceived:Connect(function(msg)
            if msg.TextSource then
                local p = Players:GetPlayerByUserId(msg.TextSource.UserId)
                if p then processChatMessage(p, msg.Text) end
            end
        end)
    end
end

task.spawn(function()
    pcall(function()
        TextChatService.TextChannels.ChildAdded:Connect(hookChannel)
        for _, channel in ipairs(TextChatService.TextChannels:GetChildren()) do
            hookChannel(channel)
        end
    end)
end)

Players.PlayerAdded:Connect(function(p)
    p.Chatted:Connect(function(m) processChatMessage(p, m) end)
end)
for _, p in ipairs(Players:GetPlayers()) do
    p.Chatted:Connect(function(m) processChatMessage(p, m) end)
end

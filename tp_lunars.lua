-- ==========================================================
-- SECURITE : REJET DE TOUTE NOUVELLE EXECUTION
-- ==========================================================
if _G.ScriptsAlreadyRunning then
    warn("[X] REFUSE : Le script est deja actif. Inutile de le relancer !")
    return
end

_G.ScriptsAlreadyRunning = true
print("[OK] Premier lancement : Initialisation des scripts...")

local VirtualInputManager = game:GetService("VirtualInputManager")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local rootPart = character:WaitForChild("HumanoidRootPart")
local humanoid = character:WaitForChild("Humanoid")

-- Variables farming
local following = false
local mobToFollow = nil
local lastPosition = rootPart.Position
local stuckTimer = 0
local killCount = 0

-- Connexions
local steppedConn = nil
local renderConn = nil

-- ==========================================================
-- UTILITAIRES
-- ==========================================================

local function pressKey(keyCode)
    VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
    task.wait(0.05)
    VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
end

-- Appuie sur 2 au tout debut
pressKey(Enum.KeyCode.Two)

-- Spam touche V
task.spawn(function()
    while true do
        pressKey(Enum.KeyCode.V)
        task.wait(0.5)
    end
end)

-- ==========================================================
-- AUTO FORCE START PARTY
-- ==========================================================

local PartyRF = ReplicatedStorage.ReplicatedStorage.Packages.Knit.Services.PartyService.RF

task.spawn(function()
    while true do
        local partyData = PartyRF.GetPartyFromPlayer:InvokeServer(player)

        if partyData and typeof(partyData) == "table" then
            local uuid = partyData.Data and partyData.Data.UUID or partyData.UUID

            if uuid and (not partyData.Data or partyData.Data.PartyStarted == false) then
                pcall(function()
                    PartyRF.ConvertUUIDToJSON:InvokeServer(uuid)
                    PartyRF.StartParty:InvokeServer(uuid)
                end)

                break
            end
        end

        task.wait(0.1)
    end
end)

-- ==========================================================
-- AUTO CLICK BOUTONS
-- ==========================================================

local function clickButton(btn)
    local inset = GuiService:GetGuiInset()
    local pos = btn.AbsolutePosition
    local size = btn.AbsoluteSize

    local x = pos.X + size.X / 2
    local y = pos.Y + size.Y / 2 + inset.Y

    VirtualInputManager:SendMouseMoveEvent(x, y, game)

    task.wait(0.01)

    VirtualInputManager:SendMouseButtonEvent(
        x, y, 0, true, game, 0
    )

    task.wait(0.01)

    VirtualInputManager:SendMouseButtonEvent(
        x, y, 0, false, game, 0
    )
end

task.spawn(function()
    while true do
        local playerGui = player:FindFirstChild("PlayerGui")

        if playerGui then
            pcall(function()
                local retryBtn = playerGui:FindFirstChild("RetryBtn", true)

                if retryBtn and retryBtn:IsA("GuiButton") then
                    clickButton(retryBtn)
                end
            end)
        end

        pcall(function()
            ReplicatedStorage:WaitForChild("ReplicatedStorage")
                :WaitForChild("Packages")
                :WaitForChild("Knit")
                :WaitForChild("Services")
                :WaitForChild("DungeonService")
                :WaitForChild("RF")
                :WaitForChild("StartDungeon")
                :InvokeServer()
        end)

        task.wait(0.5)
    end
end)

-- ==========================================================
-- AUTO COLLECT LUNAR SHARD via DropsService
-- ==========================================================

local DropsRF =
    ReplicatedStorage.ReplicatedStorage.Packages.Knit.Services.DropsService.RF

local DropCreatedSignal =
    ReplicatedStorage.ReplicatedStorage.Packages.Knit.Services.DropsService.RE.DropCreatedSignal

local TARGET_ITEMS = {
    ["Lunar Shard"] = true,
}

DropCreatedSignal.OnClientEvent:Connect(function(
    uuid,
    dropType,
    itemName,
    x,
    y,
    z,
    dropData
)
    if TARGET_ITEMS[itemName] then
        print("[GEM] " .. itemName .. " detecte ! Collecte automatique...")

        task.wait(0.1)

        local success, result = pcall(function()
            return DropsRF.CollectDrop:InvokeServer(
                uuid,
                dropData
            )
        end)

        if success then
            print("[OK] " .. itemName .. " collecte !")
        else
            print("[ERR] Echec collecte :", result)
        end
    end
end)

print("[SCAN] Auto-collect Lunar Shard actif !")

-- ==========================================================
-- FARMING MOBS
-- ==========================================================

local function getClosestMob()
    local closestMob = nil
    local closestDistance = math.huge

    for _, mob in pairs(workspace.Mobs:GetChildren()) do
        if mob:FindFirstChild("Humanoid")
            and mob:FindFirstChild("HumanoidRootPart")
            and mob.Humanoid.Health > 0 then

            local distance =
                (rootPart.Position - mob.HumanoidRootPart.Position).Magnitude

            if distance < closestDistance then
                closestDistance = distance
                closestMob = mob
            end
        end
    end

    return closestMob
end

local function moveTowardsMob()
    if mobToFollow
        and mobToFollow:FindFirstChild("HumanoidRootPart")
        and mobToFollow:FindFirstChild("Humanoid")
        and mobToFollow.Humanoid.Health > 0 then

        local mobPos = mobToFollow.HumanoidRootPart.Position
        local distance = (mobPos - rootPart.Position).Magnitude

        if distance > 3 then
            local randomOffset = Vector3.new(
                math.random(-1, 1),
                0,
                math.random(-1, 1)
            )

            local targetPos = mobPos + randomOffset

            rootPart.CFrame =
                rootPart.CFrame:lerp(
                    CFrame.new(targetPos),
                    0.9
                )
        else
            local direction = (mobPos - rootPart.Position).Unit

            local targetPos =
                mobPos - direction * 0.2

            rootPart.CFrame =
                rootPart.CFrame:lerp(
                    CFrame.new(targetPos),
                    0.18
                )
        end
    else
        following = false
        mobToFollow = nil
    end
end

-- ==========================================================
-- TP ANTI-BLOCAGE : 1 A 3 STUDS DE L'ENNEMI
-- ==========================================================

local function teleportIfStuck()
    if (rootPart.Position - lastPosition).Magnitude < 0.1 then
        stuckTimer = stuckTimer + 1

        if stuckTimer >= 10 then
            if mobToFollow
                and mobToFollow:FindFirstChild("HumanoidRootPart")
                and mobToFollow:FindFirstChild("Humanoid")
                and mobToFollow.Humanoid.Health > 0 then

                local mobPos =
                    mobToFollow.HumanoidRootPart.Position

                -- Direction aleatoire autour de l'ennemi
                local offset = Vector3.new(
                    math.random(-100, 100) / 100,
                    0,
                    math.random(-100, 100) / 100
                )

                -- Evite un vecteur quasiment nul
                if offset.Magnitude < 0.1 then
                    offset = Vector3.new(1, 0, 0)
                end

                -- Distance aleatoire entre 1 et 3 studs
                local distance =
                    math.random(100, 300) / 100

                local targetPos =
                    mobPos + offset.Unit * distance

                rootPart.CFrame =
                    CFrame.new(targetPos)

                print(
                    "[TP] TP anti-blocage a "
                    .. string.format("%.2f", distance)
                    .. " studs de l'ennemi"
                )
            end

            stuckTimer = 0
        end
    else
        stuckTimer = 0
    end

    lastPosition = rootPart.Position
end

local function followMob()
    if not following then
        local mob = getClosestMob()

        if mob then
            mobToFollow = mob
            following = true
        end
    end

    moveTowardsMob()
end

-- ==========================================================
-- COMPTEUR DE KILLS
-- ==========================================================

workspace.Mobs.ChildRemoved:Connect(function(mob)
    if mob
        and mob:FindFirstChild("Humanoid")
        and mob.Humanoid.Health <= 0 then

        killCount = killCount + 1

        if killCount >= 10 then
            killCount = 0
            task.wait(2)
        end
    end
end)

-- ==========================================================
-- START FARMING
-- ==========================================================

local function startFarming()
    if steppedConn then
        steppedConn:Disconnect()
    end

    if renderConn then
        renderConn:Disconnect()
    end

    steppedConn = RunService.Stepped:Connect(function()
        for _, part in pairs(character:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end

        rootPart.Velocity = Vector3.new(0, 0, 0)
    end)

    renderConn = RunService.RenderStepped:Connect(function()
        followMob()
        teleportIfStuck()
    end)
end

-- ==========================================================
-- RECONNEXION APRES MORT
-- ==========================================================

player.CharacterAdded:Connect(function(newCharacter)
    character = newCharacter

    rootPart =
        character:WaitForChild("HumanoidRootPart")

    humanoid =
        character:WaitForChild("Humanoid")

    following = false
    mobToFollow = nil
    lastPosition = rootPart.Position
    stuckTimer = 0
    killCount = 0

    task.wait(2)

    startFarming()
end)

-- ==========================================================
-- LANCEMENT
-- ==========================================================

startFarming()

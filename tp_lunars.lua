-- ==========================================================
-- SECURITE : REJET DE TOUTE NOUVELLE EXECUTION
-- ==========================================================
-- Garde dediee : le hub remet _G.ScriptsAlreadyRunning a false
-- avant chaque lancement. Celle-ci n'est jamais reinitialisee.
if _G.TpLunarsInstance then
    warn("[X] Script deja actif - seconde instance annulee")
    return
end
_G.TpLunarsInstance = true

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

-- ==========================================================
-- ATTAQUE (reprise de farm_halloween) : 1 / F + CLIC GAUCHE / 2 / V C G
-- ==========================================================
task.spawn(function()
    local RUN_TIME = 9
    local F_DELAY = 0.1
    local CYCLE_DELAY = 0.1

    local function holdKey(keyCode, duration)
        VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
        task.wait(duration or 0.05)
        VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
    end

    -- clic gauche au centre de l'ecran (attaque de l'arme du slot 1)
    local function clickLeft()
        local cam = workspace.CurrentCamera
        local size = cam and cam.ViewportSize or Vector2.new(800, 600)
        local x, y = size.X / 2, size.Y / 2
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
        task.wait(0.03)
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
    end

    -- Demarrage apres 3 secondes
    task.wait(3)

    while true do
        -- 1
        holdKey(Enum.KeyCode.One, 0.1)

        -- spam F + clic gauche pendant 9 secondes (slot 1)
        local startTime = os.clock()
        while os.clock() - startTime < RUN_TIME do
            holdKey(Enum.KeyCode.F, 0.05)
            clickLeft()
            task.wait(F_DELAY)
        end

        -- 2
        holdKey(Enum.KeyCode.Two, 0.1)
        task.wait(CYCLE_DELAY)

        -- V / C / G
        holdKey(Enum.KeyCode.V)
        task.wait(0.1)
        holdKey(Enum.KeyCode.C)
        task.wait(0.1)
        holdKey(Enum.KeyCode.G)
        task.wait(CYCLE_DELAY)
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
-- COMPTEUR 5 MIN + 3 KILLS (repris de farm_infinite), EN BOUCLE
-- ==========================================================
-- Toutes les 5 minutes : 3 kills espaces de 7 s, puis le compteur repart.

task.spawn(function()
    local TIMER_MINUTES = 5
    local TIMER_SECONDS = TIMER_MINUTES * 60

    local KILL_COUNT = 3
    local KILL_DELAY = 7

    while true do
        print("... Compteur " .. TIMER_MINUTES .. " minutes demarre...")

        task.wait(TIMER_SECONDS)

        print(
            "[TIME] " .. TIMER_MINUTES .. " minutes ecoulees - debut des "
            .. KILL_COUNT
            .. " kills..."
        )

        for i = 1, KILL_COUNT do
            local char = player.Character

            if char then
                local hum = char:FindFirstChildOfClass("Humanoid")

                if hum then
                    print("[KILL] Kill " .. i .. "/" .. KILL_COUNT)

                    hum.Health = 0

                    task.wait(1)

                    pcall(function()
                        ReplicatedStorage
                            .ReplicatedStorage
                            .Packages
                            .Knit
                            .Services
                            .DungeonService
                            .RF
                            .Respawned
                            :InvokeServer()
                    end)
                end
            end

            if i < KILL_COUNT then
                print("... Attente " .. KILL_DELAY .. " secondes avant le prochain kill...")
                task.wait(KILL_DELAY)
            end
        end

        print("[OK] Sequence de kills terminee - nouveau compteur")
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

game:GetService("Players").LocalPlayer.AncestryChanged:Connect(function(_, parent)
    if not parent then
        _G.TpLunarsInstance = nil
    end
end)

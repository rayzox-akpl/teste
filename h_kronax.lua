-- ==========================================================
-- SECURITE : REJET DE TOUTE NOUVELLE EXECUTION
-- ==========================================================
-- Garde dediee : le hub remet _G.ScriptsAlreadyRunning a false
-- avant chaque lancement. Celle-ci n'est jamais reinitialisee.
if _G.KronaxInstance then
    warn("[X] Kronax tourne deja - seconde instance annulee")
    return
end
_G.KronaxInstance = true

if _G.ScriptsAlreadyRunning then
    warn(" REFUSE : Le script est deja actif. Inutile de le relancer !")
    return
end

_G.ScriptsAlreadyRunning = true
print(" Premier lancement : Initialisation des scripts...")

--====================================================
-- SERVICES
--====================================================

repeat task.wait() until game:IsLoaded()

local Players = game:GetService("Players")
local VirtualInputManager = game:GetService("VirtualInputManager")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
repeat task.wait() until player

--====================================================
-- AUTO SKIP CUTSCENE + TOUCHE H
-- Demarre 6s apres le lancement, 5 appels a 1s d'intervalle,
-- puis un appui sur H. skipFinished sert au demarrage du tir.
--====================================================

local skipFinished = false

local SKIP_DELAY = 6
local SKIP_COUNT = 5
local SKIP_INTERVAL = 1

task.spawn(function()
    task.wait(SKIP_DELAY)

    for i = 1, SKIP_COUNT do
        pcall(function()
            ReplicatedStorage.ReplicatedStorage.Packages.Knit.Services
                .DungeonService.RF.VoteSkipCutscene:InvokeServer()
        end)
        print("[SKIP] " .. i .. "/" .. SKIP_COUNT)

        if i < SKIP_COUNT then
            task.wait(SKIP_INTERVAL)
        end
    end

    -- H juste apres le dernier skip
    pcall(function()
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.H, false, game)
        task.wait(0.05)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.H, false, game)
    end)
    print("[SKIP] H appuye")

    skipFinished = true
end)

--====================================================
-- AUTO START DONJON
--====================================================

-- Dans un thread : ne bloque plus la suite du script
task.spawn(function()

task.wait(5)

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

end)

--====================================================
-- CHARACTER SETUP
--====================================================

local Camera = Workspace.CurrentCamera

local function getCharacter()
    local char = player.Character or player.CharacterAdded:Wait()
    return char, char:WaitForChild("Humanoid"), char:WaitForChild("HumanoidRootPart")
end

local character, hum, hrp = getCharacter()
hum.AutoRotate = false

player.CharacterAdded:Connect(function()
    character, hum, hrp = getCharacter()
    hum.AutoRotate = false
end)

--====================================================
-- CONFIG
--====================================================

local MOB_FOLDER = workspace:WaitForChild("Mobs")
local HEIGHT = 70
local DISTANCE_MOB = 40
local ROTATION_SPEED = 3
local SAFE_HEIGHT = 2000

local AUTO_CLICK = 1
local CLICK_INTERVAL = 0.1
local HOLD_DURATION = 10

--====================================================
-- VARIABLES
--====================================================

local angle = 0
local securityMode = false
local positionInitiale = nil
local lastHealth = hum.Health
local attackInProgress = false
local isSpamming = false

local hKeyPressed = false
local rKeyPressed = false

--====================================================
-- UTIL
--====================================================

local function stabilize()
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero
end

local function pressKey(key)
    VirtualInputManager:SendKeyEvent(true, key, false, game)
    task.wait(0.01)
    VirtualInputManager:SendKeyEvent(false, key, false, game)
end

local function clickCenter()
    local viewportSize = Camera.ViewportSize
    local centerX = viewportSize.X / 2
    local centerY = viewportSize.Y / 2
    VirtualInputManager:SendMouseButtonEvent(centerX, centerY, 0, true, game, 0)
    task.wait(0.01)
    VirtualInputManager:SendMouseButtonEvent(centerX, centerY, 0, false, game, 0)
end

local function holdMouseLeft(duration)
    local viewportSize = Camera.ViewportSize
    local centerX = viewportSize.X / 2
    local centerY = viewportSize.Y / 2
    VirtualInputManager:SendMouseButtonEvent(centerX, centerY, 0, true, game, 0)
    task.wait(duration)
    VirtualInputManager:SendMouseButtonEvent(centerX, centerY, 0, false, game, 0)
end

--====================================================
-- FLOAT SYSTEM
--====================================================

local function startFloat()
    if hrp:FindFirstChild("SafeFloat") then return end
    local bv = Instance.new("BodyVelocity")
    bv.Name = "SafeFloat"
    bv.Velocity = Vector3.zero
    bv.MaxForce = Vector3.new(0, math.huge, 0)
    bv.Parent = hrp
end

local function stopFloat()
    local bv = hrp:FindFirstChild("SafeFloat")
    if bv then bv:Destroy() end
end

--====================================================
-- MOB DETECTION
--====================================================

local function findMob()
    for _, mob in pairs(MOB_FOLDER:GetChildren()) do
        if mob:FindFirstChild("HumanoidRootPart")
        and mob:FindFirstChild("Humanoid")
        and mob.Humanoid.Health > 0 then
            return mob.HumanoidRootPart
        end
    end
    return nil
end

--====================================================
-- BOSSCRYSTAL DETECTION (cristaux ACTIFS uniquement)
-- Un cristal est ACTIF quand son BillboardGui (CrystalHealth)
-- passe en Enabled = true. On ne cible QUE ceux-la.
--====================================================

local lockedCrystalPart = nil
local detectedBillboards = {}
local focusEnabled = true  -- true = focus cristaux/shards | false = focus boss (toggle N)
local bossPart = nil

-- Toggle focus cristaux/boss avec la touche N
local UserInputService = game:GetService("UserInputService")
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if input.KeyCode == Enum.KeyCode.N then
        focusEnabled = not focusEnabled
        if not focusEnabled then
            lockedCrystalPart = nil
        end
        pcall(function()
            game:GetService("StarterGui"):SetCore("SendNotification", {
                Title = "Focus change",
                Text = focusEnabled and "CRISTAUX / SHARDS" or "BOSS",
                Duration = 2
            })
        end)
        print(focusEnabled and "Focus ON : CRISTAUX/SHARDS" or "Focus OFF : BOSS")
    end
end)

-- Detection du boss (via tag Boss + fallback HP eleve)
local function registerBoss(obj)
    if obj:IsA("Model") and obj:HasTag("Boss") then
        local part = obj:FindFirstChild("HumanoidRootPart")
            or obj:FindFirstChildWhichIsA("BasePart", true)
        if part then bossPart = part end
    end
end

local function findBossFallback()
    for _, obj in pairs(workspace:GetDescendants()) do
        if obj:IsA("Model") then
            local bossHum = obj:FindFirstChild("Humanoid")
            local bossHrp = obj:FindFirstChild("HumanoidRootPart")
            if bossHum and bossHrp and bossHum.Health > 0 and bossHum.MaxHealth > 100000 then
                return bossHrp
            end
        end
    end
    return nil
end

for _, obj in pairs(workspace:GetDescendants()) do
    registerBoss(obj)
end
workspace.DescendantAdded:Connect(function(obj)
    if obj:IsA("Model") and obj:HasTag("Boss") then
        task.wait(0.1)
        registerBoss(obj)
    end
end)

-- Verifie si un objet (ou un de ses parents) est un cristal
local function isCrystal(obj)
    while obj and obj ~= workspace do
        local lowerName = string.lower(obj.Name)
        if lowerName:find("crystal") or lowerName:find("shard") then
            return true
        end
        obj = obj.Parent
    end
    return false
end

-- Surveille les BillboardGui : quand un s'active sur un cristal -> on le locke
local function scanBillboards()
    for _, gui in pairs(Workspace:GetDescendants()) do
        if gui:IsA("BillboardGui") and not detectedBillboards[gui] then
            detectedBillboards[gui] = true
            gui:GetPropertyChangedSignal("Enabled"):Connect(function()
                if gui.Enabled then
                    local adornee = gui.Adornee or gui.Parent
                    if adornee and isCrystal(adornee) and adornee:IsA("BasePart") then
                        lockedCrystalPart = adornee
                    end
                end
            end)
        end
    end
end

scanBillboards()

Workspace.DescendantAdded:Connect(function(desc)
    if desc:IsA("BillboardGui") then
        task.wait(0.1)
        scanBillboards()
    end
end)

--====================================================
-- COMBAT MANUEL (attaques automatiques retirees)
--====================================================


--====================================================
-- AUTO HEAL
--====================================================

local function startSpamLoop()
    if isSpamming then return end
    isSpamming = true

    while hum.Health < hum.MaxHealth do
        task.spawn(pressKey, Enum.KeyCode.F)
        task.spawn(pressKey, Enum.KeyCode.G)
        task.spawn(pressKey, Enum.KeyCode.C)
        task.wait(0.05)
    end

    isSpamming = false
    securityMode = false
    stopFloat()
    stabilize()

    if positionInitiale then
        hrp.CFrame = positionInitiale
    end

    hum:ChangeState(Enum.HumanoidStateType.GettingUp)
    task.wait(0.1)
    -- Retour en position, plus d'appui de touches d'attaque (combat manuel)
end

--====================================================
-- HEALTH SYSTEM
--====================================================

hum.HealthChanged:Connect(function(newHealth)
    local ratio = newHealth / hum.MaxHealth

    if securityMode and newHealth < lastHealth then
        hum.Health = lastHealth
        return
    end

    lastHealth = newHealth

    if ratio <= 0.45 and newHealth > 0 and not securityMode then
        securityMode = true
        positionInitiale = hrp.CFrame
        hrp.CFrame = hrp.CFrame + Vector3.new(0, SAFE_HEIGHT, 0)
        stabilize()
        startFloat()
        hum:ChangeState(Enum.HumanoidStateType.Physics)

        task.spawn(startSpamLoop)
    end
end)

--====================================================
-- ORBIT SYSTEM
-- Touche N :
--   Focus ON  (defaut) : Cristal/Shard actif > Mob
--   Focus OFF          : Boss uniquement
--====================================================

RunService.RenderStepped:Connect(function(dt)
    if securityMode or attackInProgress then return end

    -- Si le cristal locke a disparu, on le libere
    if lockedCrystalPart and not lockedCrystalPart.Parent then
        lockedCrystalPart = nil
    end

    local targetPart = nil

    if focusEnabled then
        -- Focus ON : cristal/shard actif d'abord, sinon les mobs
        targetPart = lockedCrystalPart or findMob()
    else
        -- Focus OFF : le boss uniquement
        targetPart = bossPart or findBossFallback()
    end

    if targetPart and targetPart.Parent then
        angle += ROTATION_SPEED * dt

        local x = math.cos(angle) * DISTANCE_MOB
        local z = math.sin(angle) * DISTANCE_MOB

        local orbitPosition = Vector3.new(
            targetPart.Position.X + x,
            targetPart.Position.Y + HEIGHT,
            targetPart.Position.Z + z
        )

        hrp.CFrame = CFrame.new(orbitPosition, targetPart.Position)
        Camera.CFrame = CFrame.new(Camera.CFrame.Position, targetPart.Position)
        stabilize()
    end
end)

--====================================================
-- ATTACK DODGE
--====================================================

local DODGE_TIME = 3

workspace.DescendantAdded:Connect(function(obj)
    if obj.Name ~= "TDecayCharge" then return end
    if attackInProgress or securityMode then return end

    attackInProgress = true

    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "[!] Boss Attack",
            Text = "TDecayCharge detecte !",
            Duration = 3
        })
    end)

    hrp.CFrame = hrp.CFrame + Vector3.new(0, SAFE_HEIGHT, 0)
    stabilize()
    startFloat()

    task.delay(DODGE_TIME, function()
        stopFloat()
        local mobPart = findMob()
        if mobPart then
            hrp.CFrame = CFrame.new(
                mobPart.Position + Vector3.new(DISTANCE_MOB, HEIGHT, 0)
            )
            stabilize()
        end
        attackInProgress = false
    end)
end)

--====================================================
-- (AUTO CLICK LOOP retire : combat manuel)
--====================================================

--====================================================
-- TIR AUTO
-- Clic gauche maintenu. Relance :
--   - 1s apres le dernier skip cutscene
--   - 1s apres avoir pris des degats
--   - a la fin des 60s (limite de l'arme)
-- Le clic n'est jamais relache pendant un heal ou un dodge.
--====================================================

local DURATION = 60          -- duree max du tir
local COOLDOWN = 1           -- recharge apres la fin naturelle
local DAMAGE_DELAY = 1       -- attente apres des degats
local FIRE_AFTER_SKIP = 1    -- attente apres le dernier skip

local fireToken = 0
local firing = false

local function fireDown()
    local vp = Camera.ViewportSize
    VirtualInputManager:SendMouseButtonEvent(vp.X / 2, vp.Y / 2, 0, true, game, 0)
    firing = true
end

local function fireUp()
    local vp = Camera.ViewportSize
    VirtualInputManager:SendMouseButtonEvent(vp.X / 2, vp.Y / 2, 0, false, game, 0)
    firing = false
end

-- Chaque appel annule le cycle precedent
local function startFire(waitTime, reason)
    fireToken = fireToken + 1
    local my = fireToken

    task.spawn(function()
        fireUp()

        if waitTime > 0 then
            local stop = os.clock() + waitTime
            while os.clock() < stop do
                task.wait(0.05)
                if my ~= fireToken then return end
            end
        end

        if my ~= fireToken then return end

        fireDown()
        print("[TIR] " .. reason)

        -- Surveille la duree max, en pause pendant heal et dodge
        local remaining = DURATION
        while remaining > 0 do
            task.wait(0.1)
            if my ~= fireToken then return end

            if not securityMode and not attackInProgress then
                remaining = remaining - 0.1
            end
        end

        if my == fireToken then
            startFire(COOLDOWN, "fin des " .. DURATION .. "s")
        end
    end)
end

-- Relance apres des degats
local lastFireHP = hum.Health

hum.HealthChanged:Connect(function(newHealth)
    if newHealth < lastFireHP and newHealth > 0
    and not securityMode and not attackInProgress then
        startFire(DAMAGE_DELAY, "degats recus")
    end
    lastFireHP = newHealth
end)

-- Demarrage : 1s apres le dernier skip cutscene
task.spawn(function()
    while not skipFinished do
        task.wait(0.2)
    end
    task.wait(FIRE_AFTER_SKIP)
    startFire(0, "1s apres le dernier skip")
end)

--====================================================
-- LIBERATION DE LA GARDE
--====================================================

player.AncestryChanged:Connect(function(_, parent)
    if not parent then
        _G.KronaxInstance = nil
    end
end)

print("[KRONAX] Instance unique active")

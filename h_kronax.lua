-- ==========================================================
-- SECURITE : REJET DE TOUTE NOUVELLE EXECUTION
-- ==========================================================
if _G.KronaxRunning then
    warn(" REFUSE : Le script est deja actif. Inutile de le relancer !")
    return
end

_G.KronaxRunning = true
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
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
repeat task.wait() until player

--====================================================
-- AUTO SKIP CUTSCENE
-- Demarre 6 secondes apres l'activation du script
-- (place avant le task.wait(5), donc vraiment 6s),
-- puis 1 appel par seconde.
--====================================================

local skipFinished = false  -- passe a true quand les skips sont termines

local SKIP_DELAY = 6        -- attente avant le premier appel
local SKIP_COUNT = 5        -- nombre d'appels
local SKIP_INTERVAL = 1     -- intervalle entre les appels

task.spawn(function()
    if SKIP_DELAY > 0 then
        task.wait(SKIP_DELAY)
    end

    for i = 1, SKIP_COUNT do
        local ok = pcall(function()
            ReplicatedStorage.ReplicatedStorage.Packages.Knit.Services
                .DungeonService.RF.VoteSkipCutscene:InvokeServer()
        end)

        print("[SKIP] VoteSkipCutscene " .. i .. "/" .. SKIP_COUNT
            .. (ok and "" or " (echec)"))

        if i < SKIP_COUNT then
            task.wait(SKIP_INTERVAL)
        end
    end

    -- H juste apres le dernier VoteSkipCutscene
    pcall(function()
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.H, false, game)
        task.wait(0.05)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.H, false, game)
    end)
    print("[SKIP] H appuye apres le dernier skip")

    skipFinished = true
    print("[SKIP] Termine")
end)


--====================================================
-- AUTO START DONJON
--====================================================

-- Dans son propre thread : ne bloque plus la mise en place
-- de l'orbit ni du reste du script.
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

    print("[START] StartDungeon appele")
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
local firstMobKilled = false
local onFirstMobKilled = nil
local bossDead = false
local retryDone = false
local bossWatch = {}

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

local watchedFirstMobs = {}

local function markFirstMobKilled()
    if firstMobKilled then return end
    firstMobKilled = true
    print("[OK] Premier mob tue - relance du tir !")
    if onFirstMobKilled then onFirstMobKilled() end
end

local function watchFirstMob(mob)
    if watchedFirstMobs[mob] then return end
    watchedFirstMobs[mob] = true

    local mobHum = mob:FindFirstChild("Humanoid") or mob:WaitForChild("Humanoid", 5)
    if not mobHum then return end

    mobHum.Died:Connect(markFirstMobKilled)
    mobHum:GetPropertyChangedSignal("Health"):Connect(function()
        if mobHum.Health <= 0 then markFirstMobKilled() end
    end)
end

for _, mob in pairs(MOB_FOLDER:GetChildren()) do
    watchFirstMob(mob)
end

MOB_FOLDER.ChildAdded:Connect(function(mob)
    if not firstMobKilled then task.spawn(watchFirstMob, mob) end
end)

MOB_FOLDER.ChildRemoved:Connect(function(mob)
    if not firstMobKilled and watchedFirstMobs[mob] then markFirstMobKilled() end
end)


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

local function markBossDead()
    if bossDead then return end
    bossDead = true
    bossPart = nil
    print("[OK] BOSS MORT")
end

local function watchBossDeath(model)
    if bossWatch[model] then return end
    bossWatch[model] = true

    local bossHum = model:FindFirstChild("Humanoid")
    if bossHum then
        bossHum.Died:Connect(markBossDead)
        bossHum:GetPropertyChangedSignal("Health"):Connect(function()
            if bossHum.Health <= 0 then markBossDead() end
        end)
    end

    model:GetAttributeChangedSignal("Health"):Connect(function()
        local hp = model:GetAttribute("Health")
        if hp and hp <= 0 then markBossDead() end
    end)

    model.AncestryChanged:Connect(function(_, parent)
        if not parent then markBossDead() end
    end)
end

for _, obj in pairs(workspace:GetDescendants()) do
    if obj:IsA("Model") and obj:HasTag("Boss") then
        watchBossDeath(obj)
    end
end

workspace.DescendantAdded:Connect(function(obj)
    task.wait(0.1)
    if obj:IsA("Model") and obj:HasTag("Boss") then
        watchBossDeath(obj)
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
-- TIR AUTO : SYSTEME DU SCRIPT 1
--====================================================

local DURATION = 60
local COOLDOWN = 1
local DAMAGE_DELAY = 1
local FIRSTMOB_DELAY = 3
local SAFETY_MARGIN = 0.2

local attackActive = true
local holding = false
local cycleToken = 0
local lastHealthAttack = hum.Health

local function centerXY()
    local vp = Camera.ViewportSize
    return vp.X / 2, vp.Y / 2
end

local function pressDown()
    local x, y = centerXY()
    VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
    holding = true
end

local function pressUp()
    local x, y = centerXY()
    VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
    holding = false
end

local function startCycle(waitTime, reason)
    cycleToken = cycleToken + 1
    local myToken = cycleToken

    task.spawn(function()
        pressUp()

        if waitTime > 0 then
            local waitEnd = os.clock() + waitTime + SAFETY_MARGIN
            while os.clock() < waitEnd do
                task.wait(0.05)
                if myToken ~= cycleToken then return end
            end
        end

        if myToken ~= cycleToken or not attackActive then return end

        pressDown()
        print("[TIR] Relance (" .. reason .. ")")

        local endTime = os.clock() + DURATION
        while os.clock() < endTime do
            task.wait(0.1)
            if myToken ~= cycleToken or not attackActive then return end

            -- Comme pour le dodge TDecayCharge :
            -- pendant la phase HEAL a 2000 studs, on ne touche PAS au clic.
            -- Le cycle est simplement mis en pause dans le temps.
            if securityMode then
                while securityMode do
                    task.wait(0.1)
                    if myToken ~= cycleToken or not attackActive then return end
                end

                -- On reprend le meme clic exactement comme il etait.
                -- Surtout : aucun pressUp() pendant le retour des 2000 studs.
                if attackActive and not holding then
                    pressDown()
                end

                -- Le temps passe en heal ne compte pas dans les 60 secondes.
                endTime = os.clock() + DURATION
            end
        end

        if myToken == cycleToken and attackActive then
            -- Le cooldown normal ne doit pas provoquer un relachement
            -- pendant la descente du heal.
            if securityMode then
                while securityMode do
                    task.wait(0.1)
                    if myToken ~= cycleToken or not attackActive then return end
                end
            end

            startCycle(COOLDOWN, "fin des " .. DURATION .. "s")
        end
    end)
end

local function watchAttackHealth(h)
    lastHealthAttack = h.Health
    h.HealthChanged:Connect(function(newHealth)
        if not attackActive then
            lastHealthAttack = newHealth
            return
        end

        if newHealth < lastHealthAttack and newHealth > 0 and not securityMode then
            startCycle(DAMAGE_DELAY, "degats recus")
        end

        lastHealthAttack = newHealth
    end)
end

watchAttackHealth(hum)

onFirstMobKilled = function()
    if attackActive then
        startCycle(FIRSTMOB_DELAY, "premier mob tue")
    end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if input.KeyCode == Enum.KeyCode.M then
        attackActive = not attackActive

        if attackActive then
            startCycle(0, "reactive")
        else
            cycleToken = cycleToken + 1
            pressUp()
        end

        pcall(function()
            StarterGui:SetCore("SendNotification", {
                Title = "Tir auto",
                Text = attackActive and "ACTIF" or "DESACTIVE",
                Duration = 2
            })
        end)
    end
end)

-- Le tir demarre 1 seconde apres le dernier VoteSkipCutscene
local FIRE_AFTER_SKIP = 1

task.spawn(function()
    while not skipFinished do
        task.wait(0.2)
    end
    task.wait(FIRE_AFTER_SKIP)
    startCycle(0, "1s apres le dernier skip")
end)

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

    -- Comme le Decay : aucun pressUp()/pressDown() au retour des 2000.
    -- Le clic qui etait maintenu avant le heal reste dans le meme etat.
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

        -- PHASE HEAL :
        -- NE PAS relacher le clic. Le tir doit rester maintenu pendant
        -- la montee a 2000, le heal ET la descente.
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
-- AUTO RETRY : SYSTEME DU SCRIPT 1
-- A la mort du boss : 20 tentatives, 1 par seconde.
--====================================================

local RETRY_ATTEMPTS = 20
local RETRY_INTERVAL = 1

local function findRetryBtn()
    local gui = player:FindFirstChild("PlayerGui")
    if not gui then return nil end

    local dungeonComplete = gui:FindFirstChild("DungeonComplete")
    if dungeonComplete then
        local main = dungeonComplete:FindFirstChild("Main")
        local endButtons = main and main:FindFirstChild("EndGameButtons")
        local btn = endButtons and endButtons:FindFirstChild("RetryBtn")
        if btn then return btn end
    end

    return gui:FindFirstChild("RetryBtn", true)
end

local function clickRetry(btn)
    local inset = GuiService:GetGuiInset()
    local pos = btn.AbsolutePosition
    local size = btn.AbsoluteSize
    local x = pos.X + size.X / 2
    local y = pos.Y + size.Y / 2 + inset.Y

    VirtualInputManager:SendMouseMoveEvent(x, y, game)
    task.wait(0.05)
    VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
    task.wait(0.05)
    VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)

    pcall(function()
        for _, conn in ipairs(getconnections(btn.Activated)) do
            conn:Fire()
        end
    end)

    pcall(function()
        for _, conn in ipairs(getconnections(btn.MouseButton1Click)) do
            conn:Fire()
        end
    end)

    pcall(function() firesignal(btn.Activated) end)
    pcall(function() firesignal(btn.MouseButton1Click) end)
end

local function pressHOnce()
    pcall(function()
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.H, false, game)
        task.wait(0.05)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.H, false, game)
    end)
end

local retryRunning = false

local function retryDungeon20Times()
    if retryRunning then return end
    retryRunning = true
    retryDone = true

    print("[RETRY] BOSS MORT -> 20 tentatives, 1 par seconde")

    cycleToken = cycleToken + 1
    pressUp()

    for attempt = 1, RETRY_ATTEMPTS do
        local retryBtn = findRetryBtn()

        if retryBtn then
            print("[RETRY] Tentative " .. attempt .. "/" .. RETRY_ATTEMPTS)
            clickRetry(retryBtn)
        else
            print("[RETRY] Tentative " .. attempt .. "/" .. RETRY_ATTEMPTS .. " : RetryBtn absent")
        end

        -- Exactement 1 tentative par seconde.
        if attempt < RETRY_ATTEMPTS then
            task.wait(RETRY_INTERVAL)
        end
    end

    -- Apres les 20 tentatives, on lance explicitement la nouvelle run.
    task.wait(0.5)

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

    task.wait(3)

    firstMobKilled = false
    bossDead = false
    bossPart = nil
    watchedFirstMobs = {}
    angle = 0

    -- H une seule fois quand la nouvelle run a commence.
    task.wait(0.5)
    pressHOnce()
    print("[RETRY] H appuye 1 fois apres les 20 tentatives")

    if attackActive then
        startCycle(0, "nouvelle run")
    end

    retryDone = false
    retryRunning = false

    print("[RETRY] Nouvelle run prete")
end

task.spawn(function()
    while true do
        task.wait(0.25)

        if bossDead and not retryRunning then
            retryDungeon20Times()
        end
    end
end)

player.CharacterRemoving:Connect(function()
    cycleToken = cycleToken + 1
    pressUp()
    _G.KronaxRunning = nil
end)


print("[OK] Script 3 exact + tir auto du script 1 + retry du script 1")

--====================================================
-- LIBERATION DU DRAPEAU
--====================================================

game:GetService("Players").LocalPlayer.AncestryChanged:Connect(function(_, parent)
    if not parent then
        _G.KronaxRunning = nil
    end
end)

-- ==========================================================
-- FARM HALLOWEEN V2 (Spooky Castle, workspace.Map.HalloweenDungeon)
-- ==========================================================
-- Base : farm_infinite (deplacement, retry).
-- En plus : va chercher la cle (Rooms.X.Key, E) puis ouvre la porte
-- (Rooms.X.KeyHole, E) avant de farmer les mobs.
-- Attaque (patch oct. 2026, 5 vies) : Crimson Scythe F / R / C / V,
-- element Time (2 puis R), potion W si PV bas, et secours a 2000 studs
-- (soin avec Time) sous 20 % de PV quand il n'y a plus de potion.
-- En moins : pas de compteur 10 min + kills.
-- Hub : interrupteur "Halloween v2", incompatible avec FarmInfinite (meme
-- deplacement). Lance partout, il attend la carte HalloweenDungeon.
-- v2 : sans la boucle TeleportPortal de farm_infinite (elle tuait le perso
-- en boucle : avec 5 vies, elle viderait toutes les vies).

-- ==========================================================
-- SECURITE : REJET DE TOUTE NOUVELLE EXECUTION
-- ==========================================================
if _G.FarmHalloweenInstance then
    warn("[X] Farm Halloween deja actif - seconde instance annulee")
    return
end
_G.FarmHalloweenInstance = true
print("[OK] Farm Halloween : initialisation...")

--====================================================
-- SERVICES
--====================================================

repeat task.wait() until game:IsLoaded()

local Players = game:GetService("Players")
local VirtualInputManager = game:GetService("VirtualInputManager")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
repeat task.wait() until player

--====================================================
-- ATTENTE DU CHATEAU D'HALLOWEEN
--====================================================
-- Le script n'agit que dans workspace.Map.HalloweenDungeon
local function inHalloween()
local map = workspace:FindFirstChild("Map")
return map ~= nil and map:FindFirstChild("HalloweenDungeon") ~= nil
end

if not inHalloween() then
print("[HALLOWEEN] pas dans le chateau -> attente de la carte HalloweenDungeon")
repeat task.wait(1) until inHalloween()
end
print("[HALLOWEEN] carte HalloweenDungeon detectee -> demarrage")

-- Objectif du moment (cle ou porte), rempli par le SCRIPT 7.
-- pos = nil : pas d'objectif, le SCRIPT 6 farme les mobs.
local Objective = { name = nil, pos = nil }

-- Mob suivi par le SCRIPT 6, vise par le SCRIPT 1.
local Combat = { target = nil }

-- Secours en cours (SCRIPT 1) : le SCRIPT 6 ne deplace plus le perso.
local Rescue = { active = false }

--====================================================
-- VIE DU JOUEUR (methode de h_kronax : Humanoid.HealthChanged)
--====================================================
-- ratio = vie / vie max, lastHit = moment du dernier coup recu,
-- lastDamage = PV perdus a ce coup. Suivi refait a chaque respawn.
local Life = { health = 0, max = 1, ratio = 1, lastHit = 0, lastDamage = 0 }

local function watchLife(char)
    local hum = char:WaitForChild("Humanoid", 10)
    if not hum then return end
    Life.health, Life.max = hum.Health, hum.MaxHealth
    Life.ratio = hum.MaxHealth > 0 and hum.Health / hum.MaxHealth or 0
    hum.HealthChanged:Connect(function(newHealth)
        if newHealth < Life.health then
            Life.lastHit = os.clock()
            Life.lastDamage = Life.health - newHealth
        end
        Life.health, Life.max = newHealth, hum.MaxHealth
        Life.ratio = hum.MaxHealth > 0 and newHealth / hum.MaxHealth or 0
    end)
end

if player.Character then task.spawn(watchLife, player.Character) end
player.CharacterAdded:Connect(watchLife)

--====================================================
-- CLICK BUTTON
--====================================================

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

-- ==========================================================
-- SCRIPT 1 - ATTAQUES : CRIMSON SCYTHE + ELEMENT TIME + SOINS
-- ==========================================================
-- Slot 1 = Crimson Scythe : F Fleau, R Cyclone d'ombres, C Coup tranchant
-- fantome, V Frenesie des faucilles. Un simple appui suffit.
-- Slot 2 = element Time (mode Support) : R = Time Dilation (buff 15 s,
-- recharge 10 s), F = Phase Rewind (+20 % PV), clic gauche = Temporal
-- Seam (+4 % PV). Le mode Support soigne aussi 3.5 % PV/s en continu ; le
-- mode Damage retire 2.5 % PV/s -> alerte si le perso est en Damage.
-- Soins (seulement 5 vies dans le donjon) :
--   * PV < POTION_HP et au moins une potion (player.VampyricPotions, 3 max)
--     -> W (+35 % PV) ;
--   * PV < RESCUE_HP et plus de potion -> SECOURS (methode h_kronax) :
--     TP a SAFE_HEIGHT studs au-dessus, flottement, passage sur Time, clic
--     gauche + F jusqu'aux PV max, puis retour a la position de depart.
task.spawn(function()

local TAP_TIME = 0.1           -- duree d'un appui
local ATTACK_RANGE = 60        -- Fleau touche jusqu'a ~70 studs autour
local TIME_EVERY = 15          -- duree du buff Time Dilation (recharge 10 s)
local POTION_HP = 0.5          -- W sous 50 % de PV
local POTION_DELAY = 2         -- secondes mini entre deux W
local RESCUE_HP = 0.2          -- secours sous 20 % de PV sans potion
local SAFE_HEIGHT = 2000       -- hauteur du secours (comme h_kronax)
local RESCUE_FULL = 0.99       -- PV a atteindre avant de redescendre
local RESCUE_TIMEOUT = 90      -- secondes max en l'air
local CD_MARGIN = 0.3          -- marge ajoutee aux recharges

-- ordre de priorite : C aspire et immobilise, F frappe tout autour 3 fois,
-- R part vers la souris (on vise le mob), V fonce droit devant (invincible)
local MOVES = {
    { key = Enum.KeyCode.C, cd = 8, name = "Coup tranchant fantome" },
    { key = Enum.KeyCode.F, cd = 5, name = "Fleau" },
    { key = Enum.KeyCode.R, cd = 7, name = "Cyclone d'ombres", aim = true },
    { key = Enum.KeyCode.V, cd = 4, name = "Frenesie des faucilles" },
}
local readyAt = {}

local function pressKey(keyCode, duration)
    VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
    task.wait(duration or 0.05)
    VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
end

-- clic gauche au centre de l'ecran (Temporal Seam avec Time en main)
local function clickCenter()
    local cam = workspace.CurrentCamera
    local size = cam and cam.ViewportSize or Vector2.new(800, 600)
    VirtualInputManager:SendMouseButtonEvent(size.X / 2, size.Y / 2, 0, true, game, 0)
    task.wait(0.03)
    VirtualInputManager:SendMouseButtonEvent(size.X / 2, size.Y / 2, 0, false, game, 0)
end

-- souris sur la cible : le Cyclone d'ombres part vers la souris
local function aimAt(pos)
    local cam = workspace.CurrentCamera
    if not cam or not pos then return end
    local screen, onScreen = cam:WorldToViewportPoint(pos)
    if onScreen then
        VirtualInputManager:SendMouseMoveEvent(screen.X, screen.Y, game)
    end
end

-- outil en main : Type "Weapons" = slot 1 (faux), "Elements" = slot 2 (Time)
local function heldType()
    local char = player.Character
    local tool = char and char:FindFirstChildOfClass("Tool")
    return tool and tool:GetAttribute("Type") or nil
end

-- 1 et 2 sont des bascules : on n'appuie que si le bon outil n'est pas en main
local function equip(slot)
    local want = slot == 1 and "Weapons" or "Elements"
    for _ = 1, 3 do
        if heldType() == want then return true end
        pressKey(slot == 1 and Enum.KeyCode.One or Enum.KeyCode.Two, TAP_TIME)
        task.wait(0.35)
    end
    return heldType() == want
end

local function targetPos()
    local mob = Combat.target
    local hrp = mob and mob.Parent and mob:FindFirstChild("HumanoidRootPart")
    return hrp and hrp.Position or nil
end

local function potions()
    return player:GetAttribute("VampyricPotions") or 0
end

local lastPotion, lastTime, lastModeWarn = 0, -math.huge, 0

-- Time en mode Damage = -2.5 % PV/s : alerte a l'ecran toutes les 30 s
local function checkTimeMode(char)
    if char:GetAttribute("TimeMode") ~= "Damage" or os.clock() - lastModeWarn < 30 then return end
    lastModeWarn = os.clock()
    warn("[TIME] element Time en mode DAMAGE : il retire 2.5 % PV/s, repasse en Support")
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "Farm Halloween",
            Text = "Time en mode DAMAGE (-2.5 % PV/s) : repasse en Support !",
            Duration = 8,
        })
    end)
end

--====================================================
-- SECOURS (methode h_kronax : TP en l'air + flottement)
--====================================================
local function stabilize(root)
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
end

local function startFloat(root)
    if root:FindFirstChild("SafeFloat") then return end
    local bv = Instance.new("BodyVelocity")
    bv.Name = "SafeFloat"
    bv.Velocity = Vector3.zero
    bv.MaxForce = Vector3.new(0, math.huge, 0)
    bv.Parent = root
end

local function stopFloat(root)
    local bv = root and root:FindFirstChild("SafeFloat")
    if bv then bv:Destroy() end
end

local function rescue(char, hum, root)
    Rescue.active = true
    local back = root.CFrame
    local high = back + Vector3.new(0, SAFE_HEIGHT, 0)
    print(string.format("[SECOURS] PV %d %% sans potion -> TP a %d studs, soin avec Time",
        math.floor(Life.ratio * 100), SAFE_HEIGHT))

    root.CFrame = high
    stabilize(root)
    startFloat(root)
    hum:ChangeState(Enum.HumanoidStateType.Physics)

    local deadline = os.clock() + RESCUE_TIMEOUT
    local lastF = -math.huge
    while hum.Parent and hum.Health > 0 and Life.ratio < RESCUE_FULL and os.clock() < deadline do
        -- on reste en haut (le flottement ne bloque que la chute)
        if (root.Position - high.Position).Magnitude > 50 then
            root.CFrame = high
            stabilize(root)
        end
        if equip(2) then
            clickCenter()                        -- Temporal Seam : +4 % PV
            if os.clock() - lastF > 1 then       -- Phase Rewind : +20 % PV
                lastF = os.clock()
                pressKey(Enum.KeyCode.F, TAP_TIME)
            end
        end
        task.wait(0.2)
    end

    -- retour sur le terrain
    if hum.Parent and hum.Health > 0 then
        stopFloat(root)
        stabilize(root)
        root.CFrame = back
        hum:ChangeState(Enum.HumanoidStateType.GettingUp)
        task.wait(0.1)
        equip(1)
        print(string.format("[SECOURS] fini (PV %d %%) -> retour sur le terrain", math.floor(Life.ratio * 100)))
    else
        print("[SECOURS] perso mort pendant le secours")
    end
    Rescue.active = false
end

-- Demarrage apres 3 secondes
task.wait(3)
equip(1)

while true do
    task.wait(0.1)

    local char = player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")

    if hum and root and hum.Health > 0 then

        checkTimeMode(char)

        -- soins : potion si on en a, sinon secours sous RESCUE_HP
        if Life.ratio < POTION_HP and potions() > 0 then
            if os.clock() - lastPotion > POTION_DELAY and equip(1) then
                lastPotion = os.clock()
                print(string.format("[POTION] PV %d %% -> W (%d potion(s))",
                    math.floor(Life.ratio * 100), potions()))
                pressKey(Enum.KeyCode.W, TAP_TIME)
            end
        elseif Life.ratio < RESCUE_HP and potions() == 0 then
            local ok, err = pcall(rescue, char, hum, root)
            if not ok then
                warn("[SECOURS] erreur : " .. tostring(err))
                stopFloat(root)
                Rescue.active = false
            end
        end

        -- pas d'attaque pendant la cle / la porte (la Frenesie ferait devier)
        local pos = not Objective.pos and targetPos() or nil

        if not Rescue.active and pos and (pos - root.Position).Magnitude <= ATTACK_RANGE then

            if os.clock() - lastTime >= TIME_EVERY then
                -- element Time : 2 puis R (Time Dilation), puis retour sur la faux
                lastTime = os.clock()
                print("[TIME] 2 + R (Time Dilation)")
                if equip(2) then
                    pressKey(Enum.KeyCode.R, TAP_TIME)
                    task.wait(0.5)
                end
                equip(1)
            elseif equip(1) then
                for _, move in ipairs(MOVES) do
                    if os.clock() >= (readyAt[move.key] or 0) then
                        if move.aim then aimAt(targetPos()) end
                        pressKey(move.key, TAP_TIME)
                        readyAt[move.key] = os.clock() + move.cd + CD_MARGIN
                        task.wait(0.4)
                        break
                    end
                end
            end

        end
    end
end

end)

task.wait(1)

-- ==========================================================
-- SCRIPT 2 - DETECTION MORT + RELANCE DE LA BOUCLE
-- ==========================================================
task.spawn(function()

local function onCharacterDied()

    print("[KILL] Personnage mort - attente du respawn...")

    player.CharacterAdded:Wait()

    task.wait(1)

    print(" Personnage respawne.")

end

local function setupDeathDetection(character)

    local humanoid =
        character:FindFirstChildOfClass("Humanoid")

    if humanoid then

        humanoid.Died:Connect(
            onCharacterDied
        )

    end

end

player.CharacterAdded:Connect(function(character)

    setupDeathDetection(character)

end)

if player.Character then

    setupDeathDetection(
        player.Character
    )

end


end)

task.wait(1)

-- ==========================================================
-- SCRIPT 3 - AUTO RETRY / PROCEED
-- ==========================================================
task.spawn(function()

local retryClicked = false

while true do

    local playerGui =
        player:FindFirstChild("PlayerGui")

    if playerGui then

        pcall(function()

            local dungeonComplete =
                playerGui:FindFirstChild(
                    "DungeonComplete"
                )

            local retryBtn =
                dungeonComplete
                and dungeonComplete:FindFirstChild("Main")
                and dungeonComplete.Main:FindFirstChild(
                    "EndGameButtons"
                )
                and dungeonComplete.Main.EndGameButtons:FindFirstChild(
                    "RetryBtn"
                )

            if retryBtn and not retryClicked then

                retryClicked = true

                print(
                    "... RetryBtn detecte - attente 1 seconde..."
                )

                task.wait(1)

                print(
                    "[OK] Clic sur RetryBtn !"
                )

                clickButton(retryBtn)

                task.wait(1)

                pcall(function()

                    ReplicatedStorage
                        :WaitForChild("ReplicatedStorage")
                        :WaitForChild("Packages")
                        :WaitForChild("Knit")
                        :WaitForChild("Services")
                        :WaitForChild("DungeonService")
                        :WaitForChild("RF")
                        :WaitForChild("StartDungeon")
                        :InvokeServer()

                end)

                task.wait(1)

                retryClicked = false

            end

            local prompts =
                playerGui:FindFirstChild(
                    "Prompts"
                )

            local proceedBtn =
                prompts
                and prompts:FindFirstChild(
                    "PromptFrame"
                )
                and prompts.PromptFrame:FindFirstChild(
                    "Buttons"
                )
                and prompts.PromptFrame.Buttons:FindFirstChild(
                    "Proceed"
                )

            if proceedBtn then

                clickButton(proceedBtn)

            end

        end)

    end

    task.wait(0.5)

end


end)

task.wait(1)

-- ==========================================================
-- SCRIPT 4 - START DONJON
-- ==========================================================
task.spawn(function()

task.wait(5)

pcall(function()

    ReplicatedStorage
        :WaitForChild("ReplicatedStorage")
        :WaitForChild("Packages")
        :WaitForChild("Knit")
        :WaitForChild("Services")
        :WaitForChild("DungeonService")
        :WaitForChild("RF")
        :WaitForChild("StartDungeon")
        :InvokeServer()

end)


end)

task.wait(1)

-- ==========================================================
-- SCRIPT 6 - FARM MOBS
-- ==========================================================
task.spawn(function()

local character =
    player.Character
    or player.CharacterAdded:Wait()

local humanoid =
    character:WaitForChild(
        "Humanoid"
    )

local rootPart =
    character:WaitForChild(
        "HumanoidRootPart"
    )

local mobToFollow = nil

local TARGET_SPEED = 80

local flyVelocity = nil

local SWITCH_DISTANCE_THRESHOLD = 5

local mainLoopConnection

RunService.RenderStepped:Connect(
    function()

        if humanoid
            and humanoid.WalkSpeed
                ~= TARGET_SPEED then

            humanoid.WalkSpeed =
                TARGET_SPEED

        end

    end
)

RunService.Stepped:Connect(
    function()

        if character then

            for _, part in pairs(
                character:GetDescendants()
            ) do

                if part:IsA("BasePart") then

                    part.CanCollide = false

                end

            end

        end

    end
)

local function getClosestMob()

    local mobsFolder =
        workspace:FindFirstChild(
            "Mobs"
        )

    if not mobsFolder then
        return nil
    end

    local closestMob = nil
    local closestDistance =
        math.huge

    for _, mob in pairs(
        mobsFolder:GetChildren()
    ) do

        local hum =
            mob:FindFirstChild(
                "Humanoid"
            )

        local hrp =
            mob:FindFirstChild(
                "HumanoidRootPart"
            )

        if hum
            and hrp
            and hum.Health > 0 then

            local dist =
                (
                    rootPart.Position
                    - hrp.Position
                ).Magnitude

            if dist <
                closestDistance then

                closestDistance = dist
                closestMob = mob

            end

        end

    end

    return closestMob

end

local function moveTowardsMob()

    -- la cle ou la porte passe avant les mobs
    local goal = Objective.pos

    if not goal then

        if not mobToFollow
            or not mobToFollow.Parent
            or not mobToFollow:FindFirstChild(
                "HumanoidRootPart"
            )
            or mobToFollow.Humanoid.Health <= 0 then

            mobToFollow = nil

            humanoid:Move(
                Vector3.zero
            )

            return

        end

        goal =
            mobToFollow
                .HumanoidRootPart
                .Position

    end

    local direction =
        goal
        - rootPart.Position

    if direction.Magnitude < 2 then

        humanoid:Move(
            Vector3.zero
        )

        return

    end

    humanoid:Move(
        direction.Unit,
        false
    )

end

local function updateFly()

    local goal = Objective.pos

    if not goal then

        if not mobToFollow
            or not mobToFollow:FindFirstChild(
                "HumanoidRootPart"
            ) then

            return

        end

        goal =
            mobToFollow
                .HumanoidRootPart
                .Position

    end

    local directionToMob =
        goal
        - rootPart.Position

    local distanceToMob =
        directionToMob.Magnitude

    local heightDifference =
        goal.Y
        - rootPart.Position.Y

    if distanceToMob <= 1 then

        if flyVelocity then

            flyVelocity:Destroy()
            flyVelocity = nil

        end

        rootPart.Velocity =
            Vector3.zero

        return

    end

    local rayOrigin =
        rootPart.Position

    local rayDirection =
        Vector3.new(
            0,
            -100,
            0
        )

    local rayParams =
        RaycastParams.new()

    rayParams.FilterDescendantsInstances =
        {character}

    rayParams.FilterType =
        Enum.RaycastFilterType.Blacklist

    local rayResult =
        workspace:Raycast(
            rayOrigin,
            rayDirection,
            rayParams
        )

    if not rayResult
        or heightDifference > 50 then

        if not flyVelocity then

            flyVelocity =
                Instance.new(
                    "BodyVelocity"
                )

            flyVelocity.MaxForce =
                Vector3.new(
                    1e5,
                    1e5,
                    1e5
                )

            flyVelocity.P =
                10000

            flyVelocity.Parent =
                rootPart

        end

        flyVelocity.Velocity =
            directionToMob.Unit
            * 100

    else

        if flyVelocity then

            flyVelocity:Destroy()
            flyVelocity = nil

        end

    end

end

local function startFarming()

    if mainLoopConnection then

        mainLoopConnection:Disconnect()

    end

    mainLoopConnection =
        RunService.RenderStepped:Connect(
            function()

                -- secours en l'air : on ne touche pas au perso
                if Rescue.active then

                    if flyVelocity then

                        flyVelocity:Destroy()
                        flyVelocity = nil

                    end

                    return

                end

                local closestMob =
                    not Objective.pos
                    and getClosestMob()
                    or nil

                if Objective.pos then

                    mobToFollow = nil

                elseif closestMob then

                    if not mobToFollow
                        or not mobToFollow.Parent
                        or mobToFollow.Humanoid.Health <= 0 then

                        mobToFollow =
                            closestMob

                    else

                        local currentDist =
                            (
                                rootPart.Position
                                - mobToFollow
                                    .HumanoidRootPart
                                    .Position
                            ).Magnitude

                        local newDist =
                            (
                                rootPart.Position
                                - closestMob
                                    .HumanoidRootPart
                                    .Position
                            ).Magnitude

                        if newDist
                            + SWITCH_DISTANCE_THRESHOLD
                            < currentDist then

                            mobToFollow =
                                closestMob

                        end

                    end

                else

                    mobToFollow = nil

                end

                Combat.target = mobToFollow

                moveTowardsMob()
                updateFly()

            end
        )

end

startFarming()

player.CharacterAdded:Connect(
    function(char)

        character = char

        humanoid =
            character:WaitForChild(
                "Humanoid"
            )

        rootPart =
            character:WaitForChild(
                "HumanoidRootPart"
            )

        startFarming()

    end
)

end)

task.wait(1)

-- ==========================================================
-- SCRIPT 7 - CLE ET PORTE DU CHATEAU
-- ==========================================================
-- La cle (Rooms.X.Key) change de place au DungeonStarted : on lit sa
-- position en direct. workspace.CastleKeyFound vaut nil avant le debut,
-- false tant que la cle est au sol, true quand elle est prise. La porte
-- (Rooms.X.KeyHole) est ouverte quand workspace.CurrentFloor augmente.
task.spawn(function()

local E_RANGE = 8           -- portee des prompts : 10 studs
local E_DELAY = 0.4
local DOOR_GIVE_UP = 45     -- secondes a appuyer sur la porte sans effet

-- telephone (Delta) : sans clavier, le E simule ne declenche pas toujours
-- le prompt -> fireproximityprompt des le premier essai
local UserInputService = game:GetService("UserInputService")
local MOBILE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local FIRE_AFTER = MOBILE and 1 or 3

local function pressE()
    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
    task.wait(0.05)
    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
end

local function getRooms()
    local map = workspace:FindFirstChild("Map")
    local hd = map and map:FindFirstChild("HalloweenDungeon")
    local inner = hd and hd:FindFirstChild("Map")
    return inner and inner:FindFirstChild("Rooms")
end

-- premier objet `name` des salles qui a un prompt actif
local function findInRooms(name)
    local rooms = getRooms()
    if not rooms then return nil end
    for _, room in ipairs(rooms:GetChildren()) do
        local obj = room:FindFirstChild(name)
        if obj then
            local prompt = obj:FindFirstChildWhichIsA("ProximityPrompt", true)
            if prompt and prompt.Enabled then
                return obj, prompt
            end
        end
    end
    return nil
end

local function partOf(obj)
    if obj:IsA("BasePart") then return obj end
    return obj:FindFirstChild("Handle") or obj:FindFirstChildWhichIsA("BasePart", true)
end

-- Il y a DEUX Rooms.1.Key, meme nom, meme prompt actif :
--  * un leurre, la des le chargement, toujours au meme endroit, jamais pris ;
--  * la vraie cle, ajoutee au DungeonStarted sur un des points KeySpawns.
-- On ecarte les cles presentes avant le debut et celle a la place du leurre.
local DECOY_POS = Vector3.new(3599.4, 62.1, 197.9)
local DECOY_RADIUS = 6
local decoys = setmetatable({}, { __mode = "k" })

local function allKeys()
    local list = {}
    local rooms = getRooms()
    if not rooms then return list end
    for _, room in ipairs(rooms:GetChildren()) do
        for _, obj in ipairs(room:GetChildren()) do
            if obj.Name == "Key" then
                local prompt = obj:FindFirstChildWhichIsA("ProximityPrompt", true)
                local part = partOf(obj)
                if prompt and prompt.Enabled and part then
                    table.insert(list, { obj = obj, part = part, prompt = prompt })
                end
            end
        end
    end
    return list
end

-- lance avant le debut du donjon : tout ce qui s'appelle Key est un leurre
if workspace:GetAttribute("CastleKeyFound") == nil then
    for _, k in ipairs(allKeys()) do
        decoys[k.obj] = true
    end
end

-- la vraie cle la plus proche, sinon nil
local function findRealKey()
    local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    local best, bestDist = nil, math.huge
    for _, k in ipairs(allKeys()) do
        local pos = k.part.Position
        if not decoys[k.obj] and (pos - DECOY_POS).Magnitude > DECOY_RADIUS then
            local d = root and (pos - root.Position).Magnitude or 0
            if d < bestDist then
                best, bestDist = k, d
            end
        end
    end
    return best
end

local function floorNow()
    return workspace:GetAttribute("CurrentFloor") or 0
end

-- etage au moment ou la cle a ete prise : la porte est ouverte quand
-- CurrentFloor depasse cette valeur. nil = pas de porte a ouvrir.
local doorFloor = nil
local doorSince = nil

-- lance en cours de partie avec la cle deja prise mais porte fermee
if workspace:GetAttribute("CastleKeyFound") == true and floorNow() == 0 then
    doorFloor = 0
end

workspace:GetAttributeChangedSignal("CastleKeyFound"):Connect(function()
    if workspace:GetAttribute("CastleKeyFound") == true then
        doorFloor = floorNow()
        print("[CLE] cle prise -> direction la porte")
    else
        doorFloor = nil
    end
    doorSince = nil
end)

-- etat a l'ecran
local statusGui = Instance.new("ScreenGui")
statusGui.Name = "HalloweenFarm"
statusGui.ResetOnSpawn = false
local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(0, 300, 0, 20)
statusLabel.Position = UDim2.new(0.5, -150, 0, 4)
statusLabel.BackgroundColor3 = Color3.fromRGB(28, 14, 6)
statusLabel.BackgroundTransparency = 0.3
statusLabel.TextColor3 = Color3.fromRGB(255, 170, 60)
statusLabel.Font = Enum.Font.GothamBold
statusLabel.TextSize = 11
statusLabel.Text = "HALLOWEEN : demarrage..."
statusLabel.Parent = statusGui
pcall(function() statusGui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)
if not statusGui.Parent then statusGui.Parent = player:WaitForChild("PlayerGui") end

local lastName = nil
local tries = 0

while true do

    local name, part, prompt = nil, nil, nil
    local keyFound = workspace:GetAttribute("CastleKeyFound")

    if keyFound == false then
        local key = findRealKey()
        if key then
            name, part, prompt = "cle", key.part, key.prompt
        end
    elseif keyFound == true and doorFloor ~= nil then
        if floorNow() > doorFloor
            or (doorSince and os.clock() - doorSince > DOOR_GIVE_UP) then
            print("[CLE] porte ouverte -> farm des mobs")
            doorFloor = nil
            doorSince = nil
        else
            local hole, p = findInRooms("KeyHole")
            if hole then
                name, part, prompt = "porte", partOf(hole), p
            end
        end
    end

    Objective.name = name
    Objective.pos = part and part.Position or nil

    if name ~= lastName then
        tries = 0
        lastName = name
        if name then print("[CLE] objectif : " .. name) end
    end

    local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    local dist = (root and Objective.pos) and (Objective.pos - root.Position).Magnitude or nil

    if name and dist and dist <= E_RANGE then
        if name == "porte" and not doorSince then
            doorSince = os.clock()
        end
        tries = tries + 1
        pressE()
        -- secours si le E clavier ne declenche pas le prompt
        if tries >= FIRE_AFTER and prompt and typeof(fireproximityprompt) == "function" then
            pcall(fireproximityprompt, prompt)
        end
    end

    local text
    if name then
        text = string.format("HALLOWEEN : %s a %s studs", name, dist and tostring(math.floor(dist)) or "?")
    elseif keyFound == false then
        text = "HALLOWEEN : vraie cle pas encore chargee"
    elseif keyFound == nil then
        text = "HALLOWEEN : attente du debut du donjon"
    else
        text = "HALLOWEEN : farm des mobs"
    end
    if Rescue.active then text = "HALLOWEEN : SECOURS en l'air (soin Time)" end
    statusLabel.Text = string.format("%s | PV %d %% | potions %d", text,
        math.floor(Life.ratio * 100 + 0.5), player:GetAttribute("VampyricPotions") or 0)

    task.wait(E_DELAY)

end

end)


game:GetService("Players").LocalPlayer.AncestryChanged:Connect(function(_, parent)
    if not parent then
        _G.FarmHalloweenInstance = nil
    end
end)

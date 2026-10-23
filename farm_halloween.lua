-- ==========================================================
-- FARM HALLOWEEN (Spooky Castle, workspace.Map.HalloweenDungeon)
-- ==========================================================
-- Base : farm_infinite (deplacement, touches 1 / F / 2 / C V G, retry).
-- En plus : va chercher la cle (Rooms.X.Key, E) puis ouvre la porte
-- (Rooms.X.KeyHole, E) avant de farmer les mobs ; clic gauche en
-- continu pendant la phase du slot 1.
-- En moins : pas de compteur 10 min + kills.
-- Hub : interrupteur "Halloween", incompatible avec FarmInfinite (meme
-- deplacement). Lance partout, il attend la carte HalloweenDungeon.

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
-- SCRIPT 1 - BOUCLE 1 / F / 2 / C V G
-- ==========================================================
task.spawn(function()

local RUN_TIME = 9
local F_DELAY = 0.1
local CYCLE_DELAY = 0.1

local function pressKey(keyCode, duration)
    VirtualInputManager:SendKeyEvent(
        true,
        keyCode,
        false,
        game
    )

    task.wait(duration or 0.05)

    VirtualInputManager:SendKeyEvent(
        false,
        keyCode,
        false,
        game
    )
end

local function pressOne()
    pressKey(Enum.KeyCode.One, 0.1)
end

local function pressTwo()
    pressKey(Enum.KeyCode.Two, 0.1)
end

local function pressCVG()
    pressKey(Enum.KeyCode.V)
    task.wait(0.1)
    pressKey(Enum.KeyCode.C)
    task.wait(0.1)
    pressKey(Enum.KeyCode.G)
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

local function startCycle()

    while true do

        -- ==========================================
        -- 1
        -- ==========================================
        print("1 Touche 1")

        pressOne()

        -- ==========================================
        -- SPAM F + CLIC GAUCHE PENDANT 9 SECONDES (slot 1)
        -- ==========================================
        print(" Spam F + clic gauche pendant " .. RUN_TIME .. " secondes")

        local startTime = os.clock()

        while os.clock() - startTime < RUN_TIME do
            pressKey(Enum.KeyCode.F, 0.05)
            clickLeft()
            task.wait(F_DELAY)
        end

        -- ==========================================
        -- 2
        -- ==========================================
        print("2 Touche 2")

        pressTwo()

        task.wait(CYCLE_DELAY)

        -- ==========================================
        -- C / V / G
        -- ==========================================
        print("[TP] C / V / G")

        pressCVG()

        task.wait(CYCLE_DELAY)

        -- Puis retour automatique sur 1
    end

end

-- Demarrage apres 3 secondes
task.wait(3)

startCycle()


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

spawn(function()

    local resetStarted = false

    while true do

        task.wait(1)

        if not resetStarted
            and workspace:FindFirstChild(
                "TeleportPortal"
            )
            and workspace.TeleportPortal:FindFirstChild(
                "Star"
            ) then

            resetStarted = true

            spawn(function()

                while true do

                    if player.Character
                        and player.Character:FindFirstChild(
                            "Humanoid"
                        ) then

                        player.Character.Humanoid.Health =
                            0

                    end

                    task.wait(0.1)

                end

            end)

        end

    end

end)
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
        if tries >= 3 and prompt and typeof(fireproximityprompt) == "function" then
            pcall(fireproximityprompt, prompt)
        end
    end

    if name then
        statusLabel.Text = string.format("HALLOWEEN : %s a %s studs", name, dist and tostring(math.floor(dist)) or "?")
    elseif keyFound == false then
        statusLabel.Text = "HALLOWEEN : vraie cle pas encore chargee"
    elseif keyFound == nil then
        statusLabel.Text = "HALLOWEEN : attente du debut du donjon"
    else
        statusLabel.Text = "HALLOWEEN : farm des mobs"
    end

    task.wait(E_DELAY)

end

end)


game:GetService("Players").LocalPlayer.AncestryChanged:Connect(function(_, parent)
    if not parent then
        _G.FarmHalloweenInstance = nil
    end
end)

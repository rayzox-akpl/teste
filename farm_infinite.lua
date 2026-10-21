-- ==========================================================
-- SECURITE : REJET DE TOUTE NOUVELLE EXECUTION
-- ==========================================================
-- Garde dediee : le hub remet _G.ScriptsAlreadyRunning a false
-- avant chaque lancement. Celle-ci n'est jamais reinitialisee.
if _G.FarmInfiniteInstance then
    warn("[X] Script deja actif - seconde instance annulee")
    return
end
_G.FarmInfiniteInstance = true

if _G.ScriptsAlreadyRunning then
warn("[X] REFUSE : Le script est deja actif. Inutile de le relancer !")
return
end

_G.ScriptsAlreadyRunning = true
print("[OK] Premier lancement : Initialisation des scripts...")

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

local function startCycle()

    while true do

        -- ==========================================
        -- 1
        -- ==========================================
        print("1 Touche 1")

        pressOne()

        -- ==========================================
        -- SPAM F PENDANT 9 SECONDES
        -- ==========================================
        print(" Spam F pendant " .. RUN_TIME .. " secondes")

        local startTime = os.clock()

        while os.clock() - startTime < RUN_TIME do
            pressKey(Enum.KeyCode.F, 0.05)
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
-- SCRIPT 5 - COMPTEUR 10 MIN + 3 KILLS
-- ==========================================================
task.spawn(function()

local TIMER_MINUTES = 10
local TIMER_SECONDS = TIMER_MINUTES * 60

local KILL_COUNT = 3
local KILL_DELAY = 7

print(
    "... Compteur 10 minutes demarre..."
)

task.wait(TIMER_SECONDS)

print(
    "[TIME] 10 minutes ecoulees - debut des "
    .. KILL_COUNT
    .. " kills..."
)

for i = 1, KILL_COUNT do

    local character =
        player.Character

    if character then

        local humanoid =
            character:FindFirstChildOfClass(
                "Humanoid"
            )

        if humanoid then

            print(
                "[KILL] Kill "
                .. i
                .. "/"
                .. KILL_COUNT
            )

            humanoid.Health = 0

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

        print(
            "... Attente "
            .. KILL_DELAY
            .. " secondes avant le prochain kill..."
        )

        task.wait(
            KILL_DELAY
        )

    end

end

print(
    "[OK] Sequence de kills terminee !"
)


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

    local direction =
        mobToFollow
            .HumanoidRootPart
            .Position
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

    if not mobToFollow
        or not mobToFollow:FindFirstChild(
            "HumanoidRootPart"
        ) then

        return

    end

    local directionToMob =
        mobToFollow
            .HumanoidRootPart
            .Position
        - rootPart.Position

    local distanceToMob =
        directionToMob.Magnitude

    local heightDifference =
        mobToFollow
            .HumanoidRootPart
            .Position.Y
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
                    getClosestMob()

                if closestMob then

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

game:GetService("Players").LocalPlayer.AncestryChanged:Connect(function(_, parent)
    if not parent then
        _G.FarmInfiniteInstance = nil
    end
end)

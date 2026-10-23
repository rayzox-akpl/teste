-- ==========================================================
-- HUB PERMANENT - CHARGEUR
-- Les scripts restent entiers sur le depot.
-- Le toggle les execute tels quels et les relance au retry.
-- ==========================================================

-- >>> LA SEULE LIGNE A CHANGER : "pseudo/nom-du-depot" de ton GitHub <<<
local GITHUB = "rayzox-akpl/teste-tel"
local BRANCH = "main"
local REPO = "https://raw.githubusercontent.com/" .. GITHUB .. "/" .. BRANCH .. "/"
local HUB_NAME = "Hub"
local HUB_VERSION = "v3.3"
-- Le hub ne se ferme JAMAIS tout seul (ni minuterie, ni ecran Start/Retry).
-- Mets true pour retrouver la fermeture automatique.
local AUTO_CLOSE = false

--====================================================
-- LISTE DES SCRIPTS
-- Ajoute une ligne pour chaque nouveau fichier du depot.
--====================================================

-- excl = scripts qui se battraient pour le personnage : en activer un
-- desactive les autres (le toggle se coupe tout seul).
local Scripts = {
    { name = "Kronax",        desc = "Boss Kronax complet",              file = "h_kronax.lua",
      excl = { "KronaxMinigun" } },
    { name = "KronaxMinigun", desc = "Kronax minigun + Start/Retry auto", file = "kronax_minigun.lua",
      excl = { "Kronax" } },
    { name = "LunosMinigun",  desc = "Lunos minigun + Start/Retry auto",  file = "lunos_minigun.lua" },
    { name = "Invaded",       desc = "Donjon envahi : cristaux puis mobs", file = "farm_invaded.lua",
      excl = { "FarmInfinite" } },
    { name = "FarmInfinite",  desc = "Farm infinite april fools",        file = "farm_infinite.lua",
      excl = { "Invaded" } },
    { name = "TpLunars",      desc = "Farm TP + Lunar Shard",            file = "tp_lunars.lua" },
}

--====================================================
-- ETAT PERSISTANT
--====================================================

-- Persistance par fichier : _G est detruit au changement de serveur
local STATE_FILE = "hub_state.json"
local HttpService = game:GetService("HttpService")

local function loadState()
    if isfile and readfile and isfile(STATE_FILE) then
        local ok, data = pcall(function()
            return HttpService:JSONDecode(readfile(STATE_FILE))
        end)
        if ok and type(data) == "table" and type(data.enabled) == "table" then
            return data
        end
    end
    return { enabled = {} }
end

local function saveState(state)
    if writefile then
        pcall(function()
            writefile(STATE_FILE, HttpService:JSONEncode({ enabled = state.enabled }))
        end)
    end
end

_G.HubState = _G.HubState or loadState()
local State = _G.HubState

-- Scripts deja lances dans CETTE session (survit au retry, pas au teleport)
_G.HubLaunched = _G.HubLaunched or {}
local Launched = _G.HubLaunched

if _G.HubGui then
    pcall(function() _G.HubGui:Destroy() end)
end

-- Jeton de session : les boucles des anciennes instances du hub
-- se terminent d'elles-memes quand ce numero change.
_G.HubSession = (_G.HubSession or 0) + 1
local SESSION = _G.HubSession
print("[HUB] Session " .. SESSION .. " -- version " .. HUB_VERSION .. ", " .. #Scripts .. " scripts")

-- ?v=os.time() : GitHub (et certains executors) gardent l'ancienne
-- version du fichier en cache plusieurs minutes. Avec un numero qui
-- change a chaque fois, on recupere toujours la derniere version poussee.
if queue_on_teleport then
    queue_on_teleport('loadstring(game:HttpGet("' .. REPO
        .. 'hub.lua?v=" .. tostring(os.time())))()')
end

--====================================================
-- SERVICES
--====================================================

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

-- Telephone : ecran tactile sans clavier (Delta mobile...). Le hub devient
-- petit, se range dans un bouton flottant, et s'efface pendant l'ecran de
-- fin pour ne jamais recouvrir Retry. FORCE_MOBILE = true/false pour forcer.
local FORCE_MOBILE = nil
local MOBILE = FORCE_MOBILE
if MOBILE == nil then
    MOBILE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

--====================================================
-- EXECUTION D'UN SCRIPT
-- On remet la garde a zero pour permettre la relance,
-- puis on execute le fichier sans le modifier.
--====================================================

local function runScript(entry, force)
    -- Le script tourne deja dans cette session : relancer creerait
    -- une seconde instance en parallele (double boucles).
    if Launched[entry.name] and not force then
        print("[HUB] " .. entry.name .. " tourne deja, relance ignoree")
        return true
    end

    -- Cache-buster : evite de recuperer une version perimee
    local url = REPO .. entry.file .. "?v=" .. tostring(tick())

    local ok, source = pcall(function()
        return game:HttpGet(url)
    end)

    if not ok or not source or #source < 20 then
        warn("[HUB] Telechargement echoue : " .. entry.file)
        return false
    end

    local fn, err = loadstring(source)
    if not fn then
        warn("[HUB] Compilation echouee : " .. entry.file .. " -> " .. tostring(err))
        return false
    end

    -- On ne touche PAS a _G.ScriptsAlreadyRunning : c'est la garde
    -- anti-double-execution des scripts. La reinitialiser laissait
    -- passer une seconde instance. Au changement de serveur, _G est
    -- vide de toute facon, donc la relance fonctionne toujours.

    -- Execution dans sa propre tache : Kronax/Lunos minigun et Invaded
    -- ATTENDENT leur carte (jusqu'a 30 s, ou en continu pour Invaded).
    -- Lances a la suite dans la meme tache, le premier bloquait les autres.
    Launched[entry.name] = true
    task.spawn(function()
        local runOk, runErr = pcall(fn)
        if not runOk then
            Launched[entry.name] = nil
            warn("[HUB] Execution : " .. entry.file .. " -> " .. tostring(runErr))
        end
    end)
    print("[HUB] " .. entry.name .. " lance")
    return true
end

--====================================================
-- RELANCE DES SCRIPTS ACTIFS
--====================================================

-- Lance uniquement ce qui est active ET pas deja en cours
local function launchMissing(reason)
    local count = 0
    for _, entry in ipairs(Scripts) do
        if State.enabled[entry.name] and not Launched[entry.name] then
            runScript(entry)
            count = count + 1
            task.wait(0.5)
        end
    end
    if count > 0 then
        print("[HUB] " .. count .. " script(s) lance(s) (" .. reason .. ")")
    end
end

-- Force la relance meme si le script tourne : a n'utiliser
-- que si tu sais que l'ancienne instance est morte.
local function forceRelaunchAll()
    for _, entry in ipairs(Scripts) do
        if State.enabled[entry.name] then
            runScript(entry, true)
            task.wait(0.5)
        end
    end
    print("[HUB] Relance forcee")
end

--====================================================
-- SURVEILLANCE DU RETRY
-- Detecte la fin du donjon et relance les scripts actifs.
--====================================================

task.spawn(function()
    local wasVisible = false

    while true do
        task.wait(1)

        -- Une instance plus recente a pris le relais
        if _G.HubSession ~= SESSION then
            print("[HUB] Session " .. SESSION .. " arretee")
            return
        end

        local gui = player:FindFirstChild("PlayerGui")
        local btn = gui and gui:FindFirstChild("RetryBtn", true)
        local visible = btn ~= nil

        -- Front montant : le bouton vient d'apparaitre
        if visible and not wasVisible then
            print("[HUB] Fin de donjon detectee")
            task.wait(6)
            -- Le retry reste sur le meme serveur : les scripts
            -- tournent toujours. On ne lance que ce qui manque.
            launchMissing("retry")
        end

        wasVisible = visible
    end
end)

--====================================================
-- INTERFACE
--====================================================

local parent
pcall(function() parent = gethui and gethui() end)
if not parent then pcall(function() parent = game:GetService("CoreGui") end) end
if not parent then parent = player:WaitForChild("PlayerGui") end

local gui = Instance.new("ScreenGui")
gui.Name = "PermanentHub"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = parent
_G.HubGui = gui

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 300, 0, 108 + #Scripts * 46)
main.Position = UDim2.new(1, -324, 0, 24)   -- coin haut droit
main.BackgroundColor3 = Color3.fromRGB(17, 18, 26)
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true
main.Parent = gui

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 12)
mainCorner.Parent = main

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(80, 120, 210)
stroke.Thickness = 2
stroke.Parent = main

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 36)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 17
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.Text = HUB_NAME .. "  " .. HUB_VERSION
title.Parent = main

local hint = Instance.new("TextLabel")
hint.Size = UDim2.new(1, 0, 0, 14)
hint.Position = UDim2.new(0, 0, 0, 32)
hint.BackgroundTransparency = 1
hint.Font = Enum.Font.Gotham
hint.TextSize = 11
hint.TextColor3 = Color3.fromRGB(120, 122, 145)
hint.Text = MOBILE and "bouton HUB pour ouvrir / fermer" or "RightCtrl pour cacher"
hint.Parent = main

--====================================================
-- TOGGLES COULISSANTS
--====================================================

local toggleRefs = {}

local function makeToggle(entry, index)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -24, 0, 38)
    row.Position = UDim2.new(0, 12, 0, 54 + (index - 1) * 46)
    row.BackgroundColor3 = Color3.fromRGB(26, 28, 38)
    row.BorderSizePixel = 0
    row.Parent = main

    local rc = Instance.new("UICorner")
    rc.CornerRadius = UDim.new(0, 8)
    rc.Parent = row

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -70, 0, 18)
    label.Position = UDim2.new(0, 10, 0, 3)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamMedium
    label.TextSize = 13
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextColor3 = Color3.fromRGB(235, 236, 245)
    label.Text = entry.name
    label.Parent = row

    local sub = Instance.new("TextLabel")
    sub.Size = UDim2.new(1, -70, 0, 14)
    sub.Position = UDim2.new(0, 10, 0, 20)
    sub.BackgroundTransparency = 1
    sub.Font = Enum.Font.Gotham
    sub.TextSize = 10
    sub.TextXAlignment = Enum.TextXAlignment.Left
    sub.TextColor3 = Color3.fromRGB(115, 118, 140)
    sub.Text = entry.desc
    sub.TextTruncate = Enum.TextTruncate.AtEnd
    sub.Parent = row

    local rail = Instance.new("TextButton")
    rail.Size = UDim2.new(0, 46, 0, 24)
    rail.Position = UDim2.new(1, -56, 0.5, -12)
    rail.BackgroundColor3 = Color3.fromRGB(58, 60, 76)
    rail.BorderSizePixel = 0
    rail.AutoButtonColor = false
    rail.Text = ""
    rail.Parent = row

    local railCorner = Instance.new("UICorner")
    railCorner.CornerRadius = UDim.new(1, 0)
    railCorner.Parent = rail

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 18, 0, 18)
    knob.Position = UDim2.new(0, 3, 0.5, -9)
    knob.BackgroundColor3 = Color3.fromRGB(225, 226, 235)
    knob.BorderSizePixel = 0
    knob.Parent = rail

    local knobCorner = Instance.new("UICorner")
    knobCorner.CornerRadius = UDim.new(1, 0)
    knobCorner.Parent = knob

    local info = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

    local function paint(on)
        TweenService:Create(rail, info, {
            BackgroundColor3 = on
                and Color3.fromRGB(64, 170, 105)
                or Color3.fromRGB(58, 60, 76)
        }):Play()

        TweenService:Create(knob, info, {
            Position = on
                and UDim2.new(1, -21, 0.5, -9)
                or UDim2.new(0, 3, 0.5, -9)
        }):Play()
    end

    local function apply(on, silent)
        State.enabled[entry.name] = on
        saveState(State)
        paint(on)

        -- scripts incompatibles : on les coupe
        if on and entry.excl then
            for _, other in ipairs(entry.excl) do
                if State.enabled[other] and toggleRefs[other] then
                    print("[HUB] " .. other .. " coupe (incompatible avec " .. entry.name .. ")")
                    toggleRefs[other](false, true)
                end
            end
        end

        if on and not silent then
            runScript(entry)
        elseif not on then
            print("[HUB] " .. entry.name .. " ne sera plus relance")
            print("      (l'instance en cours continue jusqu'au changement de serveur)")
        end
    end

    rail.MouseButton1Click:Connect(function()
        apply(not State.enabled[entry.name])
    end)

    toggleRefs[entry.name] = apply
    paint(State.enabled[entry.name] == true)
end

for i, entry in ipairs(Scripts) do
    makeToggle(entry, i)
end

--====================================================
-- BOUTON DE RELANCE MANUELLE
--====================================================

local relaunchBtn = Instance.new("TextButton")
relaunchBtn.Size = UDim2.new(1, -24, 0, 32)
relaunchBtn.Position = UDim2.new(0, 12, 0, 54 + #Scripts * 46 + 6)
relaunchBtn.BackgroundColor3 = Color3.fromRGB(48, 78, 150)
relaunchBtn.BorderSizePixel = 0
relaunchBtn.Font = Enum.Font.GothamMedium
relaunchBtn.TextSize = 13
relaunchBtn.TextColor3 = Color3.fromRGB(240, 242, 250)
relaunchBtn.Text = "Forcer la relance"
relaunchBtn.Parent = main

local rbc = Instance.new("UICorner")
rbc.CornerRadius = UDim.new(0, 8)
rbc.Parent = relaunchBtn

relaunchBtn.MouseButton1Click:Connect(function()
    forceRelaunchAll()
end)

--====================================================
-- RESTAURATION APRES TELEPORT
--====================================================

task.spawn(function()
    task.wait(2)

    if _G.HubSession ~= SESSION then return end

    local any = false
    for _, entry in ipairs(Scripts) do
        if State.enabled[entry.name] then any = true end
    end

    if any then
        launchMissing("chargement du hub")
    end
end)

--====================================================
-- RACCOURCI (PC) + MODE TELEPHONE
--====================================================

UserInputService.InputBegan:Connect(function(input, processed)
    if input.KeyCode == Enum.KeyCode.RightControl then
        main.Visible = not main.Visible
    end
end)

-- Glisser au doigt ou a la souris (Draggable ne marche pas au tactile).
-- onTap est appele si le doigt n'a presque pas bouge.
local function makeDraggable(handle, target, onTap)
    local dragging, startPos, startInput, moved = false, nil, nil, false
    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging, moved = true, false
            startInput = input.Position
            startPos = target.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType ~= Enum.UserInputType.Touch
            and input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
        local delta = input.Position - startInput
        if delta.Magnitude > 8 then moved = true end
        if moved then
            target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
            if not moved and onTap then onTap() end
        end
    end)
end

local toggleBtn = nil
local lastTouch = os.clock()

if MOBILE then
    -- panneau plus petit : l'echelle suit la hauteur de l'ecran
    local camera = workspace.CurrentCamera
    local viewY = camera and camera.ViewportSize.Y or 400
    local panelH = 108 + #Scripts * 46
    local scale = math.clamp((viewY * 0.6) / panelH, 0.4, 0.7)
    local uiScale = Instance.new("UIScale")
    uiScale.Scale = scale
    uiScale.Parent = main
    -- panneau en haut a droite, juste a gauche de la bulle
    main.AnchorPoint = Vector2.new(1, 0)
    main.Position = UDim2.new(1, -64, 0, 10)
    main.Draggable = false
    main.Visible = false            -- ferme au demarrage
    makeDraggable(title, main, nil)

    -- bulle HUB en haut a droite de l'ecran
    toggleBtn = Instance.new("TextButton")
    toggleBtn.Name = "HubToggle"
    toggleBtn.Size = UDim2.new(0, 46, 0, 46)
    toggleBtn.AnchorPoint = Vector2.new(1, 0)
    toggleBtn.Position = UDim2.new(1, -8, 0, 10)
    toggleBtn.BackgroundColor3 = Color3.fromRGB(17, 18, 26)
    toggleBtn.BackgroundTransparency = 0.15
    toggleBtn.BorderSizePixel = 0
    toggleBtn.AutoButtonColor = false
    toggleBtn.Font = Enum.Font.GothamBold
    toggleBtn.TextSize = 13
    toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    toggleBtn.Text = "HUB"
    toggleBtn.Parent = gui
    local tc = Instance.new("UICorner")
    tc.CornerRadius = UDim.new(1, 0)
    tc.Parent = toggleBtn
    local ts = Instance.new("UIStroke")
    ts.Color = Color3.fromRGB(80, 120, 210)
    ts.Thickness = 2
    ts.Parent = toggleBtn
    makeDraggable(toggleBtn, toggleBtn, function()
        main.Visible = not main.Visible
        lastTouch = os.clock()
    end)

    -- toute action dans le panneau repousse la fermeture auto
    main.InputBegan:Connect(function() lastTouch = os.clock() end)

    -- fermeture auto apres 30 s sans toucher le panneau
    task.spawn(function()
        while _G.HubSession == SESSION do
            task.wait(1)
            if AUTO_CLOSE and main.Visible and os.clock() - lastTouch > 30 then
                main.Visible = false
            end
        end
    end)
end

-- Ecran de debut / fin du jeu : on FERME le panneau une fois, au moment ou
-- Start ou Retry apparait, pour qu'il ne recouvre pas le bouton que les
-- scripts vont cliquer. Le bouton HUB reste toujours la, et tu peux rouvrir
-- le panneau quand tu veux : il n'est pas referme en boucle.
-- (v3 le cachait tant que StartBtn "existait" : en donjon ce bouton reste
-- dans l'interface, invisible a l'ecran, donc le hub disparaissait tout le
-- donjon et repartait des qu'on le rouvrait.)
local function reallyOnScreen(b)
    if not b:IsA("GuiObject") or not b.Visible then return false end
    local size, pos = b.AbsoluteSize, b.AbsolutePosition
    if size.X <= 2 or size.Y <= 2 then return false end
    local cam = workspace.CurrentCamera
    local vp = cam and cam.ViewportSize
    if vp and (pos.X + size.X < 0 or pos.Y + size.Y < 0
        or pos.X > vp.X or pos.Y > vp.Y) then
        return false
    end
    local a = b.Parent
    while a and not a:IsA("PlayerGui") do
        if (a:IsA("GuiObject") and not a.Visible)
            or (a:IsA("LayerCollector") and not a.Enabled) then
            return false
        end
        a = a.Parent
    end
    return true
end

local function gameButtonVisible()
    local pg = player:FindFirstChild("PlayerGui")
    if not pg then return false end
    for _, name in ipairs({ "RetryBtn", "StartBtn" }) do
        local b = pg:FindFirstChild(name, true)
        if b and reallyOnScreen(b) then return true end
    end
    return false
end

task.spawn(function()
    local wasBusy = false
    while _G.HubSession == SESSION do
        task.wait(0.5)
        local ok, busy = pcall(gameButtonVisible)
        busy = ok and busy
        if AUTO_CLOSE and busy and not wasBusy and main.Visible then
            main.Visible = false
            print("[HUB] Start/Retry a l'ecran -> panneau ferme (rouvrable)")
        end
        wasBusy = busy
    end
end)

print("[HUB] Charge - " .. #Scripts .. " scripts disponibles")

pcall(function()
    StarterGui:SetCore("SendNotification", {
        Title = HUB_NAME,
        Text = #Scripts .. " scripts disponibles",
        Duration = 3
    })
end)

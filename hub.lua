-- ==========================================================
-- HUB PERMANENT - CHARGEUR
-- Les scripts restent entiers sur le depot.
-- Le toggle les execute tels quels et les relance au retry.
-- ==========================================================

-- >>> LA SEULE LIGNE A CHANGER : "pseudo/nom-du-depot" de ton GitHub <<<
local GITHUB = "rayzox-akpl/teste"
local BRANCH = "main"
local REPO = "https://raw.githubusercontent.com/" .. GITHUB .. "/" .. BRANCH .. "/"
local HUB_NAME = "Hub"
local HUB_VERSION = "v3.6"
-- Le hub ne se ferme JAMAIS tout seul (ni minuterie, ni ecran Start/Retry).
-- Mets true pour retrouver la fermeture automatique.
local AUTO_CLOSE = false

--====================================================
-- LISTE DES SCRIPTS
-- Ajoute une ligne pour chaque nouveau fichier du depot.
--====================================================

-- excl = scripts qui se battraient pour le personnage : en activer un
-- desactive les autres (le toggle se coupe tout seul).
-- button = true : bouton au lieu d'un toggle. Un appui lance le script ;
-- rien n'est memorise, il n'est pas relance au teleport.
local Scripts = {
    { name = "Kronax",        desc = "Boss Kronax complet",              file = "h_kronax.lua",
      excl = { "KronaxMinigun", "Kronax mini - cristaux" } },
    { name = "KronaxMinigun", desc = "Kronax minigun + Start/Retry auto", file = "kronax_minigun.lua",
      excl = { "Kronax", "Kronax mini - cristaux" } },
    { name = "Kronax mini - cristaux", desc = "Minigun boss seul (alt)",  file = "kronax_mini_sans_cristaux.lua",
      excl = { "Kronax", "KronaxMinigun" } },
    { name = "HKronaxKey",    desc = "Achat cles Heroic Kronax (B = stop)", file = "h_kronax_key.lua",
      button = true },
    { name = "LunosMinigun",  desc = "Lunos minigun + Start/Retry auto",  file = "lunos_minigun.lua" },
    { name = "Invaded",       desc = "Donjon envahi : cristaux puis mobs", file = "farm_invaded.lua",
      excl = { "FarmInfinite" } },
    { name = "FarmInfinite",  desc = "Farm infinite april fools",        file = "farm_infinite.lua",
      excl = { "Invaded", "Halloween v2" } },
    { name = "Halloween v2",  desc = "Chateau : cle, porte, mobs, soins", file = "farm_halloween_v2.lua",
      excl = { "FarmInfinite" } },
    { name = "TpLunars",      desc = "Farm TP + Lunar Shard",            file = "tp_lunars.lua" },
}

--====================================================
-- ETAT PERSISTANT (3 couches, la plus fiable gagne)
--   1. etat injecte dans le code relance au teleport (aucun fichier)
--   2. fichier hub_state_v2.json (writefile / readfile)
--   3. _G (meme serveur uniquement)
--====================================================

local HttpService = game:GetService("HttpService")
local TeleportPlayer = game:GetService("Players").LocalPlayer

-- Relance apres teleport : queue_on_teleport nous rappelle avec
-- _G.HubBoot (l'etat), _G.HubFromTeleport et _G.HubBootStamp.
local BOOT = _G.HubBoot
local FROM_TP = _G.HubFromTeleport
local STAMP = _G.HubBootStamp
_G.HubBoot, _G.HubFromTeleport, _G.HubBootStamp = nil, nil, nil

if FROM_TP then
    if _G.HubLoadedJob == game.JobId then
        -- Un hub tourne deja dans ce serveur : on FUSIONNE l'etat recu
        -- (si plus recent) au lieu de reconstruire une 2e interface.
        print("[HUB] copie teleport fusionnee (pas de nouvelle interface)")
        if (STAMP or 0) > (_G.HubBootStamp2 or 0) then
            _G.HubBootStamp2 = STAMP or 0
            if _G.HubMerge then
                pcall(_G.HubMerge, BOOT)
            else
                _G.HubPendingBoot = BOOT   -- le hub n'a pas fini de se construire
            end
        end
        return
    end
    -- Nouveau serveur : les scripts de l'ancien sont morts
    _G.HubLaunched = {}
    _G.HubBootStamp2 = STAMP or 0
end
_G.HubLoadedJob = game.JobId
_G.HubMerge = nil

local STATE_FILES = { "hub_state_v2.json", "hub_state.json" }
local DIAG = "?"
local hintLabel, hintBase = nil, ""

local function setDiag(text)
    DIAG = text
    if hintLabel then hintLabel.Text = hintBase .. " - " .. DIAG end
end

local function decodeState(str)
    if type(str) ~= "string" then return nil end
    local ok, d = pcall(function() return HttpService:JSONDecode(str) end)
    if ok and type(d) == "table" and type(d.enabled) == "table" then
        return d
    end
    return nil
end

local function loadState()
    -- couche 1 : etat injecte au teleport
    if BOOT then
        local d = decodeState(BOOT)
        if d then DIAG = "etat recu (teleport)" return d end
    end
    -- couche 2 : fichiers
    if isfile and readfile then
        for _, f in ipairs(STATE_FILES) do
            local ok, content = pcall(function()
                if isfile(f) then return readfile(f) end
            end)
            if ok and content then
                local d = decodeState(content)
                if d then DIAG = "etat lu (fichier)" return d end
            end
        end
    end
    DIAG = "aucun etat sauvegarde"
    return { enabled = {} }
end

local function saveState(state)
    _G.HubState = state
    if not writefile then
        setDiag("pas de writefile (teleport seul)")
        return
    end
    local ok, err = pcall(function()
        writefile(STATE_FILES[1], HttpService:JSONEncode({ enabled = state.enabled }))
    end)
    setDiag(ok and "sauvegarde OK" or ("erreur fichier: " .. tostring(err)))
end

-- BOOT gagne toujours (sinon un _G perime d'un ancien serveur pourrait
-- ecraser l'etat). Sans BOOT : _G, puis fichier.
_G.HubState = (BOOT and loadState()) or _G.HubState or loadState()
local State = _G.HubState

-- Scripts deja lances dans CETTE session (survit au retry, pas au teleport)
_G.HubLaunched = _G.HubLaunched or {}
local Launched = _G.HubLaunched

-- On remet le fichier a jour des le demarrage (migration + verification)
saveState(State)

if _G.HubGui then
    pcall(function() _G.HubGui:Destroy() end)
end

-- Jeton de session : les boucles des anciennes instances du hub
-- se terminent d'elles-memes quand ce numero change.
_G.HubSession = (_G.HubSession or 0) + 1
local SESSION = _G.HubSession
print("[HUB] Session " .. SESSION .. " -- version " .. HUB_VERSION .. ", " .. #Scripts .. " scripts")

-- Relance du hub apres teleport, AVEC l'etat dedans (%q echappe la chaine).
-- Le numero de version (?v=) evite le cache de GitHub.
-- v3.6 : l'executor garde CHAQUE appel a queue_on_teleport (demarrage +
-- teleport, relances manuelles, file pas toujours videe) et chaque copie
-- retelechargeait et reexecutait tout le hub. Le code en file verifie
-- _G.HubTpRan : la 1re copie charge le hub, les suivantes ne font que
-- transmettre leur etat s'il est plus recent, sans recharger le hub.
local function queueBoot(why)
    if not queue_on_teleport then return end
    local ok, err = pcall(function()
        local json = HttpService:JSONEncode({ enabled = State.enabled })
        local code = string.format(
            'local j, s = %q, %.3f; '
            .. 'if _G.HubTpRan then '
            .. 'if s > (_G.HubTpStamp or 0) then _G.HubTpStamp = s; '
            .. 'if _G.HubMerge then pcall(_G.HubMerge, j) else _G.HubPendingBoot = j end end '
            .. 'return end; '
            .. '_G.HubTpRan = true; _G.HubTpStamp = s; '
            .. '_G.HubBoot = j; _G.HubFromTeleport = true; _G.HubBootStamp = s; '
            .. 'loadstring(game:HttpGet(%q .. tostring(os.time())))()',
            json, tick(), REPO .. "hub.lua?v=")
        queue_on_teleport(code)
    end)
    print("[HUB] queue_on_teleport (" .. why .. ") : " .. (ok and "ok" or tostring(err)))
end

-- Filet de securite si le teleport n'annonce rien
if _G.HubStartQueued ~= game.JobId then
    _G.HubStartQueued = game.JobId
    queueBoot("demarrage")
end

-- Au moment du teleport : on met en file l'etat LE PLUS RECENT
local teleportQueued = false
TeleportPlayer.OnTeleport:Connect(function(tpState)
    if tpState == Enum.TeleportState.Failed then return end
    if teleportQueued then return end
    teleportQueued = true
    queueBoot("teleport")
end)

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

    -- RESERVATION IMMEDIATE : HttpGet attend le reseau (le code est
    -- suspendu). Sans ca, plusieurs lanceurs simultanes (restauration,
    -- fusion teleport, retry) passent tous le test ci-dessus avant que
    -- le premier ait fini de telecharger -> script lance 2-3 fois.
    Launched[entry.name] = true

    -- Cache-buster : evite de recuperer une version perimee
    local url = REPO .. entry.file .. "?v=" .. tostring(tick())

    local ok, source = pcall(function()
        return game:HttpGet(url)
    end)

    if not ok or not source or #source < 20 then
        Launched[entry.name] = nil   -- libere la reservation : on pourra reessayer
        warn("[HUB] Telechargement echoue : " .. entry.file)
        return false
    end

    local fn, err = loadstring(source)
    if not fn then
        Launched[entry.name] = nil
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
hintBase = MOBILE and "bouton HUB" or "RightCtrl pour cacher"
hintLabel = hint
hint.TextSize = 10
hint.Text = hintBase .. " - " .. DIAG
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

    -- bouton simple : un appui = un lancement, pas d'etat memorise
    if entry.button then
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, 60, 0, 24)
        btn.Position = UDim2.new(1, -70, 0.5, -12)
        btn.BackgroundColor3 = Color3.fromRGB(48, 78, 150)
        btn.BorderSizePixel = 0
        btn.AutoButtonColor = true
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 11
        btn.TextColor3 = Color3.fromRGB(240, 242, 250)
        btn.Text = "LANCER"
        btn.Parent = row
        local bc = Instance.new("UICorner")
        bc.CornerRadius = UDim.new(0, 8)
        bc.Parent = btn
        btn.MouseButton1Click:Connect(function()
            btn.Text = "..."
            task.spawn(function()
                local ok = runScript(entry, true)
                btn.Text = ok and "LANCE" or "ERREUR"
                task.wait(2)
                btn.Text = "LANCER"
            end)
        end)
        return
    end

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

-- Fusion d'un etat recu au teleport dans le hub deja ouvert
local function mergeBoot(bootJson)
    local d = decodeState(bootJson)
    if not d then return end
    for _, entry in ipairs(Scripts) do
        local want = d.enabled[entry.name] == true
        if (State.enabled[entry.name] == true) ~= want and toggleRefs[entry.name] then
            toggleRefs[entry.name](want, true)
        end
    end
    setDiag("etat recu (teleport)")
    task.spawn(function() launchMissing("teleport") end)
end
_G.HubMerge = mergeBoot
if _G.HubPendingBoot then
    local pending = _G.HubPendingBoot
    _G.HubPendingBoot = nil
    mergeBoot(pending)
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

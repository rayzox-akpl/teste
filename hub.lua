-- ==========================================================
-- HUB PERMANENT - CHARGEUR
-- Les scripts restent entiers sur le depot.
-- Le toggle les execute tels quels et les relance au retry.
-- ==========================================================

local REPO = "https://raw.githubusercontent.com/rayzox-akpl/teste/main/"
local HUB_NAME = "Hub"

--====================================================
-- LISTE DES SCRIPTS
-- Ajoute une ligne pour chaque nouveau fichier du depot.
--====================================================

local Scripts = {
    { name = "Kronax",       desc = "Boss Kronax complet",        file = "h_kronax.lua" },
    { name = "FarmInfinite", desc = "Farm infinite april fools",  file = "farm_infinite.lua" },
    { name = "TpLunars",     desc = "Farm TP + Lunar Shard",      file = "tp_lunars.lua" },
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

if queue_on_teleport then
    queue_on_teleport('loadstring(game:HttpGet("' .. REPO .. 'hub.lua"))()')
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

    -- La garde des scripts bloque toute relance : on la libere
    _G.ScriptsAlreadyRunning = false

    local runOk, runErr = pcall(fn)
    if not runOk then
        warn("[HUB] Execution : " .. entry.file .. " -> " .. tostring(runErr))
        return false
    end

    Launched[entry.name] = true
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
main.Position = UDim2.new(0, 24, 0.5, -140)
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
title.Text = HUB_NAME
title.Parent = main

local hint = Instance.new("TextLabel")
hint.Size = UDim2.new(1, 0, 0, 14)
hint.Position = UDim2.new(0, 0, 0, 32)
hint.BackgroundTransparency = 1
hint.Font = Enum.Font.Gotham
hint.TextSize = 11
hint.TextColor3 = Color3.fromRGB(120, 122, 145)
hint.Text = "RightCtrl pour cacher"
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

    local any = false
    for _, entry in ipairs(Scripts) do
        if State.enabled[entry.name] then any = true end
    end

    if any then
        launchMissing("chargement du hub")
    end
end)

--====================================================
-- RACCOURCI
--====================================================

UserInputService.InputBegan:Connect(function(input, processed)
    if input.KeyCode == Enum.KeyCode.RightControl then
        main.Visible = not main.Visible
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

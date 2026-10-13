-- ==========================================================
--  FARM INVADED  --  donjon envahi : cristaux d'abord, mobs ensuite
--
--  Base : ton farm (touches 1 / F 9 s / 2 / V C G, suivi du mob le plus
--  proche a WalkSpeed 80, noclip, vol BodyVelocity, Retry / Proceed,
--  StartDungeon). Ce qui change, c'est QUI on suit.
--
--  Ce que le dump a montre :
--    * cristaux a casser : Workspace.MapContent.InvadedCrystals.LobbyCrystal
--      etiquette InvadedCrystal, attributs Health / MaxHealth,
--      CrystalState "Corrupted" -> "Purified" quand il est casse
--    * cristal du rituel : Workspace.MapContent.RecursiveRelics.PurificationRitual
--      etiquette InvadedRitual, 1 500 000 PV, 20 s sinon tout le monde meurt
--    * DECOR (pas de vie, ne pas viser) : CrystalFX, SpinShards
--    * ElementalOnly = true : seuls les degats d'element les touchent
--    * Scary Sprite : impossible a tuer, ne compte pas pour la salle
--    * Void Sprite en mode "Hold" : il te tient (HoldingUserId = toi)
--
--  ORDRE DES CIBLES
--    1. un Sprite qui te tient
--    2. le cristal du rituel (compte a rebours)
--    3. les cristaux corrompus encore en vie, le plus proche d'abord
--    4. les mobs, comme dans ton script (le plus proche, seuil de 5 studs)
--
--  Garde-fou : une cible qui ne perd aucun PV alors qu'on est dessus
--  (immunite, Scary Sprite, Mummy...) est mise de cote un moment.
--
--  EVENEMENTS ALEATOIRES (module InvadedDungeonsEvent) -- lus dans
--  l'attribut "InvadedEvents" du workspace :
--    Nuclear        : mob "Nuclear" mort -> zone 30 studs, 2,5 s -> on sort
--    LightningStorm, Eruption, Golem, Shaman : anneaux d'alerte detectes
--                     a l'apparition -> on sort de l'anneau (TP si urgent)
--    Corruption     : sol qui brule -> sauts en continu
--    BatSwarm / CursedMummy : rester au sol (pas de vol)
--    Overflow       : lave 120 studs -> on monte au-dessus pendant 20 s
--    ScarySprites, Cursed Mummy, Whirlpool : zones mobiles a eviter
--    Corrupted Shaman : cible prioritaire (ses orages partent avec lui)
--    Graceful       : healers tues avant les autres mobs
--    MummysCurse    : sarcophage casse APRES tous les cristaux
--  Journal : logs/invaded/evenements.txt (anneaux vus, gros degats) pour
--  affiner la detection si un evenement te touche encore.
--
--  Demarrage : attend d'etre dans un donjon Invaded (rien dans le hub).
--  Arret : touche B, ou _G.StopInvadedFarm(). Relancer remplace l'ancien.
-- ==========================================================

if typeof(_G.StopInvadedFarm) == "function" then
    pcall(_G.StopInvadedFarm, "remplace")
    task.wait(0.3)
end

_G.InvadedFarmToken = (_G.InvadedFarmToken or 0) + 1
local TOKEN = _G.InvadedFarmToken
local running = true
local function on()
    return running and _G.InvadedFarmToken == TOKEN
end

repeat task.wait() until game:IsLoaded()

local Players             = game:GetService("Players")
local VirtualInputManager = game:GetService("VirtualInputManager")
local GuiService          = game:GetService("GuiService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local RunService          = game:GetService("RunService")
local CollectionService   = game:GetService("CollectionService")

local player = Players.LocalPlayer
repeat task.wait() until player

--====================================================
-- ARRET AVEC B (marche aussi pendant l'attente)
--====================================================
local STOP_KEY = Enum.KeyCode.B
local stopKeyConn = game:GetService("UserInputService").InputBegan:Connect(
    function(input, gameProcessed)
        -- gameProcessed = tu ecris dans le chat : on ne coupe pas
        if gameProcessed or input.KeyCode ~= STOP_KEY then return end
        if typeof(_G.StopInvadedFarm) == "function" then
            _G.StopInvadedFarm("touche B")
        end
    end)

-- arret provisoire tant que le farm n'est pas demarre
_G.StopInvadedFarm = function(reason)
    if _G.InvadedFarmToken ~= TOKEN then return end
    running = false
    pcall(function() stopKeyConn:Disconnect() end)
    _G.StopInvadedFarm = nil
    print("[INVADED] arret pendant l'attente : " .. tostring(reason))
    local g = (gethui and pcall(gethui)) and gethui():FindFirstChild("InvadedWait")
    if g then pcall(function() g:Destroy() end) end
end

--====================================================
-- ATTENTE DU DONJON INVADED (comme Kronax qui attend son boss)
-- Dans le hub / lobby, ou dans un donjon normal, le script ne fait rien
-- et attend. Il demarre seul des que tu es dans un donjon envahi.
--====================================================
-- Signes d'un donjon envahi. L'attribut "Invaded" du workspace suffit en
-- Strike ; on accepte aussi la presence de cristaux / mobs envahis, au cas
-- ou l'attribut arrive en retard ou porte une autre valeur.
local function invadedSigns()
    local inv = workspace:GetAttribute("Invaded")
    if inv ~= nil and inv ~= false and inv ~= "" then return true end
    local mc = workspace:FindFirstChild("MapContent")
    if mc and mc:FindFirstChild("InvadedCrystals") then return true end
    return #CollectionService:GetTagged("InvadedMob") > 0
        or #CollectionService:GetTagged("InvadedCrystal") > 0
end

local function inInvadedDungeon()
    -- les raids ont leur propre script (Kronax / Lunos) : jamais ici
    local map = workspace:FindFirstChild("Map")
    if map and (map:FindFirstChild("LunosRaid") or map:FindFirstChild("TimeRaidDungeon")) then
        return false, "raid Kronax/Lunos"
    end
    if not invadedSigns() then return false, "pas envahi" end
    -- le lobby peut aussi etre "envahi" : on exige un vrai donjon
    local mode = workspace:GetAttribute("PlaceMode")
    if mode == "Dungeon" or workspace:GetAttribute("DungeonInstanceType") ~= nil then
        return true
    end
    return false, "pas un donjon (PlaceMode=" .. tostring(mode) .. ")"
end

-- Etat visible a l'ecran pendant l'attente (sur telephone la console est
-- peu pratique) : on voit tout de suite POURQUOI il attend.
local waitGui, waitLabel = nil, nil
local function waitStatus(text)
    if not waitGui then
        waitGui = Instance.new("ScreenGui")
        waitGui.Name = "InvadedWait"
        waitGui.ResetOnSpawn = false
        local l = Instance.new("TextLabel")
        l.Name = "L"
        l.Size = UDim2.new(0, 360, 0, 20)
        l.Position = UDim2.new(0.5, -180, 0, 4)
        l.BackgroundColor3 = Color3.fromRGB(20, 12, 34)
        l.BackgroundTransparency = 0.3
        l.TextColor3 = Color3.fromRGB(215, 190, 255)
        l.Font = Enum.Font.GothamBold
        l.TextSize = 11
        l.TextScaled = false
        l.Active = false
        l.Parent = waitGui
        waitLabel = l
        pcall(function() waitGui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)
        if not waitGui.Parent then waitGui.Parent = player:WaitForChild("PlayerGui") end
    end
    waitLabel.Text = text
end

print("[INVADED] script charge, verification de la carte...")
local okNow, whyNot = inInvadedDungeon()
if not okNow then
    print("[INVADED] pas dans un donjon Invaded (" .. tostring(whyNot) .. ") -> en attente (B pour annuler)")
    local lastPrint = 0
    while on() do
        local ok, why = inInvadedDungeon()
        if ok then break end
        waitStatus("INVADED : en attente du donjon envahi (" .. tostring(why) .. ")  [B = annuler]")
        if os.clock() - lastPrint > 20 then
            lastPrint = os.clock()
            print(string.format("[INVADED] attente : %s | Invaded=%s PlaceMode=%s DungeonInstanceType=%s",
                tostring(why), tostring(workspace:GetAttribute("Invaded")),
                tostring(workspace:GetAttribute("PlaceMode")),
                tostring(workspace:GetAttribute("DungeonInstanceType"))))
        end
        task.wait(1)
    end
    if waitGui then pcall(function() waitGui:Destroy() end) waitGui = nil end
    if not on() then return end
    print("[INVADED] donjon Invaded detecte (" .. tostring(workspace:GetAttribute("Invaded"))
        .. ") -> demarrage")
end

--====================================================
-- CONFIG
--====================================================
local CONFIG = {
    -- cycle de touches (identique a ta base)
    RUN_TIME     = 9,
    F_DELAY      = 0.1,
    CYCLE_DELAY  = 0.1,

    -- deplacement (identique a ta base)
    TARGET_SPEED = 80,
    SWITCH_DISTANCE_THRESHOLD = 5,
    FLY_SPEED    = 100,
    FLY_HEIGHT_DIFF = 50,

    -- cristaux
    CRYSTAL_STOP     = 3,     -- distance d'arret sur un cristal
    CRYSTAL_RANGE    = 700,   -- ignore les cristaux plus loin que ca
    SELECT_PERIOD    = 0.1,   -- choix de cible 10 fois par seconde

    -- garde-fou "cible qui ne prend pas de degats"
    STALL_RANGE      = 30,    -- on ne juge que si on est a cote
    STALL_CRYSTAL    = 20,    -- s sans perte de PV avant de passer
    STALL_MOB        = 12,
    STALL_SKIP       = 15,    -- s mise de cote

    -- visee : camera + souris sur la cible avant chaque touche, pour que
    -- les sorts d'element partent vers le cristal (ElementalOnly)
    AIM_CAMERA       = true,
    AIM_MOUSE        = true,
    CAM_BACK         = 18,
    CAM_UP           = 9,

    -- evenements
    EVENTS           = true,
    NUCLEAR_RADIUS   = 48,    -- anneau StrikeWarning vu en jeu : 95 de diametre
    NUCLEAR_TIME     = 3.2,
    HAZARD_MARGIN    = 7,     -- marge ajoutee a chaque zone
    RING_MIN         = 12,    -- diametre mini d'un anneau d'alerte
    RING_MAX         = 160,   -- diametre maxi
    RING_LIFE        = 4,     -- duree max d'une zone d'anneau
    URGENT_TP        = true,  -- TP court hors d'une zone qui va tomber
    TP_MAX           = 70,
    MOVER_RADIUS = {          -- zones mobiles (etiquette -> rayon)
        InvadedMummy     = 32,  -- Cursed Mummy : chasse a 25 studs
        InvadedWhirlpool = 26,  -- tourbillon : poursuit a 20 studs
    },
    SCARY_RADIUS     = 24,
    BLOCKED_SKIP     = 5,     -- s avant de lacher une cible coincee dans une zone mobile
    OVERFLOW_TIME    = 20,    -- 3 alerte + 10 montee + 2 + 4 descente + 1
    OVERFLOW_HEIGHT  = 140,
    EVENT_LOG        = "logs/invaded/evenements.txt",
    BIG_HIT          = 0.12,  -- coup >= 12 % de la vie -> on journalise

    -- retry
    RETRY_ON_END     = true,

    -- parties de ta base COUPEES par defaut (voir message) :
    --   kill force apres 10 minutes, et boucle de mort sur TeleportPortal
    KILL_AFTER_10MIN = false,
    PORTAL_KILL_LOOP = false,

    DEBUG = true,
}

local function log(...)
    if CONFIG.DEBUG then print("[INVADED]", ...) end
end

--====================================================
-- NETTOYAGE
--====================================================
local conns = {}
local function track(c) conns[#conns + 1] = c; return c end

--====================================================
-- REMOTES
--====================================================
local function knitService(name)
    local ok, svc = pcall(function()
        return ReplicatedStorage:WaitForChild("ReplicatedStorage", 10)
            :WaitForChild("Packages", 10):WaitForChild("Knit", 10)
            :WaitForChild("Services", 10):WaitForChild(name, 10)
    end)
    return ok and svc or nil
end

local function startDungeon()
    pcall(function()
        knitService("DungeonService").RF.StartDungeon:InvokeServer()
    end)
end

local function respawned()
    pcall(function()
        knitService("DungeonService").RF.Respawned:InvokeServer()
    end)
end

--====================================================
-- CLIC (identique a ta base)
--====================================================
local function clickButton(btn)
    local inset = GuiService:GetGuiInset()
    local x = btn.AbsolutePosition.X + btn.AbsoluteSize.X / 2
    local y = btn.AbsolutePosition.Y + btn.AbsoluteSize.Y / 2 + inset.Y
    VirtualInputManager:SendMouseMoveEvent(x, y, game)
    task.wait(0.01)
    VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
    task.wait(0.01)
    VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
end

local function guiVisible(object)
    if not object:IsA("GuiObject") or not object.Visible then return false end
    local a = object.Parent
    while a do
        if a:IsA("ScreenGui") then return a.Enabled end
        if a:IsA("GuiObject") and not a.Visible then return false end
        a = a.Parent
    end
    return false
end

--====================================================
-- PERSONNAGE
--====================================================
local character = player.Character or player.CharacterAdded:Wait()
local humanoid  = character:WaitForChild("Humanoid")
local rootPart  = character:WaitForChild("HumanoidRootPart")
local flyVelocity = nil

local function clearFly()
    if flyVelocity then
        flyVelocity:Destroy()
        flyVelocity = nil
    end
end

--====================================================
-- CIBLES
--====================================================
-- cible courante : { kind = "ritual"|"crystal"|"mob"|"holder", model, pos() }
local current = nil
local skipUntil = setmetatable({}, { __mode = "k" })
local stall = setmetatable({}, { __mode = "k" })   -- model -> {hp, t}

local function now() return os.clock() end

local function partPosition(model)
    local p = model:FindFirstChild("Root") or model:FindFirstChild("Core")
        or model.PrimaryPart
    if p and p:IsA("BasePart") then return p.Position end
    local ok, cf = pcall(model.GetPivot, model)
    if ok and cf then return cf.Position end
    return nil
end

local function crystalAlive(model)
    if not model or not model.Parent then return false end
    local hp = model:GetAttribute("Health")
    if type(hp) ~= "number" or hp <= 0 then return false end
    if model:GetAttribute("CrystalState") == "Purified" then return false end
    return true
end

local function mobAlive(model)
    if not model or not model.Parent then return nil end
    local hum = model:FindFirstChildOfClass("Humanoid")
    local hrp = model:FindFirstChild("HumanoidRootPart")
    if not hum or not hrp or hum.Health <= 0 then return nil end
    -- Scary Sprite : ne peut pas mourir, ne compte pas pour la salle
    if model:GetAttribute("ScarySprite") then return nil end
    -- Cursed Mummy : ne peut etre ni touche ni tue
    if CollectionService:HasTag(model, "InvadedMummy")
        or model.Name:lower():find("cursed mummy", 1, true) then
        return nil
    end
    return hum, hrp
end

local function objPos(o)
    if not o or not o.Parent then return nil end
    if o:IsA("BasePart") then return o.Position end
    if o:IsA("Model") then
        local hrp = o:FindFirstChild("HumanoidRootPart")
        if hrp then return hrp.Position end
        local ok, cf = pcall(o.GetPivot, o)
        if ok and cf then return cf.Position end
    end
    return nil
end

local function flat(v) return Vector3.new(v.X, 0, v.Z) end

--====================================================
-- EVENEMENTS
--====================================================
local EV = {}             -- evenements actifs : EV.Nuclear = true ...
local hazards = {}        -- zones fixes {pos, r, t0, t1, part, label, urgent}
local escapeGoal = nil    -- point sur ou on se replie
local overflowUntil, overflowY = 0, nil
local evLog = {}          -- lignes du journal

local function elog(text)
    evLog[#evLog + 1] = string.format("[%7.2f] %s", os.clock(), text)
    if #evLog > 3000 then table.remove(evLog, 1) end
    log(text)
end

local function flushLog()
    if typeof(writefile) ~= "function" then return end
    pcall(function()
        if typeof(makefolder) == "function" then
            pcall(makefolder, "logs"); pcall(makefolder, "logs/invaded")
        end
        writefile(CONFIG.EVENT_LOG, table.concat(evLog, "\n"))
    end)
end

local EVENT_TEXT = {
    Nuclear = "mobs qui explosent a leur mort (40 %, anneau 95 studs) -> on s'eloigne",
    LightningStorm = "eclairs (50 %, anneau 10 studs) -> on sort des anneaux",
    TropicalThunderstorm = "eclairs (50 %) -> on sort des anneaux",
    Eruption = "meteores (15 %, 14 studs) -> on sort des anneaux",
    Corruption = "sol corrompu (3 %/s) -> sauts en continu",
    BatSwarm = "chauves-souris si on vole -> on reste au sol",
    CursedMummy = "momie intouchable -> on l'evite, on reste au sol",
    Overflow = "lave 120 studs -> on monte au-dessus",
    ScarySprites = "Sprite geant immortel -> on l'evite",
    Whirlpool = "tourbillons -> on les evite",
    RainDance = "Shaman -> cible prioritaire",
    MoltenGolem = "Golem -> on sort de ses anneaux de slam",
    Graceful = "healers -> tues en premier",
    PurificationRitual = "rituel -> priorite absolue",
    MummysCurse = "sarcophage -> casse apres les cristaux",
}

local function readEvents()
    local s = workspace:GetAttribute("InvadedEvents")
    local set = {}
    if type(s) == "string" then
        for k in s:gmatch("[^,%s]+") do set[k] = true end
    end
    for k in pairs(set) do
        if not EV[k] then
            elog("EVENEMENT " .. k .. (EVENT_TEXT[k] and (" : " .. EVENT_TEXT[k]) or ""))
            if k == "Overflow" and rootPart then
                overflowUntil = os.clock() + CONFIG.OVERFLOW_TIME
                overflowY = rootPart.Position.Y + CONFIG.OVERFLOW_HEIGHT
            end
        end
    end
    EV = set
end

local function noAir()
    return EV.BatSwarm or EV.CursedMummy
        or #CollectionService:GetTagged("InvadedBatSwarm") > 0
end

local function addHazard(pos, r, life, label, part, urgent)
    if #hazards > 80 then table.remove(hazards, 1) end
    local t = os.clock()
    hazards[#hazards + 1] = {
        pos = pos, r = r + CONFIG.HAZARD_MARGIN, t0 = t, t1 = t + life,
        label = label, part = part, urgent = urgent,
    }
end

local function pruneHazards()
    local t = os.clock()
    for i = #hazards, 1, -1 do
        local h = hazards[i]
        local gone = h.part and not h.part.Parent and t - h.t0 > 0.2
        if t > h.t1 or gone then table.remove(hazards, i) end
    end
end

-- zones mobiles recalculees a chaque appel
local function movers()
    local out = {}
    for tag, r in pairs(CONFIG.MOVER_RADIUS) do
        for _, o in ipairs(CollectionService:GetTagged(tag)) do
            local p = objPos(o)
            if p then out[#out + 1] = { pos = p, r = r, label = tag } end
        end
    end
    local mobs = workspace:FindFirstChild("Mobs")
    if mobs then
        for _, m in ipairs(mobs:GetChildren()) do
            if m:GetAttribute("ScarySprite") then
                local p = objPos(m)
                if p then
                    out[#out + 1] = { pos = p, r = CONFIG.SCARY_RADIUS, label = "ScarySprite" }
                end
            end
        end
    end
    return out
end

local function hazardAt(p, mv)
    local fp = flat(p)
    for _, h in ipairs(hazards) do
        if (fp - flat(h.pos)).Magnitude < h.r then return h end
    end
    for _, h in ipairs(mv or {}) do
        if (fp - flat(h.pos)).Magnitude < h.r then return h end
    end
    return nil
end

-- point sur le plus proche, en restant pres de la cible si possible
local function safeSpot(target, mv)
    local my = rootPart.Position
    local best, bestScore = nil, math.huge
    for _, d in ipairs({ 10, 20, 30, 42, 55, 70 }) do
        for i = 0, 15 do
            local a = i * math.pi / 8
            local p = my + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d)
            if not hazardAt(p, mv) then
                local score = d
                if target then score = score + (flat(p) - flat(target)).Magnitude * 0.6 end
                if score < bestScore then best, bestScore = p, score end
            end
        end
        if best and d >= 20 then break end
    end
    return best
end

-- Contournement d'une zone mobile : un pas sur le cercle, du cote de la cible.
local function orbitStep(h, tpos)
    local c = flat(h.pos)
    local me = flat(rootPart.Position)
    local v = me - c
    if v.Magnitude < 0.1 then v = Vector3.new(1, 0, 0) end
    local ang = math.atan2(v.Z, v.X)
    local tv = flat(tpos) - c
    local tang = math.atan2(tv.Z, tv.X)
    local diff = (tang - ang + math.pi) % (2 * math.pi) - math.pi
    local step = math.max(-0.6, math.min(0.6, diff))
    local a = ang + step
    local R = h.r + 6
    return Vector3.new(c.X + math.cos(a) * R, rootPart.Position.Y, c.Z + math.sin(a) * R)
end

-- Nuclear : un mob marque qui meurt explose 2,5 s plus tard
local nuclearSeen = setmetatable({}, { __mode = "k" })
local function watchMob(m)
    if nuclearSeen[m] then return end
    nuclearSeen[m] = true
    local hum = m:FindFirstChildOfClass("Humanoid") or m:WaitForChild("Humanoid", 3)
    if not hum then return end
    local fired = false
    local function boom()
        if fired or not on() then return end
        if m:GetAttribute("Nuclear") ~= true then return end
        local p = objPos(m)
        if not p then return end
        fired = true
        addHazard(p, CONFIG.NUCLEAR_RADIUS, CONFIG.NUCLEAR_TIME, "Nuclear")
        elog(string.format("NUCLEAR : %s mort a (%.0f, %.0f) -> zone " .. CONFIG.NUCLEAR_RADIUS .. " studs",
            m.Name, p.X, p.Z))
    end
    track(hum.HealthChanged:Connect(function(h) if h <= 0 then boom() end end))
    track(hum.Died:Connect(boom))
end

-- Anneaux d'alerte : pieces plates et rondes qui apparaissent pendant un
-- evenement a anneaux. Couleurs du module : eclairs, meteores, golem...
local RING_EVENTS = { LightningStorm = true, TropicalThunderstorm = true,
    Eruption = true, MoltenGolem = true, RainDance = true, Nuclear = true }
-- couleurs du module, par evenement : on ne compare qu'aux evenements actifs
local RING_COLORS = {
    LightningStorm       = { Color3.fromRGB(120, 170, 255) },
    TropicalThunderstorm = { Color3.fromRGB(120, 170, 255) },
    Nuclear              = { Color3.fromRGB(190, 255, 60) },
    Eruption             = { Color3.fromRGB(255, 120, 50) },
    MoltenGolem          = { Color3.fromRGB(255, 110, 40), Color3.fromRGB(255, 50, 40) },
    RainDance            = { Color3.fromRGB(150, 60, 255), Color3.fromRGB(175, 90, 255),
                             Color3.fromRGB(120, 170, 255) },
}
local RING_WORDS = { "warn", "ring", "indicator", "telegraph", "marker",
    "circle", "zone", "bolt", "strike", "impact", "slam", "meteor" }
-- effets des cristaux et du decor : jamais des alertes
local RING_IGNORE = { "crystalfx", "spinshard", "clustershard", "corruption",
    "shell", "core", "drop", "chest",
    -- TES attaques vues dans evenements.txt (le farm les esquivait !)
    "volcanoslam", "volcanicslam", "candycane", "frostnova", "slashexplosion",
    "durperp", "invadedrain" }

-- tes attaques apprises en direct : nom des modules que TU lances
local ownAbilities = {}
local function normName(s) return (tostring(s):lower():gsub("[%s_%-%.]", "")) end
local function isOwnEffect(obj)
    local n = normName(obj.Name)
    local path = normName(obj.Parent and obj.Parent:GetFullName() or "")
    for _, w in ipairs(RING_IGNORE) do
        if n:find(w, 1, true) or path:find(w, 1, true) then return true end
    end
    for k in pairs(ownAbilities) do
        local k6 = k:sub(1, 6)
        if #k >= 6 and (n:find(k6, 1, true) or path:find(k6, 1, true)) then
            return true
        end
    end
    return false
end

local function ringEventActive()
    for k in pairs(RING_EVENTS) do if EV[k] then return true end end
    return #CollectionService:GetTagged("InvadedGolem") > 0
        or #CollectionService:GetTagged("InvadedShaman") > 0
end

local function colorClose(c)
    local active = {}
    for k, list in pairs(RING_COLORS) do
        if EV[k] then active[#active + 1] = list end
    end
    if #CollectionService:GetTagged("InvadedGolem") > 0 then
        active[#active + 1] = RING_COLORS.MoltenGolem
    end
    if #CollectionService:GetTagged("InvadedShaman") > 0 then
        active[#active + 1] = RING_COLORS.RainDance
    end
    for _, list in ipairs(active) do
        for _, k in ipairs(list) do
            local d = math.abs(c.R - k.R) + math.abs(c.G - k.G) + math.abs(c.B - k.B)
            if d < 0.35 then return true end
        end
    end
    return false
end

local function ringShape(part)
    local s = part.Size
    local dims = { s.X, s.Y, s.Z }
    table.sort(dims)
    -- une dimension fine, deux presque egales
    if dims[1] > 4 then return nil end
    if dims[3] < CONFIG.RING_MIN or dims[3] > CONFIG.RING_MAX then return nil end
    if dims[2] < dims[3] * 0.8 then return nil end
    return dims[3]
end

local excludedRoots = {}
local function excluded(obj)
    if character and obj:IsDescendantOf(character) then return true end
    for _, r in ipairs(excludedRoots) do
        if r and r.Parent and obj:IsDescendantOf(r) then return true end
    end
    return false
end

local recentParts = {}    -- pour le journal des gros degats
local function considerRing(obj, diam)
    local nameL = obj.Name:lower()
    if isOwnEffect(obj) then return end
    local named = false
    for _, w in ipairs(RING_WORDS) do
        if nameL:find(w, 1, true) then named = true break end
    end
    if not named and not colorClose(obj.Color) then
        elog(string.format("anneau ignore (couleur) : %s %s d=%.0f couleur %d,%d,%d",
            obj.Name, obj.ClassName, diam, obj.Color.R * 255, obj.Color.G * 255,
            obj.Color.B * 255))
        return
    end
    addHazard(obj.Position, diam / 2, CONFIG.RING_LIFE, "anneau " .. obj.Name, obj, true)
    elog(string.format("ANNEAU %s [%s] d=%.0f a (%.0f, %.0f) parent %s",
        obj.Name, obj.ClassName, diam, obj.Position.X, obj.Position.Z,
        obj.Parent and obj.Parent:GetFullName() or "?"))
end

local function onPartAdded(obj)
    if not on() or not obj:IsA("BasePart") then return end
    if excluded(obj) then return end
    if #recentParts > 200 then table.remove(recentParts, 1) end
    recentParts[#recentParts + 1] = { t = os.clock(), part = obj,
        name = obj.Name, size = obj.Size, pos = obj.Position }
    if not ringEventActive() then return end
    local diam = ringShape(obj)
    if diam then considerRing(obj, diam) return end
    -- souvent l'anneau grandit depuis 0 : on le surveille 1,5 s
    local s = obj.Size
    if math.min(s.X, s.Y, s.Z) > 4 then return end
    local c
    c = obj:GetPropertyChangedSignal("Size"):Connect(function()
        local d = ringShape(obj)
        if d then
            c:Disconnect()
            considerRing(obj, d)
        end
    end)
    task.delay(1.5, function() pcall(function() c:Disconnect() end) end)
end

-- Gros degats : on note ce qui est apparu autour juste avant, pour
-- reconnaitre l'attaque la prochaine fois.
local lastHp = nil
local function onMyHealth(h)
    if not humanoid then return end
    local maxHp = humanoid.MaxHealth
    if lastHp and maxHp > 0 and lastHp - h >= maxHp * CONFIG.BIG_HIT then
        local evs = {}
        for k in pairs(EV) do evs[#evs + 1] = k end
        elog(string.format("GROS COUP -%d (%d %%) evenements [%s]",
            lastHp - h, (lastHp - h) / maxHp * 100, table.concat(evs, ",")))
        local my = rootPart.Position
        local t = os.clock()
        for i = #recentParts, 1, -1 do
            local r = recentParts[i]
            if t - r.t > 3 then break end
            if (r.pos - my).Magnitude < 60 then
                elog(string.format("   vu %.1f s avant : %s taille (%.0f,%.0f,%.0f) a %.0f studs",
                    t - r.t, r.name, r.size.X, r.size.Y, r.size.Z,
                    (r.pos - my).Magnitude))
            end
        end
    end
    lastHp = h
end

local function targetHealth(t)
    if t.kind == "mob" or t.kind == "holder" then
        local hum = t.model:FindFirstChildOfClass("Humanoid")
        return hum and hum.Health or 0
    end
    return t.model:GetAttribute("Health") or 0
end

local function targetAlive(t)
    if not t then return false end
    if t.kind == "mob" or t.kind == "holder" then
        return mobAlive(t.model) ~= nil
    end
    return crystalAlive(t.model)
end

local function targetPos(t)
    if not t or not t.model.Parent then return nil end
    if t.kind == "mob" or t.kind == "holder" then
        local hrp = t.model:FindFirstChild("HumanoidRootPart")
        return hrp and hrp.Position
    end
    return partPosition(t.model)
end

local function skipped(model)
    local u = skipUntil[model]
    return u ~= nil and now() < u
end

-- Tous les objets d'une etiquette, plus le dossier connu en secours.
local function collect(tag, folderName)
    local out, seen = {}, {}
    for _, m in ipairs(CollectionService:GetTagged(tag)) do
        if m:IsA("Model") and not seen[m] then
            seen[m] = true
            out[#out + 1] = m
        end
    end
    local mc = workspace:FindFirstChild("MapContent")
    local folder = mc and mc:FindFirstChild(folderName)
    if folder then
        for _, m in ipairs(folder:GetChildren()) do
            if m:IsA("Model") and not seen[m] then
                seen[m] = true
                out[#out + 1] = m
            end
        end
    end
    return out
end

local function nearestCrystal(tag, folderName, kind)
    local best, bestD = nil, math.huge
    local myPos = rootPart.Position
    for _, m in ipairs(collect(tag, folderName)) do
        if crystalAlive(m) and not skipped(m) then
            -- le dossier RecursiveRelics peut contenir autre chose que le rituel
            if kind ~= "ritual" or m:GetAttribute("ElementalOnly") ~= nil
                or CollectionService:HasTag(m, "InvadedRitual") then
                local p = partPosition(m)
                if p then
                    local d = (p - myPos).Magnitude
                    if d < bestD and d <= CONFIG.CRYSTAL_RANGE then
                        best, bestD = m, d
                    end
                end
            end
        end
    end
    return best, bestD
end

local function spriteHoldingMe()
    local mobs = workspace:FindFirstChild("Mobs")
    if not mobs then return nil end
    local myId = tostring(player.UserId)
    for _, m in ipairs(mobs:GetChildren()) do
        local holder = m:GetAttribute("HoldingUserId")
        if holder ~= nil and tostring(holder) == myId and mobAlive(m) then
            return m
        end
    end
    return nil
end

-- Mob le plus proche (logique de ta base). Un mob "Invincible" (boss en
-- phase protegee) ne passe qu'en dernier recours.
local function closestMob()
    local mobs = workspace:FindFirstChild("Mobs")
    if not mobs then return nil end
    local best, bestD = nil, math.huge
    local healer, healerD = nil, math.huge
    local fallback, fallbackD = nil, math.huge
    local myPos = rootPart.Position
    for _, m in ipairs(mobs:GetChildren()) do
        local hum, hrp = mobAlive(m)
        if hum and not skipped(m) then
            local d = (myPos - hrp.Position).Magnitude
            local base = tostring(m:GetAttribute("Base") or "") .. m.Name
            if m:GetAttribute("Invincible") == true then
                if d < fallbackD then fallback, fallbackD = m, d end
            elseif base:lower():find("healer", 1, true) then
                -- Graceful : un healer rend la moitie des PV toutes les secondes
                if d < healerD then healer, healerD = m, d end
            elseif d < bestD then
                best, bestD = m, d
            end
        end
    end
    return healer or best or fallback
end

-- Objet special porte par une etiquette (Shaman, sarcophage...).
local function taggedTarget(tag)
    local best, bestD = nil, math.huge
    local myPos = rootPart.Position
    for _, o in ipairs(CollectionService:GetTagged(tag)) do
        local m = o:IsA("Model") and o or o:FindFirstAncestorOfClass("Model")
        if m and not skipped(m) then
            local kind, alive
            if m:FindFirstChildOfClass("Humanoid") then
                kind, alive = "mob", mobAlive(m) ~= nil
            else
                kind, alive = "special", crystalAlive(m)
            end
            local p = alive and objPos(m)
            if p and (p - myPos).Magnitude < bestD then
                best, bestD = { kind = kind, model = m }, (p - myPos).Magnitude
            end
        end
    end
    return best
end

local function makeTarget(kind, model)
    return { kind = kind, model = model }
end

local function selectTarget()
    -- 1. un Sprite me tient
    local holder = spriteHoldingMe()
    if holder then
        if not (current and current.model == holder) then
            log("un Sprite te tient -> on le tue")
        end
        return makeTarget("holder", holder)
    end

    -- 2. rituel
    local ritual = nearestCrystal("InvadedRitual", "RecursiveRelics", "ritual")
    if ritual then
        if current and current.kind == "ritual" and current.model == ritual then
            return current
        end
        log("RITUEL -> priorite absolue")
        return makeTarget("ritual", ritual)
    end

    -- 2b. Corrupted Shaman : ses orages s'arretent quand il tombe
    local shaman = taggedTarget("InvadedShaman")
    if shaman then
        if current and current.model == shaman.model then return current end
        log("SHAMAN -> prioritaire")
        return shaman
    end

    -- 3. cristaux : on garde le meme jusqu'a ce qu'il casse
    if current and current.kind == "crystal" and targetAlive(current)
        and not skipped(current.model) then
        return current
    end
    local crystal = nearestCrystal("InvadedCrystal", "InvadedCrystals", "crystal")
    if crystal then
        log("cristal ->", crystal:GetFullName())
        return makeTarget("crystal", crystal)
    end

    -- 3b. sarcophage (Mummy's Curse) : seulement apres tous les cristaux
    local sarco = taggedTarget("InvadedSarcophagus")
    if sarco then
        if current and current.model == sarco.model then return current end
        log("sarcophage -> tous les cristaux sont casses")
        return sarco
    end

    -- 4. mobs, seuil de changement comme dans ta base
    local mob = closestMob()
    if not mob then return nil end
    if current and current.kind == "mob" and targetAlive(current)
        and not skipped(current.model) and current.model ~= mob then
        local curPos, newPos = targetPos(current), targetPos(makeTarget("mob", mob))
        if curPos and newPos then
            local myPos = rootPart.Position
            if (myPos - newPos).Magnitude + CONFIG.SWITCH_DISTANCE_THRESHOLD
                >= (myPos - curPos).Magnitude then
                return current
            end
        end
    elseif current and current.kind == "mob" and current.model == mob then
        return current
    end
    return makeTarget("mob", mob)
end

-- Garde-fou : la cible ne perd pas de PV alors qu'on est dessus.
local function checkStall(t)
    if not t then return end
    local pos = targetPos(t)
    if not pos then return end
    if (pos - rootPart.Position).Magnitude > CONFIG.STALL_RANGE then
        stall[t.model] = nil
        return
    end
    local hp = targetHealth(t)
    local s = stall[t.model]
    if not s or hp < s.hp then
        stall[t.model] = { hp = hp, t = now() }
        return
    end
    local limit = (t.kind == "mob") and CONFIG.STALL_MOB or CONFIG.STALL_CRYSTAL
    if t.kind == "ritual" or t.kind == "holder" then return end
    if t.model:GetAttribute("Invincible") == true then return end
    if now() - s.t > limit then
        skipUntil[t.model] = now() + CONFIG.STALL_SKIP
        stall[t.model] = nil
        log("aucun degat sur", t.model.Name, "depuis", limit, "s -> mis de cote")
        current = nil
    end
end

--====================================================
-- DEPLACEMENT (ta base, sur une position au lieu d'un mob)
--====================================================
local function stopDistance(t)
    if t and t.kind ~= "mob" and t.kind ~= "holder" then
        return CONFIG.CRYSTAL_STOP
    end
    return 2
end

local function moveTowards(pos, t)
    local direction = pos - rootPart.Position
    if direction.Magnitude < stopDistance(t) then
        humanoid:Move(Vector3.zero)
        return
    end
    humanoid:Move(direction.Unit, false)
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function updateFly(pos)
    local directionTo = pos - rootPart.Position
    local distance = directionTo.Magnitude
    local heightDifference = pos.Y - rootPart.Position.Y

    if distance <= 1 then
        clearFly()
        rootPart.Velocity = Vector3.zero
        return
    end

    rayParams.FilterDescendantsInstances = { character }
    local rayResult = workspace:Raycast(rootPart.Position,
        Vector3.new(0, -100, 0), rayParams)

    -- BatSwarm / Cursed Mummy : on ne vole que si on tombe dans le vide
    local wantFly = not rayResult or heightDifference > CONFIG.FLY_HEIGHT_DIFF
    if noAir() and rayResult then wantFly = false end

    if wantFly then
        if not flyVelocity then
            flyVelocity = Instance.new("BodyVelocity")
            flyVelocity.MaxForce = Vector3.new(1e5, 1e5, 1e5)
            flyVelocity.P = 10000
            flyVelocity.Parent = rootPart
        end
        flyVelocity.Velocity = directionTo.Unit * CONFIG.FLY_SPEED
    else
        clearFly()
    end
end

--====================================================
-- VISEE
--====================================================
local AIM_BIND = "InvadedFarmAim"

local function aimPoint()
    local pos = targetPos(current)
    return pos
end

if CONFIG.AIM_CAMERA then
    RunService:BindToRenderStep(AIM_BIND, Enum.RenderPriority.Camera.Value + 1,
        function()
            if not on() then return end
            local pos = aimPoint()
            local cam = workspace.CurrentCamera
            if not pos or not cam or not rootPart or not rootPart.Parent then
                return
            end
            local flat = Vector3.new(pos.X - rootPart.Position.X, 0,
                pos.Z - rootPart.Position.Z)
            if flat.Magnitude < 0.5 then
                flat = rootPart.CFrame.LookVector
            end
            local eye = rootPart.Position - flat.Unit * CONFIG.CAM_BACK
                + Vector3.new(0, CONFIG.CAM_UP, 0)
            cam.CFrame = CFrame.lookAt(eye, pos)
        end)
end

local function pointMouse()
    if not CONFIG.AIM_MOUSE then return end
    local pos = aimPoint()
    local cam = workspace.CurrentCamera
    if not pos or not cam then return end
    local v, onScreen = cam:WorldToViewportPoint(pos)
    if onScreen then
        pcall(function()
            VirtualInputManager:SendMouseMoveEvent(v.X, v.Y, game)
        end)
    end
end

--====================================================
-- SCRIPT 1 - BOUCLE 1 / F / 2 / V C G (ta base)
--====================================================
local function pressKey(keyCode, duration)
    pointMouse()
    VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
    task.wait(duration or 0.05)
    VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
end

-- Les touches 1 / 2 sont des BASCULES : appuyer sur le slot deja equipe le
-- RANGE. C'est ce qui arrivait au debut : le perso avait deja l'objet en main,
-- la touche le rangeait, et il restait les mains vides (F ne faisait rien),
-- ou le 2 etait appuye "deux fois". On regarde donc ce qui est en main avant
-- d'appuyer, et on corrige si l'appui a range l'objet.
local slotTool = {}   -- [1] / [2] = nom de l'objet appris pour ce slot
local slotNoTool = {} -- slot qui n'est pas un objet Roblox : simple appui

local function equippedTool()
    local c = player.Character
    return c and c:FindFirstChildOfClass("Tool")
end

local function selectSlot(n, keyCode)
    if slotNoTool[n] then
        pressKey(keyCode, 0.1)
        return
    end
    local before = equippedTool()
    if before and slotTool[n] == before.Name then
        return   -- deja en main : surtout ne pas appuyer
    end
    pressKey(keyCode, 0.1)
    task.wait(0.2)
    local after = equippedTool()
    local retried = false
    if not after and before then
        retried = true
        -- l'appui a range l'objet qu'on tenait : c'etait deja ce slot
        log("touche " .. n .. " a range " .. before.Name .. " -> on le reprend")
        pressKey(keyCode, 0.1)
        task.wait(0.2)
        after = equippedTool()
    end
    if not retried and after and before and after == before then
        -- l'appui n'a rien change : ce slot n'est pas un objet Roblox
        slotNoTool[n] = true
        log("touche " .. n .. " : pas un objet, appui simple desormais")
    elseif after then
        if slotTool[n] ~= after.Name then
            slotTool[n] = after.Name
            log("touche " .. n .. " = " .. after.Name)
        end
    elseif not before then
        -- rien en main avant ni apres : ce slot n'est pas un objet
        slotNoTool[n] = true
        log("touche " .. n .. " : pas un objet, appui simple desormais")
    end
end

task.spawn(function()
    task.wait(1)
    while on() do
        selectSlot(1, Enum.KeyCode.One)

        local startTime = os.clock()
        while on() and os.clock() - startTime < CONFIG.RUN_TIME do
            pressKey(Enum.KeyCode.F, 0.05)
            task.wait(CONFIG.F_DELAY)
        end
        if not on() then break end

        selectSlot(2, Enum.KeyCode.Two)
        task.wait(CONFIG.CYCLE_DELAY)

        pressKey(Enum.KeyCode.V)
        task.wait(0.1)
        pressKey(Enum.KeyCode.C)
        task.wait(0.1)
        pressKey(Enum.KeyCode.G)
        task.wait(CONFIG.CYCLE_DELAY)
    end
end)

--====================================================
-- SCRIPT 2 - MORT / RESPAWN
--====================================================
local function hookDeath(char)
    local hum = char:FindFirstChildOfClass("Humanoid")
        or char:WaitForChild("Humanoid", 10)
    if not hum then return end
    lastHp = hum.Health
    track(hum.HealthChanged:Connect(function(h) pcall(onMyHealth, h) end))
    track(hum.Died:Connect(function()
        local evs = {}
        for k in pairs(EV) do evs[#evs + 1] = k end
        elog("MORT - evenements actifs [" .. table.concat(evs, ",") .. "]")
        flushLog()
        current = nil
        escapeGoal = nil
        task.delay(4, function()
            if on() and player.Character == char then
                log("pas de respawn -> Respawned")
                respawned()
            end
        end)
    end))
end
hookDeath(character)

track(player.CharacterAdded:Connect(function(char)
    character = char
    humanoid = char:WaitForChild("Humanoid")
    rootPart = char:WaitForChild("HumanoidRootPart")
    flyVelocity = nil
    current = nil
    hookDeath(char)
    log("respawn")
end))

--====================================================
-- SCRIPT 3 - AUTO RETRY / PROCEED
--====================================================
local retryBusy = false

local function findRetryBtn()
    local gui = player:FindFirstChild("PlayerGui")
    local dc = gui and gui:FindFirstChild("DungeonComplete")
    local main = dc and dc:FindFirstChild("Main")
    local eb = main and main:FindFirstChild("EndGameButtons")
    return eb and eb:FindFirstChild("RetryBtn")
end

local function doRetry(force)
    if retryBusy then return end
    retryBusy = true
    task.spawn(function()
        -- force = fin de donjon recue du serveur : on clique pendant 15 s
        local tries = force and 15 or 1
        for _ = 1, tries do
            if not on() then break end
            local btn = findRetryBtn()
            if btn and (force or guiVisible(btn)) then
                task.wait(1)
                log("clic RetryBtn")
                pcall(clickButton, btn)
                task.wait(1)
                startDungeon()
                break
            end
            task.wait(1)
        end
        task.wait(1)
        retryBusy = false
    end)
end

task.spawn(function()
    while on() do
        pcall(function()
            local btn = findRetryBtn()
            if btn and guiVisible(btn) then
                doRetry(false)
            end
            local gui = player:FindFirstChild("PlayerGui")
            local prompts = gui and gui:FindFirstChild("Prompts")
            local pf = prompts and prompts:FindFirstChild("PromptFrame")
            local buttons = pf and pf:FindFirstChild("Buttons")
            local proceed = buttons and buttons:FindFirstChild("Proceed")
            if proceed and guiVisible(proceed) then
                clickButton(proceed)
            end
        end)
        task.wait(0.5)
    end
end)

if CONFIG.RETRY_ON_END then
    task.spawn(function()
        local ds = knitService("DungeonService")
        local re = ds and ds:FindFirstChild("RE")
        local ended = re and re:FindFirstChild("DungeonEndedRemote")
        if ended then
            track(ended.OnClientEvent:Connect(function()
                log("fin du donjon recue")
                current = nil
                task.wait(2)
                if on() then doRetry(true) end
            end))
        end
    end)
end

--====================================================
-- SCRIPT 4 - START DONJON (ta base)
--====================================================
task.delay(5, function()
    if on() then startDungeon() end
end)

--====================================================
-- SCRIPT 5 - KILL APRES 10 MIN (ta base, coupe par defaut)
--====================================================
if CONFIG.KILL_AFTER_10MIN then
    task.spawn(function()
        task.wait(600)
        for i = 1, 3 do
            if not on() then return end
            local hum = player.Character
                and player.Character:FindFirstChildOfClass("Humanoid")
            if hum then
                log("kill " .. i .. "/3")
                hum.Health = 0
                task.wait(1)
                respawned()
            end
            if i < 3 then task.wait(7) end
        end
    end)
end

if CONFIG.PORTAL_KILL_LOOP then
    task.spawn(function()
        while on() do
            task.wait(1)
            local tp = workspace:FindFirstChild("TeleportPortal")
            if tp and tp:FindFirstChild("Star") then
                while on() do
                    local hum = player.Character
                        and player.Character:FindFirstChild("Humanoid")
                    if hum then hum.Health = 0 end
                    task.wait(0.1)
                end
            end
        end
    end)
end

--====================================================
-- SCRIPT 6 - FARM
--====================================================
track(RunService.RenderStepped:Connect(function()
    if not on() then return end
    if humanoid and humanoid.WalkSpeed ~= CONFIG.TARGET_SPEED then
        humanoid.WalkSpeed = CONFIG.TARGET_SPEED
    end
end))

track(RunService.Stepped:Connect(function()
    if not on() or not character then return end
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then part.CanCollide = false end
    end
end))

-- branchement des evenements
if CONFIG.EVENTS then
    readEvents()
    track(workspace:GetAttributeChangedSignal("InvadedEvents"):Connect(function()
        pcall(readEvents)
    end))

    local mobs = workspace:FindFirstChild("Mobs") or workspace:WaitForChild("Mobs", 5)
    local map = workspace:FindFirstChild("Map")
    local mc = workspace:FindFirstChild("MapContent")
    excludedRoots = { mobs, map, mc and mc:FindFirstChild("InvadedCrystals") }
    if mobs then
        for _, m in ipairs(mobs:GetChildren()) do task.spawn(watchMob, m) end
        track(mobs.ChildAdded:Connect(function(m) task.spawn(watchMob, m) end))
    end
    track(workspace.DescendantAdded:Connect(function(obj)
        local ok, err = pcall(onPartAdded, obj)
        if not ok then log("anneau : " .. tostring(err)) end
    end))

    -- apprendre TES attaques (pour ne pas les esquiver)
    task.spawn(function()
        local ok, tool = pcall(function()
            return ReplicatedStorage:WaitForChild("ReplicatedStorage", 10)
                .Abilities.Templates.ToolTemplate.RemoteEvent
        end)
        if ok and tool then
            track(tool.OnClientEvent:Connect(function(module, _, data)
                if type(data) == "table" and data.Model == character
                    and typeof(module) == "Instance" then
                    local k = normName(module.Name)
                    if not ownAbilities[k] then
                        ownAbilities[k] = true
                        elog("ta propre attaque : " .. module.Name)
                    end
                end
            end))
        end
    end)

    -- second canal : le serveur annonce aussi chaque evenement
    task.spawn(function()
        local svc = knitService("InvadedRunService")
        local re = svc and svc:FindFirstChild("RE")
        local cue = re and re:FindFirstChild("EventCue")
        if cue then
            track(cue.OnClientEvent:Connect(function(kind, data)
                if type(data) == "table" and data.Key then
                    elog("cue serveur : " .. tostring(kind) .. " " .. tostring(data.Key))
                end
            end))
        end
    end)

    task.spawn(function()
        while on() do
            task.wait(15)
            flushLog()
        end
    end)
end

-- choix de cible a 10 Hz (GetTagged a chaque image serait trop lourd)
local lastEscapeLog = 0
local blockedSince = setmetatable({}, { __mode = "k" })
task.spawn(function()
    while on() do
        local ok, err = pcall(function()
            if rootPart and rootPart.Parent and humanoid and humanoid.Health > 0 then
                if current and not targetAlive(current) then
                    current = nil
                end
                current = selectTarget()
                checkStall(current)

                -- repli hors des zones dangereuses
                pruneHazards()
                local mv = movers()
                local tpos = current and targetPos(current)
                -- le rituel tue tout le monde : seules les zones fixes l'arretent
                local ritual = current and current.kind == "ritual"
                local mine = hazardAt(rootPart.Position, not ritual and mv or nil)
                local onTarget = tpos and hazardAt(tpos, not ritual and mv or nil)
                local near = onTarget and tpos
                    and (flat(tpos) - flat(rootPart.Position)).Magnitude < onTarget.r + 25

                -- cible coincee dans une zone mobile : on passe a autre chose
                if onTarget and not onTarget.t1 and current then
                    blockedSince[current.model] = blockedSince[current.model] or os.clock()
                    if os.clock() - blockedSince[current.model] > CONFIG.BLOCKED_SKIP then
                        skipUntil[current.model] = os.clock() + 8
                        blockedSince[current.model] = nil
                        elog("cible dans " .. tostring(onTarget.label) .. " -> mise de cote 8 s")
                        current = nil
                        tpos, onTarget, near = nil, nil, nil
                    end
                elseif current then
                    blockedSince[current.model] = nil
                end
                if mine and not mine.t1 and not hazardAt(rootPart.Position) then
                    -- zone MOBILE (Scary Sprite, Mummy, tourbillon) : on la
                    -- contourne en tournant autour vers la cible
                    escapeGoal = orbitStep(mine, tpos or rootPart.Position)
                    if os.clock() - lastEscapeLog > 1 then
                        lastEscapeLog = os.clock()
                        elog("CONTOURNE : " .. tostring(mine.label))
                    end
                elseif mine or near then
                    local h = mine or onTarget
                    if not escapeGoal or hazardAt(escapeGoal, mv) then
                        escapeGoal = safeSpot(tpos, mv)
                        if os.clock() - lastEscapeLog > 1 then
                            lastEscapeLog = os.clock()
                            elog("ESQUIVE : " .. tostring(h.label))
                        end
                    end
                    -- zone qui va tomber et on est dedans : TP court
                    if CONFIG.URGENT_TP and mine and escapeGoal
                        and (mine.urgent or (mine.t1 and mine.t1 - os.clock() < 1)) then
                        local d = (flat(escapeGoal) - flat(rootPart.Position)).Magnitude
                        if d <= CONFIG.TP_MAX then
                            local rot = rootPart.CFrame - rootPart.Position
                            rootPart.CFrame = CFrame.new(escapeGoal.X,
                                rootPart.Position.Y, escapeGoal.Z) * rot
                        end
                    end
                else
                    escapeGoal = nil
                end
            end
        end)
        if not ok then warn("[INVADED] selection : " .. tostring(err)) end
        task.wait(CONFIG.SELECT_PERIOD)
    end
end)

track(RunService.RenderStepped:Connect(function()
    if not on() then return end
    if not rootPart or not rootPart.Parent or not humanoid then return end
    local pos = current and targetPos(current)
    if pos and not targetAlive(current) then pos = nil end

    -- Overflow : on reste au-dessus de la lave
    if os.clock() < overflowUntil and overflowY then
        local y = overflowY
        for _, f in ipairs(CollectionService:GetTagged("InvadedFlood")) do
            if f:IsA("BasePart") then
                y = math.max(y, f.Position.Y + f.Size.Y / 2 + 25)
            end
        end
        local base = pos or rootPart.Position
        local goal = Vector3.new(base.X, y, base.Z)
        local dir = goal - rootPart.Position
        if not flyVelocity then
            flyVelocity = Instance.new("BodyVelocity")
            flyVelocity.MaxForce = Vector3.new(1e5, 1e5, 1e5)
            flyVelocity.P = 10000
            flyVelocity.Parent = rootPart
        end
        flyVelocity.Velocity = dir.Magnitude > 1
            and dir.Unit * math.min(CONFIG.FLY_SPEED, dir.Magnitude * 4)
            or Vector3.zero
        humanoid:Move(Vector3.zero)
        return
    end

    -- repli : la zone passe avant la cible
    if escapeGoal then
        local goal = Vector3.new(escapeGoal.X, rootPart.Position.Y, escapeGoal.Z)
        moveTowards(goal, nil)
        updateFly(goal)
    elseif pos then
        moveTowards(pos, current)
        updateFly(pos)
    else
        humanoid:Move(Vector3.zero)
        clearFly()
    end

    -- Corruption : le sol brule, on saute sans arret (sauf si voler est puni)
    if EV.Corruption and not noAir()
        and humanoid.FloorMaterial ~= Enum.Material.Air then
        humanoid.Jump = true
    end
end))

--====================================================
-- STATUT A L'ECRAN
--====================================================
local statusGui = Instance.new("ScreenGui")
statusGui.Name = "InvadedFarmStatus"
statusGui.ResetOnSpawn = false
statusGui.IgnoreGuiInset = true
local label = Instance.new("TextLabel")
label.Size = UDim2.new(0, 720, 0, 22)
label.Position = UDim2.new(0.5, -360, 0, 4)
label.BackgroundColor3 = Color3.fromRGB(20, 12, 34)
label.BackgroundTransparency = 0.25
label.TextColor3 = Color3.fromRGB(215, 190, 255)
label.Font = Enum.Font.GothamBold
label.TextSize = 13
label.Text = "INVADED FARM"
label.Parent = statusGui
pcall(function() statusGui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)
if not statusGui.Parent then statusGui.Parent = player:WaitForChild("PlayerGui") end

local KIND_TEXT = {
    holder = "SPRITE QUI TE TIENT", ritual = "RITUEL", crystal = "CRISTAL",
    mob = "MOB", special = "OBJET SPECIAL",
}

task.spawn(function()
    while on() do
        local alive = 0
        for _, m in ipairs(collect("InvadedCrystal", "InvadedCrystals")) do
            if crystalAlive(m) then alive = alive + 1 end
        end
        local txt
        if current then
            local hp = targetHealth(current)
            txt = string.format("%s : %s  (%.0f PV)", KIND_TEXT[current.kind] or "?",
                current.model.Name, hp)
        else
            txt = "aucune cible"
        end
        local evs = {}
        for k in pairs(EV) do evs[#evs + 1] = k end
        if escapeGoal then txt = "ESQUIVE | " .. txt end
        label.Text = string.format("INVADED [B=stop] | cristaux %d | %s%s", alive, txt,
            #evs > 0 and (" | " .. table.concat(evs, ",")) or "")
        task.wait(0.3)
    end
end)

--====================================================
-- ARRET
--====================================================
_G.StopInvadedFarm = function(reason)
    if _G.InvadedFarmToken ~= TOKEN then return end
    running = false
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    pcall(function() RunService:UnbindFromRenderStep(AIM_BIND) end)
    clearFly()
    pcall(function() humanoid:Move(Vector3.zero) end)
    pcall(function() statusGui:Destroy() end)
    pcall(flushLog)
    pcall(function() stopKeyConn:Disconnect() end)
    _G.StopInvadedFarm = nil
    print("[INVADED] arret" .. (reason and (" : " .. tostring(reason)) or ""))
end

log("pret (jeton " .. TOKEN .. ") : rituel > cristaux > mobs  |  B = arret")

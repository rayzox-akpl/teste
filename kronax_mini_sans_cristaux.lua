--==========================================================================
--  KRONAX MINI - CRISTAUX  --  variante de kronax_minigun.lua pour un alt
--
--  Identique a kronax_minigun.lua, SAUF : ne cible jamais les cristaux /
--  reliques / mini RecursiveRelics, uniquement Kronax. Le compte principal
--  (kronax_minigun.lua) casse les cristaux et tape le boss, l'alt (ce
--  fichier) reste sur le boss. Les cristaux sont toujours DETECTES : ils
--  servent a estimer le centre de l'arene (orbite, esquives).
--  Reglage : CONFIG.TARGET_CRYSTALS (false ici).
--==========================================================================
--==========================================================================
--  KRONAX MINIGUN + AUTOEXEC  --  un seul fichier, pret pour le hub / git
--
--  Ce fichier contient :
--    1. le farm Kronax minigun complet (esquive, orbite, reliques, H initial)
--    2. le controleur de l'ancien kronax_autoexec :
--         * ne fait rien hors du raid Kronax (Map.TimeRaidDungeon) ; dans le
--           raid Lunos il laisse la place au script Lunos
--         * Start : StartBtn vu -> 5 s -> clic (1 / s jusqu'a disparition)
--         * Skip de la cinematique
--         * farm lance des que le combat commence
--         * Retry : RetryBtn vu -> farm coupe -> 10 s -> clic ; puis nouveau
--           cycle Start / Skip / farm (le farm repart neuf, H renvoye)
--  Plus besoin de autoexec/kronax_minigun.lua ni de readfile.
--  Arret : B (coupe le controleur ET le farm).
--==========================================================================
--==========================================================================
--  PARTIE 1 : LE FARM (inchange), range dans une fonction.
--  Le controleur (partie 2) l'appelle a chaque nouvelle partie.
--==========================================================================
local FARM = function()
    --==========================================================================
    --  KRONAX MINIGUN v1 -- base Kronax v0.41, maintien 60 s / pause 2 s
    --
    --  Ciblage :
    --    1. orbite courte autour de Kronax ;
    --    2. tout destructible de 1 k a 10 M PV devient la cible du minigun, sans
    --       relacher le clic : reliques a 5 M ET mini RecursiveRelics a 4 M,
    --       quel que soit leur nom ou leur dossier ;
    --    3. au-dessus de 10 M PV (999999999) c'est une sentinelle de fin de
    --       combat : jamais ciblee, retour immediat sur Kronax ;
    --    4. esquive simplifiee des telegraphes, avec rares accrocs volontaires au mur.
    --
    --  Trois voies de detection complementaires :
    --    - les 4 emplacements fixes du dossier Crystals (reliques) ;
    --    - workspace.DescendantAdded pour tout ce que le jeu cree en combat ;
    --    - un balayage borne de l'arene pour les objets simplement rallumes.
    --  B ou le bouton ARRETER coupe tout et ecrit le journal.
    --==========================================================================

    if not game:IsLoaded() then
        local loadDeadline = os.clock() + 120
        repeat task.wait(0.25) until game:IsLoaded() or os.clock() >= loadDeadline
        if not game:IsLoaded() then
            warn("[Kronax test] chargement incomplet apres 120 s -> arret")
            return
        end
    end

    if typeof(_G.StopCurrentFarm) == "function" then
        pcall(_G.StopCurrentFarm, "remplace_par_kronax_test")
        task.wait(0.2)
    end

    local _F = {}
    local CONFIG = {
        BOSS_NAME = "kronax",

        -- Distance maximale joueur <-> Kronax au-dela de laquelle on considere
        -- qu'on n'est PAS en combat (lobby, chargement, boss non stream).
        -- Le minigun et le deplacement restent totalement inactifs.
        MAX_ENGAGE_DISTANCE = 600,

        ORBIT_RADIUS       = 50,
        ORBIT_LINEAR_SPEED = 50,
        HOLD_HEIGHT        = 55,
        ALTITUDE_LIMIT     = 120,
        ALTITUDE_MARGIN    = 5,
        HOLD_HEIGHT_MAX    = 68,
        HEIGHT_STEP        = 12,
        MIN_HORIZONTAL_DISTANCE = 54,
        MOVE_RESPONSE      = 26,

        DODGE_RESPONSE     = 100,

        MINIGUN_BURST_DURATION = 60,
        MINIGUN_REHOLD_DELAY = 2,
        MINIGUN_HIT_SETTLE = 0.15,
        MINIGUN_VERIFY_GRACE = 0.35,
        MINIGUN_NO_DAMAGE_RELEASE = 1,   -- aucun degat depuis 3 s -> on lache et on reprend
        MINIGUN_FIRST_HIT_GRACE = 10,    -- apres une reprise : jusqu'a 10 s pour que le tir demarre
        EQUIP_WAIT = 1.2,
        ATTACK_REASSERT_INTERVAL = 0.45,
        SHOT_EFFECT       = "WaterExplosion",

        CRYSTAL_KEYWORDS = {"crystal", "cristal", "recursive relic"},

        MINI_CRYSTAL_KEYWORDS = {"crystal", "cristal", "relic", "shard", "fragment",
            "spike", "pillar", "shrine", "totem", "rune", "orb", "node", "core",
            "obelisk", "prism", "geode", "cluster"},
        CRYSTAL_SCAN_RADIUS = 500,
        FALLBACK_TARGET_RADIUS = 260,

        ARENA_RADIUS = 420,

        MOVEMENT_ARENA_RADIUS = 175,
        MOVEMENT_ARENA_INSET = 2,

        MOVEMENT_ARENA_SOFT = 0.97,
        MOVEMENT_ARENA_EDGE_SAMPLES = 4,
        CRYSTAL_SUCCESS_WINDOW = 10,
        CANDIDATE_POLL_INTERVAL = 0.20,

        CRYSTAL_VISUAL_MIN_SHOTS = 4,
        CRYSTAL_VISUAL_MIN_FOCUS = 2.8,

        CRYSTAL_MAX_TARGET_HEALTH = 10000000,
        -- false = focus Kronax uniquement (alt) : aucun cristal n'est cible
        TARGET_CRYSTALS = false,

        CRYSTAL_MIN_TARGET_HEALTH = 1000,

        CRYSTAL_STUCK_TIMEOUT = 15,

        MINI_APPROACH_DISTANCE = 16,
        MINI_APPROACH_HEIGHT   = 8,
        MINI_CONTACT_HEIGHT    = 5,

        MINI_TELEPORT_DISTANCE = 5,

        MINI_TELEPORT_DELAY = 5.0,
        DYNAMIC_CRYSTAL_SETTLE_DELAY = 0.06,

        RECURSIVE_RELIC_POLL_INTERVAL = 0.25,

        ARENA_SWEEP_INTERVAL = 0.80,
        ARENA_SWEEP_BUDGET = 220,

        DISCOVERY_LOG_MAX = 40,

        WARNING_KEYWORDS = {"warning", "telegraph", "danger", "indicator", "aoe"},
        WARNING_DEFAULT_RADIUS = 18,
        WARNING_RADIUS_MAX = 160,
        WARNING_LIFETIME = 2.5,

        HAZARD_DEFAULT_RADIUS = 28,

        RAIN_DROP_RADIUS = 28,
        RAIN_MAX_DROPS = 40,

        RAIN_DROP_INTERVAL = 0.56,

        RAIN_DROP_LEAD = 1.20,
        RAIN_DROP_WINDOW = 2.00,
        HAZARD_RADIUS_MAX = 160,

        SHOCKWAVE_LINGER = 4.50,
        HAZARD_LIFETIME = 2.2,

        HAZARD_TRIGGER_MARGIN = 14,
        HAZARD_ESCAPE_MARGIN = 22,

        TIMELINE_CORRIDOR_RADIUS = 60,

        TIMELINE_DODGE_HOLD = 1.75,
        TIMELINE_LINGER_MARGIN = 0.25,

        CORRIDOR_LIFETIME = 3.50,
        DODGE_RADIUS_EXTRA = 20,
        DODGE_RADIUS_MAX = 170,

        DODGE_ALTITUDES = {40, 72, 88},
        DODGE_LOCAL_RADII = {42, 82},
        DODGE_LOCAL_DIRECTIONS = 6,
        DODGE_CLEARANCE_SCORE_CAP = 30,
        DODGE_TRAVEL_SCORE_WEIGHT = 1.0,
        DODGE_MIN_HOLD = 0.65,
        DODGE_RELEASE_MARGIN = 16,
        DODGE_REPLAN_INTERVAL = 0.16,
        DODGE_CANDIDATE_COUNT = 10,

        WALL_BUMP_MIN_INTERVAL = 7.0,
        WALL_BUMP_MAX_INTERVAL = 13.0,
        WALL_BUMP_DURATION = 0.30,
        WALL_BUMP_MIN_ARENA_RADIUS = 125,
        WALL_BUMP_PUSH = 0,

        TARGETED_BURST_RATIO = 0.15,
        TARGETED_BURST_SECONDS = 0.70,

        HEROIC_PATH_SPEED = 120,
        HEROIC_TARGET_PATH_SPEED = 150,

        HEROIC_THRONE_RADIUS_X = 48,
        HEROIC_THRONE_RADIUS_Z = 32,
        HEROIC_START_RAMP = 0.75,
        HEROIC_DEPARTURE_BLEND_START = 12,
        HEROIC_DEPARTURE_BLEND_END = 90,
        HEROIC_ANCHOR_RESPONSE = 3.5,
        HEROIC_ARENA_EDGE_MARGIN = 4,
        HEROIC_ALTITUDE_BASE = 56,
        HEROIC_ALTITUDE_AMPLITUDE = 24,
        HEROIC_ALTITUDE_FREQUENCY = 0.70,
        HEROIC_DODGE_ALTITUDES = {40, 72, 88},
        HEROIC_DODGE_LOCAL_RADII = {58, 110},
        HEROIC_DODGE_LOCAL_DIRECTIONS = 6,
        HEROIC_TEMPORAL_HOLD = 0.80,

        MIN_TRAVEL_WINDOW = 0.60,
        MIN_TRAVEL_DISTANCE = 60,
        TRAVEL_KICK_ANGLE = 1.90,
        TRAVEL_KICK_COOLDOWN = 0.45,
        HEROIC_FLASH_HOLD = 1.20,

        TRACE_PERIOD = 1.0,
        MESSAGE_SCAN_INTERVAL = 1.50,
        LOG_WRITE_PERIOD = 3.0,
        LOG_MAX_LINES = 3000,
        LOG_FILE = "logs/kronax/kronax_mini_sans_cristaux_log.txt",
        VERBOSE_DIAGNOSTICS = false,

        LOG_ABILITY_PAYLOAD = true,
    }

    local Players           = game:GetService("Players")
    local RunService        = game:GetService("RunService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local UserInputService  = game:GetService("UserInputService")
    local VIM               = game:GetService("VirtualInputManager")

    local player = Players.LocalPlayer
    local character = player.Character or player.CharacterAdded:Wait()
    local humanoid = character:WaitForChild("Humanoid")
    local root = character:WaitForChild("HumanoidRootPart")

    local running = true
    local connections = {}
    local characterConnections = {}
    local bossConnections = {}
    local crystalConnections = {}

    local characterParts = {}
    local oldCollision = {}
    local partAdded = nil
    local partRemoved = nil

    local boss = nil
    local bossHumanoid = nil
    local bossLastHealth = nil
    local bossSeenAt = 0

    local weaponName = nil
    local equipping = false
    local mouseHeld = nil
    local holdStartedAt = 0
    local shotSeenThisHold = false
    local lastShotEffect = 0
    local cooldownUntil = 0
    local minigun = {
        burstUntil = nil, restartAt = nil, nextEquip = 0, nextArm = 0,
        missingSince = nil, tool = nil, deactivated = nil, releasing = false,
        stunMessages = setmetatable({}, {__mode = "k"}), nextMessageScan = 0,
        stunUntil = 0,
    }
    local reholdCount = 0
    local lastAttackAssert = -math.huge
    local lastAttackTarget = nil

    local orbitAngle = 0
    local holdHeight = CONFIG.HOLD_HEIGHT
    local sightClear = true
    local sightBlocker = nil
    local lastSightCheck = 0
    local lastHeightChange = 0
    local activeDodgeLabel = nil
    local activeDodgeUntil = 0
    local targetedBurstUntil = 0
    local timelineDodgeUntil = 0
    local heroicState = {
        mode = false,
        motionPhase = 0,
        targetedUntil = 0,
        targetedLabel = nil,
        anchorBlend = 0,
        anchor = nil,
        radiusX = CONFIG.HEROIC_THRONE_RADIUS_X,
        radiusZ = CONFIG.HEROIC_THRONE_RADIUS_Z,
        losGoal = nil,
        losGoalUntil = 0,
    }

    local crystals = {}
    local crystalSerial = 0
    local activeCrystal = nil
    local activeTarget = nil
    local crystalStats = {seen = 0, destroyed = 0, missed = 0, ignored = 0}
    local crystalCandidates = {}
    local crystalRoomCenter = nil
    local watchedCrystalFolders = setmetatable({}, {__mode = "k"})
    local ignoredCrystals = setmetatable({}, {__mode = "k"})
    local dynamicCrystalWatched = setmetatable({}, {__mode = "k"})
    local dynamicCrystalPending = setmetatable({}, {__mode = "k"})
    local discoverySeen = setmetatable({}, {__mode = "k"})
    local discoveryLogged = 0
    local miniCrystalCount = 0
    local sweepChildIndex = 1

    local hazards = {}
    local recentAbilities = {}
    local abilityCounts = {}
    local warningParts = setmetatable({}, {__mode = "k"})
    local damageBuckets = {}
    local timelineCasts = {}
    local motionSamples = {}
    local messageState = {}
    local ui = nil
    local bossInitialPosition = nil
    local usingRoomCenter = false
    local cachedDodgeGoal = nil
    local cachedDodgeGoalUntil = 0
    local wallBumpUntil = 0
    local nextWallBumpAt = os.clock() + CONFIG.WALL_BUMP_MIN_INTERVAL
    local wallCollisionEnabled = false

    local startedAt = os.clock()
    local logLines = {}
    local logDirty = false
    local lastLogWrite = 0
    local lastTrace = 0

    function _F.stamp(text)
        return string.format("[%7.2f] %s", os.clock() - startedAt, text)
    end

    function _F.pushLine(text)
        logLines[#logLines + 1] = text
        if #logLines > CONFIG.LOG_MAX_LINES then table.remove(logLines, 1) end
        logDirty = true
    end

    function _F.say(formatText, ...)
        local ok, text = pcall(string.format, formatText, ...)
        text = ok and text or tostring(formatText)
        print("[Kronax test] " .. text)
        _F.pushLine(_F.stamp(text))
    end

    function _F.writeLog(force)
        if not logDirty then return end
        local now = os.clock()
        if not force and now - lastLogWrite < CONFIG.LOG_WRITE_PERIOD then return end
        lastLogWrite = now
        logDirty = false
        if typeof(writefile) == "function" then
            pcall(writefile, CONFIG.LOG_FILE, table.concat(logLines, "\n"))
        end
    end

    if typeof(makefolder) == "function" then
        pcall(makefolder, "logs")
        pcall(makefolder, "logs/kronax")
    end

    function _F.connect(signal, callback, list)
        local connection = signal:Connect(callback)
        local targetList = list or connections
        targetList[#targetList + 1] = connection
        return connection
    end

    function _F.disconnectList(list)
        for _, connection in ipairs(list) do
            pcall(function() connection:Disconnect() end)
        end
        table.clear(list)
    end

    function _F.describe(value, depth)
        local kind = typeof(value)
        if kind == "Instance" then return value.ClassName .. ":" .. value.Name end
        if kind == "Vector3" then
            return string.format("V3(%.1f,%.1f,%.1f)", value.X, value.Y, value.Z)
        end
        if kind == "CFrame" then
            local p = value.Position
            return string.format("CF(%.1f,%.1f,%.1f)", p.X, p.Y, p.Z)
        end
        if kind == "Color3" then
            return string.format("RGB(%d,%d,%d)", value.R * 255, value.G * 255, value.B * 255)
        end
        if kind == "table" then
            if depth <= 0 then return "{...}" end
            local parts = {}
            for key, item in pairs(value) do
                parts[#parts + 1] = tostring(key) .. "=" .. _F.describe(item, depth - 1)
                if #parts >= 40 then
                    parts[#parts + 1] = "..."
                    break
                end
            end
            return "{" .. table.concat(parts, ", ") .. "}"
        end
        return tostring(value)
    end

    function _F.attributesOf(object)
        local parts = {}
        for name, value in pairs(object:GetAttributes()) do
            parts[#parts + 1] = name .. "=" .. _F.describe(value, 1)
            if #parts >= 20 then
                parts[#parts + 1] = "..."
                break
            end
        end
        return #parts > 0 and (" attrs={" .. table.concat(parts, ",") .. "}") or ""
    end

    function _F.flatDistance(a, b)
        return ((a - b) * Vector3.new(1, 0, 1)).Magnitude
    end

    function _F.flatSegmentDistance(point, segmentStart, segmentEnd)
        local direction = (segmentEnd - segmentStart) * Vector3.new(1, 0, 1)
        local offset = (point - segmentStart) * Vector3.new(1, 0, 1)
        local lengthSquared = direction:Dot(direction)
        if lengthSquared <= 0.0001 then return offset.Magnitude end
        local alpha = math.clamp(offset:Dot(direction) / lengthSquared, 0, 1)
        return (offset - direction * alpha).Magnitude
    end

    function _F.segmentDistance3D(point, segmentStart, segmentEnd)
        local direction = segmentEnd - segmentStart
        local lengthSquared = direction:Dot(direction)
        if lengthSquared <= 0.0001 then return (point - segmentStart).Magnitude end
        local alpha = math.clamp((point - segmentStart):Dot(direction)
            / lengthSquared, 0, 1)
        return (point - (segmentStart + direction * alpha)).Magnitude
    end

    function _F.flatCross(ax, az, bx, bz)
        return ax * bz - az * bx
    end

    function _F.flatSegmentsDistance(a, b, c, d)
        local rx, rz = b.X - a.X, b.Z - a.Z
        local sx, sz = d.X - c.X, d.Z - c.Z
        local qx, qz = c.X - a.X, c.Z - a.Z
        local denominator = _F.flatCross(rx, rz, sx, sz)
        if math.abs(denominator) > 0.0001 then
            local t = _F.flatCross(qx, qz, sx, sz) / denominator
            local u = _F.flatCross(qx, qz, rx, rz) / denominator
            if t >= 0 and t <= 1 and u >= 0 and u <= 1 then return 0 end
        end
        return math.min(
            _F.flatSegmentDistance(a, c, d), _F.flatSegmentDistance(b, c, d),
            _F.flatSegmentDistance(c, a, b), _F.flatSegmentDistance(d, a, b))
    end

    function _F.recordMotionSample(at, position)
        motionSamples[#motionSamples + 1] = {at = at, pos = position}
        local oldest = at - 1.6
        while #motionSamples > 0
            and (motionSamples[1].at < oldest or #motionSamples > 120) do
            table.remove(motionSamples, 1)
        end
    end

    function _F.logTimelineEvidence(at, position)
        for index = #timelineCasts, 1, -1 do
            local cast = timelineCasts[index]
            local age = at - cast.at
            if age > 2.2 then
                table.remove(timelineCasts, index)
            elseif age >= 0 then
                local currentTarget = _F.flatDistance(position, cast.target)
                local currentLine = _F.flatSegmentDistance(position,
                    cast.origin, cast.target)
                local minTarget = currentTarget
                local minLine = currentLine
                local minCrossing = math.huge
                local maxStep = 0
                local samples = 0
                local previous = nil
                for _, sample in ipairs(motionSamples) do
                    if sample.at >= cast.at - 0.03 and sample.at <= at + 0.03 then
                        samples += 1
                        minTarget = math.min(minTarget,
                            _F.flatDistance(sample.pos, cast.target))
                        minLine = math.min(minLine,
                            _F.flatSegmentDistance(sample.pos, cast.origin, cast.target))
                        if previous then
                            maxStep = math.max(maxStep,
                                _F.flatDistance(previous.pos, sample.pos))
                            minTarget = math.min(minTarget,
                                _F.flatSegmentDistance(cast.target,
                                    previous.pos, sample.pos))
                            minCrossing = math.min(minCrossing,
                                _F.flatSegmentsDistance(previous.pos, sample.pos,
                                    cast.origin, cast.target))
                        end
                        previous = sample
                    end
                end
                if minCrossing == math.huge then minCrossing = currentLine end
                _F.say("PREUVE TIMELINE #%d : age=%.3f cibleAct=%.1f axeAct=%.1f"
                        .. " minCible=%.1f minAxe=%.1f croisement=%.1f"
                        .. " pasMax=%.1f echantillons=%d",
                    cast.id, age, currentTarget, currentLine,
                    minTarget, minLine, minCrossing, maxStep, samples)
            end
        end
    end

    function _F.pivotOf(object)
        if not object or not object.Parent then return nil end
        if object:IsA("BasePart") then return object.Position end
        if object:IsA("Model") then
            local part = object:FindFirstChild("HumanoidRootPart")
                or object.PrimaryPart
                or object:FindFirstChild("Head")
                or object:FindFirstChildWhichIsA("BasePart", true)
            if part then return part.Position end
            local ok, cf = pcall(object.GetPivot, object)
            if ok then return cf.Position end
        end
        return nil
    end

    function _F.tapKey(key, virtualKey)
        local ok = pcall(function()
            VIM:SendKeyEvent(true, key, false, game)
            task.wait(0.08)
            VIM:SendKeyEvent(false, key, false, game)
        end)
        if ok then return true end
        if typeof(keypress) ~= "function" then return false end
        return pcall(function()
            keypress(virtualKey)
            task.wait(0.08)
            keyrelease(virtualKey)
        end)
    end

    function _F.releaseAttack()
        minigun.releasing = true
        if typeof(mouseHeld) == "table" then
            pcall(function()
                VIM:SendMouseButtonEvent(mouseHeld.x, mouseHeld.y, 0, false, game, 0)
            end)
        elseif mouseHeld == "executor" and typeof(mouse1release) == "function" then
            pcall(mouse1release)
        end
        mouseHeld = nil
        lastAttackAssert = -math.huge
        minigun.releasing = false
    end

    function _F.holdAttack()
        if not running or humanoid.Health <= 0 then return false end
        local camera = workspace.CurrentCamera
        if not camera then return false end
        local now = os.clock()
        if mouseHeld and now - lastAttackAssert < CONFIG.ATTACK_REASSERT_INTERVAL then
            return true
        end
        local x = camera.ViewportSize.X / 2
        local y = camera.ViewportSize.Y / 2
        pcall(function() VIM:SendMouseMoveEvent(x, y, game) end)
        if typeof(mouseHeld) == "table" then
            local ok = pcall(function()
                VIM:SendMouseButtonEvent(x, y, 0, true, game, 0)
            end)
            if ok then
                mouseHeld = {x = x, y = y}
                lastAttackAssert = now
                return true
            end
        elseif mouseHeld == "executor" and typeof(mouse1press) == "function" then
            if pcall(mouse1press) then
                lastAttackAssert = now
                return true
            end
        end
        local ok = pcall(function()
            VIM:SendMouseButtonEvent(x, y, 0, true, game, 0)
        end)
        if ok then
            mouseHeld = {x = x, y = y}
            lastAttackAssert = now
            return true
        end
        if typeof(mouse1press) == "function" and pcall(mouse1press) then
            mouseHeld = "executor"
            lastAttackAssert = now
            return true
        end
        return false
    end

    function _F.equippedTool()
        if not character or not character.Parent then return nil end
        return character:FindFirstChildOfClass("Tool")
    end

    function _F.describeWeapon(tool)
        _F.say("OUTIL MINIGUN DETECTE : %s%s", tool.Name, _F.attributesOf(tool))
    end

    function _F.weaponEquipped()
        local tool = _F.equippedTool()
        if not tool then return false end
        local name = tool.Name:lower():gsub("[^%w]", "")
        return name == "watergun" or name:find("minigun", 1, true) ~= nil
    end

    function _F.equipWeapon()
        if not running or humanoid.Health <= 0 then return false end
        if _F.weaponEquipped() then return true end
        local now = os.clock()
        if now < minigun.nextEquip then return false end
        minigun.nextEquip = now + CONFIG.EQUIP_WAIT
        _F.releaseAttack()
        _F.tapKey(Enum.KeyCode.One, 0x31)
        return running and _F.weaponEquipped()
    end

    function minigun.interrupt(reason)
        if not running or minigun.releasing or not mouseHeld then return end
        minigun.restartAt = os.clock() + CONFIG.MINIGUN_HIT_SETTLE
        _F.releaseAttack()
        _F.say("MINIGUN INTERROMPU : %s -> reprise apres liberation du controle", reason)
    end

    function minigun.watchTool(tool)
        if minigun.tool == tool then return end
        if minigun.deactivated then minigun.deactivated:Disconnect() end
        minigun.tool, minigun.deactivated = tool, nil
        if tool then
            _F.describeWeapon(tool)
            minigun.deactivated = tool.Deactivated:Connect(function()
                minigun.interrupt("outil desactive")
            end)
        end
    end

    function _F.bossPosition()
        return _F.pivotOf(boss)
    end

    -- Vrai seulement si le joueur ET Kronax existent et sont a portee de combat.
    -- Sert de garde unique : lobby, chargement, boss trop loin -> aucun engagement.
    function _F.engageDistance()
        if not root or not root.Parent then return nil end
        local bossPivot = _F.pivotOf(boss)
        if not bossPivot then return nil end
        return (bossPivot - root.Position).Magnitude
    end

    function _F.bossAlive()
        if boss == nil or boss.Parent == nil then return false end
        if bossHumanoid == nil or bossHumanoid.Health <= 0 then return false end
        local distance = _F.engageDistance()
        if distance == nil or distance > CONFIG.MAX_ENGAGE_DISTANCE then
            return false
        end
        return true
    end

    function _F.matchingBoss(model)
        if not model or not model:IsA("Model") then return false end
        if not string.find(string.lower(model.Name), CONFIG.BOSS_NAME, 1, true) then
            return false
        end
        local targetHumanoid = model:FindFirstChildOfClass("Humanoid")
        if not targetHumanoid or targetHumanoid.Health <= 0 then return false end

        local dungeon = string.lower(tostring(model:GetAttribute("Dungeon") or ""))
        return model:GetAttribute("Boss") == true
            or model:GetAttribute("Base") == "TimeBoss"
            or string.find(dungeon, "timeraid", 1, true) ~= nil
    end

    function _F.findBoss()
        for _, folderName in ipairs({"Mobs", "Enemies", "Enemy", "NPCs", "Monsters"}) do
            local folder = workspace:FindFirstChild(folderName)
            if folder then
                for _, model in ipairs(folder:GetDescendants()) do
                    if _F.matchingBoss(model) then return model end
                end
            end
        end
        for _, model in ipairs(workspace:GetDescendants()) do
            if _F.matchingBoss(model) then return model end
        end
        return nil
    end

    function _F.loweredHasAny(text, keywords)
        text = string.lower(text)
        for _, keyword in ipairs(keywords) do
            if string.find(text, keyword, 1, true) then return true end
        end
        return false
    end

    local HEALTH_NAMES = {Health = true, HP = true, HitPoints = true, Durability = true}

    local HEALTH_NAME_ORDER = {"Health", "HP", "HitPoints", "Durability"}

    function _F.arenaCenter()

        return crystalRoomCenter or _F.pivotOf(boss)
    end

    function _F.numberChildValue(object, name)
        local child = object:FindFirstChild(name)
        if child and (child:IsA("NumberValue") or child:IsA("IntValue")) then
            return child.Value, child
        end
        return nil, nil
    end

    function _F.quickHealth(object)
        if not object or not object.Parent then return nil, nil, nil end
        for _, name in ipairs(HEALTH_NAME_ORDER) do
            local attribute = object:GetAttribute(name)
            if typeof(attribute) == "number" then
                local maximum = object:GetAttribute("MaxHealth")
                return attribute, typeof(maximum) == "number" and maximum or nil, nil
            end
        end
        if object:IsA("Model") then
            local hum = object:FindFirstChildOfClass("Humanoid")
            if hum then return hum.Health, hum.MaxHealth, hum end
        end
        local maximum = _F.numberChildValue(object, "MaxHealth")
        for _, name in ipairs(HEALTH_NAME_ORDER) do
            local value, source = _F.numberChildValue(object, name)
            if value ~= nil then return value, maximum, source end
        end
        return nil, nil, nil
    end

    function _F.crystalHealth(object)
        if not object or not object.Parent then return nil, nil, nil end
        local value, maximum, source = _F.quickHealth(object)
        if value ~= nil then return value, maximum, source end
        for _, name in ipairs(HEALTH_NAME_ORDER) do
            local child = object:FindFirstChild(name, true)
            if child and (child:IsA("NumberValue") or child:IsA("IntValue")) then
                local maxChild = object:FindFirstChild("MaxHealth", true)
                local deepMax = maxChild
                    and (maxChild:IsA("NumberValue") or maxChild:IsA("IntValue"))
                    and maxChild.Value or nil
                return child.Value, deepMax, child
            end
        end
        return nil, nil, nil
    end

    function _F.untargetableHealthValue(value)
        if typeof(value) ~= "number" or value <= 0 then return false end
        return value > CONFIG.CRYSTAL_MAX_TARGET_HEALTH
    end

    function _F.untargetableCrystalHealth(health, maxHealth)
        return _F.untargetableHealthValue(health) or _F.untargetableHealthValue(maxHealth)
    end

    function _F.crystalRootFrom(object)

        local current = object
        for _ = 1, 10 do
            if not current or current == workspace then break end
            local parent = current.Parent
            local parentIsCrystalFolder = parent and parent:IsA("Folder")
                and (string.lower(parent.Name) == "crystals"
                    or _F.loweredHasAny(parent.Name, CONFIG.CRYSTAL_KEYWORDS))
            if parentIsCrystalFolder
                and (current:IsA("Model") or current:IsA("BasePart")) then
                return current, "dossier de cristaux"
            end
            current = parent
        end

        current = object
        local namedPart = nil
        for _ = 1, 7 do
            if not current or current == workspace then break end
            if (current:IsA("Model") or current:IsA("BasePart"))
                and _F.loweredHasAny(current.Name, CONFIG.CRYSTAL_KEYWORDS) then
                if current:IsA("Model") then return current, "nom" end
                namedPart = namedPart or current
            end
            current = current.Parent
        end
        return namedPart, namedPart and "nom" or nil
    end

    function _F.crystalAimPart(object)
        if not object or not object.Parent then return nil end
        if object:IsA("BasePart") then return object end
        if not object:IsA("Model") then return nil end

        local best = object.PrimaryPart
        local bestScore = best and 10000 or -math.huge
        for _, part in ipairs(object:GetDescendants()) do
            if part:IsA("BasePart") then
                local name = string.lower(part.Name)
                local score = part.Size.Magnitude
                if string.find(name, "hitbox", 1, true) then
                    score += 9000
                elseif string.find(name, "core", 1, true)
                    or string.find(name, "center", 1, true)
                    or string.find(name, "centre", 1, true)
                    or name == "root" or name == "main" then
                    score += 5000
                end
                if part.Transparency < 0.98 then score += 100 end
                local queryable = true
                pcall(function() queryable = part.CanQuery end)
                if queryable then score += 50 end
                if score > bestScore then
                    best, bestScore = part, score
                end
            end
        end
        return best
    end

    function _F.damageableRootFrom(object)
        local current = object
        for _ = 1, 8 do
            if not current or current == workspace then break end
            if current:IsA("Model") then
                local health = _F.crystalHealth(current)
                if health ~= nil then return current end
            elseif current:IsA("BasePart") then
                local health = _F.crystalHealth(current)
                if health ~= nil then return current end
            end
            current = current.Parent
        end
        return nil
    end

    function _F.belongsToPlayer(object)

        local current = object
        for _ = 1, 8 do
            if not current or current == workspace then break end
            if current:IsA("Model")
                and current:GetAttribute("Owner") ~= nil
                and current:GetAttribute("SpiritType") ~= nil then
                if not discoverySeen[current] then
                    discoverySeen[current] = true
                    _F.say("INVOCATION ALLIEE IGNOREE : %s Owner=%s SpiritType=%s",
                        current:GetFullName(), tostring(current:GetAttribute("Owner")),
                        tostring(current:GetAttribute("SpiritType")))
                end
                return true
            end
            current = current.Parent
        end

        for _, otherPlayer in ipairs(Players:GetPlayers()) do
            local otherCharacter = otherPlayer.Character
            if otherCharacter and (object == otherCharacter
                or object:IsDescendantOf(otherCharacter)) then
                return true
            end
        end
        return false
    end

    function _F.crystalAlive(object, info)
        if not object or not object.Parent then return false end

        if _F.belongsToPlayer(object) then return false end
        if ignoredCrystals[object] then return false end
        info = info or crystals[object]
        if info and (info.finished or info.ignored) then return false end
        if info and info.lastHealth ~= nil then return info.lastHealth > 0 end
        local health = _F.crystalHealth(object)
        return health == nil or health > 0
    end

    function _F.selectCrystal()
        if not CONFIG.TARGET_CRYSTALS then
            activeCrystal = nil
            return nil
        end
        local best = nil
        local bestPriority = -math.huge
        local bestDistance = math.huge
        for object, info in pairs(crystals) do
            if _F.crystalAlive(object, info) then
                local pos = _F.pivotOf(object)
                local distance = pos and root and (pos - root.Position).Magnitude or math.huge
                if info.priority > bestPriority
                    or (info.priority == bestPriority and distance < bestDistance) then
                    best, bestPriority, bestDistance = object, info.priority, distance
                end
            end
        end
        if best ~= activeCrystal then
            activeCrystal = best
            if best then
                local info = crystals[best]
                info.acquiredAt = info.acquiredAt or os.clock()
                _F.say("PRIORITE OBJECTIF #%d : %s (acquis en %.3f s)",
                    info.id, best:GetFullName(), info.acquiredAt - info.spawnedAt)
            else
                _F.say("plus aucun objectif prioritaire actif -> retour sur Kronax")
            end
        end
        return best
    end

    function _F.finishCrystal(object, reason)
        local info = crystals[object]
        if not info or info.finished then return end
        info.finished = true
        local elapsed = os.clock() - info.spawnedAt
        local health = _F.crystalHealth(object)
        local fastFocusedDisappearance = reason == "disparu/detruit"
            and info.acquiredAt ~= nil and elapsed <= CONFIG.CRYSTAL_SUCCESS_WINDOW
        if reason == "PV a zero" or reason == "desactivee/cassee"
            or health == 0 or fastFocusedDisappearance then
            crystalStats.destroyed += 1
        else
            crystalStats.missed += 1
        end
        _F.say("OBJECTIF #%d FIN : %s apres %.3f s, premier tir=%s",
            info.id, reason, elapsed,
            info.firstShotAt and string.format("%.3f s", info.firstShotAt - info.spawnedAt)
                or "non observe")
        if activeCrystal == object then
            activeCrystal = nil
            task.defer(_F.selectCrystal)
        end
    end

    function _F.ignoreHighHealthCrystal(object, health, maxHealth, reason)
        if not object or ignoredCrystals[object] then return end
        ignoredCrystals[object] = true
        crystalStats.ignored += 1

        local candidate = crystalCandidates[object]
        if candidate then
            candidate.active = false
            candidate.ignored = true
            candidate.inactiveSince = nil
        end

        local info = crystals[object]
        if info and not info.finished then
            info.finished = true
            info.ignored = true

            crystalStats.seen = math.max(0, crystalStats.seen - 1)
        end
        _F.say("CRISTAL >10M IGNORE : %s vie=%s/%s raison=%s -> FOCUS KRONAX",
            object:GetFullName(),
            health and string.format("%.0f", health) or "?",
            maxHealth and string.format("%.0f", maxHealth) or "?",
            tostring(reason))
        if activeCrystal == object then
            activeCrystal = nil
            task.defer(_F.selectCrystal)
        end
    end

    function _F.bindCrystalHealth(object, info)
        if info.healthBound then return end
        local health, maxHealth, source = _F.crystalHealth(object)
        info.lastHealth = health
        info.lastMaxHealth = maxHealth
        if health ~= nil then
            _F.say("OBJECTIF #%d vie initiale : %.0f%s", info.id, health,
                maxHealth and string.format("/%.0f", maxHealth) or "")
        end
        if source and source:IsA("Humanoid") then
            info.healthBound = true
            _F.connect(source.HealthChanged, function(value)
                if not running or info.finished then return end
                if _F.untargetableCrystalHealth(value, source.MaxHealth) then
                    _F.ignoreHighHealthCrystal(object, value, source.MaxHealth,
                        "changement Humanoid")
                    return
                end
                if info.lastHealth and value < info.lastHealth then
                    info.damageSeen = true
                    _F.say("OBJECTIF #%d DEGATS : -%.0f, reste %.0f", info.id,
                        info.lastHealth - value, value)
                end
                info.lastHealth = value
                if value <= 0 then _F.finishCrystal(object, "PV a zero") end
            end, crystalConnections)
            _F.connect(source:GetPropertyChangedSignal("MaxHealth"), function()
                if not running or info.finished then return end
                info.lastMaxHealth = source.MaxHealth
                if _F.untargetableCrystalHealth(source.Health, source.MaxHealth) then
                    _F.ignoreHighHealthCrystal(object, source.Health, source.MaxHealth,
                        "MaxHealth Humanoid")
                end
            end, crystalConnections)
        elseif source and (source:IsA("NumberValue") or source:IsA("IntValue")) then
            info.healthBound = true
            _F.connect(source:GetPropertyChangedSignal("Value"), function()
                local value = source.Value
                if _F.untargetableCrystalHealth(value, nil) then
                    _F.ignoreHighHealthCrystal(object, value, nil,
                        "changement NumberValue")
                    return
                end
                if info.lastHealth and value < info.lastHealth then
                    info.damageSeen = true
                    _F.say("OBJECTIF #%d DEGATS : -%.0f, reste %.0f", info.id,
                        info.lastHealth - value, value)
                end
                info.lastHealth = value
                if value <= 0 then _F.finishCrystal(object, "PV a zero") end
            end, crystalConnections)
        elseif not info.attributeBound then
            info.attributeBound = true
            _F.connect(object.AttributeChanged, function(name)
                if not HEALTH_NAMES[name] and name ~= "MaxHealth" then return end
                local value, maximum = _F.crystalHealth(object)
                if _F.untargetableCrystalHealth(value, maximum) then
                    _F.ignoreHighHealthCrystal(object, value, maximum,
                        "attribut " .. tostring(name))
                    return
                end
                if typeof(value) ~= "number" then return end
                if info.lastHealth and value < info.lastHealth then
                    info.damageSeen = true
                    _F.say("OBJECTIF #%d DEGATS : -%.0f, reste %.0f", info.id,
                        info.lastHealth - value, value)
                end
                info.lastHealth = value
                info.lastMaxHealth = maximum
                if value <= 0 then _F.finishCrystal(object, "PV a zero") end
            end, crystalConnections)
        end
    end

    function _F.registerCrystal(object, spawnedNow, allowFallback)
        local explicitObject, explicitMode = _F.crystalRootFrom(object)
        local explicit = explicitObject ~= nil
        object = explicitObject or (allowFallback and _F.damageableRootFrom(object) or nil)
        if not object or _F.belongsToPlayer(object) then return end
        local existing = crystals[object]
        if existing and not existing.finished then return existing end
        if existing and existing.finished then crystals[object] = nil end
        if boss and (object == boss or object:IsDescendantOf(boss)) then return end
        local loweredName = string.lower(object.Name)
        if string.find(loweredName, CONFIG.BOSS_NAME, 1, true)
            or object:GetAttribute("Boss") == true then
            return
        end
        local inEffects = object:FindFirstAncestor("Effects") ~= nil
        if not explicit and inEffects then return end

        local pos = _F.pivotOf(object)

        local centre = _F.arenaCenter()
        local maxDistance = explicit and CONFIG.CRYSTAL_SCAN_RADIUS
            or (crystalRoomCenter and CONFIG.ARENA_RADIUS
                or CONFIG.FALLBACK_TARGET_RADIUS)
        if pos and centre and (pos - centre).Magnitude > maxDistance then return end

        local health, maxHealth = _F.crystalHealth(object)
        if _F.untargetableCrystalHealth(health, maxHealth) then
            _F.ignoreHighHealthCrystal(object, health, maxHealth, "apparition")
            return
        end
        if health ~= nil and health <= 0 then return end
        if not explicit and (not _F.bossAlive() or health == nil or health <= 0) then return end
        if explicit and not spawnedNow and health == nil then return end

        if explicitMode == "nom" and health == nil then return end
        if explicit and health == nil and inEffects
            and _F.loweredHasAny(object.Name, {"effect", "particle", "glow", "beam", "aura"}) then
            return
        end

        crystalSerial += 1
        crystalStats.seen += 1
        local info = {
            id = crystalSerial,
            spawnedAt = os.clock(),
            finished = false,
            explicit = explicit,
            priority = explicit and 100 or (spawnedNow and 50 or 10),
            aimPart = _F.crystalAimPart(object),
            shotEffects = 0,
        }
        crystals[object] = info
        local targetHumanoid = object:IsA("Model")
            and object:FindFirstChildOfClass("Humanoid") or nil
        _F.say("OBJECTIF #%d SPAWN : %s [%s] mode=%s display=%s%s pos=%s", info.id,
            object:GetFullName(), object.ClassName,
            explicit and explicitMode or "nouveau modele attaquable",
            targetHumanoid and targetHumanoid.DisplayName or "-", _F.attributesOf(object),
            pos and _F.describe(pos, 1) or "?")
        if info.aimPart then
            _F.say("OBJECTIF #%d POINT VISE : %s pos=%s taille=%s", info.id,
                info.aimPart:GetFullName(), _F.describe(info.aimPart.Position, 1),
                _F.describe(info.aimPart.Size, 1))
        end
        _F.bindCrystalHealth(object, info)
        _F.connect(object.DescendantAdded, function(child)
            if info.finished then return end
            if not info.healthBound
                and (child:IsA("Humanoid") or HEALTH_NAMES[child.Name]) then
                _F.bindCrystalHealth(object, info)
            end
            if child:IsA("BasePart") then
                local aimPart = _F.crystalAimPart(object)
                if aimPart and aimPart ~= info.aimPart then
                    info.aimPart = aimPart
                    _F.say("OBJECTIF #%d NOUVEAU POINT VISE : %s pos=%s", info.id,
                        aimPart:GetFullName(), _F.describe(aimPart.Position, 1))
                end
            end
        end, crystalConnections)
        _F.connect(object.AncestryChanged, function(_, parent)
            if not parent then _F.finishCrystal(object, "disparu/detruit") end
        end, crystalConnections)
        _F.selectCrystal()
        return info
    end

    function _F.crystalCandidateSignature(object)
        local health, maxHealth = _F.crystalHealth(object)
        local signature = {
            descendants = 0,
            visibleParts = 0,
            queryParts = 0,
            enabledEffects = 0,
            health = health,
            maxHealth = maxHealth,
            attributes = "",
            visualState = "",
        }
        local attributeParts = {}
        local visualParts = {}
        local function collectAttributes(item)
            for name, value in pairs(item:GetAttributes()) do
                attributeParts[#attributeParts + 1] = item.Name .. "." .. name
                    .. "=" .. tostring(value)
            end
        end
        collectAttributes(object)
        for _, child in ipairs(object:GetDescendants()) do
            signature.descendants += 1
            collectAttributes(child)
            if child:IsA("BasePart") then
                if child.Transparency < 0.98 then signature.visibleParts += 1 end
                local queryable = true
                pcall(function() queryable = child.CanQuery end)
                if queryable then signature.queryParts += 1 end
                visualParts[#visualParts + 1] = string.format("%s:%.3f:%s:%s:%s",
                    child.Name, child.Transparency, tostring(child.Color),
                    tostring(child.Material), tostring(queryable))
            elseif child:IsA("ParticleEmitter") or child:IsA("Beam")
                or child:IsA("Trail") or child:IsA("Light") then
                local enabled = false
                pcall(function() enabled = child.Enabled end)
                if enabled then signature.enabledEffects += 1 end
                visualParts[#visualParts + 1] = child.ClassName .. ":"
                    .. child.Name .. ":" .. tostring(enabled)
            end
        end
        table.sort(attributeParts)
        table.sort(visualParts)
        signature.attributes = table.concat(attributeParts, "|")
        signature.visualState = table.concat(visualParts, "|")
        return signature
    end

    function _F.candidateChanged(current, baseline)
        if not current or not baseline then return false end

        if current.health == nil then return false end
        return current.health > 0
    end

    function _F.evaluateCrystalCandidate(object, reason)
        local candidate = crystalCandidates[object]
        if not candidate or not object.Parent then return end
        local now = os.clock()
        local signature = _F.crystalCandidateSignature(object)

        if not _F.bossAlive() then
            candidate.baseline = signature
            candidate.active = false
            candidate.inactiveSince = nil
            return
        end

        if _F.untargetableCrystalHealth(signature.health, signature.maxHealth) then
            _F.ignoreHighHealthCrystal(object, signature.health, signature.maxHealth,
                reason)
            return
        elseif candidate.ignored then

            candidate.ignored = false
            ignoredCrystals[object] = nil
            candidate.baseline = signature
            if signature.health == nil or signature.health <= 0 then return end
        end
        local changed = _F.candidateChanged(signature, candidate.baseline)
        local info = crystals[object]

        if not candidate.active and changed then
            info = _F.registerCrystal(object, true)
            if info then
                candidate.active = true
                candidate.activatedAt = now
                candidate.inactiveSince = nil
                _F.say("RELIQUE ACTIVE : %s raison=%s visible=%d effets=%d descendants=%d",
                    object:GetFullName(), tostring(reason), signature.visibleParts,
                    signature.enabledEffects, signature.descendants)
            end
        elseif candidate.active then
            if signature.health ~= nil and signature.health <= 0 then
                _F.finishCrystal(object, "PV a zero")
                candidate.active = false
                candidate.inactiveSince = nil
            elseif changed then
                candidate.inactiveSince = nil
            else
                candidate.inactiveSince = candidate.inactiveSince or now
                local focusedFor = info and info.firstShotAt
                    and now - info.firstShotAt or 0
                local enoughShots = info
                    and info.shotEffects >= CONFIG.CRYSTAL_VISUAL_MIN_SHOTS
                local focusConfirmed = enoughShots
                    and focusedFor >= CONFIG.CRYSTAL_VISUAL_MIN_FOCUS
                if now - candidate.inactiveSince >= 0.20 and focusConfirmed then
                    _F.finishCrystal(object, "desactivee/cassee")
                    candidate.active = false
                    candidate.inactiveSince = nil
                elseif now - candidate.inactiveSince >= 0.20
                    and info and not info.visualHoldLogged then
                    info.visualHoldLogged = true
                    _F.say("OBJECTIF #%d RESTE PRIORITAIRE : signal visuel termine mais"
                            .. " destruction non prouvee (%d/%d tirs, focus %.1f/%.1f s)",
                        info.id, info.shotEffects, CONFIG.CRYSTAL_VISUAL_MIN_SHOTS,
                        focusedFor, CONFIG.CRYSTAL_VISUAL_MIN_FOCUS)
                end
            end
        elseif info and not info.finished then
            candidate.active = true
            candidate.activatedAt = now
        end
    end

    function _F.bindCrystalCandidateObject(candidate, object)
        if candidate.bound[object] then return end
        candidate.bound[object] = true
        _F.connect(object.AttributeChanged, function(name)
            if running then
                task.defer(_F.evaluateCrystalCandidate,
                    candidate.object, "attribut " .. tostring(name))
            end
        end)
        if object:IsA("BasePart") then
            _F.connect(object:GetPropertyChangedSignal("Transparency"), function()
                if running then
                    task.defer(_F.evaluateCrystalCandidate,
                        candidate.object, "visibilite " .. object.Name)
                end
            end)
            pcall(function()
                _F.connect(object:GetPropertyChangedSignal("CanQuery"), function()
                    if running then
                        task.defer(_F.evaluateCrystalCandidate,
                            candidate.object, "CanQuery " .. object.Name)
                    end
                end)
            end)
        elseif object:IsA("ParticleEmitter") or object:IsA("Beam")
            or object:IsA("Trail") or object:IsA("Light") then
            pcall(function()
                _F.connect(object:GetPropertyChangedSignal("Enabled"), function()
                    if running then
                        task.defer(_F.evaluateCrystalCandidate,
                            candidate.object, "effet " .. object.Name)
                    end
                end)
            end)
        elseif object:IsA("NumberValue") or object:IsA("IntValue") then
            _F.connect(object:GetPropertyChangedSignal("Value"), function()
                if running then
                    task.defer(_F.evaluateCrystalCandidate,
                        candidate.object, "valeur " .. object.Name)
                end
            end)
        end
    end

    function _F.watchCrystalCandidate(object, index)
        if not object or crystalCandidates[object] then return end
        local candidate = {
            object = object,
            baseline = _F.crystalCandidateSignature(object),
            active = false,
            bound = {},
            inactiveSince = nil,
        }
        crystalCandidates[object] = candidate
        _F.bindCrystalCandidateObject(candidate, object)
        for _, child in ipairs(object:GetDescendants()) do
            _F.bindCrystalCandidateObject(candidate, child)
        end
        _F.connect(object.DescendantAdded, function(child)
            _F.bindCrystalCandidateObject(candidate, child)
            task.defer(_F.evaluateCrystalCandidate, object,
                "ajout " .. child.ClassName .. ":" .. child.Name)
        end)
        _F.connect(object.DescendantRemoving, function(child)
            task.delay(0.05, _F.evaluateCrystalCandidate, object,
                "retrait " .. child.ClassName .. ":" .. child.Name)
        end)
        local base = candidate.baseline
        _F.say("CRISTAL CANDIDAT[%d] : %s visible=%d effets=%d descendants=%d",
            index, object:GetFullName(), base.visibleParts,
            base.enabledEffects, base.descendants)
    end

    function _F.refreshCrystalCandidates()
        for object in pairs(crystalCandidates) do
            _F.evaluateCrystalCandidate(object, "surveillance")
        end
    end

    function _F.watchCrystalFolder(folder)
        if not folder or watchedCrystalFolders[folder] then return false end
        watchedCrystalFolders[folder] = true
        local centres = {}
        local children = folder:GetChildren()
        _F.say("DOSSIER CRYSTALS : %s contient %d enfant(s)",
            folder:GetFullName(), #children)
        for index, child in ipairs(children) do
            if child:IsA("Model") or child:IsA("BasePart") then
                _F.watchCrystalCandidate(child, index)
                local pos = _F.pivotOf(child)
                if pos then centres[#centres + 1] = pos end
            end
        end
        _F.connect(folder.ChildAdded, function(child)
            if not running then return end
            if child:IsA("Model") or child:IsA("BasePart") then
                _F.watchCrystalCandidate(child, #folder:GetChildren())
                task.defer(_F.evaluateCrystalCandidate, child,
                    "nouvel emplacement")
            end
        end)
        if #centres > 0 then
            local total = Vector3.zero
            for _, pos in ipairs(centres) do total += pos end
            crystalRoomCenter = total / #centres
            _F.say("CENTRE SALLE ESTIME PAR LES CRISTAUX : %s", _F.describe(crystalRoomCenter, 1))
        end
        return true
    end

    function _F.inArena(object)
        local pos = _F.pivotOf(object)
        local centre = _F.arenaCenter()

        if not pos or not centre then return true end
        return (pos - centre).Magnitude <= CONFIG.ARENA_RADIUS
    end

    function _F.isBossPart(object)
        if boss and (object == boss or object:IsDescendantOf(boss)) then return true end
        if object:GetAttribute("Boss") == true then return true end

        if not string.find(string.lower(object.Name), CONFIG.BOSS_NAME, 1, true) then
            return false
        end
        return object:IsA("Model")
            and object:FindFirstChildOfClass("Humanoid") ~= nil
    end

    function _F.destructibleVerdict(health, maxHealth)
        if typeof(health) ~= "number" then return nil end
        if _F.untargetableCrystalHealth(health, maxHealth) then return "sentinelle" end
        if health < CONFIG.CRYSTAL_MIN_TARGET_HEALTH then return nil end
        return "cible"
    end

    function _F.noteDiscovery(object, health, maxHealth, verdict, reason)
        if discoveryLogged >= CONFIG.DISCOVERY_LOG_MAX then return end
        if discoverySeen[object] then return end
        discoverySeen[object] = true
        discoveryLogged += 1
        _F.say("DESTRUCTIBLE VU (%s) : %s [%s] vie=%s/%s%s via %s", verdict,
            object:GetFullName(), object.ClassName,
            health and string.format("%.0f", health) or "?",
            maxHealth and string.format("%.0f", maxHealth) or "?",
            _F.attributesOf(object), tostring(reason))
    end

    function _F.acceptDestructible(object, reason, explicit)
        if not object or not object.Parent then return nil end
        local known = crystals[object]
        if known and not known.finished then return known end
        if ignoredCrystals[object] then return nil end
        if _F.isBossPart(object) or _F.belongsToPlayer(object) then return nil end
        if object:FindFirstAncestor("Effects") then return nil end

        local health, maxHealth = _F.crystalHealth(object)
        local verdict = _F.destructibleVerdict(health, maxHealth)
        if verdict == "sentinelle" then
            _F.ignoreHighHealthCrystal(object, health, maxHealth, tostring(reason))
            return nil
        end
        if verdict ~= "cible" then
            if health ~= nil then
                _F.noteDiscovery(object, health, maxHealth, "dormant/hors seuil", reason)
            end
            if not explicit then return nil end
        end
        if not explicit and not _F.inArena(object) then
            _F.noteDiscovery(object, health, maxHealth, "hors arene", reason)
            return nil
        end

        local info = _F.registerCrystal(object, true, true)
        if info and not explicit then

            info.mini = true
        end
        if not info then

            if verdict == "cible" then
                _F.noteDiscovery(object, health, maxHealth, "refuse a l'enregistrement",
                    reason)
            end
            return nil
        end
        if not explicit then
            miniCrystalCount += 1
            _F.say("MINI CRISTAL DETECTE : objectif #%d vie=%.0f/%s %s via %s",
                info.id, health,
                maxHealth and string.format("%.0f", maxHealth) or "?",
                object:GetFullName(), tostring(reason))
        end
        return info
    end

    function _F.queueDynamicCrystal(rootObject, reason)
        if not rootObject or not rootObject.Parent then return end
        local explicitRoot = _F.crystalRootFrom(rootObject)

        local resolved = explicitRoot or rootObject
        if not resolved or not resolved.Parent then return end

        if crystalCandidates[resolved] then
            task.defer(_F.evaluateCrystalCandidate, resolved, reason)
            return
        end
        local known = crystals[resolved]
        if known and not known.finished then return end
        if ignoredCrystals[resolved] then return end
        if dynamicCrystalPending[resolved] then return end
        dynamicCrystalPending[resolved] = true

        task.delay(CONFIG.DYNAMIC_CRYSTAL_SETTLE_DELAY, function()
            dynamicCrystalPending[resolved] = nil
            if not running then return end
            _F.acceptDestructible(resolved, reason, explicitRoot ~= nil)
        end)
    end

    local watchedRootCount = 0

    function _F.watchDynamicCrystalRoot(rootObject, reason)
        if not rootObject or not rootObject.Parent then return end
        if rootObject:FindFirstAncestor("Effects") then return end
        if _F.belongsToPlayer(rootObject) then return end
        if not dynamicCrystalWatched[rootObject]

            and watchedRootCount < 600 then
            dynamicCrystalWatched[rootObject] = true
            watchedRootCount += 1
            _F.connect(rootObject.AttributeChanged, function(name)
                if HEALTH_NAMES[name] or name == "MaxHealth" then
                    _F.queueDynamicCrystal(rootObject,
                        "attribut dynamique " .. tostring(name))
                end
            end)
            if rootObject:IsA("Model") then
                _F.connect(rootObject.DescendantAdded, function(child)
                    if child:IsA("Humanoid") or HEALTH_NAMES[child.Name]
                        or child.Name == "MaxHealth" then
                        _F.queueDynamicCrystal(rootObject, "vie ajoutee " .. child.Name)
                    end
                end)
            end
        end
        _F.queueDynamicCrystal(rootObject, reason)
    end

    function _F.considerDynamicCrystal(object)
        if not running or not object then return end

        local isModel = object:IsA("Model")
        local isPart = not isModel and object:IsA("BasePart")
        if not isModel and not isPart then
            local isHealthValue = object:IsA("Humanoid")
                or ((object:IsA("NumberValue") or object:IsA("IntValue"))
                    and (HEALTH_NAMES[object.Name] or object.Name == "MaxHealth"))
            if not isHealthValue then return end
            if object:FindFirstAncestor("Effects") then return end
            local rootObject = object:FindFirstAncestorOfClass("Model")
                or (object.Parent and object.Parent:IsA("BasePart") and object.Parent or nil)
            if rootObject then
                _F.watchDynamicCrystalRoot(rootObject,
                    "vie ajoutee " .. object.ClassName .. ":" .. object.Name)
            end
            return
        end
        if object:FindFirstAncestor("Effects") then return end

        local explicitRoot = _F.crystalRootFrom(object)
        if explicitRoot then
            _F.watchDynamicCrystalRoot(explicitRoot,
                "spawn " .. object.ClassName .. ":" .. object.Name)
            return
        end

        if isModel then

            _F.watchDynamicCrystalRoot(object, "spawn Model:" .. object.Name)
            return
        end

        if _F.quickHealth(object) ~= nil
            or _F.loweredHasAny(object.Name, CONFIG.MINI_CRYSTAL_KEYWORDS) then
            _F.watchDynamicCrystalRoot(object, "spawn BasePart:" .. object.Name)
        end
    end

    local sweepQueue = {}

    function _F.arenaContainers()
        local containers = {}
        local seen = {}
        local function add(object)
            if object and not seen[object] and object.Name ~= "Effects" then
                seen[object] = true
                containers[#containers + 1] = object
            end
        end
        local map = workspace:FindFirstChild("Map")
        local dungeon = map and map:FindFirstChild("TimeRaidDungeon")
        if dungeon then
            add(dungeon)

            for _, child in ipairs(dungeon:GetChildren()) do
                if child:IsA("Folder") or child:IsA("Model") then add(child) end
            end
        end
        for _, name in ipairs({"Crystals", "Objects", "Interactables", "Debris",
            "Runtime", "Temp", "Mobs"}) do
            add(workspace:FindFirstChild(name))
        end
        add(workspace)
        return containers
    end

    function _F.refillSweepQueue()
        table.clear(sweepQueue)
        for _, container in ipairs(_F.arenaContainers()) do
            if container.Parent or container == workspace then
                for _, child in ipairs(container:GetChildren()) do
                    if child:IsA("Model") or child:IsA("BasePart") then
                        sweepQueue[#sweepQueue + 1] = child
                    end
                end
            end
        end
        sweepChildIndex = 1
    end

    function _F.inspectSweepEntry(object)
        if not object.Parent then return end
        if crystalCandidates[object] or ignoredCrystals[object] then return end
        local known = crystals[object]
        if known and not known.finished then return end

        local health, maxHealth = _F.quickHealth(object)
        if health == nil then return end
        if _F.destructibleVerdict(health, maxHealth) == nil then return end
        _F.acceptDestructible(object, "balayage arene", false)
    end

    function _F.sweepArena()

        if #sweepQueue == 0 or sweepChildIndex > #sweepQueue then
            _F.refillSweepQueue()
        end

        local budget = math.max(CONFIG.ARENA_SWEEP_BUDGET,
            math.ceil(#sweepQueue / 4))
        while budget > 0 and sweepChildIndex <= #sweepQueue do
            _F.inspectSweepEntry(sweepQueue[sweepChildIndex])
            sweepChildIndex += 1
            budget -= 1
        end
    end

    function _F.dropStuckTarget()
        local object = activeCrystal
        if not object then return end
        local info = crystals[object]
        if not info or info.finished or info.damageSeen then return end
        local since = info.acquiredAt or info.spawnedAt
        if os.clock() - since < CONFIG.CRYSTAL_STUCK_TIMEOUT then return end

        local candidate = crystalCandidates[object]
        if candidate then
            candidate.active = false
            candidate.activatedAt = nil
            candidate.inactiveSince = nil
            candidate.baseline = _F.crystalCandidateSignature(object)
            ignoredCrystals[object] = nil
            _F.say("OBJECTIF #%d RELACHE SANS BLACKLIST : emplacement fixe reutilisable",
                info.id)
            _F.finishCrystal(object, "aucun degat, emplacement conserve")
            return
        end

        ignoredCrystals[object] = true
        _F.say("OBJECTIF #%d ABANDONNE : aucun degat en %.0f s -> FOCUS KRONAX (%s)",
            info.id, CONFIG.CRYSTAL_STUCK_TIMEOUT, object:GetFullName())
        _F.finishCrystal(object, "aucun degat, abandonne")
    end

    function _F.hookDynamicCrystals()

        _F.connect(workspace.DescendantAdded, _F.considerDynamicCrystal)
        _F.say("mini cristaux : detection dynamique + balayage arene actifs")
    end

    function _F.scanCrystals()

        local map = workspace:FindFirstChild("Map")
        local dungeon = map and map:FindFirstChild("TimeRaidDungeon")
        local folder = dungeon and dungeon:FindFirstChild("Crystals")
        if folder then return _F.watchCrystalFolder(folder) end

        folder = workspace:FindFirstChild("Crystals", true)
        return folder and _F.watchCrystalFolder(folder) or false
    end

    function _F.combatTarget()

        local crystal = activeCrystal
        local info = crystal and crystals[crystal] or nil
        if not _F.crystalAlive(crystal, info) then crystal = _F.selectCrystal() end
        if crystal then return crystal end
        return _F.bossAlive() and boss or nil
    end

    function _F.aimPosition(target)
        target = target or _F.combatTarget()
        local info = target and crystals[target] or nil
        local part = info and info.aimPart or nil
        if part and part.Parent and (part == target or part:IsDescendantOf(target)) then
            return part.Position
        end
        return _F.pivotOf(target) or _F.bossPosition()
    end

    function _F.recentAbilityText()
        local now = os.clock()
        for index = #recentAbilities, 1, -1 do
            local entry = recentAbilities[index]
            if now - entry.at <= 6 then
                return string.format(" apres %s (+%.2fs, annonce %.0f)",
                    entry.name, now - entry.at, entry.damage)
            end
        end
        return ""
    end

    function _F.watchBoss(model)
        _F.disconnectList(bossConnections)
        boss = model
        bossHumanoid = model and model:FindFirstChildOfClass("Humanoid") or nil
        if not bossHumanoid then return end
        bossLastHealth = bossHumanoid.Health
        bossSeenAt = os.clock()
        bossInitialPosition = _F.pivotOf(model)
        local dungeonName = string.lower(tostring(model:GetAttribute("Dungeon") or ""))
        local corrupted = string.find(string.lower(model.Name), "corrupted", 1, true)
            ~= nil or string.find(dungeonName, "corr", 1, true) ~= nil
        heroicState.mode = not corrupted and (dungeonName == "heroictimeraid"
            or bossHumanoid.MaxHealth >= 190000000)
        heroicState.motionPhase = orbitAngle
        heroicState.targetedUntil = 0
        heroicState.targetedLabel = nil
        heroicState.anchorBlend = 0
        heroicState.anchor = nil
        heroicState.radiusX = CONFIG.HEROIC_THRONE_RADIUS_X
        heroicState.radiusZ = CONFIG.HEROIC_THRONE_RADIUS_Z
        heroicState.losGoal = nil
        heroicState.losGoalUntil = 0
        heroicState.travelKickAt = 0
        heroicState.travelKicks = 0
        _F.say("BOSS DETECTE : %s, %.0f/%.0f PV%s", model.Name,
            bossHumanoid.Health, bossHumanoid.MaxHealth, _F.attributesOf(model))
        _F.say("PROFIL MOUVEMENT : %s",
            heroicState.mode and "HEROIC CONTINU" or "CORRUPTED CLASSIQUE")

        _F.connect(bossHumanoid.HealthChanged, function(health)
            if not running then return end
            if bossLastHealth and health < bossLastHealth then
                _F.say("BOSS DEGATS : -%.0f, reste %.0f/%.0f, cible=%s",
                    bossLastHealth - health, health, bossHumanoid.MaxHealth,
                    activeCrystal and ("OBJECTIF #" .. crystals[activeCrystal].id) or "KRONAX")
            end
            bossLastHealth = health
            if health <= 0 then
                _F.say("=== KRONAX TERMINE en %.2f s ===", os.clock() - bossSeenAt)
                _F.releaseAttack()
                _F.writeLog(true)
            end
        end, bossConnections)

        if CONFIG.VERBOSE_DIAGNOSTICS then
            _F.connect(model.AttributeChanged, function(name)
                _F.say("boss.%s = %s", name, _F.describe(model:GetAttribute(name), 2))
            end, bossConnections)
            _F.connect(model.DescendantAdded, function(object)
                if object:IsA("Animation") then
                    _F.say("boss animation ajoutee : %s id=%s", object.Name, object.AnimationId)
                end
            end, bossConnections)
            local animator = bossHumanoid:FindFirstChildOfClass("Animator")
                or bossHumanoid:WaitForChild("Animator", 3)
            if animator then
                _F.connect(animator.AnimationPlayed, function(track)
                    local animation = track.Animation
                    _F.say("ANIMATION KRONAX : %s id=%s longueur=%.2f vitesse=%.2f",
                        track.Name, animation and animation.AnimationId or "?",
                        track.Length, track.Speed)
                end, bossConnections)
            end
        end
    end

    local sightParams = RaycastParams.new()
    pcall(function() sightParams.FilterType = Enum.RaycastFilterType.Exclude end)
    pcall(function() sightParams.IgnoreWater = true end)

    local floorParams = RaycastParams.new()
    pcall(function() floorParams.FilterType = Enum.RaycastFilterType.Exclude end)
    pcall(function() floorParams.IgnoreWater = true end)

    local cachedFloorY = nil
    local cachedFloorAt = -math.huge

    function _F.arenaFloorY()
        local now = os.clock()
        if cachedFloorY and now - cachedFloorAt < 2 then return cachedFloorY end

        local from = crystalRoomCenter
            and Vector3.new(crystalRoomCenter.X, crystalRoomCenter.Y + 50,
                crystalRoomCenter.Z)
            or (root and root.Position) or _F.pivotOf(boss)
        if not from then return cachedFloorY end
        local ignored = {character}
        local effects = workspace:FindFirstChild("Effects")
        if effects then ignored[#ignored + 1] = effects end
        local mobs = workspace:FindFirstChild("Mobs")
        if mobs then ignored[#ignored + 1] = mobs end
        floorParams.FilterDescendantsInstances = ignored
        local hit = workspace:Raycast(from, Vector3.new(0, -600, 0), floorParams)
        if hit then
            cachedFloorY = hit.Position.Y
            cachedFloorAt = now
            return cachedFloorY
        end

        if crystalRoomCenter and not cachedFloorY then
            cachedFloorY = crystalRoomCenter.Y - 25
            cachedFloorAt = now
        end
        return cachedFloorY
    end

    function _F.altitudeCeilingY()
        local floor = _F.arenaFloorY()
        if not floor then return nil end
        return floor + CONFIG.ALTITUDE_LIMIT - CONFIG.ALTITUDE_MARGIN
    end

    function _F.checkSight(from, target)
        local ignored = {character}
        if boss then ignored[#ignored + 1] = boss end
        if activeCrystal then ignored[#ignored + 1] = activeCrystal end
        local effects = workspace:FindFirstChild("Effects")
        if effects then ignored[#ignored + 1] = effects end
        local mobs = workspace:FindFirstChild("Mobs")
        if mobs then ignored[#ignored + 1] = mobs end
        sightParams.FilterDescendantsInstances = ignored
        local result = workspace:Raycast(from, target - from, sightParams)
        return result and result.Instance or nil
    end

    function _F.restoreNoclip()
        for part, value in pairs(oldCollision) do
            if part.Parent then part.CanCollide = value end
        end
        table.clear(characterParts)
        table.clear(oldCollision)
        wallCollisionEnabled = false
        wallBumpUntil = 0
    end

    function _F.setWallCollision(enabled)
        if wallCollisionEnabled == enabled then return end
        wallCollisionEnabled = enabled
        for part in pairs(characterParts) do
            if part.Parent then
                part.CanCollide = enabled and (part == root or oldCollision[part] == true) or false
            end
        end
    end

    function _F.trackCharacterParts()
        if partAdded then partAdded:Disconnect() end
        if partRemoved then partRemoved:Disconnect() end
        _F.restoreNoclip()
        local function add(object)
            if not object:IsA("BasePart") or characterParts[object] then return end
            characterParts[object] = true
            oldCollision[object] = object.CanCollide
            object.CanCollide = false
        end
        for _, object in ipairs(character:GetDescendants()) do add(object) end
        partAdded = character.DescendantAdded:Connect(add)
        partRemoved = character.DescendantRemoving:Connect(function(object)
            characterParts[object] = nil
            oldCollision[object] = nil
        end)
    end

    local IMPACT_KEYS = {
        {"TargetPosition", true},
        {"Goal", true},
        {"EndPosition", false},
        {"Pivot", false},
        {"Position", true},
    }

    function _F.impactPoint(data)
        for _, entry in ipairs(IMPACT_KEYS) do
            local value = data[entry[1]]
            local point = nil
            if typeof(value) == "Vector3" then point = value end
            if typeof(value) == "CFrame" then point = value.Position end
            if point then
                local duration = tonumber(data.Duration)
                if not duration or duration <= 0 then
                    duration = entry[2] and CONFIG.HAZARD_LIFETIME or 1.0
                end
                return point, math.clamp(duration, 0.35, 8.0), entry[1]
            end
        end
        return nil, 0, nil
    end

    local ABILITY_PROFILES = {

        chronoshockwave = {radius = 140, lifetime = 1.5},

        timestreamdecay = {radius = 95, lifetime = 1.4},

        timelinedestruction = {
            radius = CONFIG.TIMELINE_CORRIDOR_RADIUS,
            lifetime = 2.0,
            source = "profil securise v0.26",
        },
        temporaltear = {radius = 30, lifetime = 2.2},

        flashforward = {radius = 30, lifetime = 1.0},
    }

    function _F.abilityProfile(name)
        return ABILITY_PROFILES[string.lower(tostring(name))]
    end

    function _F.payloadRadius(data, name)

        for _, key in ipairs({"Radius", "AOERadius", "HitboxRadius",
            "WarningRadius", "Width"}) do
            local value = tonumber(data[key])
            if value and value > 0 then
                return math.clamp(value, 6, CONFIG.HAZARD_RADIUS_MAX), key
            end
        end
        local size = data.Size
        if typeof(size) == "Vector3" then
            return math.clamp(math.max(size.X, size.Z) / 2, 6,
                CONFIG.HAZARD_RADIUS_MAX), "Size"
        end

        local profile = _F.abilityProfile(name)
        if profile then return profile.radius, profile.source or "profil mesure" end

        return CONFIG.HAZARD_DEFAULT_RADIUS, "telegraphe mesure"
    end

    local SPATIAL_HAZARDS = {
        timelinedestruction = "hard",

        temporaltear = "hard",

        flashforward = "hard",
    }

    function _F.addHazard(label, position, radius, lifetime, source, part,
            segmentStart)
        if typeof(position) ~= "Vector3" then return end
        local loweredLabel = string.lower(tostring(label))
        local spatialKind = SPATIAL_HAZARDS[loweredLabel]
        local hazard = {
            label = label,
            pos = position,
            radius = math.clamp(radius or CONFIG.HAZARD_DEFAULT_RADIUS, 4,
                CONFIG.HAZARD_RADIUS_MAX),
            expires = os.clock() + (lifetime or CONFIG.HAZARD_LIFETIME),
            source = source,
            part = part,
            segmentStart = typeof(segmentStart) == "Vector3" and segmentStart or nil,

            spatial = spatialKind ~= nil,
            follower = spatialKind == "follower",
            engaged = false,
        }
        hazards[#hazards + 1] = hazard

        if #hazards > 140 then table.remove(hazards, 1) end
        return hazard
    end

    function _F.ignoreForHeroicFlow(hazard, heroicFlow)
        if not heroicFlow then return false end

        return hazard.follower
    end

    function _F.hazardDistance(position, hazard)
        if hazard.segmentStart then
            if hazard.spatial then
                return _F.segmentDistance3D(position, hazard.segmentStart, hazard.pos)
            end
            return _F.flatSegmentDistance(position, hazard.segmentStart, hazard.pos)
        end
        if hazard.spatial then return (position - hazard.pos).Magnitude end
        return _F.flatDistance(position, hazard.pos)
    end

    function _F.hazardEdge(position, hazard)
        return _F.hazardDistance(position, hazard) - hazard.radius
    end

    function _F.warningPart(object)
        if object:IsA("BasePart") then
            local current = object
            for _ = 1, 5 do
                if not current then break end
                if _F.loweredHasAny(current.Name, CONFIG.WARNING_KEYWORDS) then
                    return object
                end
                current = current.Parent
            end
        end
        if (object:IsA("Model") or object:IsA("Folder"))
            and _F.loweredHasAny(object.Name, CONFIG.WARNING_KEYWORDS) then
            return object:FindFirstChildWhichIsA("BasePart", true)
        end
        return nil
    end

    function _F.registerWarning(object)
        local part = _F.warningPart(object)
        if not part then return end
        if warningParts[part] then return end
        warningParts[part] = true
        local radius = math.max(part.Size.X, part.Size.Z) / 2
        if radius < 2 then radius = CONFIG.WARNING_DEFAULT_RADIUS end
        radius = math.min(radius, CONFIG.WARNING_RADIUS_MAX)
        _F.addHazard("telegraphe " .. object.Name, part.Position, radius,
            CONFIG.WARNING_LIFETIME, "effect", part)
        _F.say("TELEGRAPHE : %s pos=%s taille=%s rayon prudent=%.0f",
            object:GetFullName(), _F.describe(part.Position, 1), _F.describe(part.Size, 1), radius)
    end

    function _F.observeEffect(object)
        if not running then return end
        local warningRelated = _F.loweredHasAny(object.Name, CONFIG.WARNING_KEYWORDS)
        if not warningRelated and object:IsA("BasePart") then
            local current = object.Parent
            for _ = 1, 5 do
                if not current then break end
                if _F.loweredHasAny(current.Name, CONFIG.WARNING_KEYWORDS) then
                    warningRelated = true
                    break
                end
                current = current.Parent
            end
        end
        if warningRelated then
            task.defer(_F.registerWarning, object)
        end
        if object.Name == CONFIG.SHOT_EFFECT and mouseHeld then
            lastShotEffect = os.clock()
            if not shotSeenThisHold then
                shotSeenThisHold = true
                _F.say("effet de tir observe pendant le maintien du minigun")
            end
            if activeCrystal and crystals[activeCrystal] then
                local info = crystals[activeCrystal]
                info.shotEffects += 1
                if not info.firstShotAt then
                    info.firstShotAt = os.clock()
                    _F.say("OBJECTIF #%d : premier tir confirme %.3f s apres spawn",
                        info.id, info.firstShotAt - info.spawnedAt)
                end
                local impact = _F.pivotOf(object)
                local targetPos = _F.aimPosition()
                if info.shotEffects <= 3 or info.shotEffects % 5 == 0 then
                    _F.say("OBJECTIF #%d IMPACT #%d : pos=%s ecart_cible=%s", info.id,
                        info.shotEffects, impact and _F.describe(impact, 1) or "?",
                        impact and targetPos
                            and string.format("%.1f", (impact - targetPos).Magnitude) or "?")
                end
            end
        end
    end

    function _F.hookEffects()
        local effects = workspace:FindFirstChild("Effects")
            or workspace:WaitForChild("Effects", 15)
        if not effects then
            _F.say("(!) workspace.Effects absent : telegraphes non observes")
            return
        end
        _F.connect(effects.DescendantAdded, _F.observeEffect)
        _F.say("workspace.Effects branche uniquement pour les nouveaux tirs/telegraphes")
    end

    function _F.hookAbilities()
        local ok, remote = pcall(function()
            return ReplicatedStorage:WaitForChild("ReplicatedStorage", 15)
                :WaitForChild("Packages", 10):WaitForChild("Knit", 10)
                :WaitForChild("Services", 10):WaitForChild("AttackService", 10)
                :WaitForChild("RE", 10):WaitForChild("AbilityFired", 10)
        end)
        if not ok or not remote then
            _F.say("(!) AbilityFired introuvable : telegraphes visuels seulement")
            return
        end

        _F.connect(remote.OnClientEvent, function(data)
            if not running or typeof(data) ~= "table" then return end
            local model = data.Model
            local fromBoss = model ~= nil and (model == boss
                or (typeof(model) == "Instance"
                    and string.find(string.lower(model.Name), CONFIG.BOSS_NAME, 1, true)))
            if not fromBoss then return end

            local name = data.AbilityName
            if typeof(name) == "Instance" then name = name.Name end
            name = tostring(name)
            local loweredName = string.lower(name)
            local isChronoShockwave = loweredName == "chronoshockwave"
            local isTimeline = loweredName == "timelinedestruction"
            local isTemporalTear = loweredName == "temporaltear"
            local isFlashForward = loweredName == "flashforward"
            local damage = tonumber(data.Damage) or 0
            local impact, lifetime, impactKey = _F.impactPoint(data)
            local origin = data.ModelPosition
            if typeof(origin) ~= "Vector3" then origin = _F.pivotOf(model) end
            local impactDistance = root and impact and _F.flatDistance(root.Position, impact) or nil
            local originDistance = root and origin and _F.flatDistance(root.Position, origin) or nil
            local abilityAt = os.clock()

            if heroicState.mode and (isTemporalTear or isFlashForward) then
                local hold = isTemporalTear and CONFIG.HEROIC_TEMPORAL_HOLD
                    or CONFIG.HEROIC_FLASH_HOLD
                heroicState.targetedUntil = math.max(
                    heroicState.targetedUntil, abilityAt + hold)
                heroicState.targetedLabel = name
                cachedDodgeGoal = nil
                cachedDodgeGoalUntil = 0
                _F.say("MOUVEMENT HEROIC CONTINU : %s, tangente maintenue %.2f s",
                    name, hold)
            end

            abilityCounts[name] = (abilityCounts[name] or 0) + 1
            recentAbilities[#recentAbilities + 1] = {
                at = abilityAt, name = name, damage = damage, impact = impact,
            }
            if #recentAbilities > 30 then table.remove(recentAbilities, 1) end

            _F.say("CAPACITE #%d %s : degats annonces=%.0f distLanceur=%s impact=%s via=%s",
                abilityCounts[name], name, damage,
                originDistance and string.format("%.0f", originDistance) or "?",
                impactDistance and string.format("%.0f", impactDistance) or "-",
                impactKey or "-")
            if isTimeline
                and typeof(origin) == "Vector3" and typeof(impact) == "Vector3" then
                timelineCasts[#timelineCasts + 1] = {
                    id = abilityCounts[name], at = abilityAt,
                    origin = origin, target = impact,
                }
                if #timelineCasts > 12 then table.remove(timelineCasts, 1) end
                _F.say("SONDE TIMELINE #%d : origine=%s cible=%s joueur=%s"
                        .. " charge=%s projectileX=%s linger=%s intervalle=%s",
                    abilityCounts[name], _F.describe(origin, 1), _F.describe(impact, 1),
                    root and _F.describe(root.Position, 1) or "?",
                    tostring(data.ChargeUp), tostring(data.ProjectileSpeedMultiplier),
                    tostring(data.LingerDuration), tostring(data.HitInterval))
            end

            if CONFIG.LOG_ABILITY_PAYLOAD and abilityCounts[name] == 1 then
                local payload = _F.describe(data, 4)
                if #payload > 2400 then payload = payload:sub(1, 2400) .. "..." end
                _F.say("PAYLOAD COMPLET %s = %s", name, payload)
            end

            if isChronoShockwave then

                local chargeUp = tonumber(data.ChargeUp) or 3
                local radius = tonumber(data.WarningRadius) or 140
                local centreOfBlast = typeof(origin) == "Vector3" and origin
                    or _F.pivotOf(model)
                if centreOfBlast then
                    _F.addHazard(name, centreOfBlast, radius,
                        chargeUp + CONFIG.SHOCKWAVE_LINGER, "shockwave", nil)
                end
                task.delay(chargeUp, function()
                    if not running then return end
                    local at = _F.bossPosition() or centreOfBlast
                    if at then
                        _F.addHazard(name, at, radius, CONFIG.SHOCKWAVE_LINGER,
                            "shockwave", nil)
                    end
                end)
                _F.say("ONDE CHRONOSHOCKWAVE : rayon %.0f, detonation dans %.2f s,"
                        .. " puis salve de %.2f s a 0.515 s par tick -- ESQUIVEE",
                    radius, chargeUp, CONFIG.SHOCKWAVE_LINGER)
            elseif typeof(data.RainPositions) == "table" and damage > 0 then

                local drops = 0
                for index = 1, CONFIG.RAIN_MAX_DROPS do
                    local point = data.RainPositions[index]
                    if typeof(point) == "Vector3" then
                        drops += 1

                        local armAt = math.max(0,
                            CONFIG.RAIN_DROP_INTERVAL * (index - 1)
                                - CONFIG.RAIN_DROP_LEAD)
                        task.delay(armAt, function()
                            if not running then return end
                            _F.addHazard(name, point, CONFIG.RAIN_DROP_RADIUS,
                                CONFIG.RAIN_DROP_WINDOW, "rain", nil)
                        end)
                    end
                end
                if drops > 0 then
                    _F.say("PLUIE %s : %d gouttes programmees, rayon %d chacune,"
                            .. " une toutes les %.2f s soit %.1f s de pluie"
                            .. " (DelayBetween serveur=%s ignore, mesure fausse)",
                        name, drops, CONFIG.RAIN_DROP_RADIUS,
                        CONFIG.RAIN_DROP_INTERVAL,
                        CONFIG.RAIN_DROP_INTERVAL * (drops - 1),
                        tostring(data.DelayBetween))
                elseif impact then
                    local radius, radiusSource = _F.payloadRadius(data, name)
                    _F.addHazard(name, impact, radius, lifetime, "ability", nil)
                    _F.say("ZONE CAPACITE %s : rayon=%.0f (%s), duree=%.2f s, pos=%s",
                        name, radius, radiusSource, lifetime, _F.describe(impact, 1))
                end
            elseif damage > 0 and impact then
                local radius, radiusSource = _F.payloadRadius(data, name)
                local profile = _F.abilityProfile(name)
                if profile and profile.lifetime then lifetime = profile.lifetime end
                if isTimeline then

                    if radius < CONFIG.TIMELINE_CORRIDOR_RADIUS then
                        radius = CONFIG.TIMELINE_CORRIDOR_RADIUS
                        radiusSource = radiusSource .. " + plancher v0.26"
                    end
                    local linger = tonumber(data.LingerDuration) or 0
                    local dodgeHold = math.max(CONFIG.TIMELINE_DODGE_HOLD,
                        linger + CONFIG.TIMELINE_LINGER_MARGIN)
                    lifetime = math.max(lifetime, dodgeHold,
                        CONFIG.CORRIDOR_LIFETIME)
                    cachedDodgeGoal = nil
                    cachedDodgeGoalUntil = 0
                    _F.addHazard(name, impact, radius, lifetime,
                        "timeline-corridor", nil, origin)

                    local lockUntil = abilityAt + dodgeHold
                    timelineDodgeUntil = math.max(timelineDodgeUntil, lockUntil)
                    activeDodgeUntil = math.max(activeDodgeUntil,
                        timelineDodgeUntil)
                    _F.say("COULOIR TIMELINE #%d : rayon=%.0f (%s), duree=%.2f s"
                            .. ", verrou=%.2f s, origine=%s, cible=%s",
                        abilityCounts[name], radius, radiusSource, lifetime,
                        lockUntil - abilityAt, _F.describe(origin, 1), _F.describe(impact, 1))
                elseif isFlashForward and typeof(origin) == "Vector3" then

                    lifetime = math.max(lifetime, CONFIG.CORRIDOR_LIFETIME)
                    _F.addHazard(name, impact, radius, lifetime,
                        "flash-corridor", nil, origin)
                    _F.say("COULOIR CAPACITE %s : rayon=%.0f (%s), duree=%.2f s"
                            .. ", origine=%s, cible=%s",
                        name, radius, radiusSource, lifetime,
                        _F.describe(origin, 1), _F.describe(impact, 1))
                else
                    _F.addHazard(name, impact, radius, lifetime, "ability", nil)
                    _F.say("ZONE CAPACITE %s : rayon=%.0f (%s), duree=%.2f s, pos=%s",
                        name, radius, radiusSource, lifetime, _F.describe(impact, 1))
                end
            elseif damage >= humanoid.MaxHealth * CONFIG.TARGETED_BURST_RATIO
                and (data.Target == character or data.Target == player) then
                targetedBurstUntil = math.max(targetedBurstUntil,
                    os.clock() + CONFIG.TARGETED_BURST_SECONDS)
                orbitAngle += math.pi * 0.70
                _F.say("ESQUIVE REFLEXE : %s cible le joueur sans point d'impact", name)
            end
        end)
        _F.say("AbilityFired branche pour Kronax")
    end

    function _F.guiObjectActuallyVisible(object)
        if not object.Visible or object.TextTransparency >= 0.98 then return false end
        local current = object.Parent
        while current and current ~= player do
            if current:IsA("GuiObject") and not current.Visible then return false end
            if current:IsA("CanvasGroup") and current.GroupTransparency >= 0.98 then
                return false
            end
            current = current.Parent
        end
        return true
    end

    function _F.interestingMessage(label)
        if not label:IsA("TextLabel") and not label:IsA("TextButton") then return false end
        local text = label.Text
        if text == "" then return false end
        if label:FindFirstAncestor("MessagesUI") then return true end
        return _F.loweredHasAny(text, {"kronax", "crystal", "cristal", "destroy", "break", "second", "time"})
    end

    function _F.scanMessages()
        local playerGui = player:FindFirstChild("PlayerGui")
        if not playerGui then return end
        local now = os.clock()
        for _, label in ipairs(playerGui:GetDescendants()) do
            if (not ui or not label:IsDescendantOf(ui))
                and _F.interestingMessage(label) and _F.guiObjectActuallyVisible(label) then
                local text = string.gsub(label.Text, "[%s\r\n]+", " ")
                local state = messageState[label]
                if not state or state.text ~= text then
                    if not state or now - state.at >= 0.75
                        or _F.loweredHasAny(text, CONFIG.CRYSTAL_KEYWORDS) then
                        _F.say("MESSAGE UI : %s", text)
                        messageState[label] = {text = text, at = now}
                    end
                end
            end
        end
    end

    function _F.nearestHazard(position, heroicFlow)
        local now = os.clock()
        local nearest = nil
        local nearestEdge = math.huge
        for index = #hazards, 1, -1 do
            local hazard = hazards[index]
            if hazard.part and hazard.part.Parent then hazard.pos = hazard.part.Position end
            if hazard.expires <= now or (hazard.part and not hazard.part.Parent) then
                table.remove(hazards, index)
            elseif not _F.ignoreForHeroicFlow(hazard, heroicFlow) then
                local edge = _F.hazardEdge(position, hazard)
                if edge < nearestEdge then nearest, nearestEdge = hazard, edge end
            end
        end
        return nearest, nearestEdge
    end

    function _F.pointSafe(point, heroicFlow)
        for _, hazard in ipairs(hazards) do
            if not _F.ignoreForHeroicFlow(hazard, heroicFlow) then
                local threshold = hazard.radius + CONFIG.HAZARD_ESCAPE_MARGIN
                if _F.hazardDistance(point, hazard) < threshold then return false end
            end
        end
        return true
    end

    function _F.cylinderPoint(point, heroic, shrink)
        if not crystalRoomCenter then return point end
        local limit = CONFIG.MOVEMENT_ARENA_RADIUS - CONFIG.MOVEMENT_ARENA_INSET
        if heroic then limit = limit - CONFIG.HEROIC_ARENA_EDGE_MARGIN end
        limit = math.max(0, limit - (shrink or 0))
        local dx = point.X - crystalRoomCenter.X
        local dz = point.Z - crystalRoomCenter.Z
        local distance = math.sqrt(dx * dx + dz * dz)
        if distance <= limit then return point end
        local scale = limit * CONFIG.MOVEMENT_ARENA_SOFT / math.max(distance, 0.001)
        return Vector3.new(crystalRoomCenter.X + dx * scale, point.Y,
            crystalRoomCenter.Z + dz * scale)
    end

    function _F.clampToMovementArena(point)
        return _F.cylinderPoint(point, false)
    end

    function heroicState.clampArena(point)
        return _F.cylinderPoint(point, true)
    end

    function _F.insideMovementArena(point)
        if not crystalRoomCenter then return true end
        return _F.flatDistance(point, crystalRoomCenter)
            <= CONFIG.MOVEMENT_ARENA_RADIUS - CONFIG.MOVEMENT_ARENA_INSET + 0.01
    end

    function _F.movementPathSafe(from, destination, heroicFlow)
        for _, hazard in ipairs(hazards) do
            if _F.ignoreForHeroicFlow(hazard, heroicFlow) then continue end
            local threshold = hazard.radius + CONFIG.HAZARD_ESCAPE_MARGIN
            local startDistance = _F.hazardDistance(from, hazard)
            local endDistance = _F.hazardDistance(destination, hazard)
            if endDistance < threshold then return false end

            if startDistance < threshold then
                local early = from + (destination - from) * 0.15
                if endDistance <= startDistance
                    or _F.hazardDistance(early, hazard) + 0.5 < startDistance then
                    return false
                end
            else
                local crossing
                if hazard.spatial then

                    crossing = math.huge
                    local span = (destination - from).Magnitude
                    local steps = math.clamp(math.ceil(span / 18), 3, 18)
                    for step = 0, steps do
                        local point = from + (destination - from) * (step / steps)
                        crossing = math.min(crossing, _F.hazardDistance(point, hazard))
                    end
                elseif hazard.segmentStart then
                    crossing = _F.flatSegmentsDistance(from, destination,
                        hazard.segmentStart, hazard.pos)
                else
                    crossing = _F.flatSegmentDistance(hazard.pos, from, destination)
                end
                if crossing < threshold then return false end
            end
        end
        return true
    end

    function _F.miniApproachGoal(aim)
        local best = nil
        local bestBlocked = nil
        local height = CONFIG.MINI_APPROACH_HEIGHT
        local distance = CONFIG.MINI_APPROACH_DISTANCE

        for step = 0, 7 do
            local angle = (math.pi * 2 / 8) * step
            local point = _F.clampToMovementArena(aim + Vector3.new(
                math.cos(angle) * distance, height, math.sin(angle) * distance))
            local blocked = _F.checkSight(point, aim) ~= nil
            if not blocked and _F.pointSafe(point) then return point, "cote degage" end
            if not blocked and not best then best = point end
            if not bestBlocked then bestBlocked = point end
        end

        local above = _F.clampToMovementArena(aim + Vector3.new(0, distance, 0))
        if _F.checkSight(above, aim) == nil and _F.pointSafe(above) then
            return above, "au-dessus"
        end
        if best then return best, "cote degage (dans un danger)" end

        return _F.clampToMovementArena(aim
            + Vector3.new(0, CONFIG.MINI_CONTACT_HEIGHT, 0)), "au contact"
    end

    function _F.baseOrbitGoal(centre, radius, height, angle)
        return centre + Vector3.new(math.cos(angle) * radius, height,
            math.sin(angle) * radius)
    end

    function heroicState.updateOrbit(centre, delta)
        if not crystalRoomCenter then
            heroicState.anchorBlend = 1
            heroicState.anchor = centre
            heroicState.radiusX = CONFIG.ORBIT_RADIUS
            heroicState.radiusZ = CONFIG.ORBIT_RADIUS
            return
        end

        local departure = bossInitialPosition
            and _F.flatDistance(centre, bossInitialPosition)
            or CONFIG.HEROIC_DEPARTURE_BLEND_END
        local targetBlend = math.clamp(
            (departure - CONFIG.HEROIC_DEPARTURE_BLEND_START)
                / math.max(1, CONFIG.HEROIC_DEPARTURE_BLEND_END
                    - CONFIG.HEROIC_DEPARTURE_BLEND_START),
            0, 1)
        local response = 1 - math.exp(-CONFIG.HEROIC_ANCHOR_RESPONSE * delta)
        heroicState.anchorBlend += (targetBlend - heroicState.anchorBlend) * response
        local blend = heroicState.anchorBlend
        heroicState.radiusX = CONFIG.HEROIC_THRONE_RADIUS_X
            + (CONFIG.ORBIT_RADIUS - CONFIG.HEROIC_THRONE_RADIUS_X) * blend
        heroicState.radiusZ = CONFIG.HEROIC_THRONE_RADIUS_Z
            + (CONFIG.ORBIT_RADIUS - CONFIG.HEROIC_THRONE_RADIUS_Z) * blend

        local rawX = crystalRoomCenter.X + (centre.X - crystalRoomCenter.X) * blend
        local rawZ = crystalRoomCenter.Z + (centre.Z - crystalRoomCenter.Z) * blend

        local anchor = _F.cylinderPoint(Vector3.new(rawX, centre.Y, rawZ), true,
            math.max(heroicState.radiusX, heroicState.radiusZ))
        heroicState.anchor = Vector3.new(anchor.X, centre.Y, anchor.Z)
    end

    function heroicState.orbitPoint(angle, worldY, scale)
        local anchor = heroicState.anchor
        if not anchor then return nil end
        local radiusScale = scale or 1
        return Vector3.new(
            anchor.X + math.cos(angle) * heroicState.radiusX * radiusScale,
            worldY,
            anchor.Z + math.sin(angle) * heroicState.radiusZ * radiusScale)
    end

    function _F.safeOrbitGoal(centre, preferred, aim, keepMoving, heroicFlow)
        local now = os.clock()
        if cachedDodgeGoal and now < cachedDodgeGoalUntil
            and (not keepMoving
                or (not root or (cachedDodgeGoal - root.Position).Magnitude > 10))
            and _F.insideMovementArena(cachedDodgeGoal)
            and _F.pointSafe(cachedDodgeGoal, heroicFlow)
            and (not root
                or _F.movementPathSafe(root.Position, cachedDodgeGoal, heroicFlow)) then
            return cachedDodgeGoal
        end

        local radii = {30, CONFIG.ORBIT_RADIUS,
            CONFIG.ORBIT_RADIUS + CONFIG.DODGE_RADIUS_EXTRA, 110}
        local largeFlatHazard = false
        for _, hazard in ipairs(hazards) do
            if not _F.ignoreForHeroicFlow(hazard, heroicFlow) then
                local effectiveRadius = hazard.radius + CONFIG.HAZARD_ESCAPE_MARGIN
                if effectiveRadius
                    > CONFIG.ORBIT_RADIUS + CONFIG.DODGE_RADIUS_EXTRA then
                    if not hazard.spatial then largeFlatHazard = true end
                    local centreGap = _F.hazardDistance(centre, hazard)
                    local needed = effectiveRadius - centreGap + 8
                    radii[#radii + 1] = math.clamp(needed,
                        CONFIG.ORBIT_RADIUS + CONFIG.DODGE_RADIUS_EXTRA,
                        CONFIG.DODGE_RADIUS_MAX)
                end
            end
        end
        if largeFlatHazard then radii[#radii + 1] = CONFIG.DODGE_RADIUS_MAX end
        local floor = _F.arenaFloorY()
        local dodgeAltitudes = heroicFlow and CONFIG.HEROIC_DODGE_ALTITUDES
            or CONFIG.DODGE_ALTITUDES
        local localRadii = heroicFlow and CONFIG.HEROIC_DODGE_LOCAL_RADII
            or CONFIG.DODGE_LOCAL_RADII
        local localDirections = heroicFlow and CONFIG.HEROIC_DODGE_LOCAL_DIRECTIONS
            or CONFIG.DODGE_LOCAL_DIRECTIONS
        local dodgeYs = {}
        for _, altitude in ipairs(dodgeAltitudes) do

            dodgeYs[#dodgeYs + 1] = floor and (floor + altitude)
                or (centre.Y + altitude)
        end
        local candidates = {}

        local function addCandidate(point)
            local bounded = heroicFlow and heroicState.clampArena(point)
                or _F.clampToMovementArena(point)
            if (bounded - point).Magnitude > 0.01 then return end
            candidates[#candidates + 1] = bounded
        end
        addCandidate(preferred)
        if crystalRoomCenter then
            for _, worldY in ipairs(dodgeYs) do
                addCandidate(Vector3.new(crystalRoomCenter.X,
                    worldY, crystalRoomCenter.Z))
            end
        end
        for step = 0, CONFIG.DODGE_CANDIDATE_COUNT - 1 do
            local radius = radii[step % #radii + 1]
            local worldY = dodgeYs[math.floor(step / #radii) % #dodgeYs + 1]
            local angle = orbitAngle
                + step * math.pi * 2 / CONFIG.DODGE_CANDIDATE_COUNT
            local point = _F.baseOrbitGoal(centre, radius, 0, angle)
            addCandidate(Vector3.new(point.X, worldY, point.Z))
        end

        if root then
            for step = 0, localDirections - 1 do
                local angle = orbitAngle
                    + step * math.pi * 2 / localDirections
                for _, radius in ipairs(localRadii) do
                    for _, worldY in ipairs(dodgeYs) do
                        addCandidate(Vector3.new(
                            root.Position.X + math.cos(angle) * radius,
                            worldY,
                            root.Position.Z + math.sin(angle) * radius))
                    end
                end
            end
        end

        if largeFlatHazard then
            if crystalRoomCenter then

                local rim = CONFIG.MOVEMENT_ARENA_RADIUS
                    - CONFIG.MOVEMENT_ARENA_INSET
                local sampleCount = math.max(4,
                    CONFIG.MOVEMENT_ARENA_EDGE_SAMPLES * 2)
                for step = 0, sampleCount - 1 do
                    local angle = math.pi * 2 * step / sampleCount
                    local worldY = dodgeYs[step % #dodgeYs + 1]
                    addCandidate(Vector3.new(
                        crystalRoomCenter.X + math.cos(angle) * rim,
                        worldY,
                        crystalRoomCenter.Z + math.sin(angle) * rim))
                end
            else

                for step = 0, CONFIG.DODGE_CANDIDATE_COUNT - 1 do
                    local angle = orbitAngle
                        + step * math.pi * 2 / CONFIG.DODGE_CANDIDATE_COUNT
                    local worldY = dodgeYs[step % #dodgeYs + 1]
                    local point = _F.baseOrbitGoal(centre,
                        CONFIG.DODGE_RADIUS_MAX, 0, angle)
                    addCandidate(Vector3.new(point.X, worldY, point.Z))
                end
            end
        end

        local ranked = {}
        local improving = {}
        local fallback = {}
        local function clearanceAt(point)
            local clearance = math.huge
            for _, hazard in ipairs(hazards) do
                if not _F.ignoreForHeroicFlow(hazard, heroicFlow) then
                    clearance = math.min(clearance, _F.hazardEdge(point, hazard))
                end
            end
            return clearance == math.huge and 100 or clearance
        end
        local currentClearance = root and clearanceAt(root.Position) or 100
        for _, point in ipairs(candidates) do
            local clearance = clearanceAt(point)
            local travel = root and (point - root.Position).Magnitude or 0
            fallback[#fallback + 1] = {
                point = point, clearance = clearance, travel = travel,
            }
            if _F.insideMovementArena(point) and _F.pointSafe(point, heroicFlow)
                and (not root
                    or _F.movementPathSafe(root.Position, point, heroicFlow)) then

                local score = math.min(clearance,
                    CONFIG.DODGE_CLEARANCE_SCORE_CAP) * 0.35
                    - travel * CONFIG.DODGE_TRAVEL_SCORE_WEIGHT
                ranked[#ranked + 1] = {point = point, score = score}
            elseif _F.insideMovementArena(point) and root
                and clearance > currentClearance + 1 then
                local early = root.Position + (point - root.Position) * 0.15
                if clearanceAt(early) + 0.5 >= currentClearance then
                    improving[#improving + 1] = {
                        point = point,
                        score = clearance * 2 - travel * 0.05,
                    }
                end
            end
        end
        table.sort(ranked, function(a, b) return a.score > b.score end)
        table.sort(improving, function(a, b) return a.score > b.score end)
        table.sort(fallback, function(a, b)
            if a.clearance == b.clearance then return a.travel < b.travel end
            return a.clearance > b.clearance
        end)

        local best = nil
        for index = 1, math.min(3, #ranked) do
            local point = ranked[index].point
            if not aim or _F.checkSight(point, aim) == nil then
                best = point
                break
            end
        end

        if not best and ranked[1] then best = ranked[1].point end

        local rootInArena = root and _F.insideMovementArena(root.Position) or false
        local rootIsSafe = rootInArena
            and _F.pointSafe(root.Position, heroicFlow) or false
        if not best and rootIsSafe and not keepMoving then best = root.Position end
        if not best and improving[1] then best = improving[1].point end
        if not best and fallback[1]
            and fallback[1].clearance > currentClearance then
            best = fallback[1].point
        end

        if not best and not rootInArena and fallback[1] then
            best = fallback[1].point
        end
        if not best and keepMoving and _F.pointSafe(preferred, heroicFlow)
            and (not root
                or _F.movementPathSafe(root.Position, preferred, heroicFlow)) then
            best = preferred
        end

        if not best and keepMoving and rootIsSafe and root then
            local phase = heroicFlow and heroicState.motionPhase or orbitAngle
            local tangent = heroicFlow and heroicState.clampArena(Vector3.new(
                root.Position.X - math.sin(phase) * 18,
                preferred.Y,
                root.Position.Z + math.cos(phase) * 18))
                or _F.clampToMovementArena(Vector3.new(
                    root.Position.X - math.sin(phase) * 18,
                    preferred.Y,
                    root.Position.Z + math.cos(phase) * 18))
            if _F.pointSafe(tangent, heroicFlow)
                and _F.movementPathSafe(root.Position, tangent, heroicFlow) then
                best = tangent
            end
        end
        if not best and root then best = root.Position end
        cachedDodgeGoal = best
        cachedDodgeGoalUntil = now + (keepMoving and 0.08
            or CONFIG.DODGE_REPLAN_INTERVAL)
        return best
    end

    function _F.enforceMinimumHorizontalDistance(goal, centre)
        local offset = (goal - centre) * Vector3.new(1, 0, 1)
        if offset.Magnitude >= CONFIG.MIN_HORIZONTAL_DISTANCE then return goal end
        local fallbackAngle = heroicState.mode and heroicState.motionPhase or orbitAngle
        local direction = offset.Magnitude > 1 and offset.Unit
            or Vector3.new(math.cos(fallbackAngle), 0, math.sin(fallbackAngle))
        return Vector3.new(
            centre.X + direction.X * CONFIG.MIN_HORIZONTAL_DISTANCE,
            goal.Y,
            centre.Z + direction.Z * CONFIG.MIN_HORIZONTAL_DISTANCE)
    end

    function heroicState.sightGoal(preferred, aim)
        if not root or not sightBlocker or not heroicState.anchor then return preferred end
        local now = os.clock()
        if heroicState.losGoal and now < heroicState.losGoalUntil then
            return heroicState.losGoal
        end
        local worldY = preferred.Y
        local floor = _F.arenaFloorY()
        if floor then
            worldY = math.max(worldY, floor + math.min(
                CONFIG.HEROIC_DODGE_ALTITUDES[#CONFIG.HEROIC_DODGE_ALTITUDES],
                holdHeight + 12))
        end
        for step = 0, 5 do
            local candidate = step == 0
                and Vector3.new(preferred.X, worldY, preferred.Z)
                or heroicState.orbitPoint(heroicState.motionPhase + step * 0.32, worldY)
            if candidate then
                candidate = heroicState.clampArena(
                    _F.enforceMinimumHorizontalDistance(candidate, _F.bossPosition() or aim))
                if _F.checkSight(candidate, aim) == nil and _F.pointSafe(candidate, true)
                    and _F.movementPathSafe(root.Position, candidate, true) then
                    heroicState.losGoal = candidate
                    heroicState.losGoalUntil = now + 0.12
                    return candidate
                end
            end
        end
        heroicState.losGoal = nil
        heroicState.losGoalUntil = 0
        return preferred
    end

    function _F.bindCharacterSignals()
        _F.disconnectList(characterConnections)
        local lastHealth = humanoid.Health
        _F.connect(humanoid.HealthChanged, function(health)
            if not running then return end
            if health < lastHealth then
                minigun.interrupt("degats recus")
                local lost = lastHealth - health
                local rounded = tostring(math.floor(lost + 0.5))
                damageBuckets[rounded] = (damageBuckets[rounded] or 0) + 1
                local centre = _F.bossPosition()
                local hazard, edge = nil, nil
                if root then hazard, edge = _F.nearestHazard(root.Position) end
                local floor = _F.arenaFloorY()
                local altitude = floor and root and (root.Position.Y - floor) or nil
                local overCeiling = altitude ~= nil
                    and altitude > CONFIG.ALTITUDE_LIMIT - CONFIG.ALTITUDE_MARGIN
                _F.say("DEGATS JOUEUR : -%.0f, reste %.0f/%.0f, distBoss=%s, altSol=%s%s%s%s",
                    lost, health, humanoid.MaxHealth,
                    centre and string.format("%.0f", (root.Position - centre).Magnitude) or "?",
                    altitude and string.format("%.0f", altitude) or "?",
                    overCeiling and " (!) AU-DESSUS DU PLAFOND" or "",
                    hazard and string.format(", danger=%s bord=%+.0f", hazard.label, edge) or "",
                    _F.recentAbilityText())

                if root then
                    local rows = {}
                    for _, zone in ipairs(hazards) do
                        local zoneEdge = _F.hazardEdge(root.Position, zone)
                        rows[#rows + 1] = {
                            edge = zoneEdge,
                            text = string.format("%s bord=%+.0f r=%.0f",
                                zone.label, zoneEdge, zone.radius),
                        }
                    end
                    table.sort(rows, function(a, b) return a.edge < b.edge end)
                    local shown = {}
                    for index = 1, math.min(6, #rows) do
                        shown[#shown + 1] = rows[index].text
                    end
                    _F.say("  ZONES ACTIVES AU COUP (%d) : %s", #rows,
                        #shown > 0 and table.concat(shown, " | ") or "aucune")
                    _F.say("  POSITION JOUEUR AU COUP : %s | Kronax : %s",
                        _F.describe(root.Position, 1),
                        centre and _F.describe(centre, 1) or "?")
                end
                local window = {}
                for index = #recentAbilities, 1, -1 do
                    local entry = recentAbilities[index]
                    local age = os.clock() - entry.at
                    if age > 2.5 then break end
                    window[#window + 1] = string.format("%s(+%.2fs)",
                        entry.name, age)
                end
                _F.say("  LANCERS 2.5 s AVANT LE COUP : %s",
                    #window > 0 and table.concat(window, " ") or "aucun")
                if root then
                    local damageAt = os.clock()
                    _F.recordMotionSample(damageAt, root.Position)
                    _F.logTimelineEvidence(damageAt, root.Position)
                end
            elseif health > lastHealth and humanoid.MaxHealth > 0
                and lastHealth <= humanoid.MaxHealth * 0.40 then

                local gained = health - lastHealth
                local meaningfulHeal = math.max(500, humanoid.MaxHealth * 0.02)
                if gained >= meaningfulHeal then
                    _F.say("SOIN IMPORTANT A BAS PV : +%.0f, %.0f -> %.0f/%.0f (Mender possible)",
                        gained, lastHealth, health, humanoid.MaxHealth)
                end
            end
            lastHealth = health
        end, characterConnections)

        _F.connect(humanoid.Died, function()
            _F.say("=== MORT DU JOUEUR ===")
            _F.releaseAttack()
            _F.writeLog(true)
        end, characterConnections)
    end

    local guiParent
    pcall(function() guiParent = gethui and gethui() or game:GetService("CoreGui") end)
    guiParent = guiParent or player:WaitForChild("PlayerGui")

    local oldUi = guiParent:FindFirstChild("KronaxTestUI")
    if oldUi then oldUi:Destroy() end

    ui = Instance.new("ScreenGui")
    ui.Name = "KronaxTestUI"
    ui.ResetOnSpawn = false
    ui.ZIndexBehavior = Enum.ZIndexBehavior.Global
    ui.Parent = guiParent

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 355, 0, 126)
    frame.Position = UDim2.new(0, 12, 0, 120)
    frame.BackgroundColor3 = Color3.fromRGB(10, 14, 24)
    frame.BackgroundTransparency = 0.14
    frame.ZIndex = 999999990
    frame.Parent = ui
    Instance.new("UICorner").Parent = frame

    local statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(1, -12, 0, 92)
    statusLabel.Position = UDim2.new(0, 6, 0, 4)
    statusLabel.BackgroundTransparency = 1
    statusLabel.TextColor3 = Color3.fromRGB(145, 220, 255)
    statusLabel.Font = Enum.Font.Code
    statusLabel.TextSize = 13
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.TextYAlignment = Enum.TextYAlignment.Top
    statusLabel.ZIndex = 999999991
    statusLabel.Parent = frame

    local stopButton = Instance.new("TextButton")
    stopButton.Size = UDim2.new(0, 170, 0, 25)
    stopButton.Position = UDim2.new(0, 6, 1, -29)
    stopButton.BackgroundColor3 = Color3.fromRGB(195, 48, 48)
    stopButton.TextColor3 = Color3.new(1, 1, 1)
    stopButton.Font = Enum.Font.SourceSansBold
    stopButton.TextSize = 15
    stopButton.Text = "ARRETER (B)"
    stopButton.ZIndex = 999999991
    stopButton.Parent = frame
    Instance.new("UICorner").Parent = stopButton

    function _F.summary()
        local abilityParts = {}
        for name, count in pairs(abilityCounts) do
            abilityParts[#abilityParts + 1] = name .. "=" .. count
        end
        table.sort(abilityParts)
        local damageParts = {}
        for amount, count in pairs(damageBuckets) do
            damageParts[#damageParts + 1] = "-" .. amount .. "x" .. count
        end
        table.sort(damageParts)
        local unresolved = math.max(0,
            crystalStats.seen - crystalStats.destroyed - crystalStats.missed)
        _F.say("RESUME OBJECTIFS : attaquables=%d detruits=%d disparus/non-confirmes=%d"
                .. " cristaux_sup10M_ignores=%d encore actifs=%d mini_detectes=%d",
            crystalStats.seen, crystalStats.destroyed, crystalStats.missed,
            crystalStats.ignored, unresolved, miniCrystalCount)
        _F.say("RESUME CAPACITES : %s", #abilityParts > 0 and table.concat(abilityParts, ", ") or "aucune")
        _F.say("RESUME DEGATS : %s", #damageParts > 0 and table.concat(damageParts, ", ") or "aucun")
    end

    function _F.stop(reason)
        if not running then return end
        running = false
        _F.releaseAttack()
        minigun.watchTool(nil)
        _F.disconnectList(characterConnections)
        _F.disconnectList(bossConnections)
        _F.disconnectList(crystalConnections)
        _F.disconnectList(connections)
        if partAdded then pcall(function() partAdded:Disconnect() end) end
        if partRemoved then pcall(function() partRemoved:Disconnect() end) end
        _F.restoreNoclip()
        _F.summary()
        _F.say("=== ARRET : %s ===", tostring(reason))
        _F.writeLog(true)
        if ui then ui:Destroy() end
        if _G.StopCurrentFarm == _F.stop then _G.StopCurrentFarm = nil end
    end

    _G.StopCurrentFarm = _F.stop
    _F.connect(stopButton.MouseButton1Click, function() _F.stop("bouton") end)
    _F.connect(UserInputService.InputBegan, function(input, processed)
        if not processed and input.KeyCode == Enum.KeyCode.B then _F.stop("touche B") end
    end)

    pcall(function()
        _F.connect(player.OnTeleport, function(state)
            if state == Enum.TeleportState.Started
                or state == Enum.TeleportState.InProgress then
                _F.stop("teleport")
            end
        end)
    end)

    _F.connect(player.CharacterAdded, function(newCharacter)
        if not running then return end
        _F.releaseAttack()
        _F.restoreNoclip()
        character = newCharacter
        humanoid = character:WaitForChild("Humanoid")
        root = character:WaitForChild("HumanoidRootPart")
        weaponName = nil
        equipping = false
        holdStartedAt = 0
        shotSeenThisHold = false
        lastShotEffect = 0
        cooldownUntil = 0
        minigun.watchTool(nil)
        minigun.burstUntil, minigun.restartAt = nil, nil
        minigun.nextEquip, minigun.nextArm = 0, 0
        minigun.missingSince, minigun.stunUntil = nil, 0
        minigun.stunMessages = setmetatable({}, {__mode = "k"})
        lastAttackTarget = nil
        activeDodgeLabel = nil
        activeDodgeUntil = 0
        targetedBurstUntil = 0
        timelineDodgeUntil = 0
        heroicState.targetedUntil = 0
        heroicState.targetedLabel = nil
        cachedDodgeGoal = nil
        cachedDodgeGoalUntil = 0
        _F.trackCharacterParts()
        _F.bindCharacterSignals()
        _F.say("RESPAWN -> re-equipement du minigun")
        task.delay(0.1, function() if running then _F.equipWeapon() end end)
    end)

    _F.trackCharacterParts()
    _F.bindCharacterSignals()

    task.wait(0.10)
    if running and humanoid.Health > 0 then
        local hSent = _F.tapKey(Enum.KeyCode.H, 0x48)
        _F.say("MINIGUN : H initial envoye une seule fois (%s)",
            hSent and "OK" or "ECHEC")
    end

    task.spawn(_F.hookEffects)
    task.spawn(_F.hookAbilities)
    task.spawn(_F.hookDynamicCrystals)

    task.spawn(function()

        local watchedFolder = nil
        while running do
            local mapContent = workspace:FindFirstChild("MapContent")
            local folder = mapContent and mapContent:FindFirstChild("RecursiveRelics")
            if folder and folder ~= watchedFolder then
                watchedFolder = folder
                local function watchChild(child, reason)
                    if child:IsA("Model") or child:IsA("BasePart") then
                        _F.watchDynamicCrystalRoot(child, reason)
                    end
                end
                for _, child in ipairs(folder:GetChildren()) do
                    watchChild(child, "present dans RecursiveRelics")
                end
                _F.connect(folder.ChildAdded, function(child)
                    watchChild(child, "ajout direct dans RecursiveRelics")
                end)
                _F.say("DOSSIER MINI CRISTAUX SURVEILLE : %s (%d enfant(s))",
                    folder:GetFullName(), #folder:GetChildren())
            end
            if folder then
                for _, child in ipairs(folder:GetChildren()) do
                    if child:IsA("Model") or child:IsA("BasePart") then

                        _F.queueDynamicCrystal(child, "controle direct RecursiveRelics")
                    end
                end
            end
            task.wait(CONFIG.RECURSIVE_RELIC_POLL_INTERVAL)
        end
    end)

    task.spawn(function()
        local noclipApplied = false
        while running do
            -- Le noclip ne s'applique qu'en engagement. Dans le lobby on restaure
            -- les collisions une seule fois pour laisser le joueur normal.
            if not _F.bossAlive() then
                if noclipApplied then
                    noclipApplied = false
                    pcall(_F.restoreNoclip)
                end
                task.wait(0.25)
            else
                noclipApplied = true
                if wallCollisionEnabled and os.clock() >= wallBumpUntil then
                    _F.setWallCollision(false)
                end
                if not wallCollisionEnabled then
                    for part in pairs(characterParts) do
                        if part.Parent and part.CanCollide then part.CanCollide = false end
                    end
                end
                task.wait(0.25)
            end
        end
    end)

    task.spawn(function()
        local crystalFolderReady = _F.scanCrystals()
        while running do
            if not crystalFolderReady then
                crystalFolderReady = _F.scanCrystals()
            end
            _F.refreshCrystalCandidates()
            task.wait(CONFIG.CANDIDATE_POLL_INTERVAL)
        end
    end)

    task.spawn(function()

        while running do
            _F.sweepArena()
            _F.dropStuckTarget()
            task.wait(CONFIG.ARENA_SWEEP_INTERVAL)
        end
    end)

    task.spawn(function()
        while running do
            _F.scanMessages()
            task.wait(CONFIG.MESSAGE_SCAN_INTERVAL)
        end
    end)

    task.spawn(function()
        while running do
            _F.writeLog(false)
            task.wait(CONFIG.LOG_WRITE_PERIOD)
        end
    end)

    function minigun.blocked(now)
        local blocked = root and root.Anchored or false
        for _, object in ipairs({character, humanoid}) do
            for _, name in ipairs({"Stunned", "Status_Stunned", "Status_Stun"}) do
                local value = object:FindFirstChild(name)
                if object:GetAttribute(name) == true
                    or (value and value:IsA("BoolValue") and value.Value) then
                    blocked = true
                end
            end
        end

        if now >= minigun.nextMessageScan then
            minigun.nextMessageScan = now + 0.25
            local gui = player:FindFirstChild("PlayerGui")
            local messages = gui and gui:FindFirstChild("MessagesUI")
            local frame = messages and messages:FindFirstChild("Frame")
            if frame then
                for _, label in ipairs(frame:GetDescendants()) do
                    if label:IsA("TextLabel") then
                        local rejected = _F.guiObjectActuallyVisible(label)
                            and label.Text:lower():find("cannot use move while stunned", 1, true) ~= nil
                        if rejected and not minigun.stunMessages[label] then
                            minigun.stunUntil = now + 0.5
                            minigun.interrupt("message stun")
                        end
                        minigun.stunMessages[label] = rejected
                    end
                end
            end
        end
        return blocked or now < minigun.stunUntil
    end

    function minigun.tick(now, desiredTarget, inCombat)
        if not running then return end
        if humanoid.Health <= 0 or not inCombat then
            _F.releaseAttack()
            minigun.burstUntil, minigun.restartAt = nil, nil
            return
        end

        -- GARDE DURE : jamais de tir sans Kronax a portee. Couvre le lobby,
        -- le chargement et tout etat ou le boss est hors de l'arene.
        local engage = _F.engageDistance()
        if engage == nil or engage > CONFIG.MAX_ENGAGE_DISTANCE then
            if mouseHeld then
                _F.say("MINIGUN : Kronax hors de portee (%s) -> relache",
                    engage and string.format("%.0f studs", engage) or "absent")
            end
            _F.releaseAttack()
            minigun.burstUntil, minigun.restartAt = nil, nil
            return
        end

        if minigun.burstUntil and now >= minigun.burstUntil then
            _F.releaseAttack()
            minigun.burstUntil, minigun.restartAt = nil, nil
            cooldownUntil = os.clock() + CONFIG.MINIGUN_REHOLD_DELAY
            local healed = _F.tapKey(Enum.KeyCode.C, 0x43)
            _F.say("MINIGUN : fin des 60 s -> pause 2 s, C soin %s", healed and "envoye" or "ECHEC")
            return
        end

        if minigun.blocked(now) then
            minigun.interrupt("stun/controle bloque")
            minigun.restartAt = math.max(minigun.restartAt or 0, now + CONFIG.MINIGUN_HIT_SETTLE)
            return
        end
        if now < cooldownUntil or now < (minigun.restartAt or 0) then return end

        local tool = _F.equippedTool()
        local name = tool and tool.Name:lower():gsub("[^%w]", "") or ""
        local ready = name:find("minigun", 1, true) ~= nil
        if not ready then
            minigun.missingSince = minigun.missingSince or now
            if now - minigun.missingSince < CONFIG.MINIGUN_VERIFY_GRACE then return end
            minigun.interrupt("minigun absent/non active")
            minigun.watchTool(nil)
            if not desiredTarget then return end
            _F.equipWeapon()
            return
        end
        minigun.missingSince = nil
        minigun.watchTool(tool)
        if not desiredTarget then return end

        -- Aucun degat pendant MINIGUN_NO_DAMAGE_RELEASE s alors qu'on tient le
        -- clic : on lache et on reprend, dans la MEME instance, comme au debut
        -- de la boucle (nouvelle rafale de 60 s).
        -- Le compteur de 3 s ne demarre qu'APRES le premier degat de la
        -- prise : le tir met du temps a se lancer, sinon on relachait avant
        -- meme d'avoir tire. Si aucun degat n'arrive du tout, on relache au
        -- bout de MINIGUN_FIRST_HIT_GRACE s.
        if mouseHeld then
            local hp = _F.quickHealth(desiredTarget)
            if hp == nil and desiredTarget.FindFirstAncestorOfClass then
                local model = desiredTarget:FindFirstAncestorOfClass("Model")
                hp = model and _F.quickHealth(model) or nil
            end
            if minigun.dmgTarget ~= desiredTarget then
                -- nouvelle cible : le clic tourne deja, on relance juste le chrono
                minigun.dmgTarget, minigun.dmgHealth = desiredTarget, hp
                minigun.lastDamageAt = now
            elseif hp then
                if minigun.dmgHealth and hp < minigun.dmgHealth - 0.5 then
                    minigun.lastDamageAt = now
                    if not minigun.dmgArmed then
                        minigun.dmgArmed = true
                        _F.say("MINIGUN : premiers degats %.1f s apres la prise",
                            now - holdStartedAt)
                    end
                end
                minigun.dmgHealth = hp
            end
            local limit = CONFIG.MINIGUN_NO_DAMAGE_RELEASE
            local why = nil
            if hp and minigun.dmgArmed and now - (minigun.lastDamageAt or now) > limit then
                why = string.format("aucun degat depuis %.0f s", limit)
            elseif hp and not minigun.dmgArmed
                and now - holdStartedAt > CONFIG.MINIGUN_FIRST_HIT_GRACE then
                why = string.format("aucun degat %.0f s apres la prise",
                    CONFIG.MINIGUN_FIRST_HIT_GRACE)
            end
            if why then
                minigun.noDamageReleases = (minigun.noDamageReleases or 0) + 1
                _F.releaseAttack()
                minigun.burstUntil = nil   -- nouvelle rafale de 60 s a la reprise
                minigun.restartAt = now + CONFIG.MINIGUN_HIT_SETTLE
                _F.say("MINIGUN : %s sur %s -> relache, nouvelle rafale de 60 s (#%d)",
                    why, desiredTarget.Name, minigun.noDamageReleases)
                return
            end
        end

        if mouseHeld then
            _F.holdAttack()
        elseif _F.holdAttack() then
            local resumed = minigun.burstUntil ~= nil
            minigun.burstUntil = minigun.burstUntil or (os.clock() + CONFIG.MINIGUN_BURST_DURATION)
            minigun.restartAt = nil
            reholdCount += 1
            holdStartedAt, lastShotEffect, shotSeenThisHold = os.clock(), os.clock(), false
            -- chaque prise repart sans degat constate : grace du premier tir
            minigun.dmgArmed = false
            minigun.dmgTarget = nil
            _F.say("MINIGUN HOLD #%d : %s, %.2f s restantes", reholdCount,
                resumed and "reprise" or "nouvelle rafale", minigun.burstUntil - os.clock())
        end
    end

    task.spawn(function()
        task.wait(0.05)
        while running do
            local inCombat = _F.bossAlive()
            local desiredTarget = inCombat and _F.combatTarget() or nil
            if desiredTarget ~= lastAttackTarget then
                lastAttackTarget = desiredTarget
                _F.say("CHANGEMENT CIBLE SANS RELACHER -> %s", desiredTarget
                    and desiredTarget:GetFullName() or "aucune cible")
            end
            minigun.tick(os.clock(), desiredTarget, inCombat)
            task.wait(0.08)
        end
    end)

    task.spawn(function()
        while running do
            if not _F.bossAlive() then
                local found = _F.findBoss()
                if found and found ~= boss then _F.watchBoss(found) end
            end
            _F.combatTarget()
            task.wait(0.75)
        end
    end)

    local movementAccumulator = 0
    local lastUiUpdate = 0
    _F.connect(RunService.RenderStepped, function(dt)
        if not running or not root or not root.Parent then return end
        -- Rien ne touche au personnage hors engagement : dans le lobby ou a plus
        -- de MAX_ENGAGE_DISTANCE studs de Kronax, on rend la main au joueur.
        if not _F.bossAlive() then
            movementAccumulator = 0
            return
        end
        movementAccumulator += math.min(dt, 0.1)
        if movementAccumulator < 1 / 60 then return end
        local delta = movementAccumulator
        movementAccumulator = 0
        root.AssemblyLinearVelocity = Vector3.zero

        local target = _F.combatTarget()
        local centre = _F.bossPosition()
        local aim = _F.aimPosition(target)
        if not centre or not aim then return end
        if target ~= activeTarget then
            activeTarget = target
            _F.say("VISEE -> %s", target and target:GetFullName() or "aucune")
        end

        local camera = workspace.CurrentCamera
        if camera then camera.CFrame = CFrame.new(camera.CFrame.Position, aim) end

        local now = os.clock()
        local miniInfo = activeCrystal and crystals[activeCrystal] or nil

        local miniTarget = miniInfo ~= nil and miniInfo.mini == true
            and target == activeCrystal
            and now - (miniInfo.acquiredAt or miniInfo.spawnedAt)
                >= CONFIG.MINI_TELEPORT_DELAY
        if now - lastSightCheck >= 0.18 then
            lastSightCheck = now
            sightBlocker = _F.checkSight(root.Position, aim)
            sightClear = sightBlocker == nil

            if miniTarget then
                holdHeight = CONFIG.HOLD_HEIGHT
            elseif sightBlocker and now - lastHeightChange >= 0.7 then
                lastHeightChange = now
                if holdHeight < CONFIG.HOLD_HEIGHT_MAX then
                    holdHeight = math.min(CONFIG.HOLD_HEIGHT_MAX,
                        holdHeight + CONFIG.HEIGHT_STEP)
                    _F.say("vue bouchee vers %s par %s -> hauteur %d",
                        activeCrystal and "OBJECTIF" or "KRONAX", sightBlocker.Name, holdHeight)
                end
            elseif sightClear and holdHeight > CONFIG.HOLD_HEIGHT then
                holdHeight = math.max(CONFIG.HOLD_HEIGHT, holdHeight - CONFIG.HEIGHT_STEP)
            end
        end

        orbitAngle += (CONFIG.ORBIT_LINEAR_SPEED / CONFIG.ORBIT_RADIUS) * delta
        local bossAtThrone = crystalRoomCenter and bossInitialPosition
            and _F.flatDistance(centre, bossInitialPosition) <= 22
        local nearThrone = bossAtThrone and now - bossSeenAt <= 4.0
        local preferred
        if heroicState.mode then
            local targetedMotion = now < heroicState.targetedUntil
            heroicState.updateOrbit(centre, delta)
            local pathSpeed = targetedMotion and CONFIG.HEROIC_TARGET_PATH_SPEED
                or CONFIG.HEROIC_PATH_SPEED
            local referenceRadius = (heroicState.radiusX + heroicState.radiusZ) / 2
            heroicState.motionPhase += pathSpeed / referenceRadius * delta

            if now >= (heroicState.travelKickAt or 0) then
                local windowStart = now - CONFIG.MIN_TRAVEL_WINDOW
                local reference = nil
                for index = #motionSamples, 1, -1 do
                    if motionSamples[index].at <= windowStart then
                        reference = motionSamples[index].pos
                        break
                    end
                end
                if reference and (root.Position - reference).Magnitude
                    < CONFIG.MIN_TRAVEL_DISTANCE then
                    heroicState.motionPhase += CONFIG.TRAVEL_KICK_ANGLE
                    heroicState.travelKickAt = now + CONFIG.TRAVEL_KICK_COOLDOWN
                    heroicState.travelKicks = (heroicState.travelKicks or 0) + 1
                end
            end
            local floor = _F.arenaFloorY()
            local altitude = CONFIG.HEROIC_ALTITUDE_BASE
                + CONFIG.HEROIC_ALTITUDE_AMPLITUDE
                    * math.sin(heroicState.motionPhase
                        * CONFIG.HEROIC_ALTITUDE_FREQUENCY)
            local worldY = floor and (floor + altitude)
                or (centre.Y + CONFIG.HOLD_HEIGHT)

            local ramp = math.clamp((now - bossSeenAt)
                / CONFIG.HEROIC_START_RAMP, 0.12, 1)
            preferred = heroicState.orbitPoint(heroicState.motionPhase, worldY, ramp)
            preferred = heroicState.clampArena(
                _F.enforceMinimumHorizontalDistance(preferred, centre))
            if heroicState.anchorBlend < 0.95 and not usingRoomCenter then
                usingRoomCenter = true
                _F.say("DEPART HEROIC MOBILE : ellipse centrale, transition progressive")
            elseif heroicState.anchorBlend >= 0.95 and usingRoomCenter then
                usingRoomCenter = false
                _F.say("Kronax avance -> ancre Heroic raccordee sans saut")
            end
        elseif nearThrone then
            preferred = Vector3.new(crystalRoomCenter.X,
                centre.Y + holdHeight, crystalRoomCenter.Z)
            if not usingRoomCenter then
                usingRoomCenter = true
                _F.say("DEPART AU CENTRE DE LA SALLE pendant que Kronax reste au trone")
            end
        else
            preferred = _F.baseOrbitGoal(centre, CONFIG.ORBIT_RADIUS,
                holdHeight, orbitAngle)
            preferred = _F.enforceMinimumHorizontalDistance(preferred, centre)
            if usingRoomCenter then
                usingRoomCenter = false
                _F.say("Kronax avance -> debut de l'orbite courte")
            end
            if sightBlocker and crystalRoomCenter then
                local middle = Vector3.new(crystalRoomCenter.X,
                    centre.Y + holdHeight, crystalRoomCenter.Z)
                if _F.pointSafe(middle) and _F.checkSight(middle, aim) == nil then
                    preferred = middle
                end
            end
        end

        if heroicState.mode and not miniTarget and sightBlocker then
            preferred = heroicState.sightGoal(preferred, aim)
        end

        local miniReason = nil
        if miniTarget then
            preferred, miniReason = _F.miniApproachGoal(aim)
        end

        local heroicFlow = heroicState.mode and not miniTarget
        preferred = heroicFlow and heroicState.clampArena(preferred)
            or _F.clampToMovementArena(preferred)
        local miniDestinationSafe = miniTarget and _F.pointSafe(preferred) or false

        local nearest, edge = _F.nearestHazard(root.Position, heroicFlow)
        local enteredDanger = nearest and edge <= CONFIG.HAZARD_TRIGGER_MARGIN
        if enteredDanger then
            activeDodgeUntil = math.max(activeDodgeUntil,
                now + CONFIG.DODGE_MIN_HOLD)
        elseif activeDodgeLabel and nearest and edge <= CONFIG.DODGE_RELEASE_MARGIN then

            activeDodgeUntil = math.max(activeDodgeUntil, now + 0.12)
        end
        local holdingDodge = activeDodgeLabel ~= nil and now < activeDodgeUntil
        local timelineLocked = now < timelineDodgeUntil
        local unsafeMiniGoal = miniTarget and not miniDestinationSafe
        local mustDodge = enteredDanger or holdingDodge or timelineLocked
            or unsafeMiniGoal
        local goal = preferred
        local response = CONFIG.MOVE_RESPONSE

        if mustDodge or now < targetedBurstUntil then

            if miniDestinationSafe then
                goal = preferred
            elseif heroicFlow
                and _F.pointSafe(preferred, true)
                and _F.movementPathSafe(root.Position, preferred, true) then

                goal = preferred
            else
                local safe = _F.safeOrbitGoal(centre, preferred, aim,
                    heroicFlow or timelineLocked, heroicFlow)
                if safe then
                    goal = safe
                end
            end
            response = CONFIG.DODGE_RESPONSE
            local label = enteredDanger and nearest.label
                or (timelineLocked and "TimelineDestruction verrouillee")
                or (unsafeMiniGoal and "danger pres OBJECTIF")
                or activeDodgeLabel or "attaque ciblee"
            if label ~= activeDodgeLabel then
                activeDodgeLabel = label
                _F.say("ESQUIVE -> %s (bord danger=%s)", label,
                    edge and string.format("%+.0f", edge) or "?")
            end
        elseif heroicFlow then

            if not _F.pointSafe(preferred, true)
                or not _F.movementPathSafe(root.Position, preferred, true) then
                local safe = _F.safeOrbitGoal(centre, preferred, aim, true, true)
                if safe then
                    goal = safe
                end
            end
            if activeDodgeLabel then
                _F.say("FIN ESQUIVE %s -> mouvement Heroic continu", activeDodgeLabel)
                activeDodgeLabel = nil
                activeDodgeUntil = 0
                cachedDodgeGoal = nil
                cachedDodgeGoalUntil = 0
            end
        elseif activeDodgeLabel then
            _F.say("FIN ESQUIVE %s -> orbite courte", activeDodgeLabel)
            activeDodgeLabel = nil
            activeDodgeUntil = 0
            cachedDodgeGoal = nil
            cachedDodgeGoalUntil = 0
        end

        local maximumSafeY = centre.Y + CONFIG.HOLD_HEIGHT_MAX
        local ceilingY = _F.altitudeCeilingY()
        local usingDodgeVolume = heroicFlow or mustDodge
            or now < targetedBurstUntil
        if usingDodgeVolume and ceilingY then
            maximumSafeY = ceilingY
        elseif ceilingY and ceilingY < maximumSafeY then
            maximumSafeY = ceilingY
        end
        if goal.Y > maximumSafeY then
            goal = Vector3.new(goal.X, maximumSafeY, goal.Z)
        end

        goal = heroicFlow and heroicState.clampArena(goal) or _F.clampToMovementArena(goal)

        local canWallBump = crystalRoomCenter and not mustDodge and not miniTarget
            and now >= targetedBurstUntil
        if wallCollisionEnabled and (now >= wallBumpUntil or not canWallBump) then
            wallBumpUntil = 0
            _F.setWallCollision(false)
        end
        if canWallBump and now >= nextWallBumpAt
            and _F.flatDistance(root.Position, crystalRoomCenter)
                >= CONFIG.WALL_BUMP_MIN_ARENA_RADIUS then
            wallBumpUntil = now + CONFIG.WALL_BUMP_DURATION
            nextWallBumpAt = now + CONFIG.WALL_BUMP_MIN_INTERVAL
                + math.random() * (CONFIG.WALL_BUMP_MAX_INTERVAL
                    - CONFIG.WALL_BUMP_MIN_INTERVAL)
            _F.setWallCollision(true)
            _F.say("ACCROC MUR volontaire : %.2f s", CONFIG.WALL_BUMP_DURATION)
        end
        if wallCollisionEnabled and now < wallBumpUntil and crystalRoomCenter then
            local radial = (goal - crystalRoomCenter) * Vector3.new(1, 0, 1)
            if radial.Magnitude < 1 then
                radial = (root.Position - crystalRoomCenter) * Vector3.new(1, 0, 1)
            end
            if radial.Magnitude >= 1 then
                local radius = CONFIG.MOVEMENT_ARENA_RADIUS + CONFIG.WALL_BUMP_PUSH
                goal = Vector3.new(
                    crystalRoomCenter.X + radial.Unit.X * radius,
                    goal.Y,
                    crystalRoomCenter.Z + radial.Unit.Z * radius)
            end
        end

        local lookAt = aim
        if (lookAt - goal).Magnitude < 1 then lookAt = goal + root.CFrame.LookVector end
        if miniTarget and miniDestinationSafe
            and (root.Position - goal).Magnitude > CONFIG.MINI_TELEPORT_DISTANCE then

            root.CFrame = CFrame.new(goal, lookAt)
            if miniInfo and miniInfo.teleportReason ~= miniReason then
                miniInfo.teleportReason = miniReason
                local actualDistance = _F.flatDistance(goal, aim)
                _F.say("TP OBJECTIF #%d : a %d studs du petit cristal (%s)",
                    miniInfo.id, math.floor(actualDistance + 0.5), tostring(miniReason))
            end
        else

            root.CFrame = root.CFrame:Lerp(CFrame.new(goal, lookAt),
                1 - math.exp(-response * delta))
        end
        _F.recordMotionSample(now, root.Position)

        if now - lastTrace >= CONFIG.TRACE_PERIOD then
            lastTrace = now
            local hpPercent = humanoid.MaxHealth > 0
                and humanoid.Health / humanoid.MaxHealth * 100 or 0
            local info = activeCrystal and crystals[activeCrystal] or nil
            local floor = _F.arenaFloorY()
            local arenaX = crystalRoomCenter
                and math.abs(root.Position.X - crystalRoomCenter.X) or nil
            local arenaZ = crystalRoomCenter
                and math.abs(root.Position.Z - crystalRoomCenter.Z) or nil
            local traceState = activeDodgeLabel and "ESQUIVE"
                or (heroicState.mode and now < heroicState.targetedUntil
                    and "TANGENTE")
                or (heroicState.mode and "MOBILE") or "ORBITE"
            _F.pushLine(_F.stamp(string.format(
                "trace etat=%-8s cible=%-12s dist3D=%-4.0f horiz=%-4.0f haut=%-4.0f"
                    .. " altSol=%-4s arenaXZ=%s/%s vue=%-7s PV=%3.0f%% dangers=%d"
                    .. " sauts=%d hold=%s",
                traceState,
                info and ("OBJECTIF#" .. info.id) or "KRONAX",
                (root.Position - centre).Magnitude,
                _F.flatDistance(root.Position, centre), root.Position.Y - centre.Y,
                floor and string.format("%.0f", root.Position.Y - floor) or "?",
                arenaX and string.format("%.0f", arenaX) or "?",
                arenaZ and string.format("%.0f", arenaZ) or "?",
                sightClear and "libre" or "BOUCHEE", hpPercent,
                #hazards, heroicState.travelKicks or 0,
                mouseHeld and "OUI" or "non")))
        end

        if now - lastUiUpdate >= 0.20 then
            lastUiUpdate = now
            local bossPercent = bossHumanoid and bossHumanoid.MaxHealth > 0
                and bossHumanoid.Health / bossHumanoid.MaxHealth * 100 or 0
            local info = activeCrystal and crystals[activeCrystal] or nil
            statusLabel.Text = string.format(
                "%s   Boss %.1f%%\n%s   PV joueur %.0f%%\n"
                    .. "Orbite %.0f / haut %.0f / %s\n"
                    .. "Objectifs %d vus / %d detruits / %d ignores\nLog : %s",
                boss and boss.Name or "recherche de Kronax", bossPercent,
                info and ("PRIORITE OBJECTIF #" .. info.id)
                    or (activeDodgeLabel and ("ESQUIVE " .. activeDodgeLabel)
                        or (heroicState.mode and now < heroicState.targetedUntil
                            and ("TANGENTE "
                                .. tostring(heroicState.targetedLabel))
                            or "Cible : Kronax")),
                humanoid.MaxHealth > 0 and humanoid.Health / humanoid.MaxHealth * 100 or 0,
                _F.flatDistance(root.Position, centre), root.Position.Y - centre.Y,
                sightClear and "vue libre" or "VUE BOUCHEE",
                crystalStats.seen, crystalStats.destroyed, crystalStats.ignored,
                CONFIG.LOG_FILE)
        end
    end)

    _F.say("LANCE -- KRONAX MINI - CRISTAUX (boss seul) / base v0.41")
    _F.say("minigun deja equipe : H initial une seule fois, maintien 60 s / pause 2 s, surveillance toutes les 0.08 s")
    _F.say("C soin conserve une fois pendant la pause de 2 s, jamais lors des reprises apres un coup")
    _F.say("orbite : rayon %d (hors nova TimestreamDecay), vitesse %d studs/s, hauteur %d",
        CONFIG.ORBIT_RADIUS, CONFIG.ORBIT_LINEAR_SPEED, CONFIG.HOLD_HEIGHT)
    _F.say("objectifs : tout destructible de %.0f a %.0f PV est casse (reliques 5 M"
            .. " et mini RecursiveRelics au sol 4 M)",
        CONFIG.CRYSTAL_MIN_TARGET_HEALTH, CONFIG.CRYSTAL_MAX_TARGET_HEALTH)
    _F.say("NOUVEAU v0.40 : une relique sans PV visibles reste prioritaire apres la fin"
            .. " du signal visuel; retour sur Kronax seulement apres %d tirs et %.1f s"
            .. " de focus", CONFIG.CRYSTAL_VISUAL_MIN_SHOTS,
        CONFIG.CRYSTAL_VISUAL_MIN_FOCUS)
    _F.say("NOUVEAU v0.40 : MapContent.RecursiveRelics controle directement toutes les"
            .. " %.2f s, sans balayage global", CONFIG.RECURSIVE_RELIC_POLL_INTERVAL)
    _F.say("NOUVEAU v0.41 : changements de chargement avant Kronax absorbes;"
            .. " OriginalThickness ne peut plus activer une relique")
    _F.say("NOUVEAU v0.41 : un emplacement fixe bloque est relache sans blacklist et"
            .. " reste reutilisable a sa prochaine vraie activation")
    _F.say("sentinelles : au-dessus de 10 M PV (999999999) jamais touchees -> focus Kronax")
    _F.say("invocations alliees : modeles Owner + SpiritType ignores (Mender jamais vise)")
    _F.say("mini cristaux : nom libre, dossier libre; rayon d'arene %d studs",
        CONFIG.ARENA_RADIUS)
    _F.say("CADRE MOUVEMENT : CYLINDRE de rayon %d studs centre sur les 4 reliques"
            .. " (marge interieure %d, Heroic %d de plus)",
        CONFIG.MOVEMENT_ARENA_RADIUS, CONFIG.MOVEMENT_ARENA_INSET,
        CONFIG.HEROIC_ARENA_EDGE_MARGIN)
    _F.say("NOUVEAU v0.37 : plancher de deplacement %d studs sur %.2f s, relance"
            .. " de trajectoire max toutes les %.2f s. Mesure : 82 et 81 studs de"
            .. " deplacement median sur les runs gagnes, 54 sur le run perdu.",
        CONFIG.MIN_TRAVEL_DISTANCE, CONFIG.MIN_TRAVEL_WINDOW,
        CONFIG.TRAVEL_KICK_COOLDOWN)
    _F.say("CONSERVE v0.36 : couloirs Timeline/Flash portes a %.2f s (6 coups"
            .. " sur 13 des runs v0.34-v0.35 pris dans un couloir age de 2.18 a"
            .. " 2.85 s, supprime a 2.00 s par le script)", CONFIG.CORRIDOR_LIFETIME)
    _F.say("CONSERVE v0.35 : les candidats d'esquive hors cylindre sont"
            .. " rejetes au lieu d'etre rabattus sur le bord (67 %% du run v0.34"
            .. " passe a rayon 155, 6 coups sur 7 pris exactement la)")
    _F.say("RAPPEL v0.34 : le cadre rectangulaire avait ses coins a %d studs,"
            .. " soit %d studs dans le mur. Journaux v0.32/v0.33 : 29 a 35 %% du"
            .. " combat passe au-dela de 175 studs, vue bouchee 50 %% du temps"
            .. " la-bas contre 0 a 4 %% dans le cylindre.",
        math.floor(CONFIG.MOVEMENT_ARENA_RADIUS * math.sqrt(2)),
        math.floor(CONFIG.MOVEMENT_ARENA_RADIUS * (math.sqrt(2) - 1)))
    _F.say("MESURE AUX DEGATS : distance signee a TOUTES les zones actives + fenetre"
            .. " de 2.5 s des lancers (le champ \"apres X\" ne nommait que le"
            .. " dernier lancer et n'a jamais prouve la source d'un coup)")
    _F.say("esquives Heroic : maillage local %d directions x %d rayons x %d hauteurs;"
            .. " perimetre reserve aux grosses AoE au sol",
        CONFIG.HEROIC_DODGE_LOCAL_DIRECTIONS, #CONFIG.HEROIC_DODGE_LOCAL_RADII,
        #CONFIG.HEROIC_DODGE_ALTITUDES)
    _F.say("VOLUME HEROIC : altitudes SOL %d a %d studs; attaques ciblees"
            .. " calculees en 3D",
        CONFIG.HEROIC_DODGE_ALTITUDES[1],
        CONFIG.HEROIC_DODGE_ALTITUDES[#CONFIG.HEROIC_DODGE_ALTITUDES])
    _F.say("VOLUME CORRUPTED : altitudes SOL %d a %d studs, bande alignee sur le"
            .. " Heroic (le palier a 115 se posait pile sur le plafond)",
        CONFIG.DODGE_ALTITUDES[1],
        CONFIG.DODGE_ALTITUDES[#CONFIG.DODGE_ALTITUDES])
    _F.say("ALTITUDE : limite mesuree %d studs au-dessus du SOL; plafond du script"
            .. " %d studs (marge %d), mesure par rayon vers le bas",
        CONFIG.ALTITUDE_LIMIT, CONFIG.ALTITUDE_LIMIT - CONFIG.ALTITUDE_MARGIN,
        CONFIG.ALTITUDE_MARGIN)
    _F.say("petits cristaux : TP a %d studs seulement apres %.0f s de visee sans kill",
        CONFIG.MINI_APPROACH_DISTANCE, CONFIG.MINI_TELEPORT_DELAY)
    _F.say("MESURE : payload complet une fois par type de capacite (rayons reels)")
    _F.say("MESURE TIMELINE : trajectoire joueur gardee en memoire; preuve ecrite seulement aux degats")
    _F.say("PROFIL HEROIC : courbe %d/%d studs/s, altitude lisse %d +/- %d;"
            .. " DEPLACEMENT INSTANTANE comme le Corrupted (bride supprimee)",
        CONFIG.HEROIC_PATH_SPEED, CONFIG.HEROIC_TARGET_PATH_SPEED,
        CONFIG.HEROIC_ALTITUDE_BASE, CONFIG.HEROIC_ALTITUDE_AMPLITUDE)
    _F.say("CADRE HEROIC : marge supplementaire %d studs contre les murs; transition"
            .. " trone -> boss progressive",
        CONFIG.HEROIC_ARENA_EDGE_MARGIN)
    _F.say("TIMELINE v0.37 : capsule 3D rayon %d, verrou minimum %.2f s, clic maintenu",
        CONFIG.TIMELINE_CORRIDOR_RADIUS, CONFIG.TIMELINE_DODGE_HOLD)
    _F.say("ESQUIVES : ChronoShockwave 140 DESORMAIS ESQUIVEE (salve de %.1f s"
            .. " a 0.515 s par tick apres 3 s de charge), nova"
            .. " TimestreamDecay %d, pluie en %d impacts programmes",
        CONFIG.SHOCKWAVE_LINGER, ABILITY_PROFILES.timestreamdecay.radius,
        CONFIG.RAIN_MAX_DROPS)
    _F.say("marges d'esquive : declenchement a %d studs du bord, sortie a %d",
        CONFIG.HAZARD_TRIGGER_MARGIN, CONFIG.HAZARD_ESCAPE_MARGIN)
    _F.say("orbite %d studs de haut, plafond relatif a Kronax %d studs",
        CONFIG.HOLD_HEIGHT, CONFIG.HOLD_HEIGHT_MAX)
    _F.say("profil performance : sonde de vie rapide, balayage borne a %d objets"
            .. " toutes les %.2f s, esquives en cache",
        CONFIG.ARENA_SWEEP_BUDGET, CONFIG.ARENA_SWEEP_INTERVAL)
    _F.say("journal leger : aucun dump de particules/animations")
    _F.say("journal : %s | arret d'urgence : B", CONFIG.LOG_FILE)
    _F.say("session PlaceId=%s JobId=%s", tostring(game.PlaceId), tostring(game.JobId))
    _F.writeLog(true)
end

--==========================================================================
--  PARTIE 2 : LE CONTROLEUR (ancien autoexec) : Start, Skip, Retry,
--  lancement / arret du farm a chaque partie.
--==========================================================================
-- Kronax Autoexec
-- Start : des que StartBtn est vu, attente 5 s puis premier clic
--         (ensuite 1 clic / s jusqu'a disparition).
-- Retry : des que RetryBtn est vu, le farm est coupe, attente 10 s
--         puis premier clic (ensuite 1 clic / s jusqu'a disparition).
-- Apres un Retry, le prochain cycle reprend Start / Skip / farm.
-- Le farm n'est lance qu'apres Start (ou si un vrai combat est deja actif).

if typeof(_G.StopKronaxAutoexec) == "function" then
    pcall(_G.StopKronaxAutoexec, "autoexec remplace")
    task.wait(0.1)
end

if not game:IsLoaded() then
    local loadDeadline = os.clock() + 120
    repeat task.wait(0.25) until game:IsLoaded() or os.clock() >= loadDeadline
    if not game:IsLoaded() then
        warn("[Kronax Autoexec] chargement incomplet apres 120 s -> arret")
        return
    end
end

-- Garde de carte : on attend la carte, puis on ne reste actif que dans le
-- raid Kronax (Map.TimeRaidDungeon). Lobby, raid Lunos, donjon Invaded ou
-- autre donjon : on se retire sans rien toucher.
do
    local deadline = os.clock() + 30
    local isKronax = false
    repeat
        local map = workspace:FindFirstChild("Map")
        if map and map:FindFirstChild("LunosRaid") then break end
        if map and map:FindFirstChild("TimeRaidDungeon") then isKronax = true break end
        if map and #map:GetChildren() > 0 and os.clock() > deadline - 22 then
            break      -- carte chargee depuis 8 s et pas de TimeRaidDungeon
        end
        task.wait(0.5)
    until os.clock() >= deadline
    if not isKronax then
        print("[Kronax Autoexec] pas dans le raid Kronax -> rien a faire")
        return
    end
end

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local player = Players.LocalPlayer
local SCAN_INTERVAL = 1.0
local DEEP_SCAN_INTERVAL = 5.0
local SKIP_SEARCH_WINDOW = 90.0
local FARM_WAIT_WINDOW = 120.0
local START_CLICK_DELAY = 1.0
local RETRY_CLICK_DELAY = 1.0

local running = true
local connections = {}
local loadedAt = os.clock()
local startFinished = false
local startClickedAt = nil
local startFoundAt = nil
local skipFinished = false
local startAttempts = 0
local skipAttempts = 0
local retryAttempts = 0
local retryPrepared = false
local retryFoundAt = nil
local nextDeepScan = 0
local farmState = "idle"
local farmPending = false
local farmPendingSince = nil

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    connections[#connections + 1] = connection
    return connection
end

local function guiVisible(object)
    if not object or not object:IsA("GuiObject") then return false end
    if object.AbsoluteSize.X <= 1 or object.AbsoluteSize.Y <= 1 then return false end
    local current = object
    while current do
        if current:IsA("GuiObject") and not current.Visible then return false end
        if current:IsA("LayerCollector") and not current.Enabled then return false end
        current = current.Parent
    end
    return true
end

local function normalizedText(object)
    if not object then return "" end
    local text = ""
    if object:IsA("TextButton") or object:IsA("TextLabel") then
        text = tostring(object.Text or "")
    end
    text = string.lower(text)
    text = string.gsub(text, "<.->", " ")
    text = string.gsub(text, "%s+", " ")
    return string.match(text, "^%s*(.-)%s*$") or ""
end

local function buttonText(button)
    local parts = {normalizedText(button)}
    for _, descendant in ipairs(button:GetDescendants()) do
        local text = normalizedText(descendant)
        if text ~= "" then parts[#parts + 1] = text end
    end
    return table.concat(parts, " ")
end

local function visibleButtonNamed(name)
    local playerGui = player:FindFirstChild("PlayerGui")
    if not playerGui then return nil end
    for _, object in ipairs(playerGui:GetDescendants()) do
        if object.Name == name and object:IsA("GuiButton")
            and guiVisible(object) then
            return object
        end
    end
    return nil
end

local function visibleButtonAtPath(root, path)
    local current = root
    for _, name in ipairs(path) do
        current = current and current:FindFirstChild(name)
        if not current then return nil end
    end
    if current:IsA("GuiButton") and guiVisible(current) then return current end
    return nil
end

local function visibleObjectAtPath(root, path)
    local current = root
    for _, name in ipairs(path) do
        current = current and current:FindFirstChild(name)
        if not current then return nil end
    end
    if current:IsA("GuiObject") and guiVisible(current) then return current end
    return nil
end

local function startButton()
    local playerGui = player:FindFirstChild("PlayerGui")
    local main = playerGui and playerGui:FindFirstChild("Main")
    local button = main and main:FindFirstChild("StartBtn")
    if button and button:IsA("GuiButton") and guiVisible(button) then
        return button
    end
    return nil
end

local function retryButton()
    local playerGui = player:FindFirstChild("PlayerGui")
    if not playerGui then return nil end

    local button = visibleButtonAtPath(playerGui, {
        "DungeonComplete", "Main", "EndGameButtons", "RetryBtn",
    }) or visibleButtonAtPath(playerGui, {
        "DungeonComplete", "Main", "Frame", "RetryBtn",
    })
    if button then return button end

    local now = os.clock()
    if now < nextDeepScan then return nil end
    nextDeepScan = now + DEEP_SCAN_INTERVAL
    return visibleButtonNamed("RetryBtn")
end

local function skipButton()
    local playerGui = player:FindFirstChild("PlayerGui")
    if not playerGui then return nil end

    local direct = playerGui:FindFirstChild("SkipCutscene", true)
    if direct and direct:IsA("GuiButton") and guiVisible(direct) then
        return direct
    end

    local skipNames = {
        SkipCutscene = true, SkipBtn = true, SkipButton = true, Skip = true,
    }
    local buttons = {}
    for _, object in ipairs(playerGui:GetDescendants()) do
        if object:IsA("GuiButton") and guiVisible(object) then
            if skipNames[object.Name] then return object end
            buttons[#buttons + 1] = object
        end
    end
    for _, button in ipairs(buttons) do
        local text = buttonText(button)
        if string.find(text, "skip", 1, true)
            or string.find(text, "passer la cinematique", 1, true)
            or text == "passer" then
            return button
        end
    end
    return nil
end

local function activeDungeonVisible()
    local playerGui = player:FindFirstChild("PlayerGui")
    return playerGui ~= nil and visibleObjectAtPath(playerGui, {
        "Main", "BossHealthBars", "DungeonTimer",
    }) ~= nil
end

local function activeKronaxBoss()
    local mobs = workspace:FindFirstChild("Mobs")
    if not mobs then return nil end
    for _, model in ipairs(mobs:GetDescendants()) do
        if model:IsA("Model")
            and string.find(string.lower(model.Name), "kronax", 1, true) then
            local humanoid = model:FindFirstChildOfClass("Humanoid")
            local dungeon = string.lower(tostring(model:GetAttribute("Dungeon") or ""))
            if humanoid and humanoid.Health > 0
                and (model:GetAttribute("Boss") == true
                    or model:GetAttribute("Base") == "TimeBoss"
                    or string.find(dungeon, "timeraid", 1, true)) then
                return model
            end
        end
    end
    return nil
end

local function clickButton(button, label)
    if not guiVisible(button) then return false end
    local position, size = button.AbsolutePosition, button.AbsoluteSize
    local inset = GuiService:GetGuiInset()
    local x = position.X + size.X / 2
    local y = position.Y + size.Y / 2 + inset.Y
    local ok = pcall(function()
        VirtualInputManager:SendMouseMoveEvent(x, y, game)
        task.wait(0.02)
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
        task.wait(0.03)
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
    end)
    if ok then
        print(("[Kronax Autoexec] clic %s envoye : %s")
            :format(label, button:GetFullName()))
    else
        warn("[Kronax Autoexec] impossible d'envoyer le clic " .. label)
    end
    return ok
end

local function stopFarm(reason)
    if typeof(_G.StopCurrentFarm) == "function" then
        pcall(_G.StopCurrentFarm, reason or "autoexec")
    end
end

local function launchFarm(reason)
    if not running then return false end
    -- Le farm est DANS ce fichier (fonction FARM plus haut) : plus besoin
    -- de readfile ni du dossier autoexec. Chaque lancement repart d'une
    -- instance neuve : H initial renvoye, boss et reliques re-detectes.
    local runOk, runError = pcall(FARM)
    if not runOk then
        warn("[Kronax Autoexec] lancement du farm impossible : " .. tostring(runError))
        return false
    end
    if not running then
        stopFarm("controleur deja arrete pendant le lancement")
        return false
    end
    print("[Kronax Autoexec] farm lance : " .. tostring(reason))
    return true
end

local function ensureFarm(reason)
    if not running or farmState ~= "idle" then return end
    farmState = "launching"
    task.spawn(function()
        local launched = launchFarm(reason)
        farmState = launched and "running" or "failed"
    end)
end

local function resetCycle(now)
    retryPrepared = false
    retryAttempts = 0
    retryFoundAt = nil
    farmState = "idle"
    loadedAt = now
    startFinished = false
    skipFinished = false
    startAttempts = 0
    skipAttempts = 0
    startClickedAt = nil
    startFoundAt = nil
    farmPending = false
    farmPendingSince = nil
end

local function stop(reason)
    if not running then return end
    running = false
    stopFarm(reason or "arret autoexec")
    for _, connection in ipairs(connections) do
        pcall(function() connection:Disconnect() end)
    end
    table.clear(connections)
    if _G.StopKronaxAutoexec == stop then _G.StopKronaxAutoexec = nil end
    _G.KronaxAutoexecRunning = nil
    print("[Kronax Autoexec] arrete : " .. tostring(reason))
end

_G.StopKronaxAutoexec = stop
_G.KronaxAutoexecRunning = true

connect(UserInputService.InputBegan, function(input, processed)
    if not processed and input.KeyCode == Enum.KeyCode.B then
        stop("touche B")
    end
end)

pcall(function()
    connect(player.OnTeleport, function(state)
        if state == Enum.TeleportState.Started
            or state == Enum.TeleportState.InProgress then
            stop("teleport; le prochain Autoexec reprendra")
        end
    end)
end)

task.spawn(function()
    while running do
        local now = os.clock()

        if farmPending then
            if activeKronaxBoss() or activeDungeonVisible() then
                farmPending = false
                ensureFarm("combat Kronax detecte")
            elseif farmPendingSince
                and now - farmPendingSince >= FARM_WAIT_WINDOW then
                farmPending = false
                warn(("[Kronax Autoexec] aucun combat apres %.0f s;"
                    .. " farm non lance"):format(FARM_WAIT_WINDOW))
            end
        end

        if not startFinished then
            local start = startButton()
            if start then
                if not startFoundAt then
                    startFoundAt = now
                    if START_CLICK_DELAY > 0 then
                        print(("[Kronax Autoexec] Start vu : attente %.0f s avant clic")
                            :format(START_CLICK_DELAY))
                    end
                end
                if now - startFoundAt >= START_CLICK_DELAY then
                    startAttempts += 1
                    if clickButton(start, "Start #" .. startAttempts) then
                        startClickedAt = now
                        farmPending = true
                        farmPendingSince = now
                    end
                end
            elseif startAttempts > 0 then
                startFinished = true
                print(("[Kronax Autoexec] Start confirme apres %d tentative(s)")
                    :format(startAttempts))
            elseif activeKronaxBoss() or activeDungeonVisible() then
                startFinished = true
                skipFinished = true
                ensureFarm("combat Kronax deja actif")
                print("[Kronax Autoexec] combat deja actif; Start inutile")
            end

        elseif not skipFinished then
            local skip = skipButton()
            if skip then
                skipAttempts += 1
                clickButton(skip, "Skip cinematique #" .. skipAttempts)
            elseif skipAttempts > 0 then
                skipFinished = true
                print(("[Kronax Autoexec] Skip confirme apres %d tentative(s)")
                    :format(skipAttempts))
            elseif startClickedAt
                and now - startClickedAt >= SKIP_SEARCH_WINDOW then
                skipFinished = true
                print("[Kronax Autoexec] fenetre Skip terminee")
            end
        end

        local retry = retryButton()
        if retry then
            startFinished = true
            skipFinished = true
            if not retryPrepared then
                retryPrepared = true
                retryFoundAt = now
                farmPending = false
                farmPendingSince = nil
                stopFarm("retry detecte")
                print(("[Kronax Autoexec] Retry vu : attente %.0f s avant clic")
                    :format(RETRY_CLICK_DELAY))
            end
            if retryFoundAt and now - retryFoundAt >= RETRY_CLICK_DELAY then
                retryAttempts += 1
                clickButton(retry, "Retry #" .. retryAttempts)
            end
        elseif retryPrepared and retryAttempts > 0
            and (startButton() or activeDungeonVisible()) then
            print(("[Kronax Autoexec] Retry confirme apres %d tentative(s);"
                .. " nouvelle execution"):format(retryAttempts))
            resetCycle(now)
        end

        task.wait(SCAN_INTERVAL)
    end
end)

if running then
    print(("[Kronax Autoexec] actif : Start delai %.0f s, Retry delai %.0f s,"
        .. " puis 1 clic / %.0f s, arret B")
        :format(START_CLICK_DELAY, RETRY_CLICK_DELAY, SCAN_INTERVAL))
end

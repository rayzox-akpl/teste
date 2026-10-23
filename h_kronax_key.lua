-- ==========================================================
--  ACHAT DE CLES HEROIC KRONAX  --  version rapide
--
--  InvokeServer est bloquant : il attend la reponse du serveur. Le debit
--  ne depend donc pas d'un task.wait mais du nombre d'appels en vol en
--  meme temps. D'ou les taches paralleles.
--
--  Et pas de task.wait dans la boucle : il attendrait une frame entiere,
--  16 ms a 60 images par seconde, alors qu'InvokeServer rend deja la main
--  pendant l'aller-retour. On ne cede la main que si l'appel revient en
--  moins de 4 ms, sinon une boucle sans yield figerait le client.
--
--  F7 pour arreter.
-- ==========================================================

local TACHES = 1000    -- appels simultanes

-- hub : un 2e appui sur le bouton coupe l'achat en cours avant de relancer
if _G.StopAchatCles then
    pcall(_G.StopAchatCles)
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RF = ReplicatedStorage
    :WaitForChild("ReplicatedStorage")
    :WaitForChild("Packages")
    :WaitForChild("Knit")
    :WaitForChild("Services")
    :WaitForChild("MiscContentService")
    :WaitForChild("RF")
    :WaitForChild("PurchaseHeroicKronaxKey")

local actif = true

_G.StopAchatCles = function()
    actif = false
    print("[cles] arret")
end

game:GetService("UserInputService").InputBegan:Connect(function(input, saisie)
    if not saisie and (input.KeyCode == Enum.KeyCode.F7 or input.KeyCode == Enum.KeyCode.B) then
        _G.StopAchatCles()
    end
end)

for _ = 1, TACHES do
    task.spawn(function()
        while actif do
            local avant = os.clock()
            pcall(function() RF:InvokeServer() end)
            if os.clock() - avant < 0.004 then task.wait() end
        end
    end)
end

print("[cles] lance avec " .. TACHES .. " taches -- F7 pour arreter")

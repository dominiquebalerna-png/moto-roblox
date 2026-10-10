-- MotoClient (LocalScript)
-- Dove va: StarterPlayer > StarterPlayerScripts
-- Passo 1: muove le parti della moto in vetrina per controllare che tutto sia montato bene:
-- ruote che girano, manubrio che sterza, forcella che affonda, forcellone che molleggia.
-- Nell'Output le righe di questo script iniziano con [Moto].

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local VERSIONE = 1
local cartella = Workspace:WaitForChild("Moto")

local NOMI_GIUNTI = { "Sterzo", "Forcella", "RuotaDavanti", "Forcellone", "RuotaDietro" }
local giuntiPerMoto = {} -- [moto] = { Sterzo = Motor6D, ... }

local function giunti(moto)
	local g = giuntiPerMoto[moto]
	if g then
		return g
	end
	g = {}
	local trovati = 0
	for _, nome in ipairs(NOMI_GIUNTI) do
		local j = moto:FindFirstChild("Giunto_" .. nome, true)
		if j and j:IsA("Motor6D") then
			g[nome] = j
			trovati += 1
		end
	end
	if trovati < #NOMI_GIUNTI then
		-- la moto potrebbe non essere ancora arrivata tutta: riprovo al prossimo frame
		return nil
	end
	giuntiPerMoto[moto] = g
	print(string.format("[Moto] Client v%d: animazione vetrina attiva su %s (giunti trovati: %d su %d)",
		VERSIONE, moto.Name, trovati, #NOMI_GIUNTI))
	return g
end

cartella.ChildRemoved:Connect(function(moto)
	giuntiPerMoto[moto] = nil
end)

local inizio = os.clock()
RunService.RenderStepped:Connect(function()
	local t = os.clock() - inizio
	for _, moto in ipairs(cartella:GetChildren()) do
		if moto:IsA("Model") and moto:GetAttribute("Demo") then
			local g = giunti(moto)
			if g then
				local giro = -t * 5 -- angolo negativo attorno a X = la ruota rotola in avanti
				g.RuotaDietro.Transform = CFrame.Angles(giro, 0, 0)
				g.RuotaDavanti.Transform = CFrame.Angles(giro, 0, 0)
				g.Sterzo.Transform = CFrame.Angles(0, math.rad(28) * math.sin(t * 0.8), 0)
				g.Forcella.Transform = CFrame.new(0, 0.4 * (0.5 + 0.5 * math.sin(t * 2.2)), 0)
				g.Forcellone.Transform = CFrame.Angles(-math.rad(7) * (0.5 + 0.5 * math.sin(t * 1.7)), 0, 0)
			end
		end
	end
end)

print("[Moto] Client v" .. VERSIONE .. " avviato")

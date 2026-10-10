-- MotoServer (Script)
-- Dove va: ServerScriptService
-- Passo 1 del gioco nuovo: carica la moto 3D (Yamaha YZ125) da ServerStorage > MotoModello,
-- le da' colori e materiali, la monta sui perni (ruote, sterzo, forcella, forcellone)
-- e la mette in vetrina davanti allo SpawnLocation.
-- Nell'Output le righe di questo script iniziano con [Moto].

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local VERSIONE = 1

local function log(...)
	print("[Moto]", ...)
end

-- Geometria della moto in stud (1 stud = 0,28 m), uguale a quella del file 3D.
-- Origine = asse della ruota dietro, -Z = davanti, +Y = su, +X = lato destro.
local GEOMETRIA = {
	AsseDietro = Vector3.new(0, 0, 0),
	AsseDavanti = Vector3.new(0, 0.0402, -5.1536),
	PernoForcellone = Vector3.new(0, 0.4283, -2.0347),
	PernoSterzo = Vector3.new(0, 2.4006, -3.8463),
	DirSterzo = Vector3.new(0, 0.9136, 0.4066), -- asse dello sterzo verso l'alto (24 gradi)
	Terra = -1.19, -- altezza del terreno rispetto all'asse dietro
	DistanzaAvanti = 5, -- distanza tra i cubetti RIF_Origine e RIF_Avanti
	DistanzaSu = 3, -- distanza tra i cubetti RIF_Origine e RIF_Su
}

local function materiale(nome, riserva)
	local ok, m = pcall(function()
		return Enum.Material[nome]
	end)
	return ok and m or riserva
end

local GOMMA = materiale("Rubber", Enum.Material.Plastic)
local TESSUTO = materiale("Leather", Enum.Material.Fabric)

-- colore, materiale, riflesso
local MATERIALI = {
	Blu = { Color3.fromRGB(18, 42, 190), Enum.Material.SmoothPlastic, 0.04 },
	BluCerchio = { Color3.fromRGB(22, 52, 175), Enum.Material.Metal, 0.1 },
	Nero = { Color3.fromRGB(22, 22, 24), Enum.Material.SmoothPlastic, 0 },
	Sella = { Color3.fromRGB(24, 24, 26), TESSUTO, 0 },
	NeroOpaco = { Color3.fromRGB(35, 35, 38), Enum.Material.SmoothPlastic, 0 },
	Gomma = { Color3.fromRGB(28, 28, 28), GOMMA, 0 },
	Alluminio = { Color3.fromRGB(172, 174, 178), Enum.Material.Metal, 0.05 },
	Oro = { Color3.fromRGB(176, 138, 62), Enum.Material.Metal, 0.15 },
	Cromo = { Color3.fromRGB(205, 205, 210), Enum.Material.Metal, 0.25 },
	Molla = { Color3.fromRGB(205, 140, 55), Enum.Material.SmoothPlastic, 0.05 },
	Argento = { Color3.fromRGB(190, 190, 195), Enum.Material.Metal, 0.1 },
	Motore = { Color3.fromRGB(150, 152, 158), Enum.Material.Metal, 0.05 },
	Ciano = { Color3.fromRGB(60, 185, 235), Enum.Material.SmoothPlastic, 0 },
	Bianco = { Color3.fromRGB(235, 235, 235), Enum.Material.SmoothPlastic, 0 },
	Disco = { Color3.fromRGB(150, 150, 156), Enum.Material.Metal, 0.15 },
}

local GRUPPI = { "Corpo", "Sterzo", "Forcella", "RuotaDavanti", "Forcellone", "RuotaDietro" }

-- chi e' attaccato a chi (figlio -> padre)
local PADRE = {
	Sterzo = "Corpo",
	Forcella = "Sterzo",
	RuotaDavanti = "Forcella",
	Forcellone = "Corpo",
	RuotaDietro = "Forcellone",
}

local function trovaRif(modello, nome)
	for _, d in ipairs(modello:GetDescendants()) do
		if d:IsA("BasePart") and string.find(d.Name, "RIF_" .. nome, 1, true) then
			return d
		end
	end
	return nil
end

local function nuovoPerno(nome, cf, genitore)
	local p = Instance.new("Part")
	p.Name = "Perno_" .. nome
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.Transparency = 1
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Anchored = false
	p.CFrame = cf
	p.Parent = genitore
	return p
end

local function costruisciMoto(nome, cfDestinazione)
	local sorgente = ServerStorage:FindFirstChild("MotoModello")
	if not sorgente then
		warn("[Moto] ERRORE: non trovo ServerStorage > MotoModello. Importa MotoYZ125.glb e rinominalo MotoModello.")
		return nil
	end
	if not sorgente:IsA("Model") then
		warn("[Moto] ERRORE: MotoModello deve essere un Model, invece e' un " .. sorgente.ClassName)
		return nil
	end

	local m = sorgente:Clone()

	-- 1) scala: i cubetti RIF devono essere a 5 stud (avanti) e 3 stud (su) dall'origine
	local rO, rA, rS = trovaRif(m, "Origine"), trovaRif(m, "Avanti"), trovaRif(m, "Su")
	if not (rO and rA and rS) then
		warn("[Moto] ERRORE: mancano i cubetti RIF_Origine / RIF_Avanti / RIF_Su nel modello importato.")
		return nil
	end
	local distA = (rA.Position - rO.Position).Magnitude
	local fattore = GEOMETRIA.DistanzaAvanti / distA
	if math.abs(fattore - 1) > 0.001 then
		m:ScaleTo(m:GetScale() * fattore)
	end
	local o, a, s = rO.Position, rA.Position, rS.Position
	log(string.format("Scala corretta di x%.3f. Controllo: avanti = %.2f (deve essere 5), su = %.2f (deve essere 3)",
		fattore, (a - o).Magnitude, (s - o).Magnitude))

	-- 2) orientamento: ricostruisco il sistema di riferimento del file 3D
	local avanti = (a - o).Unit
	local su = s - o
	su = (su - avanti * su:Dot(avanti)).Unit
	local destra = avanti:Cross(su)
	local cfModello = CFrame.fromMatrix(o, destra, su)

	-- 3) nuovo modello con i perni
	local moto = Instance.new("Model")
	moto.Name = nome

	local G = GEOMETRIA
	local rotSterzo = CFrame.fromMatrix(Vector3.zero, Vector3.xAxis, G.DirSterzo)
	local cfPerni = {
		Corpo = CFrame.new(),
		RuotaDietro = CFrame.new(G.AsseDietro),
		Forcellone = CFrame.new(G.PernoForcellone),
		Sterzo = CFrame.new(G.PernoSterzo) * rotSterzo,
		Forcella = CFrame.new(G.AsseDavanti) * rotSterzo,
		RuotaDavanti = CFrame.new(G.AsseDavanti),
	}
	local perni = {}
	for _, gruppo in ipairs(GRUPPI) do
		perni[gruppo] = nuovoPerno(gruppo, cfDestinazione * cfPerni[gruppo], moto)
	end
	perni.Corpo.Anchored = true
	moto.PrimaryPart = perni.Corpo

	-- 4) sposto, coloro e saldo ogni pezzo al perno del suo gruppo
	local conta = {}
	local sconosciuti = {}
	local tolteApparenze = 0
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("SurfaceAppearance") then
			d:Destroy()
			tolteApparenze += 1
		end
	end
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") then
			local gruppo, colore = string.match(p.Name, "^(%w+)_(%w+)")
			if gruppo == "RIF" then
				continue
			end
			if not perni[gruppo] then
				table.insert(sconosciuti, p.Name)
				continue
			end
			local rel = cfModello:ToObjectSpace(p.CFrame)
			p.Anchored = false
			p.CFrame = cfDestinazione * rel
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Massless = true
			p.CastShadow = true
			local mat = MATERIALI[colore]
			if mat then
				p.Color = mat[1]
				p.Material = mat[2]
				p.Reflectance = mat[3]
			else
				table.insert(sconosciuti, p.Name .. " (colore?)")
			end
			p.Name = gruppo .. "_" .. colore
			p.Parent = moto
			local w = Instance.new("WeldConstraint")
			w.Part0 = perni[gruppo]
			w.Part1 = p
			w.Parent = p
			conta[gruppo] = (conta[gruppo] or 0) + 1
		end
	end
	m:Destroy()
	if #sconosciuti > 0 then
		warn("[Moto] Pezzi con nome non riconosciuto: " .. table.concat(sconosciuti, ", "))
	end
	if tolteApparenze > 0 then
		log("Tolte " .. tolteApparenze .. " SurfaceAppearance create dall'importazione (i colori li decide lo script)")
	end

	-- 5) giunti mobili: Motor6D dal perno padre al perno figlio
	for figlio, padre in pairs(PADRE) do
		local j = Instance.new("Motor6D")
		j.Name = "Giunto_" .. figlio
		j.Part0 = perni[padre]
		j.Part1 = perni[figlio]
		j.C0 = perni[padre].CFrame:ToObjectSpace(perni[figlio].CFrame)
		j.C1 = CFrame.new()
		j.Parent = perni[figlio]
	end

	local righe = {}
	for _, gruppo in ipairs(GRUPPI) do
		table.insert(righe, gruppo .. " " .. (conta[gruppo] or 0))
		if not conta[gruppo] then
			warn("[Moto] ATTENZIONE: nessun pezzo trovato per il gruppo " .. gruppo)
		end
	end
	log("Pezzi montati: " .. table.concat(righe, ", "))
	return moto
end

-- cartella delle moto
local cartella = Workspace:FindFirstChild("Moto")
if not cartella then
	cartella = Instance.new("Folder")
	cartella.Name = "Moto"
	cartella.Parent = Workspace
end

-- posizione della vetrina: 14 stud davanti allo SpawnLocation, vista di fianco
local spawn = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
local base = spawn and spawn.Position or Vector3.new(0, 5, 0)
local pos = base + Vector3.new(0, 0, -14)
local parametri = RaycastParams.new()
parametri.FilterType = Enum.RaycastFilterType.Exclude
parametri.FilterDescendantsInstances = { cartella }
local colpo = Workspace:Raycast(pos + Vector3.new(0, 50, 0), Vector3.new(0, -200, 0), parametri)
local yTerra = colpo and colpo.Position.Y or 0
pos = Vector3.new(pos.X, yTerra - GEOMETRIA.Terra + 0.02, pos.Z)
local cfVetrina = CFrame.lookAt(pos, pos + Vector3.xAxis)

local moto = costruisciMoto("Moto_Vetrina", cfVetrina)
if moto then
	moto:SetAttribute("Demo", true)
	moto.Parent = cartella
	log("Versione " .. VERSIONE .. ": vetrina pronta in " .. moto:GetFullName())
end

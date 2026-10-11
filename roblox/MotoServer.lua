-- MotoServer (Script)
-- Dove va: ServerScriptService
-- Carica la moto 3D (Yamaha YZ125) da ServerStorage > MotoModello, le da' colori e materiali,
-- la monta sui perni (ruote, sterzo, forcella, forcellone) e ne crea una per ogni giocatore,
-- vicino a dove nasce. Con E si sale (ProximityPrompt "Sali"), con E si scende.
-- La guida la fa il MotoClient: qui il server da' al pilota il controllo della fisica.
-- Nell'Output le righe di questo script iniziano con [Moto].

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local VERSIONE = 6

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
	PernoCodino = Vector3.new(0, 2.0882, -0.6693), -- dove il codino (parafango dietro) si piega
	DirSterzo = Vector3.new(0, 0.9136, 0.4066), -- asse dello sterzo verso l'alto (24 gradi)
	Terra = -1.19, -- altezza del terreno rispetto all'asse dietro
	Sella = Vector3.new(0, 2.0, -1.45), -- centro del sedile (invisibile) su cui si siede il pilota
	DistanzaAvanti = 5, -- distanza tra i cubetti RIF_Origine e RIF_Avanti
	DistanzaSu = 3, -- distanza tra i cubetti RIF_Origine e RIF_Su
}

-- La moto viene ingrandita di questo fattore (1 = misure del file 3D, dove 1 stud = 0,28 m).
-- Lo leggono anche MotoClient e PosaPilota dall'attributo "Scala" della moto.
local SCALA_MOTO = 1.08
local GEO = {}
for k, v in pairs(GEOMETRIA) do
	GEO[k] = (k == "DirSterzo") and v or v * SCALA_MOTO
end
local TELAIO_OFFSET = CFrame.new(0, 0.9 * SCALA_MOTO, -2.6 * SCALA_MOTO) -- dall'asse dietro al centro del Telaio

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
	SellaBlu = { Color3.fromRGB(34, 44, 140), TESSUTO, 0 },
	Titanio = { Color3.fromRGB(72, 72, 78), Enum.Material.Metal, 0.1 },
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

local GRUPPI = { "Corpo", "Sterzo", "Forcella", "RuotaDavanti", "Forcellone", "RuotaDietro", "Codino" }

-- chi e' attaccato a chi (figlio -> padre)
local PADRE = {
	Sterzo = "Corpo",
	Forcella = "Sterzo",
	RuotaDavanti = "Forcella",
	Forcellone = "Corpo",
	RuotaDietro = "Forcellone",
	Codino = "Corpo",
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
	local fattore = GEO.DistanzaAvanti / distA
	if math.abs(fattore - 1) > 0.001 then
		m:ScaleTo(m:GetScale() * fattore)
	end
	local o, a, s = rO.Position, rA.Position, rS.Position
	log(string.format("Scala corretta di x%.3f. Controllo: avanti = %.2f (deve essere %.2f), su = %.2f (deve essere %.2f)",
		fattore, (a - o).Magnitude, GEO.DistanzaAvanti, (s - o).Magnitude, GEO.DistanzaSu))

	-- 2) orientamento: ricostruisco il sistema di riferimento del file 3D
	local avanti = (a - o).Unit
	local su = s - o
	su = (su - avanti * su:Dot(avanti)).Unit
	local destra = avanti:Cross(su)
	local cfModello = CFrame.fromMatrix(o, destra, su)

	-- 3) nuovo modello con i perni
	local moto = Instance.new("Model")
	moto.Name = nome

	local G = GEO
	local rotSterzo = CFrame.fromMatrix(Vector3.zero, Vector3.xAxis, G.DirSterzo)
	local cfPerni = {
		Corpo = CFrame.new(),
		RuotaDietro = CFrame.new(G.AsseDietro),
		Forcellone = CFrame.new(G.PernoForcellone),
		Sterzo = CFrame.new(G.PernoSterzo) * rotSterzo,
		Forcella = CFrame.new(G.AsseDavanti) * rotSterzo,
		RuotaDavanti = CFrame.new(G.AsseDavanti),
		Codino = CFrame.new(G.PernoCodino),
	}
	local perni = {}
	for _, gruppo in ipairs(GRUPPI) do
		perni[gruppo] = nuovoPerno(gruppo, cfDestinazione * cfPerni[gruppo], moto)
	end

	-- telaio fisico invisibile: e' lui che si muove, tutto il resto e' saldato sopra.
	-- Sta 1,3 stud sopra il terreno, cosi' non striscia: l'altezza la tiene il client con i raggi.
	local telaio = Instance.new("Part")
	telaio.Name = "Telaio"
	-- lungo dalla ruota davanti fin quasi all'asse dietro: in impennata non tocca terra
	telaio.Size = Vector3.new(1.2, 1.6, 5) * SCALA_MOTO
	telaio.CFrame = cfDestinazione * TELAIO_OFFSET
	telaio.Transparency = 1
	telaio.CanCollide = true
	telaio.CanTouch = false
	telaio.Anchored = true
	telaio.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0, 0, 100, 1)
	telaio.Parent = moto
	local saldaCorpo = Instance.new("WeldConstraint")
	saldaCorpo.Part0 = telaio
	saldaCorpo.Part1 = perni.Corpo
	saldaCorpo.Parent = telaio
	moto.PrimaryPart = telaio

	local att = Instance.new("Attachment")
	att.Name = "Centro"
	att.Parent = telaio
	local orient = Instance.new("AlignOrientation")
	orient.Name = "Orientamento"
	orient.Mode = Enum.OrientationAlignmentMode.OneAttachment
	orient.Attachment0 = att
	orient.MaxTorque = math.huge
	orient.Responsiveness = 60
	orient.CFrame = telaio.CFrame.Rotation
	orient.Enabled = false
	orient.Parent = telaio

	-- sedile invisibile + tasto E per salire
	local sella = Instance.new("Seat")
	sella.Name = "Sella"
	sella.Size = Vector3.new(1, 0.3, 1.6) * SCALA_MOTO
	sella.CFrame = cfDestinazione * CFrame.new(G.Sella)
	sella.Transparency = 1
	sella.CanCollide = false
	sella.CanTouch = false -- niente seduta toccandola per sbaglio: si sale solo con E
	sella.Massless = true
	sella.Parent = moto
	local saldaSella = Instance.new("WeldConstraint")
	saldaSella.Part0 = telaio
	saldaSella.Part1 = sella
	saldaSella.Parent = sella
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Sali"
	prompt.ActionText = "Sali"
	prompt.ObjectText = "Yamaha YZ125"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = sella

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
			if gruppo == "Codino" then
				warn("[Moto] Il modello e' vecchio (manca il Codino): reimporta MotoYZ125.glb come MotoModello per avere il codino che si piega")
			else
				warn("[Moto] ATTENZIONE: nessun pezzo trovato per il gruppo " .. gruppo)
			end
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

-- evento delle sgommate: il pilota dice 0 (niente), 1 (ruota bloccata) o 2 (burnout);
-- lo scrivo come attributo della moto, cosi' tutti vedono fumo e righe nere
local eventoSgomma = ReplicatedStorage:FindFirstChild("MotoSgomma")
if not eventoSgomma then
	eventoSgomma = Instance.new("RemoteEvent")
	eventoSgomma.Name = "MotoSgomma"
	eventoSgomma.Parent = ReplicatedStorage
end
eventoSgomma.OnServerEvent:Connect(function(giocatore, stato)
	if type(stato) ~= "number" then
		return
	end
	stato = math.clamp(math.floor(stato), 0, 2)
	for _, moto in ipairs(cartella:GetChildren()) do
		if moto:GetAttribute("Pilota") == giocatore.UserId then
			moto:SetAttribute("Sgomma", stato)
		end
	end
end)

-- caduta: il pilota e' andato oltre 100 gradi. Lo stacco dalla moto e la moto vola via ribaltandosi;
-- dopo 3,5 secondi si rimette dritta e si puo' risalire con E
local eventoCaduta = ReplicatedStorage:FindFirstChild("MotoCaduta")
if not eventoCaduta then
	eventoCaduta = Instance.new("RemoteEvent")
	eventoCaduta.Name = "MotoCaduta"
	eventoCaduta.Parent = ReplicatedStorage
end

-- evento per scendere con E (lo manda il MotoClient)
local eventoScendi = ReplicatedStorage:FindFirstChild("MotoScendi")
if not eventoScendi then
	eventoScendi = Instance.new("RemoteEvent")
	eventoScendi.Name = "MotoScendi"
	eventoScendi.Parent = ReplicatedStorage
end

local function filtroTerreno(escludi)
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	p.FilterDescendantsInstances = escludi
	return p
end

-- CFrame dell'asse dietro con la moto dritta, appoggiata sul terreno sotto "pos", che guarda verso "dir"
local function cfAppoggiata(pos, dir, escludi)
	local colpo = Workspace:Raycast(pos + Vector3.new(0, 20, 0), Vector3.new(0, -200, 0), filtroTerreno(escludi))
	local y = colpo and colpo.Position.Y or pos.Y
	dir = Vector3.new(dir.X, 0, dir.Z)
	if dir.Magnitude < 0.01 then
		dir = Vector3.new(0, 0, -1)
	end
	local p = Vector3.new(pos.X, y - GEO.Terra + 0.02, pos.Z)
	return CFrame.lookAt(p, p + dir.Unit)
end

local function parcheggia(moto)
	-- la moto si rimette dritta dove si trova e viene bloccata (Anchored)
	local telaio = moto:FindFirstChild("Telaio")
	if not telaio then
		return
	end
	local asse = telaio.CFrame * TELAIO_OFFSET:Inverse()
	local escludi = { cartella }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(escludi, p.Character)
		end
	end
	local cf = cfAppoggiata(asse.Position, asse.LookVector, escludi)
	telaio.Orientamento.Enabled = false
	telaio.AssemblyLinearVelocity = Vector3.zero
	telaio.AssemblyAngularVelocity = Vector3.zero
	telaio.Anchored = true
	moto:PivotTo(cf * TELAIO_OFFSET)
end

local function collegaSella(moto, proprietario)
	local sella = moto.Sella
	local telaio = moto.Telaio
	local prompt = sella.Sali

	prompt.Triggered:Connect(function(giocatore)
		local char = giocatore.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 or sella.Occupant then
			return
		end
		if hum.SeatPart then
			return
		end
		sella:Sit(hum)
	end)

	sella:GetPropertyChangedSignal("Occupant"):Connect(function()
		local hum = sella.Occupant
		if hum then
			local giocatore = Players:GetPlayerFromCharacter(hum.Parent)
			prompt.Enabled = false
			telaio.Anchored = false
			telaio.Orientamento.CFrame = telaio.CFrame.Rotation
			telaio.Orientamento.Enabled = true
			if giocatore then
				telaio:SetNetworkOwner(giocatore)
				moto:SetAttribute("Pilota", giocatore.UserId)
				log(giocatore.Name .. " e' salito su " .. moto.Name .. " (controllo della fisica dato a " .. giocatore.Name .. ")")
			end
		else
			moto:SetAttribute("Pilota", nil)
			moto:SetAttribute("Sgomma", 0)
			if moto:GetAttribute("Caduta") then
				return -- dopo una caduta la moto vola: la parcheggio piu' tardi
			end
			parcheggia(moto)
			prompt.Enabled = true
			log("Sceso da " .. moto.Name .. ": moto parcheggiata")
		end
	end)
end

eventoCaduta.OnServerEvent:Connect(function(giocatore)
	for _, moto in ipairs(cartella:GetChildren()) do
		if moto:GetAttribute("Pilota") == giocatore.UserId and not moto:GetAttribute("Caduta") then
			local telaio = moto:FindFirstChild("Telaio")
			local sella = moto:FindFirstChild("Sella")
			if not (telaio and sella) then
				continue
			end
			moto:SetAttribute("Caduta", true)
			local w = sella:FindFirstChild("SeatWeld")
			if w then
				w:Destroy()
			end
			local hum = giocatore.Character and giocatore.Character:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.Sit = false
			end
			telaio.Orientamento.Enabled = false
			telaio:SetNetworkOwner(nil)
			-- la moto continua un po' e si ribalta all'indietro
			telaio.AssemblyLinearVelocity = telaio.AssemblyLinearVelocity * 0.8 + Vector3.new(0, 10, 0)
			telaio.AssemblyAngularVelocity = telaio.CFrame.RightVector * 4
			log(giocatore.Name .. " e' caduto all'indietro con " .. moto.Name)
			task.delay(3.5, function()
				if moto.Parent then
					moto:SetAttribute("Caduta", nil)
					parcheggia(moto)
					sella.Sali.Enabled = true
					log(moto.Name .. " rimessa dritta: premi E per risalire")
				end
			end)
		end
	end
end)

eventoScendi.OnServerEvent:Connect(function(giocatore)
	local char = giocatore.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum.SeatPart and hum.SeatPart.Name == "Sella" and hum.SeatPart:IsDescendantOf(cartella) then
		local seatWeld = hum.SeatPart:FindFirstChild("SeatWeld")
		if seatWeld then
			seatWeld:Destroy()
		end
		hum.Sit = false
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if hrp then
			-- scende dal lato sinistro della moto
			hrp.CFrame = hrp.CFrame * CFrame.new(-2.5, 1, 0)
		end
	end
end)

-- corpo slanciato: piu' alto e piu' sottile, in proporzione con la moto (1 stud = 0,28 m)
-- Cambio i valori di scala dell'Humanoid: Roblox ridimensiona il corpo senza rifare le articolazioni.
local SCALA_CORPO = {
	BodyHeightScale = 1.15,
	BodyWidthScale = 0.8,
	BodyDepthScale = 0.8,
	HeadScale = 0.85,
}

local PROPORZIONI = {
	Gambe = 1.22, -- gambe piu' lunghe
	Mani = 0.72, -- mani piu' piccole
}

local function slancia(giocatore, char)
	local hum = char:WaitForChild("Humanoid", 10)
	if not hum then
		return
	end
	if hum.RigType ~= Enum.HumanoidRigType.R15 then
		warn("[Moto] " .. giocatore.Name .. " ha un personaggio R6: corpo slanciato e posa servono R15 "
			.. "(Game Settings > Avatar > Avatar Type: R15).")
		return
	end
	if not giocatore:HasAppearanceLoaded() then
		giocatore.CharacterAppearanceLoaded:Wait()
	end
	if char.Parent == nil then
		return
	end
	hum.AutomaticScalingEnabled = true
	for nome, valore in pairs(SCALA_CORPO) do
		local nv = hum:FindFirstChild(nome)
		if not nv then
			nv = Instance.new("NumberValue")
			nv.Name = nome
			nv.Parent = hum
		end
		nv.Value = valore
	end
	-- proporzioni da ragazzo vero (le gambe Roblox sono corte e le mani enormi):
	-- gambe piu' lunghe, mani piu' piccole. Aspetto che Roblox abbia finito di scalare.
	task.wait(0.5)
	if char.Parent == nil then
		return
	end
	hum.AutomaticScalingEnabled = false -- cosi' Roblox non rimette le misure di prima
	local function allunga(nomeParte, k)
		local p = char:FindFirstChild(nomeParte)
		if not (p and p:IsA("BasePart")) then
			return 0
		end
		local vecchiaY = p.Size.Y
		p.Size = Vector3.new(p.Size.X, p.Size.Y * k, p.Size.Z)
		for _, a in ipairs(p:GetChildren()) do
			if a:IsA("Attachment") then
				a.Position = Vector3.new(a.Position.X, a.Position.Y * k, a.Position.Z)
			end
		end
		return vecchiaY * (k - 1)
	end
	local function rimpicciolisci(nomeParte, k)
		local p = char:FindFirstChild(nomeParte)
		if not (p and p:IsA("BasePart")) then
			return
		end
		p.Size = p.Size * k
		for _, a in ipairs(p:GetChildren()) do
			if a:IsA("Attachment") then
				a.Position = a.Position * k
			end
		end
	end
	local piu = allunga("RightUpperLeg", PROPORZIONI.Gambe) + allunga("RightLowerLeg", PROPORZIONI.Gambe)
	allunga("LeftUpperLeg", PROPORZIONI.Gambe)
	allunga("LeftLowerLeg", PROPORZIONI.Gambe)
	for _, nome in ipairs({ "RightHand", "LeftHand" }) do
		rimpicciolisci(nome, PROPORZIONI.Mani)
	end
	-- i giunti classici (Motor6D) vanno ricostruiti dagli attachment; quelli nuovi li seguono da soli
	local haMotor6D = false
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("Motor6D") and d.Part1 and d.Part1.Name == "RightUpperLeg" then
			haMotor6D = true
		end
	end
	if haMotor6D then
		pcall(function()
			hum:BuildRigFromAttachments()
		end)
	end
	hum.HipHeight += piu
	char:SetAttribute("Slanciato", true)
	log(string.format("Corpo slanciato per %s: altezza x%.2f, larghezza x%.2f, profondita' x%.2f, testa x%.2f, gambe x%.2f, mani x%.2f (HipHeight %.2f)",
		giocatore.Name, SCALA_CORPO.BodyHeightScale, SCALA_CORPO.BodyWidthScale,
		SCALA_CORPO.BodyDepthScale, SCALA_CORPO.HeadScale, PROPORZIONI.Gambe, PROPORZIONI.Mani, hum.HipHeight))
end

-- una moto per ogni giocatore, 10 stud davanti a dove nasce (la prima volta)
local function motoDelGiocatore(giocatore)
	local nome = "Moto_" .. giocatore.Name
	local esistente = cartella:FindFirstChild(nome)
	if esistente then
		return esistente
	end
	local char = giocatore.Character
	local hrp = char and char:WaitForChild("HumanoidRootPart", 5)
	if not hrp then
		return nil
	end
	local davanti = hrp.CFrame.LookVector
	local destra = hrp.CFrame.RightVector
	-- la moto sta di traverso davanti al giocatore, cosi' la vedi di fianco
	local pos = hrp.Position + davanti * 8 - destra * 2.6
	local cf = cfAppoggiata(pos, destra, { cartella, char })
	local moto = costruisciMoto(nome, cf)
	if not moto then
		return nil
	end
	moto:SetAttribute("Proprietario", giocatore.UserId)
	moto:SetAttribute("Scala", SCALA_MOTO)
	moto.Parent = cartella
	collegaSella(moto, giocatore)
	log("Versione " .. VERSIONE .. ": creata " .. moto.Name .. ". Avvicinati e premi E per salire.")
	return moto
end

local function nuovoPersonaggio(giocatore, char)
	task.spawn(slancia, giocatore, char)
	task.wait(0.5)
	motoDelGiocatore(giocatore)
end

local function collegaGiocatore(giocatore)
	giocatore.CharacterAdded:Connect(function(char)
		nuovoPersonaggio(giocatore, char)
	end)
	if giocatore.Character then
		task.spawn(nuovoPersonaggio, giocatore, giocatore.Character)
	end
end

Players.PlayerAdded:Connect(collegaGiocatore)
for _, giocatore in ipairs(Players:GetPlayers()) do
	collegaGiocatore(giocatore)
end

Players.PlayerRemoving:Connect(function(giocatore)
	local moto = cartella:FindFirstChild("Moto_" .. giocatore.Name)
	if moto then
		moto:Destroy()
	end
end)

log("Server versione " .. VERSIONE .. " avviato")

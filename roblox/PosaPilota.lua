-- PosaPilota (ModuleScript)
-- Dove va: ReplicatedStorage  (nome esatto: PosaPilota)
-- Calcola la posa del pilota seduto sulla moto: bacino sulla sella, mani sulle manopole,
-- piedi sulle pedane, ginocchia piegate, busto in avanti.
-- Usa le misure VERE del personaggio (lunghezza di braccia e gambe), quindi va bene
-- per qualsiasi avatar R15, anche se gli manca qualche giunto (es. le caviglie).
-- Non tocca niente da solo: restituisce i valori "Transform" da scrivere nei Motor6D.

local Posa = {}

-- Geometria della moto (stud, sistema della moto: origine asse dietro, -Z avanti, +Y su, +X destra)
Posa.MANOPOLA = Vector3.new(1.22, 3.306, -3.309) -- destra; la sinistra ha X negativa (moto a riposo)
Posa.PEDANA = Vector3.new(0.62, 0.31, -2.17) -- piano della pedana, destra
-- profilo della sella: { z, altezza della superficie }
Posa.SELLA = {
	{ -0.60, 2.17 }, { -1.34, 2.14 }, { -2.01, 2.12 }, { -2.30, 2.15 }, { -2.54, 2.24 },
}

-- parte del corpo -> chiave del giunto che la muove
local PARTI = {
	Root = "LowerTorso", Waist = "UpperTorso", Neck = "Head",
	RS = "RightUpperArm", RE = "RightLowerArm", RW = "RightHand",
	LS = "LeftUpperArm", LE = "LeftLowerArm", LW = "LeftHand",
	RH = "RightUpperLeg", RK = "RightLowerLeg", RA = "RightFoot",
	LH = "LeftUpperLeg", LK = "LeftLowerLeg", LA = "LeftFoot",
}
local OBBLIGATORI = { "Root", "Waist", "RS", "RE", "LS", "LE", "RH", "RK", "LH", "LK" }
Posa.PARTI = PARTI

-- Un giunto puo' essere di due tipi:
--  * Motor6D (avatar classici): Part0, Part1, C0, C1, Transform
--  * AnimationConstraint (avatar nuovi, "Avatar Joint Upgrade"): Attachment0, Attachment1, Transform
-- Per la posa li tratto allo stesso modo con una piccola tabella: { inst, Part1, C0, C1 }.
local function avvolgi(d)
	if d:IsA("Motor6D") then
		if d.Part0 and d.Part1 then
			return { inst = d, tipo = "Motor6D", Part1 = d.Part1, C0 = d.C0, C1 = d.C1 }
		end
	elseif d:IsA("AnimationConstraint") then
		local a0, a1 = d.Attachment0, d.Attachment1
		if a0 and a1 and a0.Parent and a1.Parent and a1.Parent:IsA("BasePart") then
			return { inst = d, tipo = "AnimationConstraint", Part1 = a1.Parent, C0 = a0.CFrame, C1 = a1.CFrame }
		end
	end
	return nil
end

-- rilegge C0/C1 (cambiano quando il corpo viene ridimensionato)
function Posa.aggiorna(g)
	for chiave in pairs(PARTI) do
		local j = g[chiave]
		if j then
			local d = j.inst
			if j.tipo == "Motor6D" then
				j.C0, j.C1 = d.C0, d.C1
			elseif d.Attachment0 and d.Attachment1 then
				j.C0, j.C1 = d.Attachment0.CFrame, d.Attachment1.CFrame
			end
		end
	end
end

-- Cerca i giunti per la PARTE che muovono (non per nome del giunto: alcuni avatar li chiamano diversamente)
function Posa.trovaGiunti(personaggio)
	local perParte = {}
	local tipi = {}
	for _, d in ipairs(personaggio:GetDescendants()) do
		if d:IsA("Motor6D") or d:IsA("AnimationConstraint") or d:IsA("BallSocketConstraint") then
			tipi[d.ClassName] = (tipi[d.ClassName] or 0) + 1
		end
		local j = avvolgi(d)
		if j then
			-- se ci sono tutti e due i tipi per la stessa parte, preferisco il Motor6D se e' attivo
			local prima = perParte[j.Part1.Name]
			if not prima or (j.tipo == "Motor6D" and d.Enabled) then
				perParte[j.Part1.Name] = j
			end
		end
	end
	local elencoTipi = {}
	for nome, n in pairs(tipi) do
		table.insert(elencoTipi, nome .. " " .. n)
	end
	table.sort(elencoTipi)
	Posa.ultimiTipi = #elencoTipi > 0 and table.concat(elencoTipi, ", ") or "nessun giunto"
	local g = { hrp = personaggio:FindFirstChild("HumanoidRootPart") }
	local trovati, mancanti = 0, {}
	for chiave, parte in pairs(PARTI) do
		if perParte[parte] then
			g[chiave] = perParte[parte]
			trovati += 1
		else
			table.insert(mancanti, parte)
		end
	end
	local ok = g.hrp ~= nil
	for _, chiave in ipairs(OBBLIGATORI) do
		if not g[chiave] then
			ok = false
		end
	end
	table.sort(mancanti)
	return g, ok, trovati, mancanti
end

local function altezzaSella(z)
	local s = Posa.SELLA
	if z >= s[1][1] then
		return s[1][2]
	end
	for i = 1, #s - 1 do
		local a, b = s[i], s[i + 1]
		if z <= a[1] and z >= b[1] then
			local t = (z - a[1]) / (b[1] - a[1])
			return a[2] + (b[2] - a[2]) * t
		end
	end
	return s[#s][2]
end

-- rotazione che porta l'asse aL sull'asse aW e (quanto possibile) xL su xW
local function ruotaDaBasi(aL, xL, aW, xW)
	aL = aL.Unit
	xL = (xL - aL * xL:Dot(aL)).Unit
	aW = aW.Unit
	xW = (xW - aW * xW:Dot(aW)).Unit
	local mL = CFrame.fromMatrix(Vector3.zero, xL, aL, xL:Cross(aL))
	local mW = CFrame.fromMatrix(Vector3.zero, xW, aW, xW:Cross(aW))
	return mW * mL:Inverse()
end

local function perpendicolare(v)
	local p = v:Cross(Vector3.new(0, 1, 0))
	if p.Magnitude < 1e-3 then
		p = v:Cross(Vector3.new(1, 0, 0))
	end
	return p.Unit
end

-- IK a due ossa: spalla S, bersaglio T. Restituisce gomito E, polso W (raggiungibile) e asse della cerniera
local function dueOssa(S, T, L1, L2, polo)
	local d = T - S
	local dist = d.Magnitude
	local dn = dist > 1e-4 and d / dist or Vector3.new(0, -1, 0)
	dist = math.clamp(dist, math.abs(L1 - L2) + 1e-3, (L1 + L2) * 0.999)
	local a = (L1 * L1 - L2 * L2 + dist * dist) / (2 * dist)
	local h = math.sqrt(math.max(L1 * L1 - a * a, 0))
	local p = polo - dn * polo:Dot(dn)
	if p.Magnitude < 1e-4 then
		p = perpendicolare(dn)
	end
	p = p.Unit
	local E = S + dn * a + p * h
	local W = S + dn * dist
	return E, W, p:Cross(dn).Unit
end

-- posa di un segmento attaccato al giunto j (padre in cfPadre) con rotazione voluta "rot"
local function segmento(cfPadre, j, rot)
	local cfGiunto = cfPadre * j.C0
	local cf = CFrame.new(cfGiunto.Position) * rot * CFrame.new(-j.C1.Position)
	return cf, cfGiunto:Inverse() * cf * j.C1
end

-- lunghezze di un arto (braccio o gamba)
local function lunghezze(j1, j2, j3)
	local p1a, p1b = j1.C1.Position, j2.C0.Position
	local p2a = j2.C1.Position
	local p2b
	if j3 then
		p2b = j3.C0.Position
	else
		p2b = p2a - Vector3.new(0, j2.Part1.Size.Y * 0.9, 0)
	end
	return (p1b - p1a).Magnitude, (p2b - p2a).Magnitude, p1a, p1b, p2a, p2b
end

-- un arto intero: j1 (spalla/anca), j2 (gomito/ginocchio), j3 (polso/caviglia, puo' mancare)
local function arto(out, cfPadre, j1, j2, j3, bersaglio, polo, segnoX, rotFine)
	local L1, L2, p1a, p1b, p2a, p2b = lunghezze(j1, j2, j3)
	local S = (cfPadre * j1.C0).Position
	local E, W, asse = dueOssa(S, bersaglio, L1, L2, polo)
	local xL = Vector3.new(segnoX, 0, 0)
	local r1 = ruotaDaBasi(p1b - p1a, xL, E - S, asse)
	local cf1 = CFrame.new(S) * r1 * CFrame.new(-p1a)
	out[j1] = (cfPadre * j1.C0):Inverse() * cf1 * j1.C1
	local E1 = cf1 * p1b
	local r2 = ruotaDaBasi(p2b - p2a, xL, W - E1, asse)
	local cf2 = CFrame.new(E1) * r2 * CFrame.new(-p2a)
	out[j2] = (cf1 * j2.C0):Inverse() * cf2 * j2.C1
	local cf3 = nil
	if j3 then
		cf3, out[j3] = segmento(cf2, j3, rotFine or r2)
	end
	return cf2, cf3, E1
end

--[[
  Calcola la posa.
  g      = giunti (da trovaGiunti)
  moto   = CFrame del sistema della moto nel mondo (Perno_Corpo)
  sterzo = CFrame del manubrio nel mondo diviso quello a riposo: le manopole seguono lo sterzo
           (passare moto * C0 * Transform * C0:Inverse() del Giunto_Sterzo, in sistema moto)
  dyn    = movimenti del corpo: { busto = rad in piu' in avanti, scivola = stud indietro sulla sella,
           rollio = rad di piega del corpo dentro la curva, molleggio = stud in su/giu' }
  Restituisce: tabella [Motor6D] = Transform, piu' info per i controlli.
]]
function Posa.calcola(g, moto, sterzo, dyn)
	dyn = dyn or {}
	local out = {}
	local info = {}
	local hrpCF = g.hrp.CFrame
	local rotMoto = moto.Rotation
	local giu = rotMoto:VectorToWorldSpace(Vector3.new(0, -1, 0))
	local avanti = rotMoto:VectorToWorldSpace(Vector3.new(0, 0, -1))
	local destra = rotMoto:VectorToWorldSpace(Vector3.new(1, 0, 0))

	-- misure del personaggio
	local L1b, L2b = lunghezze(g.RS, g.RE, g.RW)
	local mano = 0.25
	if g.RW then
		local presa = g.RW.Part1:FindFirstChild("RightGripAttachment")
		local pPresa = presa and presa.Position or Vector3.new(0, -g.RW.Part1.Size.Y * 0.5, 0)
		mano = (pPresa - g.RW.C1.Position).Magnitude
	end
	local braccio = L1b + L2b + mano
	local spessoreCoscia = g.RH.Part1.Size.Z * 0.5
	local centroAnche = (g.RH.C0.Position + g.LH.C0.Position) * 0.5
	local alzaBusto = (g.Waist.C0.Position - centroAnche).Magnitude -- dalle anche alla vita
	local spalleSuVita = g.RS.C0.Position - g.Waist.C1.Position -- dalla vita alla spalla (nel busto)

	-- manopole nel mondo (seguono il manubrio)
	local manD = sterzo * Posa.MANOPOLA
	local manS = sterzo * Vector3.new(-Posa.MANOPOLA.X, Posa.MANOPOLA.Y, Posa.MANOPOLA.Z)

	-- busto in avanti (guida normale) + movimenti
	local busto = math.rad(20) + (dyn.busto or 0)
	local rollio = dyn.rollio or 0

	-- dove sedersi: le anche stanno dietro alle pedane (ginocchia in avanti); tra -1,95 e -1,45
	-- scelgo il punto che lascia le braccia piegate (circa 75% di estensione)
	local zMigliore, errMin = -1.75, math.huge
	for k = 0, 10 do
		local z = -1.95 + k * 0.05
		local hz = Vector3.new(0, 0, z)
		local spalla = hz + Vector3.new(0, altezzaSella(z) + spessoreCoscia + alzaBusto
			+ spalleSuVita.Y * math.cos(busto), -spalleSuVita.Y * math.sin(busto))
		local dist = (spalla - Vector3.new(0, Posa.MANOPOLA.Y, Posa.MANOPOLA.Z)).Magnitude
		local errore = math.abs(dist - 0.75 * braccio)
		if errore < errMin then
			errMin, zMigliore = errore, z
		end
	end
	local zAnche = zMigliore + (dyn.scivola or 0)
	-- la sella e' morbida: il pilota ci affonda un po'
	local yAnche = altezzaSella(zAnche) + spessoreCoscia - 0.08 + (dyn.molleggio or 0)
	info.zAnche = zAnche

	-- bacino (LowerTorso): appoggiato sulla sella, ruotato col busto per meta'
	local rotBacino = rotMoto * CFrame.Angles(0, 0, rollio) * CFrame.Angles(-busto * 0.35, 0, 0)
	local posAnche = moto * Vector3.new(0, yAnche, zAnche)
	local cfBacino = CFrame.new(posAnche) * rotBacino * CFrame.new(-centroAnche)
	out[g.Root] = (hrpCF * g.Root.C0):Inverse() * cfBacino * g.Root.C1

	-- busto (UpperTorso)
	local rotBusto = rotMoto * CFrame.Angles(0, 0, rollio * 1.3) * CFrame.Angles(-busto, 0, 0)
	local cfBusto
	cfBusto, out[g.Waist] = segmento(cfBacino, g.Waist, rotBusto)

	-- testa: guarda avanti
	if g.Neck then
		local rotTesta = rotMoto * CFrame.Angles(0, 0, rollio * 0.6) * CFrame.Angles(-math.rad(6), 0, 0)
		local _, t = segmento(cfBusto, g.Neck, rotTesta)
		out[g.Neck] = t
	end

	-- braccia: polso un po' prima della manopola, cosi' la mano la stringe
	local function braccio1(j1, j2, j3, manopola, lato)
		local S = (cfBusto * j1.C0).Position
		local polso = manopola + (S - manopola).Unit * mano
		local polo = destra * lato * 0.55 + giu * 0.8 - avanti * 0.3
		-- mano: dorso in su, dita attorno alla manopola
		local dir = (manopola - S).Unit
		local rotMano = ruotaDaBasi(Vector3.new(0, -1, 0), Vector3.new(lato, 0, 0), dir, destra * lato)
		local _, cfMano = arto(out, cfBusto, j1, j2, j3, polso, polo, 1, rotMano)
		return cfMano
	end
	local cfManoD = braccio1(g.RS, g.RE, g.RW, manD, 1)
	local cfManoS = braccio1(g.LS, g.LE, g.LW, manS, -1)

	-- gambe: caviglia sopra la pedana, ginocchia in avanti e un po' in fuori (stringono la moto)
	local function gamba(j1, j2, j3, lato)
		local piede = j3 and j3.Part1
		local sopraSuola = piede and (j3.C1.Position.Y + piede.Size.Y * 0.5) or 0.25
		local dietro = piede and math.max(0, -j3.C1.Position.Z) or 0.15
		local p = Posa.PEDANA
		-- appoggio sull'avampiede: il tallone e' un po' alzato
		local bersaglio = moto * Vector3.new(p.X * lato, p.Y + sopraSuola + 0.08, p.Z + 0.18 + dietro)
		local polo = avanti * 1.0 + destra * lato * 0.45 - giu * 0.25
		local rotPiede = rotMoto * CFrame.Angles(-math.rad(12), lato * math.rad(6), 0)
		arto(out, cfBacino, j1, j2, j3, bersaglio, polo, -1, rotPiede)
		return bersaglio
	end
	info.caviglia = gamba(g.RH, g.RK, g.RA, 1)
	gamba(g.LH, g.LK, g.LA, -1)

	info.manD, info.manS = manD, manS
	info.cfManoD, info.cfManoS = cfManoD, cfManoS
	info.braccio = braccio
	return out, info
end

return Posa

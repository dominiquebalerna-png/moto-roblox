-- Prova la posa del pilota con un personaggio R15 finto (misure tipiche), a varie scale.
-- Uso: luau test/prova_posa.luau
local finto = require("./finto_roblox")
Vector3, CFrame = finto.Vector3, finto.CFrame
-- la posa viene incollata qui da esegui.sh (luau da riga di comando non legge file)
local Posa = (function()
--POSA--
end)()

local function parte(nome, sx, sy, sz, figli)
	return { Name = nome, Size = Vector3.new(sx, sy, sz), FindFirstChild = function(self, n) return figli and figli[n] end }
end
local function giunto(p1, c0, c1)
	return { Part1 = p1, C0 = CFrame.new(c0[1], c0[2], c0[3]), C1 = CFrame.new(c1[1], c1[2], c1[3]), Transform = CFrame.new() }
end

local function rig(h, w, d, conCaviglie, kg, km)
	kg, km = kg or 1, km or 1
	local function s(x, y, z) return { x * w, y * h, z * d } end
	local function sg(x, y, z) return { x * w, y * h * kg, z * d } end
	local function sm(x, y, z) return { x * w * km, y * h * km, z * d * km } end
	local mano = parte("RightHand", 0.6 * w * km, 0.4 * h * km, 0.6 * d * km, { RightGripAttachment = { Position = Vector3.new(0, -0.15 * h * km, 0) } })
	local manoS = parte("LeftHand", 0.6 * w * km, 0.4 * h * km, 0.6 * d * km, { LeftGripAttachment = { Position = Vector3.new(0, -0.15 * h * km, 0) } })
	local g = {
		hrp = { CFrame = CFrame.new() },
		Root = giunto(parte("LowerTorso", 2 * w, 0.4 * h, 1 * d), s(0, -0.2, 0), s(0, -0.2, 0)),
		Waist = giunto(parte("UpperTorso", 2 * w, 1.6 * h, 1 * d), s(0, 0.2, 0), s(0, -0.8, 0)),
		Neck = giunto(parte("Head", 1.2, 1.2, 1.2), s(0, 0.8, 0), s(0, -0.5, 0)),
		RS = giunto(parte("RightUpperArm", 1 * w, 1.17 * h, 1 * d), s(1.0, 0.56, 0), s(-0.5, 0.39, 0)),
		RE = giunto(parte("RightLowerArm", 1 * w, 1.05 * h, 1 * d), s(0, -0.33, 0), s(0, 0.2, 0)),
		RW = giunto(mano, s(0, -0.5, 0), sm(0, 0.12, 0)),
		LS = giunto(parte("LeftUpperArm", 1 * w, 1.17 * h, 1 * d), s(-1.0, 0.56, 0), s(0.5, 0.39, 0)),
		LE = giunto(parte("LeftLowerArm", 1 * w, 1.05 * h, 1 * d), s(0, -0.33, 0), s(0, 0.2, 0)),
		LW = giunto(manoS, s(0, -0.5, 0), sm(0, 0.12, 0)),
		RH = giunto(parte("RightUpperLeg", 1 * w, 1.22 * h * kg, 1 * d), s(0.5, -0.2, 0), sg(0, 0.42, 0)),
		RK = giunto(parte("RightLowerLeg", 1 * w, 1.19 * h * kg, 1 * d), sg(0, -0.33, 0), sg(0, 0.29, 0)),
		LH = giunto(parte("LeftUpperLeg", 1 * w, 1.22 * h * kg, 1 * d), s(-0.5, -0.2, 0), sg(0, 0.42, 0)),
		LK = giunto(parte("LeftLowerLeg", 1 * w, 1.19 * h * kg, 1 * d), sg(0, -0.33, 0), sg(0, 0.29, 0)),
	}
	if conCaviglie then
		g.RA = giunto(parte("RightFoot", 1 * w, 0.3 * h, 1.2 * d), sg(0, -0.55, 0), s(0, 0.1, 0))
		g.LA = giunto(parte("LeftFoot", 1 * w, 0.3 * h, 1.2 * d), sg(0, -0.55, 0), s(0, 0.1, 0))
	end
	return g
end

-- cinematica diretta: dove finiscono davvero le parti con i Transform calcolati
local function fk(g, T)
	local cf = {}
	local function pos(j, padreCF)
		local t = T[j] or CFrame.new()
		return padreCF * j.C0 * t * j.C1:Inverse()
	end
	cf.LT = pos(g.Root, g.hrp.CFrame)
	cf.UT = pos(g.Waist, cf.LT)
	cf.RUA = pos(g.RS, cf.UT); cf.RLA = pos(g.RE, cf.RUA)
	cf.LUA = pos(g.LS, cf.UT); cf.LLA = pos(g.LE, cf.LUA)
	if g.RW then cf.RH = pos(g.RW, cf.RLA); cf.LH = pos(g.LW, cf.LLA) end
	cf.RUL = pos(g.RH, cf.LT); cf.RLL = pos(g.RK, cf.RUL)
	cf.LUL = pos(g.LH, cf.LT); cf.LLL = pos(g.LK, cf.LUL)
	if g.RA then cf.RF = pos(g.RA, cf.RLL) end
	return cf
end

local errori = 0
local function controlla(cond, msg)
	if not cond then errori += 1; print("  ERRORE: " .. msg) end
end
local function f(v) return string.format("(%.2f, %.2f, %.2f)", v.X, v.Y, v.Z) end

-- nome, altezza, larghezza, profondita', caviglie, gambe, mani, scala moto, gambe lunghe abbastanza?
local casi = {
	{ "standard 1.0, moto 1.0", 1, 1, 1, true, 1, 1, 1, false },
	{ "quello del gioco: 1.15/0.8/0.8, gambe 1.22, mani 0.72, moto 1.08", 1.15, 0.8, 0.8, true, 1.22, 0.72, 1.08, true },
	{ "come il gioco ma senza caviglie", 1.15, 0.8, 0.8, false, 1.22, 0.72, 1.08, true },
	{ "basso 0.9, moto 1.08", 0.9, 1, 1, true, 1, 1, 1.08, false },
}
-- moto in un punto qualsiasi del mondo, girata e piegata, con lo sterzo girato
local motoCF = CFrame.new(10, 3, -4) * CFrame.Angles(0, math.rad(35), 0) * CFrame.Angles(math.rad(4), 0, math.rad(-15))
for _, caso in ipairs(casi) do
	local nome, h, w, d, cav = caso[1], caso[2], caso[3], caso[4], caso[5]
	local kg, km, K, lunghe = caso[6], caso[7], caso[8], caso[9]
	print("== " .. nome)
	local g = rig(h, w, d, cav, kg, km)
	-- hrp dove lo mette la sella (circa sopra la sella), qualsiasi posizione va bene
	g.hrp.CFrame = motoCF * CFrame.new(0, 3.5, -1.5)
	local sterzoLocale = CFrame.new(0, 2.4006, -3.8463) * CFrame.Angles(0, 0, 0)
	for _, angolo in ipairs({ 0, 20, -20 }) do
		local asse = CFrame.fromMatrix(Vector3.new(0, 2.4006, -3.8463) * K, Vector3.new(1, 0, 0), Vector3.new(0, 0.9136, 0.4066))
		local sterzo = motoCF * asse * CFrame.Angles(0, math.rad(angolo), 0) * asse:Inverse()
		local T, info = Posa.calcola(g, motoCF, sterzo, { busto = 0, scivola = 0, rollio = math.rad(-8) }, K)
		local p = fk(g, T)
		local loc = motoCF:Inverse()
		-- mani: punto di presa sulla manopola
		local presaD = p.RH * Vector3.new(0, -0.15 * h * km, 0)
		local presaS = p.LH * Vector3.new(0, -0.15 * h * km, 0)
		local eD = (presaD - info.manD).Magnitude
		local eS = (presaS - info.manS).Magnitude
		-- gomiti e ginocchia (nel sistema della moto)
		local gomitoD = loc * (p.RLA * g.RE.C1.Position)
		local ginD = loc * (p.RLL * g.RK.C1.Position)
		local ancaD = loc * (p.RUL * g.RH.C1.Position)
		print(string.format("  sterzo %3d: mani a %.3f / %.3f stud dalle manopole; gomito dx %s; ginocchio dx %s; anca %s",
			angolo, eD, eS, f(gomitoD), f(ginD), f(ancaD)))
		controlla(eD < 0.12 and eS < 0.12, "mani lontane dalle manopole")
		-- polso dritto: la mano continua l'avambraccio (come nel video), nocche in su
		local dita = -(p.RH.m[2])
		local avambraccio = -(p.RLA.m[2])
		local piegaPolso = math.deg(math.acos(math.clamp(dita:Dot(avambraccio), -1, 1)))
		local nocche = p.RH.m[1]:Dot(motoCF.m[2])
		if angolo == 0 then print(string.format("  polso piegato di %.0f gradi, dorso della mano verso l'alto %.2f", piegaPolso, nocche)) end
		controlla(piegaPolso < (lunghe and 25 or 35), string.format("polso piegato troppo (%.0f gradi)", piegaPolso))
		controlla(nocche > 0.4, "dorso della mano non verso l'alto")
		controlla(gomitoD.X > 0.55 and gomitoD.X < 1.75, "gomito destro troppo dentro o troppo fuori")
		if lunghe then
			controlla(ginD.Z < ancaD.Z - 0.3, "ginocchio non in avanti rispetto all'anca")
		end
		controlla(ginD.X > 0.5, "ginocchio dentro la moto")
		if cav then
			local cav3 = p.RF * g.RA.C1.Position
			local eC = (cav3 - info.caviglia).Magnitude
			local suola = loc * (p.RF * Vector3.new(0, -0.15 * h, 0))
			if lunghe then -- con le gambe corte (scala 1) i piedi non arrivano: va bene, restano tesi verso la pedana
				controlla(eC < 0.1, string.format("caviglia lontana dalla pedana (%.2f)", eC))
			end
			if angolo == 0 then print(string.format("  caviglia a %.3f dal bersaglio, suola dx %s (pedana a y 0.31)", eC, f(suola))) end
		else
			local fine = loc * (p.RLL * (g.RK.C1.Position - Vector3.new(0, g.RK.Part1.Size.Y * 0.9, 0)))
			if angolo == 0 then print("  fondo gamba dx " .. f(fine)) end
		end
		-- coscia sopra la sella: l'anca deve stare sopra la superficie
		controlla(ancaD.Y > 2.0 * K, "anca sotto la sella")
		if angolo == 0 then print(string.format("  seduto a z = %.2f, braccio lungo %.2f", info.zAnche, info.braccio)) end
	end
end
-- gas aperto e impennata: la mano deve restare sulla manopola, i piedi sulle pedane
do
	print("== gas aperto + impennata a 60 gradi (pilota del gioco)")
	local K = 1.08
	local g = rig(1.15, 0.8, 0.8, true, 1.22, 0.72)
	for _, caso in ipairs({ { 0, 0 }, { 60, 1 }, { 85, 1 } }) do
		local th = math.rad(caso[1])
		local moto = CFrame.new(0, 2, 0) * CFrame.Angles(th, 0, 0)
		g.hrp.CFrame = moto * CFrame.new(0, 3.5, -1.5)
		local asse = CFrame.fromMatrix(Vector3.new(0, 2.4006, -3.8463) * K, Vector3.new(1, 0, 0), Vector3.new(0, 0.9136, 0.4066))
		local sterzo = moto * asse * asse:Inverse()
		local dyn = { busto = th * 0.6, scivola = math.min(th, 1.2) * 0.3, rollio = 0, gas = caso[2] }
		local T, info = Posa.calcola(g, moto, sterzo, dyn, K)
		local p = fk(g, T)
		local eD = ((p.RH * Vector3.new(0, -0.15 * 1.15 * 0.72, 0)) - info.manD).Magnitude
		local eS = ((p.LH * Vector3.new(0, -0.15 * 1.15 * 0.72, 0)) - info.manS).Magnitude
		local eC = ((p.RF * g.RA.C1.Position) - info.caviglia).Magnitude
		local busto = math.deg(math.asin(math.clamp(-(p.UT.m[2]):Dot(Vector3.new(0, 0, 1)), -1, 1)))
		print(string.format("  impennata %d, gas %d: mani a %.3f / %.3f, caviglia a %.3f, busto inclinato in avanti (rispetto alla strada) %.0f gradi",
			caso[1], caso[2], eD, eS, eC, busto))
		controlla(eD < 0.12 and eS < 0.12, "mani lontane dalle manopole (impennata/gas)")
		controlla(eC < 0.15, "piede lontano dalla pedana (impennata)")
	end
end

print(errori == 0 and "TUTTO OK" or ("ERRORI: " .. errori))

-- JSON con le parti del pilota (moto ferma nell'origine) per disegnarlo sopra il modello 3D
do
	local g = rig(1.15, 0.8, 0.8, true, 1.22, 0.72)
	g.hrp.CFrame = CFrame.new(0, 3.5, -1.5)
	local dyn = { busto = 0, scivola = 0, rollio = 0 }
	local T = Posa.calcola(g, CFrame.new(), CFrame.new(), dyn, 1.08)
	local p = fk(g, T)
	local function voce(cfp, j, sx, sy, sz)
		local m = cfp.m
		return string.format('{"p":[%.4f,%.4f,%.4f],"r":[%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f],"s":[%.3f,%.3f,%.3f]}',
			cfp.p.X, cfp.p.Y, cfp.p.Z, m[1].X, m[1].Y, m[1].Z, m[2].X, m[2].Y, m[2].Z, m[3].X, m[3].Y, m[3].Z, sx, sy, sz)
	end
	local l = {}
	local function add(cfp, part) table.insert(l, voce(cfp, nil, part.Size.X, part.Size.Y, part.Size.Z)) end
	add(p.LT, g.Root.Part1); add(p.UT, g.Waist.Part1)
	add(p.UT * g.Neck.C0 * (T[g.Neck] or CFrame.new()) * g.Neck.C1:Inverse(), g.Neck.Part1)
	add(p.RUA, g.RS.Part1); add(p.RLA, g.RE.Part1); add(p.RH, g.RW.Part1)
	add(p.LUA, g.LS.Part1); add(p.LLA, g.LE.Part1); add(p.LH, g.LW.Part1)
	add(p.RUL, g.RH.Part1); add(p.RLL, g.RK.Part1); add(p.RF, g.RA.Part1)
	add(p.LUL, g.LH.Part1); add(p.LLL, g.LK.Part1)
	add(p.LLL * g.LA.C0 * (T[g.LA] or CFrame.new()) * g.LA.C1:Inverse(), g.LA.Part1)
	print("JSON[" .. table.concat(l, ",") .. "]")
end

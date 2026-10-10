-- MotoClient (LocalScript)
-- Dove va: StarterPlayer > StarterPlayerScripts
-- Guida della moto (versione base, senza impennata):
--   W = gas, S = freno, A / D = sterzo, E = scendi (anche Spazio).
-- Muove anche le parti di TUTTE le moto: ruote che girano, manubrio che sterza,
-- forcella e forcellone che ammortizzano, piega in curva.
-- Nell'Output le righe di questo script iniziano con [Moto].

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local VERSIONE = 2
local giocatore = Players.LocalPlayer
local cartella = Workspace:WaitForChild("Moto")
local eventoScendi = ReplicatedStorage:WaitForChild("MotoScendi")

-- geometria (uguale al MotoServer), in stud
local PASSO = 5.1536 -- distanza tra le ruote
local R_DIETRO = 1.19 -- raggio gomma dietro
local R_DAVANTI = 1.23 -- raggio gomma davanti
local TELAIO_ASSE = CFrame.new(0, -0.9, 2.6) -- dal centro del Telaio all'asse dietro

-- guida
local VEL_MAX = 95 -- stud/s (circa 95 km/h)
local ACCEL = 30
local FRENATA = 55
local ATTRITO = 3
local STERZO_MAX = math.rad(32) -- angolo di sterzo da fermo
local PIEGA_MAX = math.rad(48)

local NOMI_GIUNTI = { "Sterzo", "Forcella", "RuotaDavanti", "Forcellone", "RuotaDietro" }

-- ---------------------------------------------------------------- parti mobili (tutte le moto)

local stati = {} -- [moto] = stato grafico

local function statoDi(moto)
	local st = stati[moto]
	if st then
		return st
	end
	local g = {}
	for _, nome in ipairs(NOMI_GIUNTI) do
		local j = moto:FindFirstChild("Giunto_" .. nome, true)
		if not (j and j:IsA("Motor6D")) then
			return nil -- la moto non e' ancora arrivata tutta
		end
		g[nome] = j
	end
	local telaio = moto:FindFirstChild("Telaio")
	if not telaio then
		return nil
	end
	st = {
		giunti = g,
		telaio = telaio,
		giroDietro = 0,
		giroDavanti = 0,
		sterzo = 0,
		forc = 0.12, forcVel = 0, -- forcella: affondamento (stud)
		amm = 0.05, ammVel = 0, -- forcellone: affondamento (stud)
		velPrima = Vector3.zero,
	}
	stati[moto] = st
	print(string.format("[Moto] Client v%d: parti mobili collegate su %s (giunti: 5 su 5)", VERSIONE, moto.Name))
	return st
end

cartella.ChildRemoved:Connect(function(moto)
	stati[moto] = nil
end)

-- molla semplice: x va verso "obiettivo", con rimbalzo smorzato
local function molla(x, v, obiettivo, dt, k, c)
	local a = k * (obiettivo - x) - c * v
	v += a * dt
	x += v * dt
	return x, v
end

local function aggiornaGrafica(moto, st, dt, mia)
	local tel = st.telaio
	local cf = tel.CFrame
	local vel = tel.AssemblyLinearVelocity
	local velAvanti = vel:Dot(cf.LookVector)
	local accel = (vel - st.velPrima) / math.max(dt, 1 / 240)
	st.velPrima = vel

	-- ruote: giro = distanza / raggio (angolo negativo = rotola in avanti)
	st.giroDietro -= velAvanti / R_DIETRO * dt
	st.giroDavanti -= velAvanti / R_DAVANTI * dt

	-- sterzo: per la mia moto uso il comando, per le altre lo stimo dalla rotazione
	local sterzo
	if mia then
		sterzo = mia.angoloSterzo
	else
		local yaw = tel.AssemblyAngularVelocity:Dot(cf.UpVector)
		sterzo = math.atan(yaw * PASSO / math.max(math.abs(velAvanti), 2)) * math.sign(velAvanti + 0.01)
		sterzo = math.clamp(sterzo, -STERZO_MAX, STERZO_MAX)
	end
	st.sterzo += (sterzo - st.sterzo) * math.min(1, dt * 12)

	-- sospensioni: frenando affonda davanti, accelerando si siede dietro, i colpi verticali le comprimono
	local longit = accel:Dot(cf.LookVector) -- + accelera, - frena
	local vert = accel:Dot(cf.UpVector)
	local obForc = math.clamp(0.12 - longit * 0.006 + vert * 0.002, 0, 0.75)
	local obAmm = math.clamp(0.05 + longit * 0.003 + vert * 0.002, 0, 0.45)
	if mia and not mia.aTerra then
		obForc, obAmm = 0, 0 -- in aria le sospensioni si allungano
	end
	st.forc, st.forcVel = molla(st.forc, st.forcVel, obForc, dt, 180, 14)
	st.amm, st.ammVel = molla(st.amm, st.ammVel, obAmm, dt, 160, 13)
	st.forc = math.clamp(st.forc, 0, 0.8)
	st.amm = math.clamp(st.amm, 0, 0.5)

	local g = st.giunti
	g.RuotaDietro.Transform = CFrame.Angles(st.giroDietro, 0, 0)
	g.RuotaDavanti.Transform = CFrame.Angles(st.giroDavanti, 0, 0)
	g.Sterzo.Transform = CFrame.Angles(0, st.sterzo, 0)
	g.Forcella.Transform = CFrame.new(0, st.forc, 0)
	-- forcellone lungo 2,08 stud: alzare la ruota di "amm" = ruotarlo di amm/2,08
	g.Forcellone.Transform = CFrame.Angles(-st.amm / 2.08, 0, 0)
end

-- ---------------------------------------------------------------- guida (solo la mia moto)

local guida = nil -- stato della guida quando sono in sella

local function tasto(...)
	for _, k in ipairs({ ... }) do
		if UserInputService:IsKeyDown(k) then
			return true
		end
	end
	return false
end

local function parametriRaggi(moto)
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	local escludi = { cartella }
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl.Character then
			table.insert(escludi, pl.Character)
		end
	end
	p.FilterDescendantsInstances = escludi
	return p
end

local function iniziaGuida(moto)
	local tel = moto:WaitForChild("Telaio")
	local look = tel.CFrame.LookVector
	guida = {
		moto = moto,
		telaio = tel,
		orient = tel:WaitForChild("Orientamento"),
		vel = 0,
		yaw = math.atan2(-look.X, -look.Z),
		beccheggio = 0,
		piega = 0,
		sterzoIn = 0,
		angoloSterzo = 0,
		aTerra = true,
		raggi = parametriRaggi(moto),
		tempoRaggi = 0,
	}
	print("[Moto] Sei in sella a " .. moto.Name .. ". W gas, S freno, A/D sterzo, E scendi.")
end

local function fineGuida()
	if guida then
		print("[Moto] Sei sceso dalla moto")
	end
	guida = nil
	local cam = Workspace.CurrentCamera
	if cam then
		cam.FieldOfView = 70
	end
end

local function guidaPasso(dt)
	local g = guida
	local tel = g.telaio
	if tel.Anchored then
		return -- il server non mi ha ancora dato la moto
	end

	-- comandi
	local gas = tasto(Enum.KeyCode.W, Enum.KeyCode.Up) and 1 or 0
	local freno = tasto(Enum.KeyCode.S, Enum.KeyCode.Down) and 1 or 0
	local dx = tasto(Enum.KeyCode.D, Enum.KeyCode.Right) and 1 or 0
	local sx = tasto(Enum.KeyCode.A, Enum.KeyCode.Left) and 1 or 0
	g.sterzoIn += ((dx - sx) - g.sterzoIn) * math.min(1, dt * 6)

	-- velocita'
	local v = g.vel
	if gas > 0 then
		v += ACCEL * (1 - math.clamp(v / VEL_MAX, 0, 1)) * dt
	end
	if freno > 0 then
		if v > 0.5 then
			v -= FRENATA * dt
		else
			v = math.max(v - 8 * dt, -5) -- da fermo con S va piano all'indietro
		end
	end
	v -= math.sign(v) * math.min(math.abs(v), (ATTRITO + 0.004 * v * v) * dt)
	-- se sbatto contro un muro la velocita' vera e' piu' bassa: mi adeguo
	local velVera = tel.AssemblyLinearVelocity
	local avantiPiatto = Vector3.new(-math.sin(g.yaw), 0, -math.cos(g.yaw))
	local vVera = velVera:Dot(avantiPiatto)
	if v > 0 and vVera < v - 12 then
		v = math.max(vVera + 12, 0)
	end
	g.vel = v

	-- terreno: un raggio sotto ogni ruota
	local asse = tel.CFrame * TELAIO_ASSE
	local pDietro = asse.Position
	local pDavanti = pDietro + avantiPiatto * PASSO
	local giu = Vector3.new(0, -(R_DIETRO + 3), 0)
	local su = Vector3.new(0, 1.5, 0)
	local cDietro = Workspace:Raycast(pDietro + su, giu - su, g.raggi)
	local cDavanti = Workspace:Raycast(pDavanti + su, giu - su, g.raggi)
	local aTerra = cDietro ~= nil and (pDietro.Y - cDietro.Position.Y) < R_DIETRO + 0.6

	-- sterzo e piega (solo a terra)
	local sterzoMax = STERZO_MAX / (1 + math.abs(v) / 20)
	g.angoloSterzo = -g.sterzoIn * sterzoMax
	local yawRate = 0
	if aTerra then
		yawRate = v * math.tan(g.angoloSterzo) / PASSO
	end
	g.yaw += yawRate * dt
	local gravita = Workspace.Gravity
	local piegaOb = aTerra and math.clamp(math.atan(v * yawRate / gravita), -PIEGA_MAX, PIEGA_MAX) or g.piega * 0.98
	g.piega += (piegaOb - g.piega) * math.min(1, dt * 5)

	-- beccheggio dal terreno
	if aTerra and cDavanti then
		local ob = math.atan2(cDavanti.Position.Y - cDietro.Position.Y, PASSO)
		g.beccheggio += (ob - g.beccheggio) * math.min(1, dt * 12)
	end

	-- velocita' da dare al telaio
	local vy = velVera.Y
	if aTerra then
		local yOb = cDietro.Position.Y + R_DIETRO * math.cos(g.piega)
		vy = math.clamp((yOb - pDietro.Y) * 18, -40, 60) + v * math.sin(g.beccheggio)
	end
	local orizz = avantiPiatto * v * math.cos(g.beccheggio)
	tel.AssemblyLinearVelocity = Vector3.new(orizz.X, vy, orizz.Z)

	-- orientamento: direzione, beccheggio, piega
	g.orient.CFrame = CFrame.Angles(0, g.yaw, 0) * CFrame.Angles(g.beccheggio, 0, 0) * CFrame.Angles(0, 0, g.piega)
	g.aTerra = aTerra

	-- campo visivo che si allarga con la velocita'
	local cam = Workspace.CurrentCamera
	if cam then
		local fov = 70 + math.clamp(math.abs(v), 0, VEL_MAX) * 0.22
		cam.FieldOfView += (fov - cam.FieldOfView) * math.min(1, dt * 4)
	end
end

-- ---------------------------------------------------------------- salire / scendere

local function collegaPersonaggio(char)
	local hum = char:WaitForChild("Humanoid")
	hum.Seated:Connect(function(seduto, sedile)
		if seduto and sedile and sedile.Name == "Sella" and sedile:IsDescendantOf(cartella) then
			iniziaGuida(sedile.Parent)
		else
			fineGuida()
		end
	end)
	hum.Died:Connect(fineGuida)
end

if giocatore.Character then
	task.spawn(collegaPersonaggio, giocatore.Character)
end
giocatore.CharacterAdded:Connect(collegaPersonaggio)

UserInputService.InputBegan:Connect(function(input, giaUsato)
	if giaUsato then
		return
	end
	if input.KeyCode == Enum.KeyCode.E and guida then
		eventoScendi:FireServer()
	end
end)

-- ---------------------------------------------------------------- ciclo

RunService.Heartbeat:Connect(function(dt)
	if guida then
		if guida.moto.Parent ~= cartella then
			fineGuida()
		else
			guidaPasso(dt)
		end
	end
end)

RunService.RenderStepped:Connect(function(dt)
	for _, moto in ipairs(cartella:GetChildren()) do
		if moto:IsA("Model") then
			local st = statoDi(moto)
			if st then
				aggiornaGrafica(moto, st, dt, guida and guida.moto == moto and guida or nil)
			end
		end
	end
end)

print("[Moto] Client v" .. VERSIONE .. " avviato")

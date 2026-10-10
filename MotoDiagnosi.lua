-- MotoDiagnosi (LocalScript)
-- Dove va: StarterPlayer > StarterPlayerScripts
-- Non cambia niente nel gioco: stampa solo informazioni nell'Output (righe che iniziano con [Diag]).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local inizio = os.clock()

local function log(...)
	print(string.format("[Diag %.1fs]", os.clock() - inizio), ...)
end

local GIUNTI_STANDARD = {
	"Root", "Waist", "Neck",
	"RightShoulder", "RightElbow", "RightWrist",
	"LeftShoulder", "LeftElbow", "LeftWrist",
	"RightHip", "RightKnee", "RightAnkle",
	"LeftHip", "LeftKnee", "LeftAnkle",
}

local function nome(x)
	return x and x.Name or "nil"
end

local function elencaGiunti(char, titolo)
	local hum = char:FindFirstChildOfClass("Humanoid")
	log("==== " .. titolo .. " ====")
	log("RigType:", hum and hum.RigType.Name or "NESSUN Humanoid")

	local trovati = {}
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("JointInstance") then
			trovati[d.Name] = true
			log(string.format("%s '%s' in %s | Part0=%s Part1=%s | Enabled=%s",
				d.ClassName, d.Name, nome(d.Parent), nome(d.Part0), nome(d.Part1), tostring(d.Enabled)))
		elseif d:IsA("AnimationConstraint") or d:IsA("BallSocketConstraint") or d:IsA("HingeConstraint") then
			trovati[d.Name] = true
			log(string.format("%s '%s' in %s | Enabled=%s", d.ClassName, d.Name, nome(d.Parent), tostring(d.Enabled)))
		end
	end

	local mancanti = {}
	for _, g in ipairs(GIUNTI_STANDARD) do
		if not trovati[g] then
			table.insert(mancanti, g)
		end
	end
	log("Giunti standard MANCANTI:", #mancanti == 0 and "nessuno" or table.concat(mancanti, ", "))

	local animate = char:FindFirstChild("Animate")
	log("Script Animate presente:", animate ~= nil)
end

local function seguiPersonaggio(char)
	char:WaitForChild("Humanoid")
	task.wait(1)
	elencaGiunti(char, "Personaggio appena creato")

	-- Se qualcosa (es. ApplyDescription o il ragdoll) toglie o rimette i giunti, lo vediamo qui
	char.DescendantRemoving:Connect(function(d)
		if d:IsA("JointInstance") or d:IsA("AnimationConstraint") then
			log("RIMOSSO giunto:", d.ClassName, d.Name, "da", nome(d.Parent))
		elseif d:IsA("BasePart") then
			log("RIMOSSA parte del corpo:", d.Name)
		end
	end)
	char.DescendantAdded:Connect(function(d)
		if d:IsA("JointInstance") or d:IsA("AnimationConstraint") then
			task.defer(function()
				log("AGGIUNTO giunto:", d.ClassName, d.Name, "in", nome(d.Parent))
			end)
		elseif d:IsA("BasePart") then
			log("AGGIUNTA parte del corpo:", d.Name)
		end
	end)

	local hum = char:FindFirstChildOfClass("Humanoid")
	hum.Seated:Connect(function(seduto, sedile)
		log("Seated:", seduto, "sedile:", sedile and sedile:GetFullName() or "nil")
		if not seduto then
			return
		end
		task.wait(1)
		elencaGiunti(char, "Dopo essere salito in moto")

		-- Per 6 secondi controlliamo: chi muove le braccia? Le animazioni sono ferme?
		local spalla = char:FindFirstChild("RightShoulder", true)
		local animator = hum:FindFirstChildOfClass("Animator")
		for i = 1, 6 do
			if not hum.Sit then
				break
			end
			if spalla and spalla:IsA("Motor6D") then
				local c0 = spalla.C0
				local rx, ry, rz = c0:ToEulerAnglesXYZ()
				log(string.format("RightShoulder C0 rot = %d, %d, %d gradi | ancora nel personaggio: %s",
					math.deg(rx), math.deg(ry), math.deg(rz), tostring(spalla:IsDescendantOf(char))))
			else
				log("RightShoulder NON è un Motor6D (o non esiste):", spalla and spalla.ClassName or "nil")
			end
			if animator then
				local nomi = {}
				for _, traccia in ipairs(animator:GetPlayingAnimationTracks()) do
					table.insert(nomi, traccia.Name .. "(" .. traccia.Animation.AnimationId .. ")")
				end
				log("Animazioni in corso:", #nomi == 0 and "nessuna" or table.concat(nomi, " | "))
			end
			task.wait(1)
		end
	end)
end

if player.Character then
	task.spawn(seguiPersonaggio, player.Character)
end
player.CharacterAdded:Connect(seguiPersonaggio)
log("Diagnosi avviata per", player.Name)

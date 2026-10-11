-- Versione minima di Vector3 e CFrame di Roblox, per provare i calcoli fuori da Studio.
local V = {}
V.__index = V
local function v3(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V)
end
V.__add = function(a, b) return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V.__sub = function(a, b) return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V.__unm = function(a) return v3(-a.X, -a.Y, -a.Z) end
V.__mul = function(a, b)
	if type(a) == "number" then return v3(a * b.X, a * b.Y, a * b.Z) end
	if type(b) == "number" then return v3(a.X * b, a.Y * b, a.Z * b) end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V.__div = function(a, b) return v3(a.X / b, a.Y / b, a.Z / b) end
V.__index = function(t, k)
	if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z) end
	if k == "Unit" then local m = math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z); return v3(t.X / m, t.Y / m, t.Z / m) end
	return V[k]
end
function V.Dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
function V.Cross(a, b) return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X) end
local Vector3 = { new = v3, zero = v3(0, 0, 0), xAxis = v3(1, 0, 0), yAxis = v3(0, 1, 0), zAxis = v3(0, 0, 1) }

local C = {}
local function cf(p, m) -- m = colonne {r, u, b}
	return setmetatable({ p = p, m = m }, C)
end
local I = { v3(1, 0, 0), v3(0, 1, 0), v3(0, 0, 1) }
local function rot(m, v) return m[1] * v.X + m[2] * v.Y + m[3] * v.Z end
C.__mul = function(a, b)
	if getmetatable(b) == V then return a.p + rot(a.m, b) end
	return cf(a.p + rot(a.m, b.p), { rot(a.m, b.m[1]), rot(a.m, b.m[2]), rot(a.m, b.m[3]) })
end
C.__index = function(t, k)
	if k == "Position" then return t.p end
	if k == "Rotation" then return cf(v3(0, 0, 0), t.m) end
	if k == "RightVector" then return t.m[1] end
	if k == "UpVector" then return t.m[2] end
	if k == "LookVector" then return -t.m[3] end
	return C[k]
end
function C.Inverse(a)
	local m = a.m
	local mt = { v3(m[1].X, m[2].X, m[3].X), v3(m[1].Y, m[2].Y, m[3].Y), v3(m[1].Z, m[2].Z, m[3].Z) }
	return cf(-rot(mt, a.p), mt)
end
function C.VectorToWorldSpace(a, v) return rot(a.m, v) end
local CFrame = {}
function CFrame.new(x, y, z)
	if type(x) == "table" then return cf(x, I) end
	return cf(v3(x or 0, y or 0, z or 0), I)
end
function CFrame.fromMatrix(p, r, u, b)
	b = b or r:Cross(u)
	return cf(p, { r, u, b })
end
local function rx(a) local c, s = math.cos(a), math.sin(a); return cf(v3(), { v3(1, 0, 0), v3(0, c, s), v3(0, -s, c) }) end
local function ry(a) local c, s = math.cos(a), math.sin(a); return cf(v3(), { v3(c, 0, -s), v3(0, 1, 0), v3(s, 0, c) }) end
local function rz(a) local c, s = math.cos(a), math.sin(a); return cf(v3(), { v3(c, s, 0), v3(-s, c, 0), v3(0, 0, 1) }) end
function CFrame.Angles(x, y, z) return rx(x) * ry(y) * rz(z) end
function CFrame.fromAxisAngle(asse, ang)
	local u = asse.Unit
	local c, s = math.cos(ang), math.sin(ang)
	local function r(v) -- formula di Rodrigues
		return v * c + u:Cross(v) * s + u * (u:Dot(v) * (1 - c))
	end
	return cf(v3(0, 0, 0), { r(v3(1, 0, 0)), r(v3(0, 1, 0)), r(v3(0, 0, 1)) })
end

return { Vector3 = Vector3, CFrame = CFrame }

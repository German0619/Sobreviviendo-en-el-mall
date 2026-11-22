--!strict
-- Utilidades generales.

local Util = {}

function Util.deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value :: any do
		copy[Util.deepCopy(k)] = Util.deepCopy(v)
	end
	return (copy :: any) :: T
end

-- Rellena en `target` las claves que falten usando `template` (recursivo).
-- No sobrescribe valores existentes. Sirve para migrar datos guardados viejos.
function Util.reconcile(target: { [any]: any }, template: { [any]: any })
	for k, v in template do
		if target[k] == nil then
			target[k] = Util.deepCopy(v)
		elseif type(v) == "table" and type(target[k]) == "table" then
			Util.reconcile(target[k], v)
		end
	end
end

-- Elige una clave de `weights` ({ clave = peso }) al azar segun su peso.
function Util.weightedRandom<K>(weights: { [K]: number }, rng: Random?): K?
	local total = 0
	for _, w in weights do
		total += math.max(w, 0)
	end
	if total <= 0 then
		return nil
	end
	local roll = (rng or Random.new()):NextNumber(0, total)
	local last: K? = nil
	for key, w in weights do
		if w > 0 then
			last = key
			roll -= w
			if roll <= 0 then
				return key
			end
		end
	end
	return last
end

-- Convierte un texto en un nombre de atributo valido ("Patio de comidas" -> "Patio_de_comidas").
function Util.attributeKey(s: string): string
	return (string.gsub(s, "[^%w_]", "_"))
end

-- 12345 -> "$12,345"
function Util.formatMoney(amount: number): string
	local s = tostring(math.floor(amount))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return "$" .. formatted
end

-- Hora del juego (0..6) -> "12:00 AM", "3:30 AM", ...
function Util.formatGameHour(hour: number): string
	local h = math.floor(hour)
	local m = math.floor((hour - h) * 60)
	local displayH = if h == 0 then 12 else h
	return string.format("%d:%02d AM", displayH, m)
end

return Util

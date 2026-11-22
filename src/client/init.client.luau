--!strict
-- Punto de entrada del cliente. Arranca cada ModuleScript hijo que tenga Start().
-- (Fase 2+: HUD, Flashlight, MissionUI, ShopUI, ClassUI, Sounds)

for _, child in script:GetChildren() do
	if child:IsA("ModuleScript") then
		local ok, mod = pcall(require, child)
		if ok and type(mod) == "table" and type(mod.Start) == "function" then
			task.spawn(mod.Start)
		elseif not ok then
			warn("[Client] Error cargando", child.Name, mod)
		end
	end
end

print("[Client] Sobreviviendo en el Mall: cliente iniciado")

--!strict
-- Punto de entrada del cliente del LOBBY. Arranca cada ModuleScript hijo que tenga Start().
-- LobbyHUD: diamantes y botones laterales. LobbyPanels: registro de paneles.

for _, child in script:GetChildren() do
	if child:IsA("ModuleScript") then
		local ok, mod = pcall(require, child)
		if ok and type(mod) == "table" and type(mod.Start) == "function" then
			task.spawn(mod.Start)
		elseif not ok then
			warn("[LobbyClient] Error cargando", child.Name, mod)
		end
	end
end

print("[LobbyClient] Sobreviviendo en el Mall: cliente del lobby iniciado")

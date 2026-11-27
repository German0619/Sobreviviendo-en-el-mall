# Plan: zonas de servicio oscuras, sodas acumulables y hoja de ruta del documento de diseño

## Contexto

- El documento `Sobreviviendo_en_el_Mall.md` es la recopilación de diseño completa: lobby, enemigos por niveles, eventos, jefes y armas.
- Hay dos cambios inmediatos:
  1. **Zonas de servicio oscuras.** Bodega, servicio, almacén y oficinas deben estar a oscuras: son las zonas donde se juega con la linterna. Hoy están iluminadas con fluorescentes.
  2. **Sodas negativas acumulables.** Hoy solo hay una soda activa: `VendingService` usa la clave fija `"Soda"` en `PlayerStats.AddEffect` y una nueva reemplaza a la anterior.
     - Las negativas deben acumularse, cada una con su propio temporizador. Si se repite la misma, se suma el tiempo.
     - Las positivas siguen reemplazándose entre ellas.
- Además, el resto del documento se ordena en fases, de modo que cada fase deja el juego jugable y prepara la siguiente.

---

## Fase 1: zonas de servicio oscuras — [HECHO]

**Zonas afectadas:** Bodega, Servicio, Almacén alto, Oficinas, Escalera de servicio, Administración, Sala de descanso, Baños P2, Archivo y Sala de máquinas.

1. **`src/shared/Config.luau`:** añadir `Config.DarkZones = { ... }` con esa lista.
2. **`src/server/LightService.luau`:**
   - En `Start()`, marcar cada zona oscura con `LightService.SetReason(zone, "Ambient", true)`. Así `IsZoneDark` y `IsDarkAt` devuelven true:
     - el Maniquí solo se ve con la linterna, una bengala o visión nocturna (ya funciona así en `Mannequin:IsSeenBy`);
     - el HUD ya avisa con `Dark_<zona>`.
   - `ResetAll()` debe volver a aplicar la razón `"Ambient"`, porque ahora borra todas las razones.
   - Publicar `Ambient_<zona>` en GameState para que el HUD pueda distinguir "zona de servicio, usa la linterna" de un apagón.
3. **`src/server/MallBuilder.luau`** (`buildService`, `buildOffices`):
   - **Luces:** quitar los paneles fluorescentes `ceilingPanel(... cold)` de esas zonas. En su lugar, una función nueva `emergencyLight(cf)`: una luz de emergencia roja o ámbar, tenue (alcance ~10, brillo ~0.4), cada ~40 studs. No lleva el tag MallLight, así que siempre está encendida y no se puede "reparar".
   - **Lo que se mantiene:** los carteles de SALIDA (ya son luminosos), el brillo de los monitores de seguridad y administración, y la máquina de sodas de la sala de descanso.
   - **Misiones Reparar luces:** quitar sus tableros (`electricPanel`) en las zonas oscuras, porque no tienen sentido allí.
   - **Generadores:** cambiar `PowersZones` para que la misión siga teniendo efecto.
     - El generador de la planta baja pasa a alimentar `Patio de comidas,Entrada`.
     - El de la sala de máquinas pasa a alimentar `Cine,Zona de juegos`.
   - **Misiones que se quedan, pensadas para jugar con linterna:** basura al contenedor, cajas de reponer, desatascar baños, revisar cámaras, derrames y objetos perdidos.
4. **`src/enemies/Blackout.luau`:** en `ChooseZone`, excluir las zonas de `Config.DarkZones`, porque apagar una zona que ya está oscura no aporta nada.
5. **`src/client/HUD.luau`:** si la zona tiene `Ambient_`, mostrar "Zona de servicio sin luz: usa la linterna [F]" en vez del aviso de apagón.

### Ajustes extra — [HECHO]
- **Iluminación del mall al 40 %:** `Config.MallLightScale = 0.4`. `MallBuilder` multiplica el brillo de todas las luces del mapa al construirlo.
- **Linterna en línea recta:**
  - el cono es más estrecho (`Config.Flashlight.Angle` = 38);
  - el foco se coloca delante del pecho con un desplazamiento horizontal, para que no quede dentro del torso;
  - tu propio cuerpo no proyecta sombra en tu cliente;
  - una luz local (`FlashlightHitGlow`) va un poco separada de la superficie donde choca el haz y sigue el tamaño del círculo del cono, con alcance mínimo de 8 studs. Con calidad gráfica baja Roblox calcula la luz en bloques de unos 4 studs y una luz más pequeña desaparece: por eso antes no se veía al mirar al suelo ni al acercarse a algo;
  - el rayo sale de los ojos (la cámara) e ignora partes invisibles, y si estás pegado a una pared el foco se recorta para no quedar dentro de ella.
- **Baños detallados** (Servicio P1 y Baños P2), con funciones nuevas en `MallBuilder`:
  - `toilet`: tanque, taza con agua, tapa y toma de agua;
  - `stallRow`: cubículos con mamparas, puertas abiertas, portarrollos y barra superior. Uno está cerrado con un cartel "FUERA DE SERVICIO" y se ven zapatos bajo la puerta;
  - `urinal`: urinarios con mamparas;
  - `vanity`: encimera con lavabos, grifos, jaboneras y espejo (roto en P1);
  - secamanos, papelera, cubo con fregona, desagüe, manchas, charco y un fluorescente fundido;
  - azulejo en las paredes de P2.
  - Se mantienen las mismas misiones Desatascar: 3 en Servicio y 2 en Baños P2.
- **Casillero con cámara fija** (`src/client/Defense.luau`): al esconderte, la cámara mira al frente del casillero. Solo puedes asomarte un poco (±25° horizontal, ±12° vertical) y hay una leve respiración. Al salir vuelve la cámara normal.

## Fase 2: sodas negativas acumulables — [HECHO]

**Reglas:**
- **Positivas** (Turbo, Ojos de gato, Regeneración, Estamina infinita, y la soda a elección): un solo hueco. Una positiva nueva reemplaza a la anterior.
- **Negativas** (Pesadez, Visión borrosa, Cansancio):
  - cada una tiene su propio efecto y temporizador, y conviven entre sí y con la positiva;
  - repetir la misma suma tiempo: si quedaban 10 s y la nueva dura 20 s, quedan 30 s.
- Los modificadores ya se multiplican entre efectos en `PlayerStats.Compute`, así que Turbo y Pesadez juntos se compensan.
- Morir lo borra todo, como hasta ahora.

**Cambios:**
1. **`src/server/VendingService.luau` → `ApplyEffect`:**
   - Positiva: clave `"SodaPos"` en `PlayerStats.AddEffect` (reemplaza a la anterior). Borra el atributo de la positiva previa.
   - Negativa: clave `"Soda_" .. effectId`. Se guarda `negEndsAt[player][effectId]`.
     - Si ya está activa, la duración nueva es lo que le quedaba más la duración nueva.
     - Se vuelve a llamar a `AddEffect` con esa duración; su sistema de token ya descarta el temporizador viejo.
   - Atributos para el HUD: `SodaEnds_<effectId>` con el tiempo de servidor en que acaba, uno por efecto activo. Se quitan `SodaName`, `SodaEndsAt` y `SodaPositive`.
   - `clearSoda` (al morir o reaparecer) borra todos los `SodaEnds_*` y la tabla `negEndsAt`.
   - Aviso: "Visión borrosa +20 s (total 30 s)".
   - Actualizar el comentario de cabecera, que dice "Solo una soda activa a la vez".
2. **`src/client/HUD.luau`** (~línea 606): sustituir la etiqueta única de soda por una lista de todos los atributos `SodaEnds_*`.
   - Cada línea muestra el nombre (`Config.SodaEffects[id].DisplayName`) y el tiempo restante.
   - Verde si es positiva, rojo si es negativa, ordenadas por lo que les queda.
3. **`src/shared/Config.luau`:** actualizar los comentarios de `VendingMachines` y `SodaEffects`. No hacen falta datos nuevos: ya existe `Positive`.
4. **`src/client/Effects.luau`:** no hay cambios. Ya reacciona a `Flag_BlurryVision` y los demás flags, que `PlayerStats.publishFlags` publica con varios efectos a la vez.

---

## Hoja de ruta del documento (fases siguientes; cada una se planifica en detalle al empezarla)

**Ya hecho según el documento:**
- Clases y ruleta con probabilidades visibles.
- Slots hasta 5.
- Reemplazo automático de la clase.
- Diamantes ganados y comprados por separado (`DataService.PaidDiamonds`), y regla de azar restringido.
- Tienda de Robux: diamantes, slot, x2 billetes, linterna premium.
- Salas públicas y privadas con viaje conjunto.
- Enemigos de nivel 1 a 3: Maniquí, Apagón, Eco, Rastro y Vigilante.
- Revivir y soda a elección en el mall.
- Logros básicos, que ya dan diamantes.
- Defensas: destello, bengala, petardo, escondites y porrazo.
- Mapa de 2 pisos.

**Fase 3: director de aparición por presupuesto.** Base de todo lo demás. — [HECHO] (probado en una noche real del mall: plan impreso una sola vez, aparición escalonada)
- Implementado en `src/server/SpawnDirector.luau` (plan puro, probado con 200 planes por caso) y `EnemyService.StartNight`. Valores en `Config.SpawnDirector`, `Config.Enemies[x].Tier/MaxPerFloor` y `Config.Floors`.
- Curva inicial: noche 1 → 3 enemigos; noche 5 con 2 jugadores → ~9; noche 7 con 4 → ~16; desde ~noche 10 con 5 jugadores se llenan los topes (17–18).
- El aviso de contramedida sale la primera vez que aparece cada tipo en la partida (ya no depende de `UnlockNight`).
- Sustituye a `Config.getEnemyCount` y a `EnemyService.spawnEnemy`:
  - cada enemigo tiene un nivel 1–3 con coste 1, 3 o 6;
  - el presupuesto crece con la noche y con los jugadores;
  - se sortea por los porcentajes de la tabla del documento;
  - topes: como mucho 1 o 2 de nivel 3, y un máximo por tipo y piso;
  - cada enemigo se asigna a un piso según dónde estén los jugadores;
  - el aviso de la primera aparición se mantiene.
- Primero con los 5 enemigos actuales.

**Fase 4: armas gratuitas.** — [HECHO] (`src/server/WeaponService.luau`, `Config.Weapons`; tecla [R] / botón táctil)
- Probado en el mall: taser (aturde 10 s, gasta usos y enfriamiento), trapeador (empuja 7 studs), extintor (nube), cartel (trampa) y linterna UV (haz morado, más consumo). Al morir se pierde el arma.
- Falta comprobar jugando: que la nube ciegue y que el cartel frene (las zonas se probaron solas), la UV contra el Eco y el taser contra el Vigilante (nivel 3).
- Para la Fase 7: la Estatua usará `Config.Enemies.<x>.TaserImmune = true`; los enemigos nuevos pueden definir `OnTaser` y `OnUV` (el Reflejo y el Mímico, revelables con UV).
- Van antes que los enemigos nuevos porque son sus contramedidas.
- Un hueco de arma con su tecla, compra con billetes en la tienda del mall, se pierde al morir, con enfriamientos.
- Taser (10 usos), extintor, cartel de piso mojado (trampa), linterna UV (revela al Reflejo, al Mímico y al Eco) y trapeador.
- Se reutilizan `DefenseService` (aturdir, empujar) y `ShopService`.

**Fase 5: enemigos nuevos de nivel 1.** — [HECHO] (`src/enemies/Cart.luau`, `Moth.luau`, `Balloon.luau`; `Config.Enemies.Cart/Balloon/Moth`)
- Carrito (desde la noche 2): embiste y queda aturdido si choca con una pared.
  - Al verte tiembla 0,9 s y embiste en línea recta (42 studs/s, unos 55 studs, 30 de daño una vez).
  - Si choca con una pared queda aturdido 4 s.
  - Solo embiste si te ve también a la altura de los pies, para no chocar con patas de bancos.
  - El destello y el porrazo lo aturden.
- Globo (desde la noche 3): revienta si lo miras y atrae enemigos.
  - Si lo miras fijamente unos 3 s (cono de 15°) se hincha y revienta; el estallido es un señuelo que atrae a los enemigos en 90 studs.
  - A oscuras solo cuenta como mirarlo si lo alumbras, hay una bengala o tienes visión nocturna.
  - El taser, el destello o el porrazo lo revientan en silencio si estás a 15 studs o más; de cerca hace ruido.
  - Reaparece en otro sitio a los 45 s.
- Polillas (desde la noche 4): persiguen la linterna y le drenan la batería.
  - Persiguen la linterna encendida y chupan 5 de batería por segundo; no hacen daño.
  - Si la apagas te pierden a los 3 s.
  - Prefieren una bengala; el petardo las atrae si no persiguen a nadie; el destello las dispersa 15 s.
- Probado en el mall:
  - Carrito: carga, golpe único y parada.
  - Globo: se hincha y revienta al mirarlo; a oscuras no.
  - Polillas: persecución, drenaje y huida al apagar la linterna.
- Falta probar jugando: Polillas con la bengala y el destello; el Carrito chocando con una pared tras el arreglo de los pies.

**Fase 6: enemigos nuevos de nivel 2.** — [HECHO] (`src/enemies/Reflection.luau`, `Duct.luau`, `Cashier.luau`, `Intercom.luau`; `Config.Enemies.Reflection/Duct/Cashier/Intercom`)
- Tags nuevos en `Tags.luau`, que pone `MallBuilder`; en un mapa hecho a mano hay que ponerlos en Studio:
  - `ReflectiveSurface`: vidrios de los escaparates y espejos de los baños.
  - `CeilingVent`: rejillas de las tiendas, más 20 nuevas en los techos de los pasillos de las dos plantas.
- Reflejo (desde la noche 4): aparece en vidrios y escaparates.
  - Es una silueta semitransparente pegada a un cristal cerca de un jugador, y cambia de cristal cada ~12 s.
  - Si la miras fijamente 1,5 s (cono de 20°; a oscuras hay que alumbrarla), sale y te persigue 12 s: 30 de daño y desaparece.
  - El destello la devuelve a los cristales; la UV la marca a través de las paredes; el porrazo y el taser la aturden.
- Ducto (desde la noche 5): va por las rejillas del techo.
  - Se oye por dentro del techo y oye a quien corre a menos de 55 studs.
  - Al llegar a la rejilla la hace temblar 1,3 s (con aviso en pantalla), cae, se queda agazapado 0,8 s y persigue 7 s: 35 de daño.
  - Es negro con ojos naranjas que dan luz; tras golpear vuelve al techo.
  - Caminar no lo atrae; el destello, el porrazo y el taser lo hacen subir; el petardo lo hace bajar donde explota.
- Cajero (desde la noche 4): roba billetes.
  - Persigue a quien ve con 10 billetes o más y le roba el 30%; luego huye 14 s.
  - Si lo aturdes en ese tiempo, el dinero vuelve a su dueño; si no, se pierde. No hace daño.
- Megafonía (desde la noche 6): anuncia misiones falsas.
  - Sin cuerpo: cada 45–70 s anuncia una tarea falsa con el mismo aviso y el mismo "!" que las reales, a 40–120 studs de los jugadores.
  - Al acercarte salta una alarma que atrae a los enemigos en 110 studs.
  - No sale en la lista de tareas del HUD; el destello borra la marca y la UV la marca como "FALSA".
- Probado jugando: los cuatro funcionan.

**Fase 7: enemigos nuevos de nivel 3.** — [HECHO] (`src/enemies/Statue.luau`, `Mimic.luau`, `Hunter.luau`; `src/shared/EntityModels.luau`; `Config.Enemies.Statue/Mimic/Hunter`)
- Modelos del mapa que cobran vida: la Estatua y los Maniquíes.
  - Son modelos del mapa (`EntityModels`: la Estatua, y el Maniquí con la plantilla `EnemyTemplates.Mannequin` si existe), con los tags `FountainStatue` y `DisplayMannequin`.
  - El enemigo toma el modelo del mapa (`Common.claimMapModel`) y, al terminar la noche, lo devuelve a su sitio (`HomeCFrame`).
  - En el lobby, `PlazaService` pone la misma estatua en la fuente de la plaza y sube la luna hasta sus manos.
- `SpawnDirector` admite `MaxTotal` (tope de un tipo en todo el mall).
- `Config.Debug.Tier3MaxOverride` sirve para probar varios de nivel 3 a la vez.
- Estatua de la fuente (desde la noche 6, `MaxTotal` 1): solo la frenan las bengalas.
  - Despierta en la fuente central (ojos rojos, tiembla) y salta al suelo.
  - Te siente a través de las paredes (110 studs). Va a 9,5, más lenta que caminar, pero no para; 50 de daño.
  - Solo la frena la luz de una bengala: no entra en ella y se queda de piedra.
  - Es inmune al destello, a los empujones, al taser y a los petardos.
- Mímico (desde la noche 8, `MaxTotal` 2): una máquina expendedora viva.
  - Se esconde en una de las máquinas que ya existen, sin crear una nueva, y no se mueve.
  - Muerde (60) al intentar comprar (`VendingService.MimicTriggered`) o al quedarse delante 2,5 s; después cambia de máquina, lejos de los jugadores.
  - Pistas: con alguien cerca, sus luces parpadean y gotea por la bandeja.
  - La UV, el destello, el taser y los empujones le hacen enseñar los dientes; el destello lo deja 3 s sin morder.
- Cazador (desde la noche 9, `MaxTotal` 1): marca al jugador más solo.
  - Es alto, lleva sombrero y un farol rojo.
  - Marca al jugador más solo (contorno rojo y aviso) y lo persigue sabiendo dónde está (a 15,5); 45 de daño, y luego desaparece y vuelve lejos.
  - La marca se rompe si te juntas 3 s con otro jugador, si te escondes con él a más de 25 studs, o a los 35 s.
- Probado jugando: el Maniquí del escaparate, la Estatua, el Mímico y el Cazador.

**Fase 8: director de eventos.** — [HECHO] (partes 1 y 2) (`src/server/EventDirector.luau`, `src/server/Events/*`, `Config.EventDirector`, `Config.Events`)
- Director:
  - Un evento cada 2–3 minutos, con máximo 1 activo, enfriamiento por evento y planta asignada (la de más jugadores, con azar).
  - Eventos por noche, decididos al empezarla (`PerNight`):
    - noches 1–4: como mucho 1 (65 %);
    - noches 5–10: como mucho 2 (70 % cada uno);
    - noche 11 en adelante: 3, con 2 negativos asegurados.
  - Pesos: los negativos ×1,25; los positivos pierden un 6 % por noche (mínimo ×0,35). Los más fuertes tienen menos peso base.
- Aviso: texto morado, dos pitidos (graves si es malo, agudos si es bueno) y una línea bajo el reloj con nombre, planta y tiempo. Va debajo de la línea de habilidades.
- Misiones de evento (`MissionService.StartEventMission`):
  - no cuentan para la cuota, no pagan y no avanzan el reloj;
  - salen arriba de la lista, en morado, "sin pago";
  - si caducan, el evento sigue.
- Para probar: `Config.Debug.OnlyEvents` (no repite hasta que salen todos) y `EventDelayOverride`; también `EventDirector.Force(id)`.
- Eventos hechos (10), todos probados jugando:
  - **Apagón general:** todo el mall a oscuras hasta reiniciar los generadores principales; máximo 4 min.
  - **Neblina:** niebla clásica de Lighting (`FogEnd` 38; la Atmosphere se quita mientras dura) durante 90 s; los enemigos ven un 40 % menos.
  - **Baterías débiles:** las linternas gastan el doble durante 2 min.
  - **Oleada:** enemigos de nivel 1 en una planta durante 60 s (3 más 1 cada 3 noches, máximo 8).
  - **Jugador marcado:** atrae a los enemigos con un señuelo que le sigue; se anula juntándose 1,5 s con un compañero.
  - **Megafonía hackeada:** una Megafonía que anuncia tareas falsas cada 20–30 s durante 2 min.
  - **Alarma de incendio:** rociadores en un círculo de 40 studs junto a un jugador; dentro vas al 60 % y se apagan las bengalas; apagar el panel más cercano lo termina.
  - **Hora de oro:** tareas ×2 (la lista muestra "x2") y enemigos un 15 % más rápidos durante 2 min.
  - **Suministros:** caja con bengala, batería y botiquín para quien la abre.
  - **Cámaras amigas:** usar los monitores revela a todas las entidades 10 s a través de las paredes.
- Parte 2 [HECHO] (5 eventos más, todos probados jugando; utilidades en `Events/EventUtil`):
  - **Piso aislado:**
    - rejas en el extremo de cada escalera (tag nuevo `FloorConnector`) en una planta;
    - desbloquear una reja (15 s, desde los dos lados) las abre todas; se abren solas a los 7,5 min.
  - **Persianas cerradas:**
    - 6 tiendas de la planta se sellan hasta el suelo, con colisión;
    - cada una se abre con su misión (también desde dentro); se abren solas a los 2,5 min;
    - la misión normal Bajar persianas no toca una persiana sellada (`EventSealed`).
  - **Mercader nocturno:** 60 s con 3 ofertas al azar de 12, cada una con su botón E.
    - Armas mejoradas: Taser de 20 usos, Extintor de 12, Carteles de 6, UV rebajada; también la Linterna Pro rebajada.
    - Exclusivos (`MerchantOnly`, `Config.MerchantOrder`): Botiquín grande, Bengala de magnesio, Batería de litio, Petardo gordo, Bomba de humo y Soda misteriosa.
  - **Maletín perdido:**
    - aparece en una zona oscura; llevarlo te deja al 75 % de velocidad;
    - entregarlo en Objetos perdidos da 500; si mueres, cae al suelo.
  - **Tienda abierta:**
    - la persiana baja y sube, y dentro hay 3 bolsas de billetes;
    - al entrar salta una alarma que atrae a los enemigos 15 s.
- Ajustes hechos de paso:
  - Cartel de piso mojado: el caballete ya no sale invertido; deja a los enemigos al 30 % en un radio de 9.
  - Revivir pagando (Robux o ficha): 20 s en los que los enemigos te ignoran y no te hacen daño (`ProtectedUntil`). Se ve como un contorno azul suave y "PROTEGIDO" en el HUD.

**Fase 9: jefes cada 5 noches.** — [HECHO] (`src/server/BossService.luau`, `src/server/Bosses/*`, `src/client/BossAlert.luau`, `Config.Bosses`; cuerpos en `src/enemies/Luni|Manager|Collector|Converted`)
- Noche de jefe (cada 5 noches, en el orden de `Config.Bosses.Order`, de más fácil a más difícil):
  - mitad de enemigos y mitad de tareas, y sin eventos al azar;
  - las misiones del jefe son misiones de evento (no pagan ni avanzan el reloj);
  - para ganar hay que completar las tareas y vencer al jefe (el reloj se queda en 5:59 mientras viva);
  - alerta en pantalla, latido grave de música (`MusicSoundId` para poner una de verdad) y progreso bajo el reloj.
- Al vencerlo:
  - billetes para todos;
  - `Lifetime.BossesDefeated` (tabla "Jefes vencidos") y `Lifetime.Boss_<Id>`;
  - un logro por jefe.
- Para probar: `Config.Debug.ForceBoss`.
- Jefes (todos probados jugando):
  - **Luni** (noche 5, 400 billetes, logro de 150 diamantes):
    - mascota gigante que corre detrás del grupo más numeroso; el destello, el taser y los empujones solo la frenan;
    - se vence atrayéndola al cuarto del generador y activando el apagón de sector con ella dentro (3 s en equipo, 0,5 s jugando solo).
  - **El Gerente** (noche 10, 500 billetes, 250 diamantes):
    - con su walkie pide refuerzos de nivel 1 y 2 cada 30 s (tantos como radios le quedan; duran 50 s; Reflejo sí, Cajero no) y cierra persianas;
    - se vence destruyendo sus 3 radios.
  - **El Coleccionista** (noche 15, 600 billetes, 350 diamantes):
    - un caído que no revivan en 30 s se convierte en un maniquí enemigo con su nombre, y él va un 15 % más rápido por cada uno;
    - se vence llevando 3 objetos perdidos a los pedestales de sus tiendas.
  - **La Central** (noche 20, 800 billetes, 500 diamantes):
    - IA sin cuerpo: las cámaras la avisan y atraen enemigos; apaga luces, cierra persianas y anuncia tareas falsas;
    - se vence reiniciando 3 servidores en plantas distintas antes de que acabe la cuenta atrás (30 s en equipo, 120 s solo).
- [PROGRAMADO, falta probar] Noche 25 en adelante: el documento dice que los jefes se repiten "con más vida y velocidad y mecánicas combinadas" (p. ej. Luni junto al Gerente). Decidido el 2026-11-24:
  - **Parejas** (`Config.Bosses.Pairs`): 25 Luni + Gerente, 30 Gerente + Coleccionista, 35 Coleccionista + Central, 40 Central + Luni, y se repiten. Hay que vencer a los dos; cada uno da su premio y cuenta para su logro.
  - **Refuerzo por vuelta** (`Config.Bosses.Scaling`; vuelta 1 = noches 25–40, vuelta 2 = 45–60…): +15 % de velocidad (tope +60 %) y +1 objetivo (tope +3). El objetivo es `ExtraField`: radios del Gerente, objetos del Coleccionista, servidores de la Central y apagones de Luni (tras cada apagón se recupera a los 10 s y el siguiente es en otro generador). Las órdenes del Gerente y las acciones de la Central también son más frecuentes (`FasterFields`).
  - Los objetivos dicen el número reforzado (`{n}` en `Objective`; Luni usa `ObjectiveMany`). En el HUD, con dos jefes, el progreso de cada uno va en su línea y los avisos bajan para no taparlo; el cartel de alerta muestra los dos objetivos.

**Fase 10: lobby completo.**
- [HECHO] Cuadros de sala físicos (`PadService` + `PadUI`): se entra solo subiéndose, no se sale caminando (solo saltando) y salir del cuadro es salir de la sala.
- [HECHO] Inicio automático a los 40 s (o al llenarse, o con INICIAR PARTIDA del anfitrión).
- [HECHO] Puesto de CLASES (panel nativo `ClassPanel`). El puesto de MEJORAS abre las mejoras permanentes (`PermanentPanel`): ver *Tiendas del lobby* abajo.
- [HECHO] Tablas de clasificación (noche récord y jefes vencidos) con OrderedDataStore (`LeaderboardService`).
- [HECHO] Panel de logros con "!" (`AchievementService` + `AchievementsPanel`): 12 logros que se reclaman.
- [HECHO] Giro automático hasta una clase.
- [HECHO] Tiro afortunado con Robux, que garantiza una clase épica o superior.
- [HECHO] Ventajas VIP: 50 💎 diarios (cuentan como comprados), ruleta 20% más barata, [VIP] en el chat y cuadro dorado.

### Tiendas del lobby (decidido el 2026-11-23)

Las cuatro ideas se usan, **cada una en su propia tienda**. Todas con paneles nativos (`NativeUI`) y abiertas desde un puesto de la plaza (tag `LobbyStand` + círculo de luz en el suelo).

| Tienda | Dónde | Qué vende | Moneda | Depende de |
|---|---|---|---|---|
| **Mejoras permanentes** | Puesto **MEJORAS** (ya existe) | Ventajas pequeñas que se conservan en todas las partidas | Diamantes | Nada: se puede hacer ya |
| **Maestría de clase** | Dentro del puesto **CLASES** | Niveles de cada clase, que suben jugándola | Se gana jugando | Nada |
| **Taquilla del conserje** | Puesto nuevo en la plaza | Consumibles que te esperan al empezar la próxima partida | Diamantes | Objetos del mall (baterías, botiquines, bengalas ya existen) |
| **Caja de cosméticos** — [HECHO en la Fase 11] | Puestos CAJA y SKINS | Skins de linterna y de armas, con rarezas | Diamantes / Robux | Fase 4 (armas) y Fase 11 (skins) |

1. **Mejoras permanentes** (puesto MEJORAS):
   - Pocos niveles y efecto pequeño por nivel, con topes bajos: es una ventaja que se puede comprar, porque los diamantes se venden con Robux.
   - Ejemplos: +3% de vida por nivel (hasta 5), +5% de batería por nivel, billetes extra al empezar cada partida, un botiquín gratis al empezar.
   - Datos: `data.PermanentUpgrades[id] = nivel`. El mall los aplica en `PlayerStats.Compute` (multiplicadores) y al iniciar la partida (billetes y objetos iniciales).
   - Antes de programarla, proponer una tabla de mejoras con niveles y costos para ajustarla.
   - [HECHO] (`PermanentUpgradeService`, `src/client/PermanentPanel.luau`, `Config.PermanentUpgrades`). Tabla elegida (2026-11-24, la versión ~40% más barata, unos 8900 💎 en total):
     - Vida reforzada: +3% de vida por nivel, 5 niveles (90 · 180 · 300 · 480 · 720).
     - Buen aliento: +4% de estamina por nivel, 5 niveles (60 · 120 · 210 · 330 · 480).
     - Pila de repuesto: +5% de batería por nivel, 5 niveles (60 · 120 · 210 · 330 · 480).
     - Paso ligero: +2% de velocidad por nivel, 3 niveles (400 · 900 · 1600).
     - Adelanto de sueldo: +50 billetes al empezar cada partida por nivel, 4 niveles (90 · 180 · 300 · 480).
     - Kit de inicio: batería, luego + botiquín, luego + bengala al empezar cada partida, 3 niveles (120 · 240 · 420).
   - **Reinicio con Robux** (producto `PermanentReset`, 99 R$): quita los niveles y devuelve el 100% de lo gastado como **puntos de mejora** (`data.UpgradePoints`), que solo sirven para volver a comprar mejoras y se gastan antes que los diamantes.
2. **Maestría de clase** (puesto CLASES):
   - Cada clase sube de nivel al jugar con ella y mejora un poco su bonificación (p. ej. Corredor nivel 3: +15% de velocidad en vez de +10%).
   - La maestría se guarda **por clase** (`data.ClassMastery[clase]`), así no se pierde aunque la ruleta reemplace la clase del slot.
   - [HECHO] (`Config.ClassMastery`, `ClassService.OnNightSurvived`, `PlayerStats`, detalle de `ClassPanel`). Decidido el 2026-11-24:
     - 1 noche de maestría por cada noche sobrevivida con la clase equipada; niveles a las 3 · 8 · 15 · 25 · 40 noches.
     - Sin recompensa extra al subir: solo un aviso y la mejora de la clase.
     - Por nivel: Conserje y Conserje experimentado +2% de vida, estamina y batería · Corredor +1% de velocidad · Atleta +4% de estamina · Electricista +0.1 de reparación · Guardia +4% de vida · Ahorrador +2% de pago · Visión nocturna +5% de batería · Médium +3% de vida · Sombra +0.1 de detección · Médico +0.2 al revivir · Guardián lunar +2% de vida, estamina y velocidad.
3. **Taquilla del conserje** (puesto nuevo):
   - Consumibles comprados con diamantes que se entregan al empezar la próxima partida y se gastan al usarlos.
   - Datos: `data.Locker[itemId] = cantidad`. El mall los entrega al iniciar la partida y los descuenta.
   - No tiene azar.
   - [HECHO] (`LockerService`, `src/client/LockerPanel.luau`, `Config.Locker`; puesto `LockerStand` en x=−55, z=−60, frente a la CAJA). Decidido el 2026-11-24:
     - Solo objetos normales: batería 15 💎, petardo 15 💎, bengala 20 💎, botiquín 25 💎; hasta 10 guardados de cada uno. Los exclusivos del mercader no se venden.
     - Al empezar cada partida se entrega 1 de cada objeto guardado (si cabe en la mochila); el resto espera a la siguiente.
4. **Caja de cosméticos** (puesto nuevo, junto con la Fase 11):
   - Solo estética, sin ventaja de juego.
   - Es un objeto aleatorio: probabilidades siempre visibles y respetar `PaidRandomItemsRestricted`, igual que la ruleta.

**Plaza:** hay que añadir en Studio dos puestos nuevos (Taquilla y Cosméticos) con el tag `LobbyStand`, su `PromptPart` y su círculo de luz (`FloorGlow`).

**Orden sugerido:** Mejoras permanentes → Maestría de clase → Taquilla del conserje → Caja de cosméticos (con la Fase 11).

**Fase 11: monetización de armas** — [HECHO] (probado jugando)
- Parte 1: **modelos en la mano** (`src/shared/HeldModels.luau`).
  - 16 modelos (armas, objetos de la mochila y linterna) y las piezas que pintan las skins.
  - Los demás los ven en tus manos: la herramienta en la derecha y la linterna en la izquierda.
  - Tú los ves con `src/client/ViewModel.luau`, una copia local delante de la cámara; los reales se esconden solo para ti.
- Parte 2: **armas con Robux** (IDs en `Config.GamePasses` / `Config.DevProducts`).
  - **Taser infinito** (pase, 199 R$): el taser no gasta usos.
  - **Recarga de taser** (producto, 15 R$): +10 usos, con un botón en la tienda del mall.
  - **Fumigador de entidades** (pase, 350 R$, `FumigatorService`):
    - 1 uso por noche, rociando al enemigo sin moverte 2, 4 u 8 s según su nivel;
    - el enemigo no vuelve en toda la noche;
    - no sirve con jefes ni con la Megafonía.
- Parte 3: **skins** (`CosmeticsService`, `src/client/CosmeticsPanel.luau`, `Config.Skins`, `Config.Cosmetics`).
  - 6 skins (Camuflaje, Blanco hielo, Carmesí, Neón, Dorado y Luna) para la linterna y las 5 armas.
  - Puesto **CAJA** (x=55, z=−60):
    - 250 💎 o 79 R$ (producto `CosmeticSpin`) por giro;
    - probabilidades visibles (Común 55 %, Rara 30 %, Épica 12 %, Legendaria 3 %);
    - repetida = +100 💎;
    - respeta `PaidRandomRestricted`.
  - Puesto **SKINS** (centro): compra directa (300, 600, 1200 o 2500 💎) y equipar una skin por objeto.
  - Datos: `data.Skins`, `data.EquippedSkins`; el mall las lee de `Skin_<objeto>`.
- [HECHO] Que las skins también cambien el color de los efectos de las armas (rayo del taser, nube del extintor...). (2026-11-24: cada skin tiene un color de efecto, `Config.Skins[...].Effect`; rayo y destello del taser, nube y chorro del extintor teñidos, cartel con el color y material de la skin y charco teñido, onda del trapeador, haz UV mezclado a medias y luz de la linterna con un toque del 20 %, `Config.SkinEffects`.)

**Fase 12: interfaz adaptable (PC, teléfono, tablet y consola).** — [HECHO] (2026-11-24)
Que toda la interfaz use las herramientas nativas de Roblox para adaptarse a cada pantalla y control.

*Hecho el 2026-11-24 (probado con el simulador en Galaxy A06, iPhone 17 Pro, iPad Pro M5 y Xbox One):*
- Ya existían `UIKit.adapt` (escala y notch) e `InputHints` (teclas según el control) en toda la UI del mall, y la mochila nativa para los objetos.
- **Solo horizontal** (`LandscapeSensor`), fijado en `init.client` y reaplicado al aparecer el personaje.
- **Botones táctiles** (`src/client/TouchButtons.luau`): en dos arcos alrededor del botón de saltar (correr, linterna y destello cerca; habilidad o escondite, mejoras y lobby fuera). Antes, en el Galaxy A06, correr quedaba debajo del de saltar y lobby y destello se salían de pantalla.
- **Ventanas** (`UIKit.window`): se encogen hasta caber en la pantalla; la tienda baja de alto y usa su scroll. La X mide al menos 44 px reales en táctil.
- **Texto mínimo** en táctil: los textos fijos crecen hacia 10 px reales, solo hasta donde caben en su caja.
- **Consola**: la UI se ve 1.3 veces más grande (hasta 1.7).
- Ajustes tras revisarlo el usuario: en **teléfono** el bloque central (hora, noche, fase y habilidades) es más pequeño y está más arriba (`UIKit.isPhone`), y las columnas izquierda (barras) y derecha (billetes, tareas) van pegadas bajo la barra de Roblox (las líneas vacías de sodas y arma ya no dejan hueco); en **tablet** los botones táctiles miden al menos el 55 % del botón de saltar (66 px en el iPad Pro).
- Tienda: filas más altas con la descripción en dos líneas (antes se cortaba en todas las pantallas).
- Pendiente de revisar jugando: la lista de tareas con muchas tareas en un teléfono pequeño, y los márgenes de la tele en consola (*overscan*).

*Estado actual (revisado el 2026-11-22):*
- Toda la UI se crea por código en `src/client` (HUD, ClassUI, LobbyUI, RoomUI, ShopUI, SodaUI, StoreUI, UpgradeUI, Defense) con el helper `UIKit`.
- Los tamaños son en píxeles fijos: unos 100 `fromOffset` frente a casi ningún tamaño proporcional.
- No hay `UIScale` ni `UIAspectRatioConstraint`, y no se usa `ScreenInsets` para el notch.
- Los textos muestran teclas de PC ([F], [G], [P], [L], [U], [C], [1]-[4], [Espacio]/[E]) también en el teléfono.
- Botones táctiles: tienen botón Linterna, Destello, Habilidad, Correr y Mejoras. No lo tienen Iniciar partida [P] ni los objetos [1]-[4]; falta comprobar Volver al lobby [L] y Clases [C].
- El juego permite cualquier orientación (`ScreenOrientation = Sensor`). Un teléfono pequeño deja unos 705×338 de pantalla útil (Galaxy A06).
- *Nota (2026-11-23):* la UI nueva del lobby (`LobbyHUD`, `PadUI`, `ClassPanel`, `ShopPanel`, `AchievementsPanel`) ya nació adaptable con `NativeUI` (tamaños en Scale con límites y `ScreenInsets`). Lo pendiente es la UI del mall.

*Cambios:*
1. **`UIKit.screen(nombre)`**, un helper común para crear cada `ScreenGui`:
   - `ScreenInsets = DeviceSafeInsets`, para no quedar bajo el notch ni la barra;
   - un `UIScale` que se ajusta al tamaño de pantalla (`ViewportSize`), con diseño base 1280×720 y límites de 0.6 a 1.25; en consola, algo más grande para leer desde el sofá.
   - Así la UI en píxeles se adapta sin rehacer cada pantalla.
2. **Ventanas** (`UIKit.window`):
   - tamaño máximo relativo a la pantalla (`UISizeConstraint` + escala);
   - contenido con `ScrollingFrame` cuando no quepa;
   - botón de cerrar de al menos 44×44 en táctil.
3. **Textos de teclas según el dispositivo:** un módulo `InputHints` que use `UserInputService.PreferredInput` (o `TouchEnabled`/`GamepadEnabled`):
   - PC muestra "[F]";
   - teléfono muestra el icono o el texto del botón táctil ("toca LUZ");
   - mando muestra el botón (R1, X…).
   - El HUD y las ventanas lo consultan en vez de escribir "[F]" a mano.
4. **Botones táctiles para todas las acciones:**
   - poner `createTouchButton = true` en Iniciar partida, Volver al lobby y Clases;
   - hacer tocables las ranuras de objetos [1]-[4] de la barra inferior;
   - colocar los botones de `ContextActionService` (`SetPosition`) en un arco junto al botón de saltar, sin taparse;
   - salir del escondite con un botón visible en táctil.
5. **HUD:**
   - barras y textos con `AutomaticSize` y `TextScaled` + `UITextSizeConstraint` (mínimo legible);
   - en pantallas bajas, la lista de tareas y la de sodas se compactan o se pliegan.
6. **Orientación:** decidir entre fijar horizontal (`LandscapeSensor`, lo más simple para un juego en primera persona) o soportar vertical con un diseño propio. Recomendado: solo horizontal.

*Verificación:* simulador de dispositivos de Studio en Play con un teléfono pequeño (Galaxy A06, 800×360), un iPhone con notch (17 Pro), una tablet (iPad Pro 13") y una consola (Xbox, 1080p). En cada una, revisar:
- que nada quede fuera de pantalla ni bajo el notch;
- que el texto no se corte;
- que los botones midan al menos 44 px;
- que cada acción tenga botón táctil y que los textos de teclas cambien según el dispositivo.

**Fase 13: pulido** (la última; es el punto 10 de `plan sobreviviendo en el mall.txt`).
- Sonido, ambientación, balance y pruebas con varios jugadores.
  - [HECHO] (probado jugando) Sonido y ambientación (2026-11-25). Todos los audios en `Config.Sounds` (gratuitos de la Creator Store: APM, Pro Sound Effects, DistroKid, o incluidos en Roblox). Sin música de persecución (decisión del usuario).
    - Música por fase con fundido (`client/Audio`): lobby, espera/preparación (volumen bajo, 0.18), noche, noche avanzada desde la 10, resultados; el jefe tiene su pista (`Config.Bosses.MusicSoundId`, BossAlert); golpe al perder.
    - Ambiente del mall: zumbido de fluorescentes, eco de nave de noche y sonidos sueltos al azar a tu alrededor (goteos, metal, crujidos, voces).
    - Enemigos (`server/EnemySounds`, desde EnemyService): bucle (siempre o al andar), voz al azar y golpe al atacar.
    - Acciones: `server/SfxService` (PlayAt 3D para armas, defensas, escondites, revivir; PlayFor / remote `PlaySfx` para comprar, recoger, tareas); campanas al empezar la noche, sonido a las 6 AM y al morir.
  - [HECHO] (probado jugando) Iluminación de terror que empeora noche a noche (`Config.Lighting`, `LightService`): de la noche 1 (luz normal) a la 7 (`FullFromNight`) las lámparas se tiñen de fluorescente amarillo verdoso y alumbran menos, la pantalla gana contraste y pierde color, y de noche hay tubos muertos y tubos que parpadean con chispazo cerca de los jugadores (a veces se mueren). Todo en proporción a la noche.
  - [HECHO] (probado jugando) Animaciones de ataque para todos los enemigos (2026-11-25). El daño llega igual que antes (no cambia la dificultad); `Common.playAttack(model)` pone el atributo `AttackAt` y `EnemyAnimator` hace la pose segun el estilo: Swipe (zarpazo: Cazador, Reflejo, Vigilante, Coleccionista, Luni, Gerente con el brazo libre, Apagon que ademas se abalanza), Grab (agarre rigido: Maniqui y convertidos), Pounce (salto del Rastro), Raise (patas delanteras del Ducto). Eco estira los brazos (hombros `Motor6D.C0`) y se esfuma al terminar; el Cazador tambien espera al final del golpe. Cajero: los billetes vuelan a su ranura con un "ding". Estatua, Mimico y Carrito ya tenian el suyo.
- [HECHO] (probado jugando) Mejorar el diseño de las entidades hechas con piezas (2026-11-25; el usuario pidió todas las que se vieran simples, con piezas y no con mallas de IA).
  - Globo (gota con cara pintada, brillo, nudo y cordel rizado), Polillas (5 polillas con alas, manchas y antenas), Carrito (cesta de rejilla, chasis, ruedas con radios, compras, placa PLAZA LUNA), Cajero (letrero, visera, camara, teclado, boca con dientes y billetes, pegatina, patas con piston y garras), Ducto (costillas, columna, mandibula con dientes, 6 ojos, 6 patas con garras, cola), Cazador (solapas, cinturon, gancho, bufanda, botas, guantes con garras, farol con marco), Reflejo (dedos larguisimos, pelo, sonrisa que brilla con los ojos, trozos de espejo), Gerente (traje completo, placa GERENTE, gafas, llaves, auricular), Coleccionista (chistera, gorguera, mascara pintada y agrietada, vitrina con figuritas y correas), Luni (luna llena sin la bola oscura, gorro de dormir, gorguera, LUNI y estrellas, guantes, zapatones, crateres y boca con dientes) y Mimico (colmillos, encias, lengua y pupilas).
  - Estatua rehecha a peticion del usuario (imagen de referencia): un guerrero/golem de piedra con casco, capa y un hacha doble levantada delante con las manos en el pomo; ojos y runas naranjas al despertar. Camina con las piernas (EnemyAnimation "Golem"). El chorro de la fuente del mall sale del pomo (`STATUE_HANDS_Y`); la luna del lobby flota sobre el casco (`STATUE_TOP_Y`).
  - Hachazo de la Estatua: brazos y hacha soldados a un eje en los hombros (`AxeRig`, `EntityModels.setStatueSwing`). Levanta el hacha (aviso, `SwingWindup`), la deja caer (`SwingStrike`; daña si sigues delante a `SwingReach`) y la recupera (`SwingRecover`). No anda mientras tanto; una bengala lo cancela.
- [HECHO] (probado jugando) Los enemigos que caminan suben como mucho 1.8 studs de un paso (`MAX_STEP` en `Common`): la Estatua ya no se sube al techo de los puestos.
- [HECHO] (probado jugando) Eco copia el aspecto de un jugador de la partida (2026-11-25): `Players:CreateHumanoidModelFromDescription` con su avatar (ropa, accesorios, cara) y su nombre encima como el de un jugador; nunca copia a su presa y jugando solo te copia a ti. Cambia de aspecto cada vez que desaparece. Anda con las animaciones de Roblox; al alumbrarlo es una silueta negra (Highlight) con ojos blancos. Ya no usa la plantilla de malla del conserje ni EnemyAnimator.
  - Los 5 de malla (Eco, Apagon, Maniqui, Vigilante, Rastro) se dejan como estan: ya son los mas detallados.
  - Rendimiento: los detalles llevan el atributo `Detail` (soldado a la raiz) o `Follow` (soldado a esa extremidad) y `Common.prepareModel` los suelda sin anclar; el servidor solo mueve las piezas principales. `EnemyAnimator` ignora las piezas no ancladas.
  - `Common.getHeight` mide del pivote a lo mas bajo: un sombrero que sobresale ya no hace flotar al enemigo.
- [HECHO] (probado jugando) Animaciones de movimiento para todas las entidades que no las tienen, como el Maniquí. (2026-11-24, `src/server/EnemyAnimator.luau`, `Config.EnemyAnimation`.)
  - En el servidor (los enemigos son modelos anclados), después de que cada enemigo se mueve: extremidades reconocidas por el nombre de la pieza, giradas sobre su articulación según lo que avanza; quietos no se mueven.
  - Bípedos (Eco, Cazador, Gerente, Reflejo, Vigilante, Luni, Cajero) con brazos y piernas alternos; lo que llevan en la mano o los pies (walkie, linterna, guantes, zapatos) sigue a su extremidad. Maniquí rígido y a tirones. Coleccionista solo brazos. Rastro a cuatro patas, Ducto patas de araña, Carrito ruedas.
  - Las plantillas de una sola pieza del mall (`ServerStorage.EnemyTemplates`: Eco, Apagón, Maniquí, Vigilante, Rastro) se separaron en piezas con `segment_mesh` (IA de Studio): Torso, LeftArm, RightArm, LeftLeg, RightLeg (el Rastro, FrontLeftLeg…; el Apagón, LowerBody). Las originales quedan en `ServerStorage.EnemyTemplatesBackup`. **Hay que guardar el place del mall** para conservarlas.
  - Eco y Apagón: estilo Flotante (siempre se mecen ±0,3 studs, brazos colgando que se balancean y se inclinan al desplazarse).
  - Si un modelo sigue siendo de una pieza (p. ej. un maniquí del mapa), el cuerpo entero se balancea sobre los pies al andar.
  - Al acabar la noche las piezas vuelven a su pose de reposo (los maniquíes y la estatua vuelven al mapa).
- [HECHO] Ruleta de clases: el resultado aparece en el slot antes de que la ruleta se pare. Debe mostrarse solo cuando termine el giro. (`ClassPanel` muestra la clase anterior en slots y carrete hasta que termina la animación, también en el tiro afortunado.)
- [HECHO] (probado jugando; hay que GUARDAR el place del lobby para conservarlo) Mejorar el diseño del lobby (2026-11-25). Hecho en el place del lobby (no en el código):
  - Materiales PBR generados con IA en MaterialService (LobbyFloorTile1, LobbyAisleMarble1, LobbyWallPanel, LobbyCeilingTile3, LobbyWalnut, LobbyGranite1, LobbyBrushedSteel1, LobbyShutter) aplicados a suelo, pasillo, paredes, techo, persianas, marcos, columnas, barandillas, balcones, puestos, bancos, macetas y punto de aparición.
  - Iluminación: atardecer (ClockTime 18.3) que se ve por el tragaluz, luz ambiente cálida, exposición +0.25, lámparas más fuertes, bloom suave; se quitaron 2 cielos duplicados.
  - Cuadros de sala: base de mármol azul y dorado; muros de cristal tintado con una tira de neón arriba (carpeta Glow: PadService la colorea por estado). Misma altura (no se sale caminando).
  - `Workspace.Lobby.Details`: columnas con base, anillo de latón, capitel y carteles iluminados; luz indirecta violeta bajo los balcones y cálida en lo alto de las paredes; fuente con agua visible (antes peleaba con el borde), aro de granito, luces bajo el agua y anillo de latón en el suelo; 4 estandartes de Plaza Luna; papeleras; directorio junto a la entrada.
  - Ajustes pedidos por el usuario (2026-11-25, probados):
    - Brillo del lobby: exposición −0.1 (antes +0.25), luz ambiente más baja, bloom 0.4; lámparas del techo sobre las tiendas 1.1 y de los balcones 0.8 (antes 2.2); persianas y lamas de las tiendas cerradas en gris oscuro; paredes un poco menos blancas.
    - Puestos (CLASES, MEJORAS, SKINS, CAJA, TAQUILLA): toldo y mostrador oscuros en vez de blancos, el borde del mostrador ya no es neón, círculo del suelo más tenue (0.75), foco 0.7 y luz del cartel 0.45.
    - Cuadros de sala: base azul liso (SmoothPlastic, sin mármol). Los muros de cristal con la tira de color por estado se quedan.
    - Fuente con el agua del mall: el vaso macizo pasa a ser muro de mármol + fondo de azulejo azul con monedas; dos láminas con el material `Mall_FountainWater2` (copiado al MaterialService del lobby) que giran en sentidos opuestos, agua sobre el plato con cortina que cae del borde, bruma y focos bajo el agua que titilan. `WaterFX` ya arranca en el lobby y `PlazaService` pone el chorro entre las manos de la Estatua.
- [HECHO] (probado jugando) Mejorar el diseño de la ruleta de clases (2026-11-25, con la imagen de referencia del usuario). `ClassPanel`: lista de probabilidades a la izquierda, RUEDA en el centro (un sector por clase con el color de su rareza y solo su nombre, flecha arriba, GIRAR en el centro con su precio, aro con remaches; gira 5 vueltas y frena en la clase que salio, con un clic por sector; el nombre ganador parpadea) y detalle con "Girar hasta" y tiro afortunado a la derecha. Los sectores se rellenan por anillos de barras (sin mezclar colores con el vecino).
- [HECHO] (probado jugando) Balance tras jugar de 3 (2026-11-25: imposible pasar la noche 2; demasiados enemigos al principio y los maniquíes te ven lejísimos y no te sueltan).
  - Dificultad progresiva (`Config.Difficulty`, `Config.getDifficulty`): noche 1 al 60 % de velocidad, 40 % de daño y visión a la mitad (45 studs); sube hasta lo normal en la noche 8 y la velocidad sigue +5 %/noche después. Daño en `Common.damage`, visión en `Common.canSee` (`Common.SetDifficulty` desde EnemyService).
  - Te sueltan (`Config.Detection.GiveUp*`, `Awareness:ShouldGiveUp`): tras 15 s persiguiéndote o si les sacas 45 studs (y 10 más de lo que llegaron a acercarse); luego te ignoran 10 s. Todos los que usan la detección común; la Estatua nunca suelta, y la marca del Cazador y el olor del Rastro van aparte.
  - Menos enemigos (`Config.SpawnDirector.Budget` 1 + 1/noche, +20 % por jugador extra): con 3 jugadores noche 1 = 2, noche 2 = 4, noche 3 = 6, noche 5 = 10 (antes 5, 8, 12, 20).
- [HECHO] (probado jugando) Mapa y misiones (pedido el 2026-11-25):
  - **Visión nocturna**: en las zonas sin luz se seguía viendo negro (la corrección de color no aclara el negro). Ahora `client/Effects` también sube la luz ambiente y la exposición solo en tu pantalla mientras la tienes (soda o clase) y las devuelve al quitarla.
  - **Lista de tareas** (`Config.MissionSpawn`, `Config.getVisibleMissions`, `MissionService`): siempre 3 a la vez (4 con 3 jugadores o más), nunca más de las que faltan para la cuota (si faltan 2, se ven 2: las sobrantes que nadie empezó se retiran sin penalización). Al completar o fallar una, sale otra a los 4 s.
  - **Estacionamiento abierto** (`MallBuilder.buildParking`): las puertas de vidrio de la Entrada quedan abiertas; zona "Estacionamiento" vallada (no se salta), 6 farolas que cuentan como luces de la zona (el Apagón las apaga, Reparar luces en el tablero de la fachada), 6 coches (2 con la puerta abierta = escondites "Coche"), corral de carritos, contenedor (vale para Sacar la basura), derrames, objeto perdido, cámara y 2 puntos de aparición de enemigos.
  - **Misiones nuevas**: Rellenar máquina (caja de refrescos de un palet → máquina), Reiniciar cajas (3 cajas registradoras de un ala), Apagar escaparates (3 pantallas de escaparate de un ala; se encienden la noche siguiente), Recoger bandejas (3 bandejas de las mesas → cubo del patio), Juntar carritos (3 carritos del estacionamiento → corral).
  - **Misiones progresivas** (fábrica `Missions/Sequence`: solo se ve el siguiente punto y la lista dice su zona): Ronda de seguridad (fichar en orden en 3 relojes de control de zonas distintas y de las dos plantas; 10 relojes) y Entrega de paquete (recoger en un palet → mostrador de una tienda de la otra planta → firmar el albarán en Administración). 240 s y 90 de pago.
- [HECHO] (probado jugando) No revivir y ver a un compañero (2026-11-25): botón "No revivir · ver a un compañero" en la pantalla de muerte (`client/Spectate`). Cámara en tercera persona detrás de un compañero vivo; ◀ / ▶ (o Q / E, L1 / R1) para cambiar y "Volver" para regresar a la pantalla de muerte. El cuerpo sigue revivible (Médico o Robux). Se corta solo al revivir, al acabar la noche o si no queda nadie en pie.
- [HECHO] (probado jugando) Misiones, tanda 2 (2026-11-25):
  - Cerrar grifos (3 grifos de un baño con agua y sonido; si caduca, charco que huele el Rastro), Reiniciar recreativas (3 máquinas con música y luces que atraen enemigos), Apagar proyector (mantener E en el panel del fondo de la sala de cine), Revisar extintores (3 de una planta; recarga tu extintor), Teléfono sonando (la lista dice "Sigue el timbre"; marcador solo a 25 studs), Vaciar papeleras (3 de un ala → contenedor), Inventario (3 tiendas en orden → Administración), Purgar la caldera (3 válvulas en orden, de las dos plantas → mantener E en la caldera, con vapor).
  - Sonidos nuevos en `Config.Sounds.Missions` (elegidos por nombre en la Creator Store).
  - `Multi` admite `OnActivate`/`OnFail`; `WeaponService.Refill`; `Cleanup` recibe `silent` (al retirar una tarea sin fallar no deja charco).
- [HECHO] (probado jugando) Sonido de las alarmas (2026-11-25): la misión Apagar alarma no sonaba y el evento Alarma de incendio usaba un pitido provisional. Los primeros timbres sonaban a teléfono (pausas entre timbres): ahora sonidos continuos, `Config.Sounds.Missions.Alarm` (alarma de 2 tonos rápida) y `FireAlarm` (pitidos rápidos continuos), de Pro Sound Effects.
- [HECHO] (probado jugando) Música del lobby al 40 % (0.35 → 0.14): se oía demasiado fuerte.
- [HECHO] (probado jugando) Agrandar el mall (2026-11-25). Construido en Edit sin errores (13 850 piezas, zonas sin duplicar); falta jugarlo.
  - **Planta alta más ancha**: el hueco del atrio pasa de 24 a 12 (`VOID` 12 → 6); los pasillos altos miden 14 en vez de 8. Más luces bajo y sobre los pasillos; bancos y maceteros recolocados; los puentes son cortos (allí llegan las escaleras).
  - **Pasajes**: donde estaban las tiendas del centro de la galería (columna 3) se abre un pasaje a cada ala en las dos plantas. Esas 4 tiendas se mudaron al Ala Norte.
  - **Ala Norte** (iluminada, z 110..207): cruza el servicio y las oficinas (puertas de personal a los lados). Los baños de la planta baja se movieron al oeste del pasaje y las salas de las oficinas se reorganizaron (Administración, Descanso | Baños P2, Archivo, Máquinas). 4 tiendas por planta (Juguetería Pipo, Óptica Visión, Relojería Tic Tac, Gimnasio Titán, Salón Glamour, Bici Ruta) y 2 **cerradas y a oscuras** (Novias Azahar, Disfraces Carnaval: persiana a media altura, sábanas, maniquíes).
  - **Pasillo de servicio** (a oscuras): detrás de las tiendas del Ala Norte, con puertas traseras de cada tienda, un pasillo al fondo con escalera entre plantas (ruta para escapar dando la vuelta) y, en planta baja, puertas al servicio y a la oficina de seguridad.
  - **Ala Sur en obras** (toda a oscuras, z -167..-70): valla de obra en la entrada, plásticos colgando que tapan la vista (los enemigos ven a través), andamios, material, cables; 4 locales en obras por planta ("Próxima apertura", baño portátil o armario de obra como escondite).
  - **Grandes almacenes cerrados** "Almacenes Estrella" (z -227..-167, 2 plantas, a oscuras): percheros y muebles con sábanas, maniquíes (algunos del enemigo Maniquí), probadores, pancarta de liquidación y **escaleras mecánicas paradas** que unen las plantas.
  - **Misiones nuevas**: Desenchufar herramientas (obra: 3 herramientas encendidas con ruido, chispas y foco que falla; atraen enemigos), Tapar maniquíes (grandes almacenes: los maniquíes destapados se han girado solos), Luces de emergencia (pasillo de servicio: cambiar 3 baterías deja el pasillo algo iluminado hasta la noche siguiente). Además, las alas tienen los puntos de las misiones de siempre.
  - Directorio actualizado con las alas. `Config.MapScale` (1.5) sin tocar: con el mapa más grande los enemigos se reparten más; subir si se queda fácil.
- [HECHO] Borrada `Workspace.VistaPreviaEnemigos` del place del mall (2026-11-25). Para que dure, hay que guardar/publicar el place del mall.
- [HECHO] (probado jugando) Entidad nueva: **La Garra** (idea del usuario, 2026-11-25). `server/ClawService`, `client/ClawFX`, `Config.Claw`.
  - Desde la noche 3. Cuando el equipo deja caducar 3 tareas en la noche, se agarra al jugador vivo con menos tareas completadas esa noche (empate: al azar).
  - Sin cuerpo: en su pantalla, dos manos monstruosas (imagen dibujada para el juego, `assets/icons/claw_hand.png`), una desde abajo y otra desde arriba con los dedos encajados, se cierran despacio sobre la cámara durante el minuto mientras la oscuridad de los bordes se cierra como un túnel (rediseño 2026-11-25: la primera versión se movía de lado a lado muy rápido y no se entendía). Respiración y latido que se acelera, y arriba "LA GARRA · 0/2 tareas · 0:42". Al matar, las manos se cierran de golpe. Los demás le ven con un contorno rojo oscuro.
  - Tiene 60 s para completar 2 tareas ÉL MISMO; si no, muere (zarpazos rojos en pantalla) y se le puede revivir como siempre (Médico o Robux).
  - Se va si las completa, si se llega a la cuota, si cae por otra cosa o al acabar la noche. Al irse, la cuenta de falladas vuelve a 0 (otras 3 y vuelve); las falladas mientras está agarrada no cuentan.
  - Prueba: `Config.Debug.ClawGrabOnStart` (segundos tras empezar la noche: se agarra sola), `Config.Debug.ClawFailsOverride` (1 = se agarra con la primera fallada, desde cualquier noche) o `game.ServerStorage.DebugClaw:Invoke()` en la barra de comandos del servidor durante la noche. Avisos `[Garra]` en la salida.
- [HECHO] (probado jugando) Pantalla de carga (2026-11-25; antes se veía todo negro al entrar). `src/first/LoadingScreen.client.luau` en ReplicatedFirst (nuevo en `default.project.json`), la misma en el lobby y en el mall:
  - Fondo azul noche, luna creciente y "PLAZA LUNA" que parpadean como un fluorescente, barra de progreso con el paso ("Despertando a los maniquíes...") y un consejo al azar cada 5 s.
  - Espera a que cargue el juego, a que exista el mapa (`Workspace.Mall` o `Workspace.Lobby`), a tu personaje y a que bajen las descargas pendientes (máx. 8 s); se ve al menos 2.5 s y se desvanece.
  - También en los viajes lobby ↔ mall (`TeleportService:SetTeleportGui`): al llegar la reemplaza la del place sin que se vea negro.
  - Arreglo (2026-11-25): en el mall se quitaba antes de tiempo y se veía negro unos segundos (StreamingEnabled: el modelo del mapa existe enseguida pero sus piezas llegan poco a poco). Ahora pide el streaming alrededor del personaje y espera a que haya suelo bajo los pies y a que las piezas cercanas dejen de llegar (máx. 20 s).
- [HECHO] (probado jugando) El doble de enemigos (2026-11-25: "spawnean poquísimos"). `Config.SpawnDirector.CountMultiplier = 2` (presupuesto x2) y `CapMultiplier = 2` (topes por planta x2 en los niveles 1 y 2; el nivel 3 sigue con su tope). Solo / 3 jugadores: noche 1 = 3 / 4, noche 2 = 6 / 8, noche 3 = 9 / 12, noche 5 = 15 / 21, noche 10 = 30 / 42 (antes la mitad).
- [PENDIENTE, para luego] (pedido el 2026-11-25):
  - Añadir más misiones (hecha la tanda 2 de arriba; más si hace falta).
  - Agrandar el mall (hecho arriba).
  - Subir la dificultad si hace falta (tras probar el balance con amigos).
  - Pantalla de carga (hecha abajo).
  - Aclarar qué pasa al fallar una tarea: pasa a la Fase 14.
- [HECHO] Subir el precio de las armas: en una sola noche se ganan fácilmente más de 300 billetes.
  - Escalonadas: Trapeador 400, Cartel 700, Extintor 1100, Linterna UV 1600, Taser 3200 (no alcanza antes de terminar la noche 5 sin el pase x2). Mercader en proporción (3800, 1400, 1100, 1000).
  - El taser se vuelve a comprar cuando se le acaban los usos, un 25 % más caro cada vez en la misma partida (`RebuyGrowth`, `Config.getShopPrice`, atributo `TaserBuys`).
- [HECHO] Revivir con Robux no debe hacer perder los objetos (hoy morir vacía el inventario aunque luego revivas).
  - Al caer se guarda una copia de objetos y armas; revivir pagando (Robux o ficha) la devuelve (`ShopService.RestoreAfterRevive`). Con el Médico se pierden.
- [HECHO] Poder llevar más de un arma (hoy solo hay un hueco de arma).
  - Sin límite (una de cada tipo), cada una en su casilla de la mochila. [R] usa la de la mano o la última que tuviste (`WeaponService.SetActive`). Comprar una que ya llevas la recarga (el taser no).

**Fase 14: arreglos rápidos** — [HECHO] (pedidos el 2026-11-25; cambios pequeños, se prueban juntos).
- [HECHO] (probado jugando) Jugador marcado (evento): hay que estar 10 s seguidos junto a un compañero para quitar la marca (era 1.5 s; `Config.Events.MarkedPlayer.ClearSeconds`).
- [HECHO] (probado jugando) Los marcadores de las tareas ("!", "▼" del destino) se ven desde cualquier lugar del mapa (`MaxDistance = math.huge` en `MissionService.addMarker` y `Missions/Common.makeMarker`; antes 90 y 120). El Teléfono sonando sigue solo de cerca (`MarkerDistance = 25`).
- [HECHO] (probado jugando) Sodas: las positivas duran el doble (Turbo 60 s, Ojos de gato 90, Regeneración 40, Estamina infinita 40; las negativas igual) y la soda a elección de Robux dura el doble que la normal (`Config.ChoiceSoda.DurationMultiplier` 1.5 → 2).
- [HECHO] (probado jugando) Escondite del coche: dentro se veían las rendijas de un casillero (la vista de escondite era igual para todos). Ahora el coche tiene su vista (`client/Defense`): techo, montantes, salpicadero con volante, cristal tintado y la cámara a la altura de la ventanilla.
- [HECHO] (probado jugando) Fallo del maletín perdido: no se podía entregar. La misión Objeto perdido dejaba un prompt "Entregar" fijo en el mismo mostrador y Roblox solo muestra un prompt por tecla: salía el suyo ("No llevas lo que hace falta aquí"). Ahora los prompts de entrega de las misiones de llevar objetos (`Missions/Carry`) solo se encienden mientras alguien lleva uno de sus objetos.
- [HECHO] (probado jugando) Aviso de tarea fallida concreto: "Tarea fallida: X. Los enemigos van un 4 % más rápido (total esta noche: +12 %)." y, si la tarea tiene efecto propio, lo dice (`Config.MissionFailEffects`: luces, generador, charcos que huele el Rastro).
- Probado con StartNight 2, OnlyEvents { "LostBriefcase", "MarkedPlayer" } y EventDelayOverride 15 (ya devueltos a lo normal).

**Fase 15: enemigos y eventos rediseñados** — [HECHO] (pedidos el 2026-11-25; decisiones del usuario el mismo día).
- [HECHO] (probado jugando) El Gerente (jefe noche 10): 5 radios (eran 3) escondidas: sin luz que se vea de lejos y su "!" solo a 5 studs (`MarkerDistance` nuevo en `MissionService.StartEventMission`). Se encuentran por el oído: cada radio suena (voces de walkie con estática, `Config.Sounds.Missions.ManagerRadio`) hasta 40 studs. `Config.Bosses.Manager.Radios / RadioMarkerDistance / RadioSoundDistance`.
- [HECHO] (probado jugando) El Cajero: va a por el jugador con MÁS billetes del mall (aunque no lo vea; no a los escondidos ni con al menos `MinCash`) y quien lo aturde (destello, porrazo, taser) se queda con TODO lo que robó; si lo aturde algo que no dice quién fue, el jugador más cercano. Las víctimas reciben aviso de quién se quedó su dinero.
- [HECHO] (probado jugando) Maletín perdido maldito (`server/CurseService`, `client/CurseFX`, `Config.Curse`):
  - Entregarlo en Objetos perdidos: +500 para quien lo entrega.
  - Quedárselo: mientras lo llevas, prompt "Quedármelo" con [F] (mantener 2 s; la E es la de entregar): +500 y quedas maldito tú solo.
  - Si se acaba el tiempo y nadie hizo nada: malditos todos los que siguen en pie.
  - Maldito = doble de daño (`Common.damage`), aura morada que ven todos, bordes morados y "☠ MALDITO" en tu pantalla. Se quita al caer (al revivir ya no) o al terminar la noche.
- [HECHO] (probado jugando) Luni (jefa noche 5): al vencerla, el apagón se extiende a TODO el mall (razón `MallBlackout` en todas las zonas; quedan las luces de emergencia y las salidas) hasta reiniciar 2 generadores (tareas de evento, mantener E 6 s; el Electricista más rápido). Si no, dura el resto de la noche. `Config.Bosses.Luni.MallBlackoutGenerators / RestartHoldSeconds`.
- [HECHO] (probado jugando) Fallo: al revivir, la linterna desaparecía de la mano en primera persona. `client/ViewModel` creaba una carpeta nueva al volver a la cámara y los modelos de la mano se quedaban en la vieja (descolgada); ahora reutiliza siempre la misma.
- Las pruebas de esta fase se dejan para el final (decisión del usuario, 2026-11-25).
- Prueba 1 (maletín y Cajero): `Config.Debug` StartNight 4, OnlyEnemies { "Cashier" }, OnlyEvents { "LostBriefcase" }, EventDelayOverride 15, StudioStartCash 800. Prueba 2 (jefes): `ForceBoss = "Manager"` y luego `"Luni"`.
**Fase 16: armas con daño** — [HECHO] (pedido el 2026-11-25; decisiones del usuario el mismo día).
- [HECHO] (probado jugando) Vida de los enemigos (`EnemyService.Damage / Kill / CanBeDamaged`, `Config.Combat`):
  - Se pueden herir todos los que tienen cuerpo salvo los jefes, la Estatua (solo la paran las bengalas) y los sin cuerpo (Megafonía, Reflejo; La Garra no es un enemigo).
  - Golpes para matar según el nivel (`Config.Combat.HitsToKill`): machete 3 / 5 / 9, pistola 2 / 3 / 6. Barra de vida roja sobre el enemigo unos segundos tras cada golpe y destello rojo al herirlo.
  - Al morir: humo negro, +25 billetes para quien lo mata y reaparece lejos de los jugadores a los 60 s (los de eventos y jefes no reaparecen). El Cajero suelta lo robado para quien lo mata.
- [HECHO] (probado jugando) Machete: 5000 billetes en la tienda del mall. Tajo cuerpo a cuerpo (7 studs, delante) cada 1 s que además lo frena un instante; se desgasta: 40 tajos y se rompe (se vuelve a comprar).
- [HECHO] (probado jugando) Pistola (pase de Robux "Pistola", 399 R$): 12 balas que se recargan al empezar cada noche. Con ella en la mano sale una mirilla en el centro (`client/Crosshair`) y las balas que quedan; dispara hacia donde apuntas con la cámara (primera persona), con un poco de ayuda al apuntar para el teléfono. 30 studs de alcance, trazo de bala y fogonazo. Modelos nuevos en `HeldModels` (Machete, Pistol).
- [HECHO] Pase Pistola creado en Roblox el 2026-11-26 por Open Cloud (ID 2101050207, 399 R$, a la venta; icono `assets/icons/pass_pistol.png`). Para probar en Studio: `Config.Debug.StudioOwnedPasses = { "Pistol" }`.
- Prueba (al final, con las de la Fase 15): `Config.Debug` StudioOwnedPasses { "Pistol" } y StudioStartCash 6000 (para comprar el machete).
- [HECHO] (probado jugando) Fallo: las luces lejanas se apagaban. Los dos places tenían `Workspace.StreamOutBehavior = Opportunistic` con `StreamingMinRadius = 64`: Roblox descargaba las piezas a más de 64 studs (lámparas incluidas). Ahora `StreamOutBehavior = Default` (solo descarga si falta memoria) y `StreamingMinRadius = 128`. Es un ajuste del PLACE (no está en git): hay que guardar/publicar el mall y el lobby para que dure.
**Animaciones de las armas** (pedido el 2026-11-26).
- [PROGRAMADO, falta probar] Animaciones hechas por código (`client/WeaponAnims`), en primera persona (`ViewModel.Play`) y en el brazo derecho de los demás jugadores (hombro, solo en cada cliente). El servidor marca cada uso confirmado con el atributo `WeaponAnim` (`WeaponService.Use`). Machete: tajo en diagonal. Pistola: retroceso. Taser: estocada con sacudida. Trapeador: impulso y empujón. Extintor: tiembla al rociar. Cartel: bajarlo al suelo. La Linterna UV no se anima (solo se enciende y apaga).
- [PROGRAMADO, falta probar] Sin cursor del ratón en el centro de la pantalla mientras se juega en primera persona (`client/Crosshair`: `MouseIconEnabled` falso con el ratón bloqueado en el centro; en los menús vuelve).
- Prueba: `Config.Debug` StudioStartCash 15000 y StudioOwnedPasses { "Pistol" }. Para ver el brazo de otro jugador: Test → Clients and Servers con 2 jugadores.

**Avisos, escaleras bloqueadas y bestiario** (pedido el 2026-11-26).
- [PROGRAMADO, falta probar] Avisos que no tapan la pantalla: los rehízo Tsuku19 en `client/Alerts` (commit 26d8d25: tarjetas con icono, como mucho 4, el mismo texto se renueva con "×2", carteles grandes para los eventos). Mi versión en `client/HUD` se descartó para no pisar la suya. Seguían tapando: mismo diseño pero discreto. Tarjetas de 360 px (antes 470), texto 14, fondo semitransparente, 3 a la vez (2 en móvil), duran 3-5,5 s (antes 4-8). El cartel de evento pasa a 620 px (antes 920), en el tercio de abajo (antes en el centro) y dura como mucho 4 s. El borde rojo de los eventos malos es más fino y suave.
- [PROGRAMADO, falta probar] Piso aislado: ya no se salta la reja. Encima, una pared invisible hasta el techo; la reja es más ancha y hay paredes invisibles por fuera de las barandillas en los primeros 12 studs (`Events/IsolatedFloor`). Pendiente de decidir: desde la planta alta aún se puede saltar la barandilla de la galería y caer a la baja.
- [PROGRAMADO, falta probar] Sin avisos de entidades nuevas (se quitaron los `Hint`). En su lugar, **bestiario** en el lobby (botón BESTIARIO junto a LOGROS, `client/BestiaryPanel`): 20 entradas (`Config.Bestiary`), vacío al principio. Cada entidad se desbloquea para siempre (`data.Bestiary`, `server/BestiaryService`) al verla de cerca (30 studs, de frente y sin paredes) o al sufrirla (Eco, Mímico, Megafonía, La Garra; las cámaras desbloquean al Vigilante); los jefes, al empezar su noche. Desbloqueada: foto, noche, qué es y cómo sobrevivirla. Aviso al desbloquear: "Nueva entrada en el bestiario: X".
- [PROGRAMADO, falta probar] Sin aviso de "Nueva tarea": las tareas se ven en la lista de la derecha y con su marca (`MissionService`). La Megafonía tampoco avisa (si no, cualquier aviso sería falso). Su marca falsa ahora se ve desde todo el mapa, como las reales. Bestiario de la Megafonía actualizado.
- [PROGRAMADO, falta probar] Fotos del bestiario: sacadas en el mall (atrio de noche, con luz de linterna; el Mímico en su máquina, La Central en la sala de cámaras, La Garra con el dibujo de su mano). Están en `assets/bestiary/*.png`, subidas como Image (aprobadas) y puestas en `Config.Bestiary.Photos`.
- [PENDIENTE: subirlas a mano] Icono (512×512) y miniatura (1920×1080) de la experiencia: capturas reales con varias entidades en el atrio y el título "SOBREVIVIENDO EN EL MALL". Están en `assets/thumbnails/icon.png` y `thumbnail.png`, y ya se subieron como imágenes (icono 98390859378613, miniatura 90702555904239). No se pudieron poner en el juego por Open Cloud porque el juego es de la cuenta 10076076766 y Studio tenía abierta la sesión con otra cuenta: hay que ponerlas desde el Creator Dashboard (Configuraciones → Básico: icono y miniaturas).
- Prueba: noche 7, `OnlyEvents { "IsolatedFloor" }`, `EventDelayOverride 10`. En la consola sale `[Bestiario] <jugador> encontró: <entidad>`. Para ver el panel lleno o vacío en el lobby: `Config.Debug.StudioBestiary = "All"` o `"Empty"` (con API Services se guarda en tus datos).
- [HECHO] (probado en Studio, 2026-11-26) **Ruletas físicas en la plaza** (pedido: "que la ruleta sea una ruleta a la que vas y gastas diamantes"). `server/RouletteService` + `server/RouletteBuilder` + `client/LobbyRoulettes`, `Config.LobbyRoulettes`, tag `LobbyRoulette`, remote `RequestWheelSpin`.
  - Dos ruedas de feria (clases donde estaba el puesto CLASES; skins donde estaba CAJA): sectores con color, nombre y %, separadores dorados, clavijas, lengüeta roja, aro con bombillas, marquesina, consola con botón rojo y pantalla de precio, cartel de probabilidades al lado.
  - [E] en la consola: cobra y sortea con `ClassService.Spin` / `CosmeticsService.Spin` (mismo precio, VIP, política de objetos aleatorios, reemplazo del slot, repetida = 💎). Con clase Épica o mejor, la primera pulsación pide confirmar. [F] en el cartel abre el panel de antes (clases y slots / caja con Robux).
  - El servidor decide el resultado y el ángulo; cada cliente anima la rueda con la hora del servidor (la ven todos, también quien entra a mitad). Clic y lengüeta por clavija, bombillas en persecución, cartel "X consiguió …" y confeti. Una persona a la vez por rueda; la placa sobre la cabeza y los slots esperan a que pare.
  - El panel CLASES conserva su rueda para "Girar hasta" y el tiro afortunado.
- [HECHO] (guardado en el place del lobby, versión 278) **Lobby más realista** (2026-11-26):
  - Puestos TAQUILLA, SKINS y MEJORAS rehechos como quioscos: zócalo de granito, mueble trasero de nogal con caja de luz y estantes con producto, mostrador con vitrina iluminada y encimera de mármol, marquesina con focos y borde de color, cartel luminoso. Se quitaron del place los puestos CLASES y CAJA (ahora son ruletas).
  - Maceteros: jardineras redondas de granito con borde de latón, tierra, piedras y dos higueras (malla PBR "Fiddle-leaf fig" de la Creator Store, sin scripts).
  - Las 6 tiendas de la planta baja ya no tienen persiana: escaparate de cristal con puerta, cartel "CERRADO · Abrimos a las 10:00", caja de la persiana enrollada e interior iluminado (café con barra, menú y mesas; moda con maniquíes vestidos y percheros; juguetería; zapatería; librería; electrónica con televisores). Se abrió la pared lateral de la planta baja detrás de cada una (`WallWest`/`WallEast` partidas). Las de arriba siguen cerradas.
  - Cuadros de sala: zócalo de granito con filo de latón y postes de acero con remate dorado (base azul y muros de color sin cambios).
  - Dos lámparas de anillo de latón colgadas del tragaluz, 6 bancos de nogal y acero (2 junto a la fuente, 4 bajo los balcones), dos máquinas expendedoras junto a la entrada y pantallas de récords 4 studs más arriba (la rueda de clases las tapaba).
  - Nota: en Studio, `Glass` oculta las SurfaceGui y lo transparente que hay detrás; los escaparates y vitrinas usan SmoothPlastic transparente.
- [PROGRAMADO, falta probar] **Victoria más llamativa y sin tiempo de mejoras** (2026-11-26). Entre noches solo queda la preparación (30 s): se quitaron las fases Results (10 s) y Upgrades (30 s). Al ganar, `client/VictoryScreen` (7 s, `Config.Night.VictorySeconds`): destello dorado, rayos que giran, resplandor, bordes dorados, dos ráfagas de confeti, "¡SOBREVIVISTE!" enorme que entra con rebote, "NOCHE X SUPERADA" y el pago con el total contando. Después se abre sola la ventana de mejoras ([U] sigue funcionando en la preparación). El panel del HUD queda solo para el fin de partida. Se quitó la música Results.

**Orden elegido:**
- La Fase 3 cambia la base de cómo aparece el peligro; el resto se apoya en ella.
- Las armas van antes que los enemigos nuevos porque cada enemigo necesita su contramedida.
- Los eventos van antes que los jefes porque los jefes usan las misiones de evento.
- El lobby es independiente y se puede intercalar.
- Fases 14 → 15 → 16 (2026-11-25): primero los arreglos rápidos (se prueban en una partida), luego los rediseños de enemigos y eventos, y al final las armas con daño, que cambian la base del combate y necesitan decisiones de diseño.
- La interfaz adaptable (Fase 12) también es independiente. Conviene hacerla antes de la Fase 10 (lobby) y de las armas (Fase 4), que añaden más UI y botones: si `UIKit.screen` e `InputHints` ya existen, la UI nueva nace adaptable. Es obligatoria antes de publicar, porque gran parte de los jugadores de Roblox juegan en teléfono.

---

## Archivos clave (fases 1 y 2)
- `src/server/LightService.luau`: `SetReason`, `ResetAll`, `IsDarkAt`.
- `src/server/MallBuilder.luau`: `buildService`, `buildOffices`, `ceilingPanel`, `electricPanel`, `exitSign`.
- `src/enemies/Blackout.luau`: `ChooseZone`.
- `src/server/VendingService.luau`: `ApplyEffect`, `clearSoda`.
- `src/server/PlayerStats.luau`: `AddEffect`; ya admite varias claves y reemplazo por token, así que no hay cambios.
- `src/client/HUD.luau`: la etiqueta de soda y el aviso de zona.
- `src/shared/Config.luau`: `DarkZones` y los comentarios de las sodas.

## Verificación
1. **Rojo sincronizado y Play en Studio:**
   - Teletransportar al jugador a la bodega y a las oficinas y capturar pantalla: deben verse oscuras, con solo las luces de emergencia y los carteles de SALIDA; la linterna [F] ilumina.
   - Comprobar en el servidor: `LightService.IsDarkAt(posición en la bodega) == true`, y que no quedan tableros FixLights en las zonas oscuras (contar los MissionSpot por zona).
   - Reiniciar el generador de planta baja y comprobar que oscurece el Patio de comidas y la Entrada.
2. **Sodas** (llamando a `VendingService.ApplyEffect` desde el servidor):
   - Blurry y luego Tired: deben existir `SodaEnds_Blurry` y `SodaEnds_Tired` con sus tiempos, y `Flag_BlurryVision` debe seguir activo.
   - Otra Blurry: `SodaEnds_Blurry` aumenta en 20 s.
   - Speed y luego Vision: solo queda `SodaEnds_Vision`.
   - Slow con Speed: `WalkSpeed ≈ base × 1.25 × 0.75`.
   - Captura del HUD con la lista de sodas.
   - Matar al personaje: se borra todo.
3. La consola no debe mostrar errores, y el plan del proyecto (`plan sobreviviendo en el mall.txt`) se actualiza con estas fases.

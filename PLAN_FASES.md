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

**Fase 3: director de aparición por presupuesto.** Base de todo lo demás. — [HECHO, falta probar una noche real en el mall]
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

**Fase 4: armas gratuitas.**
- Van antes que los enemigos nuevos porque son sus contramedidas.
- Un hueco de arma con su tecla, compra con billetes en la tienda del mall, se pierde al morir, con enfriamientos.
- Taser (10 usos), extintor, cartel de piso mojado (trampa), linterna UV (revela al Reflejo, al Mímico y al Eco) y trapeador.
- Se reutilizan `DefenseService` (aturdir, empujar) y `ShopService`.

**Fase 5: enemigos nuevos de nivel 1.**
- Carrito: embiste y queda aturdido si choca con una pared.
- Polilla de luz: persigue la linterna y le drena la batería.
- Globo: revienta si lo miras y atrae enemigos.

**Fase 6: enemigos nuevos de nivel 2.**
- Reflejo: aparece en vidrios y escaparates.
- Ducto: va por las rejillas, que ya existen en los techos.
- Cajero: roba billetes.
- Megafonía: anuncia misiones falsas.

**Fase 7: enemigos nuevos de nivel 3.**
- Estatua de la fuente: solo la frenan las bengalas.
- Mímico: máquina expendedora viva que reutiliza `vendingMachine`.
- Cazador: marca al jugador más solo.

**Fase 8: director de eventos.**
- Lanza un evento cada 2–3 minutos, con máximo 1 activo, enfriamientos y un piso asignado.
- Añade un tipo "misión de evento" a `MissionService`: no cuenta para la cuota, no paga y se muestra con otro color en el HUD.
- **Evento nuevo: Neblina** (malo, en todo el mall), que se suma a los 15 del documento:
  - Una niebla densa entra poco a poco (~10 s) en las dos plantas y dura unos 90 s.
  - Se implementa subiendo la densidad y la bruma de la `Atmosphere` de Lighting con un tween en `LightService`, y luego bajándola. Opcionalmente, partículas de niebla a ras de suelo en el atrio.
  - La visibilidad baja mucho: la linterna corta menos y la luz de las lámparas apenas llega.
  - Los enemigos también ven menos: se reduce temporalmente `Config.Detection.SenseRange`.
  - Sinergia: favorece al Eco y al Ducto, que te oyen sin necesidad de verte.
  - Se anuncia con sonido y texto en pantalla, como los demás eventos.
- Los 15 eventos, empezando por los que reutilizan sistemas existentes:
  - Apagón general (LightService y generadores);
  - Oleada (director de aparición);
  - Baterías débiles;
  - Hora de oro;
  - Cámaras amigas (la misión CheckCameras);
  - Suministros.

**Fase 9: jefes cada 5 noches.**
- El Gerente, Luni, El Coleccionista y La Central.
- Usan las misiones de evento, el 50% del presupuesto de peligro y un pago, un logro y diamantes al vencerlos.
- Al vencer un jefe, sumar 1 a `data.Lifetime.BossesDefeated`: la tabla "Jefes vencidos" del lobby ya lee ese dato (`LeaderboardService`).

**Fase 10: lobby completo.**
- [HECHO] Cuadros de sala físicos (`PadService` + `PadUI`): se entra solo subiéndose, no se sale caminando (solo saltando) y salir del cuadro es salir de la sala.
- [HECHO] Inicio automático a los 40 s (o al llenarse, o con INICIAR PARTIDA del anfitrión).
- [HECHO] Puesto de CLASES (panel nativo `ClassPanel`). El puesto de MEJORAS sigue en "Próximamente": ver *Tiendas del lobby* abajo.
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
| **Caja de cosméticos** | Puesto nuevo en la plaza | Skins de linterna y de armas, con rarezas | Diamantes | Fase 4 (armas) y Fase 11 (skins) |

1. **Mejoras permanentes** (puesto MEJORAS):
   - Pocos niveles y efecto pequeño por nivel, con topes bajos: es una ventaja que se puede comprar, porque los diamantes se venden con Robux.
   - Ejemplos: +3% de vida por nivel (hasta 5), +5% de batería por nivel, billetes extra al empezar cada partida, un botiquín gratis al empezar.
   - Datos: `data.PermanentUpgrades[id] = nivel`. El mall los aplica en `PlayerStats.Compute` (multiplicadores) y al iniciar la partida (billetes y objetos iniciales).
   - Antes de programarla, proponer una tabla de mejoras con niveles y costos para ajustarla.
2. **Maestría de clase** (puesto CLASES):
   - Cada clase sube de nivel al jugar con ella y mejora un poco su bonificación (p. ej. Corredor nivel 3: +15% de velocidad en vez de +10%).
   - La maestría se guarda **por clase** (`data.ClassMastery[clase]`), así no se pierde aunque la ruleta reemplace la clase del slot.
3. **Taquilla del conserje** (puesto nuevo):
   - Consumibles comprados con diamantes que se entregan al empezar la próxima partida y se gastan al usarlos.
   - Datos: `data.Locker[itemId] = cantidad`. El mall los entrega al iniciar la partida y los descuenta.
   - No tiene azar.
4. **Caja de cosméticos** (puesto nuevo, junto con la Fase 11):
   - Solo estética, sin ventaja de juego.
   - Es un objeto aleatorio: probabilidades siempre visibles y respetar `PaidRandomItemsRestricted`, igual que la ruleta.

**Plaza:** hay que añadir en Studio dos puestos nuevos (Taquilla y Cosméticos) con el tag `LobbyStand`, su `PromptPart` y su círculo de luz (`FloorGlow`).

**Orden sugerido:** Mejoras permanentes → Maestría de clase → Taquilla del conserje → Caja de cosméticos (con la Fase 11).

**Fase 11: monetización de armas** (al final, como dice el documento).
- Taser infinito, recarga de taser, skins de armas y caja de cosméticos.
- Fumigador de entidades: hay que decidir antes si es consumible o pase.

**Fase 12: interfaz adaptable (PC, teléfono, tablet y consola).**
Que toda la interfaz use las herramientas nativas de Roblox para adaptarse a cada pantalla y control.

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

**Orden elegido:**
- La Fase 3 cambia la base de cómo aparece el peligro; el resto se apoya en ella.
- Las armas van antes que los enemigos nuevos porque cada enemigo necesita su contramedida.
- Los eventos van antes que los jefes porque los jefes usan las misiones de evento.
- El lobby es independiente y se puede intercalar.
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

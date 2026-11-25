# Sobreviviendo en el Mall --- Recopilación de diseño

**Fecha:** 22 de noviembre de 2026

## Sobreviviendo en el Mall --- Recopilación de diseño

Nov 22, 2026 · @Jhan

### Lobby

El lobby es el punto de inicio de la experiencia: aquí el jugador elige
su clase, gira la ruleta, compra y arma su sala antes de viajar al mall.
Es un espacio social y seguro, sin enemigos, donde se ven las salas y
los demás jugadores.

El diseño toma como referencia cuatro capturas de otro juego de Roblox y
las adapta a la temática del mall nocturno:

  -----------------------------------------------------------------------
  Captura                 Qué se toma             Cómo queda en el juego
  ----------------------- ----------------------- -----------------------
                          Panel de recompensas    Ruleta de clases: se
                          con rareza y            gira con diamantes y
                          probabilidad, detalle   muestra siempre la
                          del premio y botones de rareza y la
                          abrir                   probabilidad de cada
                                                  clase, caja de
                                                  cosmeticos (skin para
                                                  armas)

                          Plataformas blancas en  Cuadros de sala pública
                          el suelo, se crea la    y solo amigos
                          sala al subirse en      
                          ellos.                  

                          Puestos por función     Puesto de CLASES,
                          (CLASES, MEJORAS) y     tablas de clasificación
                          tablas de clasificación y un puesto de MEJORAS
                          al fondo                por decidir (ver
                                                  Mejoras y tablas de
                                                  clasificación)

                          Plaza abierta: cuadros  Plaza del mall con la
                          de sala al frente,      misma distribución y
                          puestos al fondo y      contador de diamantes
                          contador de moneda en   en el HUD
                          pantalla                
  -----------------------------------------------------------------------

#### Zonas del lobby

plano de la plaza · 5 zonas y el HUD

La plaza no tiene enemigos. Los puestos del fondo se usan de pie, los
cuadros del frente crean y reúnen las salas, y los botones del HUD
(línea punteada) abren la tienda, los logros y la lista de salas sin
ocupar espacio físico.

#### Creación de salas

Las salas se arman en el lobby, nunca en el mall: al mall solo se viaja
con la partida ya iniciada. Cada sala se representa con un cuadro blanco
en el suelo con el texto "Toca para crear un grupo".

Cuadro libre: al tocarlo o colocarse sobre el se abre el panel de
creación, donde el jugador elige sala pública o solo amigos.

Cuadro ocupado: muestra el nombre del anfitrión, los jugadores actuales
sobre 5 y un candado si es privada. Los demás jugadores se unen tocando
el cuadro o colocandose sobre el.

Inicio: el anfitrión pulsa INICIAR PARTIDA, o la partida arranca sola al
llenarse la sala o despues de 40 segundos, las personas deben estar en
el lobby.

#### Clases y ruleta

El puesto de CLASES abre el panel de clases y ruleta (botón CLASES Y
RULETA). Sigue el formato de la caja de referencia: a la izquierda la
lista de clases con su rareza y su probabilidad, al centro la animación
de giro y a la derecha el detalle de la clase seleccionada con sus
bonificaciones. La ruleta solo se usa en el lobby, y las probabilidades
se muestran siempre.

  Rareza       Clases
  ------------ -------------------------------------------------
  Común        Conserje, Corredor, Atleta
  Rara         Electricista, Guardia, Ahorrador
  Épica        Visión nocturna, Médico (probabilidad muy baja)
  Legendaria   Medium, Sombra

Costo: cada giro se paga con diamantes. No se paga directamente con
Robux. Existirá una opción de tiro afortunado que será para garantizar
una clase epica o superior, esta se pagará con robux.

Slots: gratis hay 1; se compran hasta 5 con Robux y cada slot nuevo
empieza con Conserje. Antes de crear la sala se elige qué slot usar.

Reemplazo: la clase que sale reemplaza automáticamente a la del slot
equipado, sea mejor o no. Para cambiar otro slot, se equipa y se gira.

Se puede elegir una clase y tocar para hacer giros automaticamente hasta
que salga esa clase

#### Tienda de Robux

Se abre con el botón TIENDA del lateral izquierdo y muestra el precio
real en Robux de cada producto.

  -----------------------------------------------------------------------
  Producto                            Efecto
  ----------------------------------- -----------------------------------
  Paquetes de diamantes (3)           Suman diamantes para la ruleta,
                                      caja de cosmeticos o mejoras
                                      permanentes

  Slot de clase                       Un slot más, hasta 5 en total;
                                      empieza con Conserje

  x2 Billetes                         Duplica el pago de cada noche

  Linterna Premium                    Linterna Pro siempre, con haz
                                      dorado
  -----------------------------------------------------------------------

Revivir y la soda a elección son productos de la partida y se compran en
el mall, no aquí.

#### Mejoras y tablas de clasificación

Tablas de clasificación. Van al fondo de la plaza, como en la
referencia, sobre pantallas grandes. La principal es la noche récord.
Como segunda tabla se propone jefes vencidos, un dato nuevo que habría
que registrar. Cada tabla muestra el top de jugadores con nombre y
avatar, y se actualiza al terminar una partida y cada cierto tiempo.

#### Logros y progreso

El botón LOGROS (trofeo del lateral izquierdo) abre la lista de logros.
Muestra un "!" cuando hay uno por reclamar, como en la referencia. Los
logros dan diamantes.

Se guarda por jugador:

Diamantes.

Slots de clase y la clase de cada uno.

Noche récord.

Logros.

Estadísticas.

Los diamantes tienen tres fuentes: compra con Robux, +100 cada 5 noches
sobrevividas y logros. Cada jefe vencido (noches 5, 10, 15, 20...) suma
un logro propio. Los billetes, las mejoras y los objetos de la partida
no se guardan, así que el lobby nunca los muestra.

#### Flujo del jugador

flujo del jugador · lobby a mall y regreso

El jugador entra, elige clase y slot, crea una sala o se une a una, y
espera en el lobby. El viaje al mall solo ocurre cuando el anfitrión
inicia o la sala se llena; al perder, todos regresan al lobby.

#### Monetización y políticas de Roblox

La ruleta es aleatoria y los diamantes se pueden comprar con Robux, así
que el lobby cumple estas reglas:

Probabilidades siempre visibles en el panel de la ruleta, para todas las
clases.

Cuentas con compras de azar restringidas: según las reglas de Roblox,
solo pueden girar con diamantes ganados jugando, y la tienda no les
ofrece diamantes.

Dos saldos: los diamantes ganados y los comprados se cuentan por
separado, aunque la pantalla muestre un solo total.

Pueden haber opciones de comprar directamente con robux

### Enemigos

Los enemigos tienen tres niveles de peligro y aparecen al azar según la
noche. Todos tienen al menos una contramedida clara.

#### Niveles de peligro

  -----------------------------------------------------------------------
  Nivel             Enemigo           Qué hace          Cómo se evita
  ----------------- ----------------- ----------------- -----------------
  1                 Maniquí           Solo se mueve     Mirarlo; el
                                      cuando nadie lo   destello lo
                                      mira              congela 4 s

  1                 Apagón            Apaga zonas del   La luz de la
                                      mall              linterna lo hace
                                                        retroceder; el
                                                        destello lo
                                                        ahuyenta

  1                 Carrito (nuevo)   Carrito de        Esquivarlo: si
                                      compras fantasma  choca con una
                                      que embiste en    pared, queda
                                      línea recta       aturdido

  1                 Polilla de luz    Enjambre que      Apagar la
                    (nuevo)           persigue la       linterna o lanzar
                                      linterna y le     un petardo
                                      drena la batería  

  1                 Globo (nuevo)     Flota quieto; si  No mirarlo, o
                                      lo miras mucho,   destruirlo de
                                      revienta y atrae  lejos
                                      enemigos          

  2                 Eco               Fantasma con el   Alumbrarlo lo
                                      nombre de un      revela y lo hace
                                      compañero; te oye desaparecer;
                                      a través de las   petardos; el
                                      paredes y se      Medium lo ve
                                      lanza al estar    
                                      cerca             

  2                 Rastro            Si pisas un       Limpiar los
                                      derrame te marca  derrames y no
                                      20 s y te sigue a pisarlos;
                                      donde vayas       destello y
                                                        porrazo

  2                 Reflejo (nuevo)   Aparece en        Evitar o tapar
                                      vidrios y         los cristales
                                      escaparates y te  
                                      ataca por la      
                                      espalda si lo     
                                      miras             

  2                 Ducto (nuevo)     Se mueve por las  Ir en grupo y
                                      rejillas de       escuchar las
                                      ventilación y cae rejillas
                                      sobre jugadores   
                                      aislados          

  2                 Cajero (nuevo)    Roba billetes al  El destello o el
                                      tocarte           porrazo lo hacen
                                                        soltarlos

  2                 Megafonía (nuevo) Anuncia misiones  Verificar la
                                      falsas para       misión en el HUD
                                      llevarte a una    
                                      trampa            

  3                 Vigilante         Patrulla y ve por Esquivar los
                                      las cámaras de    haces rojos; el
                                      seguridad; es el  destello ciega
                                      que más daña      las cámaras 20 s
                                                        y lo aturde

  3                 Estatua de la     Gigante, lenta e  Solo las bengalas
                    fuente (nuevo)    imparable         la frenan

  3                 Mímico (nuevo)    Máquina           Se detecta por un
                                      expendedora viva  detalle visual,
                                      que parece normal como un parpadeo
                                      hasta que compras 

  3                 Cazador (nuevo)   Marca al jugador  Quedarse cerca de
                                      que está más solo un compañero
                                      y no suelta la    rompe la marca
                                      persecución       
  -----------------------------------------------------------------------

#### Aparición por noche

Cada noche tiene un porcentaje de aparición por nivel. Estos valores son
un punto de partida para ajustar jugando.

  Noche            Nivel 1   Nivel 2   Nivel 3
  ---------------- --------- --------- ---------
  1-2              85%       15%       0%
  3-4              60%       35%       5%
  5-7              40%       40%       20%
  8-10             25%       45%       30%
  11 en adelante   15%       40%       45%

#### Reglas de aparición

Presupuesto de peligro: un enemigo de nivel 1 cuesta 1 punto, uno de
nivel 2 cuesta 3 y uno de nivel 3 cuesta 6. Cada noche tiene un
presupuesto que crece con la noche y con el número de jugadores, y se
sortea hasta gastarlo.

Tope de nivel 3: máximo 1 o 2 a la vez, con aparición escalonada.

Sin regla de no repetir: pueden salir varios del mismo tipo, por ejemplo
varios Maniquíes, porque el mall tiene dos pisos.

Tope por tipo y por piso: por ejemplo, máximo 3 Maniquíes por piso, para
que no se amontonen.

Reparto entre pisos: cada enemigo se asigna a un piso según cuántos
jugadores haya en cada uno.

Aviso: la primera vez que aparece un enemigo se muestra su contramedida.

### Eventos aleatorios

Durante la noche, un director de eventos lanza sucesos al azar que
cambian el ritmo de la partida. Hay 15 eventos: malos, buenos y mixtos.

  -----------------------------------------------------------------------
  Tipo                    Evento                  Qué pasa
  ----------------------- ----------------------- -----------------------
  Malo                    Apagón general          Todo el mall queda a
                                                  oscuras hasta que se
                                                  arreglen los
                                                  generadores, al
                                                  arreglar los
                                                  generadores principales
                                                  se debe restablecer en
                                                  cada tienda la
                                                  electricidad; solo
                                                  sirven linternas y
                                                  bengalas

  Malo                    Piso aislado            Las escaleras se
                                                  bloquean y un piso
                                                  queda cortado hasta
                                                  completar una misión de
                                                  reparación

  Malo                    Alarma de incendio      Los rociadores mojan el
                                                  piso: ralentiza, apaga
                                                  bengalas y el ruido
                                                  tapa los pasos

  Malo                    Baterías débiles        La linterna gasta el
                                                  doble durante 2 minutos

  Malo                    Persianas cerradas      Varias tiendas se
                                                  sellan y hay que
                                                  abrirlas con una misión

  Malo                    Oleada                  Una horda de enemigos
                                                  de nivel 1 aparece
                                                  durante 60 s

  Malo                    Jugador marcado         Un jugador al azar
                                                  atrae enemigos; se
                                                  anula acercándose a un
                                                  compañero

  Malo                    Megafonía hackeada      Anuncia misiones falsas
                                                  que llevan a una zona
                                                  peligrosa

  Bueno                   Hora de oro             Las misiones pagan el
                                                  doble 2 minutos, pero
                                                  los enemigos van más
                                                  rápido

  Bueno                   Suministros             Cae una caja con
                                                  bengalas, baterías o
                                                  botiquines en un punto
                                                  marcado

  Bueno                   Mercader nocturno       Un vendedor aparece 60
                                                  s con ofertas raras y
                                                  se va

  Bueno                   Cámaras amigas          Todos ven a los
                                                  enemigos durante 10 s

  Mixto                   Maletín perdido         Un maletín con billetes
                                                  aparece en una zona
                                                  peligrosa; cargarlo te
                                                  ralentiza

  Mixto                   Tienda abierta          Una tienda sellada se
                                                  abre con botín, pero
                                                  activa una alarma al
                                                  entrar
  -----------------------------------------------------------------------

#### Cómo funcionan

Director de eventos: lanza uno cada 2 o 3 minutos, con máximo 1 activo y
un enfriamiento por evento.

Pesos por noche: las primeras noches solo aparece 1 evento aleatorio, a
partir de la noche 5 pueden aparecer más.

Aviso claro: cada evento se anuncia con sonido y texto en pantalla.

Piso: cada evento se asigna a un piso concreto.

Sinergia con enemigos: por ejemplo, el apagón general fortalece al
Apagón y la alarma de incendio da ventaja al Eco.

#### Misiones de evento

Las misiones que nacen de un evento, como reabrir un piso o abrir
persianas, no cuentan para la cuota de la noche, no dan dinero y no
avanzan el reloj. Su única recompensa es resolver el problema. Se
muestran aparte de las misiones normales, con otro color o icono, y si
caducan solo prolongan el efecto del evento.

Hay excepciones: Maletín perdido y Tienda abierta pueden dar billetes
como botín, y Hora de oro sigue duplicando el pago de las misiones
normales.

### Jefes

Hay un jefe cada 5 noches (5, 10, 15, 20...). No se les mata a tiros: se
les vence cumpliendo un objetivo en equipo mientras se sobrevive.

  -----------------------------------------------------------------------
  Noche             Jefe              Qué hace          Cómo se vence
  ----------------- ----------------- ----------------- -----------------
  5                 El Gerente        Hombre de traje   Destruir 3 radios
                                      que patrulla con  repartidas por el
                                      un walkie y       mall; cada una le
                                      ordena cerrar     quita capacidad
                                      persianas; cada   de llamar
                                      minuto llama      refuerzos, hasta
                                      refuerzos de      que se va
                                      nivel 1 y marca y 
                                      persigue a quien  
                                      ve                

  10                Luni, la mascota  Mascota gigante   El destello la
                                      de Plaza Luna que frena, pero no la
                                      corre de noche y  detiene; hay que
                                      persigue al grupo llevarla al
                                      más numeroso      cuarto de
                                                        generadores y
                                                        activar el apagón
                                                        de sector para
                                                        dejarla sin
                                                        energía

  15                El Coleccionista  Convierte a los   Reanimar a los
                                      jugadores caídos  caídos antes de
                                      en maniquíes a su que se
                                      servicio, que     transformen y
                                      resucitan como    completar 3
                                      enemigos; cuantos ofrendas
                                      más caídos, más   (devolver objetos
                                      fuerte            perdidos a sus
                                                        tiendas)

  20                La Central        La IA de          Llegar a la sala
                                      seguridad del     de control y
                                      mall: controla    reiniciar 3
                                      cámaras, puertas, servidores en
                                      luces y megafonía pisos distintos,
                                                        lo que obliga a
                                                        dividirse

  25 en adelante    Los jefes se      Mismo orden, con  Igual que cada
                    repiten           más vida y        jefe
                                      velocidad y       
                                      mecánicas         
                                      combinadas, por   
                                      ejemplo Luni      
                                      junto al Gerente  
  -----------------------------------------------------------------------

#### Reglas de las noches de jefe

Aviso: pantalla de alerta y música propia, para que se sienta distinto.

Presupuesto reducido: la noche de jefe usa solo el 50% del presupuesto
de peligro normal.

Misiones del jefe: cuentan como eventos, así que no dan progreso de
noche ni dinero.

Recompensa: al vencer al jefe, un pago extra, los +100 diamantes de cada
5 noches y un logro por jefe.

Si fallan: la partida termina como cualquier derrota.

### Armas

Las armas son defensas temporales y limitadas: aturden o apartan a los
enemigos, pero no convierten el juego en un juego de disparos. Se lleva
una equipada a la vez, con su propia tecla, y todas tienen enfriamiento.

#### Armas gratuitas (billetes)

Se compran con billetes en la tienda del mall y se pierden al morir,
como los demás objetos.

  -----------------------------------------------------------------------
  Arma                    Efecto                  Límite
  ----------------------- ----------------------- -----------------------
  Taser                   Aturde a un enemigo 10  10 usos y enfriamiento
                          s                       de 8-10 s

  Extintor                Nube que bloquea la     Usos limitados, por
                          visión de los enemigos  definir
                          5 s; buena contra el    
                          Rastro y la Polilla de  
                          luz                     

  Cartel de piso mojado   Trampa que ralentiza a  Se coloca en el suelo;
                          los enemigos que pasan  usos limitados

  Linterna UV             Revela al Reflejo, al   Gasta batería
                          Mímico y al Eco         

  Trapeador               Empujón corto que       Enfriamiento
                          aturde menos que el     
                          Porrazo del Guardia     
  -----------------------------------------------------------------------

#### Armas con Robux

  -----------------------------------------------------------------------
  Arma                    Efecto                  Notas
  ----------------------- ----------------------- -----------------------
  Taser infinito          Igual que el taser      Mismo efecto y
                          gratuito, sin límite de enfriamiento; no pega
                          usos                    más fuerte

  Recarga de taser        +10 usos                Compra suelta

  Skins de armas          Dorado, neón y otros    Solo cosméticas

  Fumigador de entidades  Elimina a un enemigo    Exclusivo de Robux (ver
                          hasta el final de la    abajo)
                          noche                   
  -----------------------------------------------------------------------

#### Fumigador de entidades

Efecto: elimina a un enemigo hasta el final de la noche; vuelve a
aparecer la noche siguiente.

Canalización: hay que apuntar a corta distancia sin que te aturdan ni te
muevas; si se interrumpe, se cancela.

Tiempo según el nivel: 2 s para nivel 1, 4 s para nivel 2 y 8 s para
nivel 3.

Límites: un uso por jugador y por noche, y no funciona contra jefes.

Sin recompensa: matar enemigos no da billetes ni progreso de noche.

Por decidir: si se vende como consumible por uso o como pase con un uso
por noche, y si el director reemplaza al enemigo eliminado a los 60 s.

#### Reglas de equilibrio

El taser infinito no es más fuerte que el gratuito: solo evita quedarse
sin usos.

Contra el nivel 3 el taser aturde solo 1 s, la Estatua de la fuente es
inmune y los jefes quedan fuera o muy limitados.

Los diamantes servirían solo para skins de armas, para no tocar la
economía de la ruleta.

El juego debe poder ganarse sin armas de Robux; como ayudan a todo el
equipo, no solo a quien paga, encajan en un juego cooperativo.

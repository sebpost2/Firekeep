# Cómo conectar a los amigos sin abrir puertos — Veredicto y plan

> Este archivo es el análisis honesto de qué conviene para el server
> **Cave Horror Project** (Minecraft 1.20.1 Forge, 136 mods), con amigos remotos
> no-técnicos y **sin poder abrir puertos** en el router. El server está impecable
> (TPS 20/20); el problema es SOLO cómo viaja la conexión hasta los amigos.

---

## ⚠️ ACTUALIZACIÓN (2026-07-07) — lo que se probó y confirmó

- **Se puso el agente de playit en "IPv4 only" (toggle "Allow IPv6 / used for routing").**
  Comprobado por DNS que **NO alcanza**: ese toggle solo controla cómo *la laptop
  sale* hacia playit, no lo que ven los amigos. La dirección
  `wildland-priced.gl.joinmc.link` **sigue entregando un registro IPv6 (AAAA)** a
  quien se conecta, así que el amigo con IPv6 roto puede seguir agarrándolo.
  (Verificar con: `nslookup -type=AAAA wildland-priced.gl.joinmc.link` — si aparece
  un AAAA, sigue dual-stack. En playit compartido ese AAAA no se puede quitar.)
- **El problema NO le pega a todos los amigos**, solo a los que tienen IPv6 malo en
  su ISP. Los demás entran bien con la dirección normal.
- **SOLUCIÓN ELEGIDA (gratis, sin tocar nada del host):** el amigo afectado agrega
  en su launcher (CurseForge → modpack → Java → *Additional Arguments*) el argumento
  **`-Djava.net.preferIPv4Stack=true`** una sola vez. Fuerza a *su* Minecraft a usar
  solo IPv4 → esquiva el IPv6 roto, misma dirección de siempre, no abre puertos.
- Dato del túnel por si sirve: IPv4 de playit `147.185.221.26`, puerto SRV `56975`
  (pueden cambiar en el plan compartido).

---

## 🔧 OPTIMIZACIONES DEL SERVER (2026-07-07) — aplicadas

Se afinó `server.properties` de **Cave Horror Project** para que la ráfaga del
handshake de mods y el juego aguanten mejor sobre el relay compartido de playit y
una **subida modesta por WiFi**. Respaldo guardado en `server.properties.bak`.

> ⚠️ Nota: el server **reescribe `server.properties` al apagar** y borra los
> comentarios `#`, por eso el detalle vive acá (no dentro del archivo).

| Ajuste | Antes | Ahora | Por qué |
|--------|-------|-------|---------|
| `network-compression-threshold` | 256 | **64** | Comprime más paquetes (incluida la ráfaga de sync de 136 mods) → **menos subida** por WiFi, que es el cuello de botella. Trade-off: un poco más de CPU (la laptop tiene de sobra). El consejo genérico de "subir a 512 para ahorrar CPU" es para servers limitados por CPU, no por banda como este. |
| `max-tick-time` | 60000 | **180000** | Da 3 min de margen para logins pesados / generación de chunks de un pack grande sin que el watchdog crea que se colgó y **mate el server**. No se usa `-1` para conservar algo de protección ante un cuelgue real. |
| `sync-chunk-writes` | true | **true (se dejó así a propósito)** | Se probó `false` (menos micro-tirones), pero se **revirtió a `true`** porque la laptop se apaga sola por sobrecalentamiento **bastante seguido** (en arreglo). Con `false`, un apagón abrupto puede perder/corromper los últimos chunks; con `true` se guarda a disco de forma segura. Además la laptop tiene **SSD/NVMe**, así que el costo de fluidez de `true` es mínimo (casi imperceptible). Cuando la temperatura esté resuelta, se puede volver a evaluar `false`. |

**Verificados y ya correctos (no se tocaron):** `server-ip=` vacío (bind a
`0.0.0.0`), `prevent-proxy-connections=false` (CRÍTICO: playit es un proxy),
`player-idle-timeout=0` (no expulsa durante cargas largas), `view-distance=8`,
`simulation-distance=6` (equilibrio login/CPU sin arruinar la atmósfera del pack).

*Opcional a futuro (no aplicado para no alterar la experiencia de terror):* bajar
`entity-broadcast-range-percentage` de 100 a ~75 ahorraría algo de subida, a costa
de que mobs lejanos se "actualicen" un poco menos.

---

## ⚙️ JVM / RENDIMIENTO — Aikar's flags (2026-07-07) — aplicadas

Se afinó `user_jvm_args.txt` de **Cave Horror Project** con el set canónico de
**Aikar's flags** (G1GC) para un heap de **8 GB**, en **Java 17** (Temurin
17.0.19, el portátil de `tools\java\17`). Respaldo en `user_jvm_args.txt.bak`.

| Ajuste | Antes | Ahora | Por qué |
|--------|-------|-------|---------|
| `-Xms` (RAM inicial) | 4G | **8G** | Aikar recomienda **Xms = Xmx**: la JVM no pierde tiempo agrandando el heap en caliente (menos tirones al cargar chunks/logins). Con `AlwaysPreTouch` la memoria igual se reserva de una; fijarla evita el churn. |
| `-Xmx` (RAM máxima) | 8G | **8G (sin cambios)** | Se **mantiene en 8 GB a propósito**. NO se sube por el **sobrecalentamiento** de la laptop (en arreglo): más RAM = más presión/calor sin necesidad real hoy. La laptop tiene 23 GB, así que 8 GB no ahoga al sistema. |
| Resto de flags G1GC | ya estaban | **se dejaron (son los de Aikar)** | `+UseG1GC`, `+ParallelRefProcEnabled`, `MaxGCPauseMillis=200`, `+DisableExplicitGC`, `+AlwaysPreTouch`, `G1NewSizePercent=30`, `G1MaxNewSizePercent=40`, `G1HeapRegionSize=8M`, `G1ReservePercent=20`, `InitiatingHeapOccupancyPercent=15`, etc. Son el estándar actual para 1.20.1 + muchos mods. NO se metieron flags de heaps grandes (>12 GB). |

**Verificado:** se corrió el `java.exe` de Java 17 con esos flags + `-version` y la
JVM los **aceptó limpio** (sin `Unrecognized VM option`, exit 0). Con
`-XX:+PrintFlagsFinal` se confirmó `UseG1GC=true`, `InitialHeapSize=MaxHeapSize=8 GB`,
`MaxGCPauseMillis=200`, `AlwaysPreTouch=true`, `G1HeapRegionSize=8M`. El arranque
(`run.bat`) sigue leyendo `user_jvm_args.txt` con un flag por línea, sin cambios.

### 🧱 Chunky (pre-generación de chunks) — YA instalado
El mod **Chunky** (de *pop4959*, el oficial) **ya está en `mods\` (`Chunky-1.3.146.jar`)**
y es compatible con Forge 1.20.1 (declara Forge `[46,)` y Minecraft `[1.20,1.21)`).
Es server-side y seguro. Pre-generar chunks **de antemano** evita los tirones de
generar terreno en vivo cuando entran los amigos. Cómo usarlo, en la consola del
server (o por RCON):

```
/chunky radius 3000     (radio en bloques desde el spawn; 3000 es un buen inicio)
/chunky start           (arranca la pre-generación; puede tardar y usar CPU)
/chunky pause  |  /chunky continue  |  /chunky cancel
```

> ⚠️ Por el **sobrecalentamiento**: pre-generar es intensivo en CPU. Hacelo en
> ratos cortos (`pause`/`continue`) y con la laptop bien ventilada, o cuando el
> tema térmico esté resuelto. No es urgente; el server funciona sin pre-generar.

---

## 🧭 VEREDICTO ACTUAL (2026-07-07)

- **Quedarse en playit.gg optimizado** (server afinado arriba + tip de IPv4 en el
  cliente del amigo afectado). Es lo de menos fricción y ya funciona para la mayoría.
- **Plan B: Tailscale** (LAN virtual) si algún amigo sigue con handshake inestable.
  Todo listo, no hay que tocar el server (ver Plan #1b).
- **Candidato a probar: E4MC** (mod de túnel gratis que se activa desde el propio
  Minecraft/mundo; genera una dirección temporal). Puede ser aún más simple que
  playit para sesiones puntuales; queda pendiente de evaluar.
- **Ethernet (a futuro):** hoy la laptop va por **WiFi** y todo está pensado para
  funcionar así (no depende de abrir puertos ni de cable). Cuando se pueda pasar la
  laptop a **cable Ethernet**, la subida será más estable y bajará la latencia del
  relay — **mejora recomendada, no requisito**.

---

## VEREDICTO CORTO

**playit.gg NO es la opción más estable para tu caso.** No hace falta tirarlo a la
basura todavía, pero:

1. **Probá primero un ajuste de 2 minutos en playit** (ponerlo en **solo IPv4** +
   elegir región). Esto ataca EXACTO el problema que ya diagnosticamos: el IPv6
   flojo de la red del amigo. Es gratis, no cambia nada para los amigos, y puede
   alcanzar. **Empezá por acá.**
2. **Si querés lo más estable y GRATIS:** cambiá la capa de red a **Tailscale**
   (una LAN virtual / VPN mesh). Tus amigos entran por una IP como si estuvieran
   en tu casa. Suele ser más estable para el "handshake" pesado de 136 mods y
   elimina el problema del IPv6. Costo: cada amigo instala Tailscale y hace login
   una vez.
3. **Si estás dispuesto a pagar ~US$20–24/mes y que "simplemente funcione":**
   contratá **hosting administrado** (BisectHosting/Apex). Es la única opción que
   elimina TODO el lío (túnel, VPN, NAT, configuraciones), corre 24/7 con IP
   pública real y buena conexión para todos, **incluido vos**.

Por qué playit falla en tu caso: playit es un **relay TCP compartido** en un
datacenter (todos pasan por ahí, incluido el host que hace un rodeo). Ese relay es
justo lo que corta el handshake de mods a la mitad, y su dominio doble
(IPv4 + IPv6) hace que la red del amigo elija el IPv6 malo. Una VPN mesh o el
hosting pago no tienen ese cuello.

---

## RANKING

| # | Opción | Costo | ¿Amigos instalan algo? | Estabilidad esperada | Para no-técnicos |
|---|--------|-------|------------------------|----------------------|------------------|
| 1a | **playit en solo-IPv4 + región** (probar YA) | Gratis | No (misma dirección) | Media-alta si el problema era el IPv6 | Fácil (solo el host toca el panel) |
| 1b | **Tailscale** (LAN virtual) | Gratis (hasta 6 usuarios) | Sí: instalar + login 1 vez | Alta (P2P directo) o Media-alta (si cae a relay, igual mejor que playit) | Media (una instalación guiada) |
| 2 | **Hosting administrado** (BisectHosting 8GB) | ~US$20–24/mes | No | Muy alta (IP pública real, 24/7) | Muy fácil (nada que configurar) |
| 3 | **ZeroTier** (LAN virtual alternativa) | Gratis (25 nodos) | Sí: instalar + ID de red | Alta/Media, parecida a Tailscale | Media (host autoriza a cada amigo) |
| 4 | **Radmin VPN** (LAN virtual, solo Windows) | Gratis | Sí: instalar (sin cuenta) | Media | Fácil, pero solo Windows y menos transparente |
| — | **Cloudflare Tunnel / ngrok / bore** | — | Sí/limitado | Mala para MC | ❌ No recomendado (ver abajo) |

### Por qué se descartan los túneles públicos
- **Cloudflare Tunnel:** solo hace HTTP/HTTPS bien. Para el TCP crudo de Minecraft
  necesitás que **cada amigo instale `cloudflared`** o pagar Spectrum (plan
  Enterprise). Peor que playit para esto.
- **ngrok (gratis):** para TCP te pide **tarjeta**, la **dirección cambia cada vez**
  que reinicia, y tiene **límite de datos** mensual. No sirve para algo estable.
- **bore / localhost.run / serveo:** relays chicos, sin garantías, direcciones
  cambiantes. No para un grupo fijo.

---

## PLAN #1a — Ajuste rápido de playit (probá esto primero, gratis, 2 min)

No cambia nada para los amigos; la dirección `wildland-priced.gl.joinmc.link` sigue
igual. Solo lo hace el host:

1. Entrá a **https://playit.gg** e iniciá sesión.
2. Menú **Agents** → elegí el agente `from-key-9e1d` (el de esta laptop).
3. Ponelo en **IPv4 only** (fuerza IPv4, evita el IPv6 malo del amigo).
4. Cambiá la **región** a la más cercana a ustedes (mirá el ping en
   https://ping.playit.gg). Puede que tengas que probar 2–3 regiones.
5. Que el amigo **reinicie Minecraft** y vuelva a entrar. Probá el handshake de mods.

Si con esto el amigo entra estable → **listo, quedate con playit** (es lo de menos
fricción). Si sigue con rubber-banding o se corta el handshake → pasá al Plan #1b.

---

## PLAN #1b — Cambiar a Tailscale (lo más estable gratis)

**Qué NO cambia:** el server, los scripts, `Start.bat`, `Detener Server.bat`, el
mundo y los mods siguen igual. El server ya escucha en `0.0.0.0:25565`, así que
**no hay que tocar nada del server**. Solo cambia CÓMO se conectan los amigos.
El **host sigue entrando por LAN** (`localhost` o `192.168.100.49:25565`), directo
y perfecto — nada de rodeos.

### Lado HOST (una sola vez)
1. Descargá Tailscale de **https://tailscale.com/download** (Windows) e instalalo.
   *(Requiere permiso de administrador solo para instalar, como cualquier programa.)*
2. Abrí Tailscale e **iniciá sesión** (podés usar tu cuenta de Google — la más fácil).
3. Doble click en **`Ver IP Tailscale.bat`** (lo dejé preparado) para ver la IP
   `100.x.y.z` de esta laptop. **Esa IP + `:25565` es lo que le pasás a los amigos**
   (ej: `100.101.102.103:25565`).
4. Arrancá el server como siempre (podés usar `Start.bat`; el túnel de playit puede
   seguir prendido o no, da igual — Tailscale es independiente).

### Lado AMIGO (una sola vez cada uno, guialos por llamada)
1. Instalar Tailscale de **https://tailscale.com/download** e iniciar sesión.
2. El host los invita a su red Tailscale (**Admin console → Users → Invite**, o
   compartir el dispositivo del server con **Share**). El amigo **acepta la invitación**.
3. En Minecraft: **Multiplayer → Add Server →** pegar `100.x.y.z:25565` (la IP que
   dio el host). Necesita el modpack **Cave Horror Project 1 v3.4.1** instalado.
4. Listo. Entra como si estuviera en la LAN de tu casa.

**Plan gratis de Tailscale:** hasta **6 usuarios** (vos + 5 amigos) y dispositivos
ilimitados. Alcanza de sobra para este grupo.

**Honestidad sobre el "peor caso":** si tanto tu red como la del amigo son NAT muy
cerradas (CGNAT simétrico), Tailscale no logra conexión directa P2P y usa un
**relay propio (DERP)**. Aun así suele ser **mejor que playit** porque: (a) va por
WireGuard/UDP, más robusto para la ráfaga de 136 mods; (b) evita el IPv6 problemático;
(c) elige el mejor camino solo. Si logra P2P directo (lo más común), es claramente
superior en latencia. En casi todos los casos, igual o mejor que playit.

---

## PLAN #2 — Hosting administrado (si querés pagar y olvidarte)

La opción que **realmente elimina el problema de raíz** para un grupo no-técnico:
- **BisectHosting "BisectOne" 8GB ≈ US$23.99/mes** (aprox US$3/GB, slots ilimitados,
  instalación de modpacks en 1 click; muchos packs tipo Cave Horror están listos).
  Apex Hosting es similar en precio.
- **Qué elimina:** sin túnel, sin VPN, sin abrir puertos, sin NAT, sin depender de
  tu laptop ni de tu subida. IP pública real y buen peering para **todos, incluido vos**.
  Corre **24/7** aunque apagues la laptop. Los amigos solo pegan una dirección.
- **Contras:** es un gasto mensual y el mundo/mods viven en el server del proveedor
  (se puede migrar tu mundo actual subiéndolo). La laptop queda libre.

Si la frustración con la conexión es lo que más pesa y no te molesta pagar, **esta
es objetivamente la mejor experiencia**. Si "gratis" es requisito, quedate en 1a/1b.

---

## Recordatorio de lo que YA está listo (no se toca)
- Server Cave Horror sano (TPS 20/20, 8GB), scripts de arranque/apagado, RCON,
  menú `Start.bat`, `Detener Server.bat`. Todo eso se reutiliza igual con cualquier
  opción; **solo cambia la capa de red**.
- Preparado sin riesgo para el camino Tailscale: script
  `_shared\scripts\show-tailscale-address.ps1` (inerte hasta que instales Tailscale).

## Fuentes
- Tailscale plan gratis (6 usuarios, dispositivos ilimitados): tailscale.com/pricing
- Tailscale y CGNAT / tipos de conexión (directo vs DERP): tailscale.com/docs/reference/connection-types y blog NAT traversal
- ZeroTier gratis (25 nodos): zerotier.com/pricing
- Radmin VPN (gratis, solo Windows, cap 100 Mbps): radmin-vpn.com
- Cloudflare Tunnel/ngrok límites para Minecraft TCP: ngrok.com/docs/using-ngrok-with/minecraft
- playit IPv4-only + regiones/ping: playit.gg/support/how-to-lower-ping
- Precio hosting modded 8GB: bisecthosting.com/minecraft-servers

# Game Servers — Guía rápida

Esta carpeta te deja levantar servers de juegos en tu propia PC, usando **playit.gg**
para que la gente se conecte sin tener que abrir puertos en el router.

Todo es **gratis** (Java de Adoptium + playit.gg) y no necesitás instalar nada
a mano: Java se descarga solo la primera vez que hace falta.

## ✅ Requisitos

- Windows.
- Conexión a internet (para descargar el modpack, Java y el túnel).
- No hace falta ser admin de la PC ni tener Minecraft instalado en esta
  máquina — solo tus amigos necesitan el juego para conectarse.

---

## 🆕 Primera vez (no tenés ningún server todavía)

1. Doble click en `Start.bat`.
2. Como todavía no creaste ningún server, el menú va a mostrar solo la opción
   **"Crear un server nuevo"**. Elegila.
3. Te va a pedir:
   - Un **nombre** para el server (el que quieras, ej. `MiModpack`).
   - La **ruta o link a un archivo `.mrpack`** (ver abajo cómo conseguirlo).
     Si no tenés uno todavía, apretá Enter y lo instalás a mano después
     (ver "Agregar OTRO modpack" más abajo).
4. El script instala todo solo: descarga mods y server jar, detecta qué
   versión de Java necesita, te pregunta cuánta memoria RAM darle, y te pide
   que aceptes la EULA de Minecraft (tenés que leerla y escribir `acepto`).
5. Listo — volvé a abrir `Start.bat` y ahora vas a ver tu server en la lista.
   Elegilo para arrancarlo (ver la sección de abajo).

### ¿Dónde consigo un archivo `.mrpack`?

Los modpacks de [Modrinth](https://modrinth.com) traen este formato:

1. Entrá a la página del modpack en modrinth.com.
2. Andá a la pestaña **"Versions"** y elegí la versión que quieras.
3. Descargá el archivo que termina en **`.mrpack`** (es el modpack completo,
   no un mod individual).
4. Guardalo en cualquier carpeta (ej. Descargas) y usá esa ruta en el paso 3
   de arriba — o copiá el link de descarga directa y pegalo en vez de la ruta.

> **Importante:** la instalación automática hoy solo funciona con modpacks de
> **Fabric**. Si el `.mrpack` es de Forge, Quilt o NeoForge, el script te va a
> avisar y te va a mandar a la "Opción manual" de abajo (todavía no se puede
> instalar solo). Los modpacks de **CurseForge** tampoco tienen `.mrpack` —
> para esos también seguí la "Opción manual".

---

## ▶ Cómo arrancar un server (lo normal del día a día)

1. Doble click en `Start.bat` (o en el acceso directo del escritorio, si te
   armaste uno).
2. Sale un menú con los servers que tenés. Elegí el número.
3. Se abre el **túnel de playit.gg** y arranca el server.

---

## ⏹ Cómo APAGAR el server (la forma fácil y segura)

**Doble click en `Detener Server.bat`** (en esta misma carpeta).

Eso hace todo solo:
- Le manda `stop` al server para que **guarde el mundo bien**.
- Espera a que termine de cerrar.
- Cierra el **túnel de playit.gg**.

No hace falta buscar la ventana ni escribir nada. Cuando dice "Listo", ya está.

> Detecta solo cuál server está corriendo, así que sirve aunque lo hayas
> arrancado desde el menú y ya no encuentres la ventana.

**Evitá cerrar con la X** de la ventana: puede matar el server sin guardar el
mundo. Usá `Detener Server.bat`. (Si igual apretás Ctrl+C o cerrás la ventana,
el sistema ahora intenta guardar por las dudas, pero el botón es lo seguro.)

También podés apagarlo escribiendo `stop` en la ventana del server, como antes.

---

## 🌐 playit.gg — la PRIMERA vez (solo una vez, antes de invitar amigos de afuera)

Si arrancás un server y la ventana dice que **falta `secret.key`** (playit.gg
todavía no está vinculado a tu cuenta), corré esto una sola vez:

```
powershell -ExecutionPolicy Bypass -File "_shared\scripts\setup-playit.ps1"
```

1. El script te va a mostrar un **link** y lo abre solo en el navegador.
2. Iniciá sesión (creá cuenta gratis si no tenés) y apretá "Allow / Claim".
3. Esperá a que el script diga "OK! playit.gg quedo vinculado".
4. Paso final (una sola vez): entrá a
   [playit.gg/account/tunnels](https://playit.gg/account/tunnels), "Add Tunnel"
   → tipo **Minecraft Java** → que apunte al puerto local `25565`.

Las siguientes veces reconecta solo, no tenés que hacer nada. Cada vez que
arranques un server vas a ver la **dirección para tus amigos** (tipo
`algo.playit.gg`) grande en la consola, y se copia sola al portapapeles.

Sin este paso, el server igual funciona para gente en tu misma WiFi
(`<IP-local>:25565`) — solo hace falta para amigos de otra red.

---

## 🛠 ¿Los amigos remotos laguean / se corta el handshake de mods?

Si la conexión con amigos de afuera es inestable (rubber-banding, timeouts, se
corta la sincronización de mods), leé **`CONEXION - Opciones y Plan.md`** en esta
carpeta. Resumen del veredicto:

1. **Probá primero (gratis, 2 min):** en el panel de playit.gg poné el agente en
   **solo IPv4** y elegí la **región** más cercana. Ataca justo el problema del
   IPv6 flojo. No cambia nada para los amigos.
2. **Lo más estable gratis:** cambiar a **Tailscale** (LAN virtual). Cada amigo
   instala Tailscale y hace login una vez; entra por una IP `100.x.x.x:25565`.
   El script `Ver IP Tailscale.bat` te muestra tu IP (funciona recién cuando
   instales Tailscale).
3. **Si querés pagar y olvidarte:** hosting administrado (~US$20–24/mes) — sin
   túnel, sin VPN, 24/7, la mejor experiencia para todos.

---

## ➕ Agregar OTRO modpack de Minecraft

Opción fácil (recomendada), si el modpack está en Modrinth (trae un archivo
`.mrpack`, ver "¿Dónde consigo un archivo `.mrpack`?" más arriba):
1. Abrí `Start.bat` y elegí la opción **"Crear un server nuevo"** del menú.
2. Poné un nombre y pegá la ruta o el link del `.mrpack` cuando te lo pida.
3. El script instala mods, server jar y config solo, detecta la versión de Java
   que necesita, te pregunta la RAM y te pide que aceptes la EULA.
4. Arrancalo desde el menú (`Start.bat`).

Opción manual (para modpacks de CurseForge, que no tienen `.mrpack`):
1. `Minecraft\scripts\new-server.ps1 -Name "NombreDelPack"`
2. Copiá los "Server Files" del modpack dentro de esa carpeta nueva.
3. Editá `run.config.ps1` (versión de Java) y `user_jvm_args.txt` (memoria).
4. Poné `eula=true` en `eula.txt`.
5. Arrancalo desde el menú (`Start.bat`).

---

## ❓ Problemas comunes (primera vez)

**Windows Defender pregunta "¿Permitir acceso?" para Java o playit.exe.**
Es normal — el server necesita abrir un puerto de red. Apretá **"Permitir
acceso"** (Allow access). Si lo cerrás o le decís que no, el server anda pero
tus amigos de otra red no van a poder conectarse.

**El antivirus borra o bloquea `playit.exe` o `mrpack.exe`.**
Son herramientas de terceros sin firma digital, así que algún antivirus
puede marcarlas como sospechosas por las dudas. Si un server no arranca o
`new-server.ps1` dice que no encuentra `mrpack.exe`/`playit.exe`, revisá la
cuarentena/historial de tu antivirus y restauralos (son seguros: son las
mismas herramientas oficiales de Modrinth y playit.gg).

**El server no arranca / se cierra solo con un error de memoria.**
Puede ser que el modpack pida más RAM de la que tiene tu PC. Fijate cuánta
memoria RAM total tenés (clic derecho en la barra de tareas → Administrador
de tareas → Rendimiento) y no le asignes al server más de lo que sobra
después de dejarle algo a Windows (ej. si tenés 16 GB, no le des más de
10-12 GB al server).

**La primera vez tarda mucho / parece colgado.**
La primera vez que arrancás, se descarga Java (si hace falta) y, si creaste
el server con un `.mrpack`, también los mods y el server jar. Puede tardar
varios minutos según tu internet — dejalo correr.

---

## 🕹 Otros juegos (a futuro)

La estructura ya está pensada para más juegos, no solo Minecraft. Cuando
quieras sumar uno (que tenga server dedicado), se crea una carpeta al lado de
`Minecraft\` con la misma lógica y el menú de `Start.bat` lo detecta solo.
El túnel de playit.gg (`_shared\tools\playit`) se reusa para todos.

---

## 📁 Cómo está organizado

```
GameServers\
  Start.bat / Start.ps1        <- menú para arrancar cualquier server (o crear uno nuevo)
  Detener Server.bat           <- apaga el server de forma segura (guarda el mundo)
  _shared\
    tools\playit\playit.exe    <- túnel playit.gg (compartido)
    tools\mrpack.exe           <- instalador de modpacks de Modrinth
  Minecraft\
    tools\java\                <- versiones de Java portátiles (se descargan solas)
    scripts\                   <- new-server.ps1, install-java.ps1
    servers\
      _template\               <- plantilla base para nuevos servers
      TuModpack\                <- cada server que crees aparece acá
```

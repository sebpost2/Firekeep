# Game Servers — Guía rápida

Esta carpeta corre servers de juegos en esta laptop, usando **playit.gg** para que
la gente se conecte sin tener que abrir puertos en el router.

Todo es **gratis** (Java de Adoptium + playit.gg).

---

## ▶ Cómo arrancar un server (lo normal del día a día)

1. Doble click en el acceso directo **"Game Servers"** del escritorio
   (o abrí `Start.bat` en esta carpeta).
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

> El server en sí está impecable; lo que falla es SOLO cómo viaja la conexión.

---

## 🌐 playit.gg — la PRIMERA vez (solo una vez)

La primera vez que arranca, playit.gg te va a mostrar un **link** en la consola.

1. Abrí ese link en el navegador e iniciá sesión (creá cuenta gratis si no tenés).
2. En el panel de playit.gg, agregá un túnel:
   - Tipo: **Minecraft Java**
   - Local address: `127.0.0.1:25565`
3. playit.gg te da una **dirección** tipo `algo.playit.gg` (o `algo.gl.joinmc.link`).
   **Esa** es la que le pasás a tus amigos para que entren al server.

Las siguientes veces reconecta solo, no tenés que hacer nada.

---

## 🎮 Servers instalados

### Cave Horror Project (Minecraft 1.20.1, Forge)
- Modpack de terror con +130 mods. Versión **v3.4.1**.
- Carpeta: `Minecraft\servers\Cave Horror Project\`
- Memoria asignada: **8 GB** (editable en `user_jvm_args.txt`).
- **Importante:** tus amigos necesitan el **mismo modpack** instalado en su
  CurseForge (Cave Horror Project 1, v3.4.1) para poder entrar.
- **Optimizado (2026-07-07)** para aguantar mejor sobre playit + WiFi: más
  compresión de red, watchdog con más margen y escritura de chunks no bloqueante.
  El detalle está en `CONEXION - Opciones y Plan.md`.

> 💡 Al arrancar, la ventana **muestra la dirección bien grande y la copia sola al
> portapapeles**: pegala en WhatsApp con Ctrl+V. También incluye un mensaje listo
> para un amigo nuevo (dirección + modpack + tip si no entra).

---

## ➕ Agregar OTRO modpack de Minecraft

Opción fácil (recomendada), si el modpack está en Modrinth o tenés el `.mrpack`:
1. Pedímelo y te lo dejo instalado como hice con Cave Horror Project.

Opción manual:
1. `Minecraft\scripts\new-server.ps1 -Name "NombreDelPack"`
2. Copiá los "Server Files" del modpack dentro de esa carpeta nueva.
3. Editá `run.config.ps1` (versión de Java) y `user_jvm_args.txt` (memoria).
4. Poné `eula=true` en `eula.txt`.
5. Arrancalo desde el menú (`Start.bat`).

---

## 🕹 Otros juegos (a futuro)

La estructura ya está pensada para más juegos, no solo Minecraft. Cuando
quieras sumar uno (que tenga server dedicado), se crea una carpeta al lado de
`Minecraft\` con la misma lógica y el menú de `Start.bat` lo detecta solo.
El túnel de playit.gg (`_shared\tools\playit`) se reusa para todos.

> Nota: Hytale todavía no tiene server dedicado público; cuando salga, se agrega acá.

---

## 📁 Cómo está organizado

```
GameServers\
  Start.bat / Start.ps1        <- menú para arrancar cualquier server
  Detener Server.bat           <- apaga el server de forma segura (guarda el mundo)
  _shared\
    tools\playit\playit.exe    <- túnel playit.gg (compartido)
    tools\mrpack.exe           <- instalador de modpacks de Modrinth
  Minecraft\
    tools\java\17, \21         <- versiones de Java portátiles (sin instalar nada)
    scripts\                   <- new-server.ps1, install-java.ps1
    servers\
      _template\               <- plantilla base para nuevos servers
      Cave Horror Project\     <- el server instalado (mods, config, mundo)
```

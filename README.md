# Game Servers — Quick Guide

This folder lets you run game servers on your own PC, using **playit.gg** so
people can connect without opening ports on your router.

It's all **free** (Adoptium Java + playit.gg) and you don't need to install
anything by hand: Java downloads itself the first time it's needed.

## Requirements

- Windows.
- Internet connection (to download the modpack, Java, and the tunnel).
- You don't need to be an admin on the PC or have Minecraft installed on
  this machine — only your friends need the game to connect.

---

## First time (you don't have any server yet)

1. Double-click `Start.bat`.
2. Since you haven't created a server yet, the menu will show only the
   **"Create a new server"** option. Pick it.
3. It'll ask you for:
   - A **name** for the server (whatever you like, e.g. `MyModpack`).
   - The **path or link to a `.mrpack` file** (see below on how to get one).
     If you don't have one yet, press Enter and install it manually later
     (see "Add ANOTHER modpack" below).
4. The script installs everything on its own: downloads mods and the server
   jar, detects which Java version it needs, asks how much RAM to give it,
   and asks you to accept the Minecraft EULA (you have to read it and type `accept`).
5. Done — open `Start.bat` again and you'll now see your server in the list.
   Pick it to start it (see the section below).

### Where do I get a `.mrpack` file?

Modpacks from [Modrinth](https://modrinth.com) come in this format:

1. Go to the modpack's page on modrinth.com.
2. Go to the **"Versions"** tab and pick the version you want.
3. Download the file ending in **`.mrpack`** (that's the whole modpack,
   not an individual mod).
4. Save it anywhere (e.g. Downloads) and use that path in step 3 above —
   or copy the direct download link and paste that instead of the path.

> **Important:** automatic installation currently only works with **Fabric**
> modpacks. If the `.mrpack` is Forge, Quilt, or NeoForge, the script will
> warn you and point you to the "Manual option" below (it can't be
> auto-installed yet). **CurseForge** modpacks don't have a `.mrpack`
> either — for those, also follow the "Manual option".

---

## Starting a server (day-to-day)

1. Double-click `Start.bat` (or a desktop shortcut, if you made one).
2. A menu with your servers shows up. Pick the number.
3. The **playit.gg tunnel** opens and the server starts.

---

## Stopping the server (the easy, safe way)

**Double-click `Stop Server.bat`** (in this same folder).

That does everything on its own:
- Sends `stop` to the server so it **saves the world properly**.
- Waits for it to finish closing.
- Closes the **playit.gg tunnel**.

No need to find the window or type anything. When it says "Done", you're set.

> It automatically detects which server is running, so it works even if you
> started it from the menu and can no longer find the window.

**Avoid closing with the X** on the window: it can kill the server without
saving the world. Use `Stop Server.bat`. (If you do press Ctrl+C or close the
window anyway, the system now tries to save just in case, but the button is
the safe option.)

You can also stop it by typing `stop` in the server's window, like before.

---

## playit.gg — the FIRST time (only once, before inviting friends from outside)

If you start a server and the window says **`secret.key` is missing**
(playit.gg isn't linked to your account yet), run this once:

```
powershell -ExecutionPolicy Bypass -File "_shared\scripts\setup-playit.ps1"
```

1. The script will show you a **link** and open it in your browser on its own.
2. Sign in (create a free account if you don't have one) and click "Allow / Claim".
3. Wait for the script to say "OK! playit.gg is linked".
4. Last step (once): go to
   [playit.gg/account/tunnels](https://playit.gg/account/tunnels), "Add Tunnel"
   → type **Minecraft Java** → point it to local port `25565`.

From then on it reconnects on its own, nothing to do. Every time you start
a server you'll see the **address for your friends** (something like
`something.playit.gg`) big in the console, copied to your clipboard automatically.

Without this step, the server still works for people on your same WiFi
(`<local-IP>:25565`) — it's only needed for friends on another network.

---

## Remote friends lagging / mod handshake cutting out?

If the connection with friends from outside is unstable (rubber-banding,
timeouts, mod sync cutting out), there's a general troubleshooting rundown:

1. **Try this first (free, 2 min):** in the playit.gg panel, set the agent to
   **IPv4 only** and pick the closest **region**. This targets a common
   flaky-IPv6 issue head-on. Nothing changes for your friends.
2. **Most stable free option:** switch to **Tailscale** (virtual LAN). Each
   friend installs Tailscale and logs in once; they connect via an IP like
   `100.x.x.x:25565`. The `View Tailscale IP.bat` script shows you your IP
   (works once you've installed Tailscale).
3. **If you want to pay and forget about it:** managed hosting (~$20–24/mo) —
   no tunnel, no VPN, 24/7, the best experience for everyone.

---

## Adding ANOTHER Minecraft modpack

Easy option (recommended), if the modpack is on Modrinth (comes with a
`.mrpack` file, see "Where do I get a `.mrpack` file?" above):
1. Open `Start.bat` and pick **"Create a new server"** from the menu.
2. Enter a name and paste the path or link to the `.mrpack` when asked.
3. The script installs mods, server jar, and config on its own, detects the
   Java version it needs, asks about RAM, and asks you to accept the EULA.
4. Start it from the menu (`Start.bat`).

Manual option (for CurseForge modpacks, which don't have a `.mrpack`):
1. `Minecraft\scripts\new-server.ps1 -Name "PackName"`
2. Copy the modpack's "Server Files" into that new folder.
3. Edit `run.config.ps1` (Java version) and `user_jvm_args.txt` (memory).
4. Set `eula=true` in `eula.txt`.
5. Start it from the menu (`Start.bat`).

---

## Common problems (first time)

**Windows Defender asks "Allow access?" for Java or playit.exe.**
That's normal — the server needs to open a network port. Click **"Allow
access"**. If you close it or say no, the server still runs but friends on
another network won't be able to connect.

**Antivirus deletes or blocks `playit.exe` or `mrpack.exe`.**
These are third-party tools without a digital signature, so some antivirus
software may flag them as suspicious just in case. If a server won't start
or `new-server.ps1` says it can't find `mrpack.exe`/`playit.exe`, check your
antivirus's quarantine/history and restore them (they're safe: they're the
same official tools from Modrinth and playit.gg).

**The server won't start / closes on its own with a memory error.**
The modpack might be asking for more RAM than your PC has. Check your total
RAM (right-click the taskbar → Task Manager → Performance) and don't assign
the server more than what's left over after leaving Windows some room (e.g.
if you have 16 GB, don't give the server more than 10-12 GB).

**The first time takes forever / looks stuck.**
The first time you start it, Java downloads (if needed) and, if you created
the server with a `.mrpack`, so do the mods and the server jar. It can take
several minutes depending on your internet — let it run.

---

## Other games (down the road)

The structure is already built for more games, not just Minecraft. When you
want to add one (that has a dedicated server), a folder gets created next to
`Minecraft\` following the same logic, and the `Start.bat` menu picks it up
on its own. The playit.gg tunnel (`_shared\tools\playit`) is reused for all of them.

---

## How it's organized

```
GameServers\
  Start.bat / Start.ps1        <- menu to start any server (or create a new one)
  Stop Server.bat               <- stops the server safely (saves the world)
  _shared\
    tools\playit\playit.exe    <- playit.gg tunnel (shared)
    tools\mrpack.exe           <- Modrinth modpack installer
  Minecraft\
    tools\java\                <- portable Java versions (download themselves)
    scripts\                   <- new-server.ps1, install-java.ps1
    servers\
      _template\               <- base template for new servers
      YourModpack\              <- each server you create shows up here
```

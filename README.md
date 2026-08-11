# Firekeep — Quick Guide

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

1. Double-click `Start.bat`. A window opens.
2. Since you haven't created a server yet, the picker at the top will be
   empty — click **New Server**.
3. Fill in the form:
   - A **name** for the server (whatever you like, e.g. `MyModpack`).
   - The **modpack** — drag the downloaded file straight onto the field, or
     click **Browse...** to pick it, or paste a direct download link (see
     below on where to get one). Leave it blank if you don't have one yet —
     you can copy files in manually later (see "Adding ANOTHER Minecraft
     modpack" below).
   - **Max memory** (defaults to `6G`, edit if you need more/less).
   - Check the box confirming you've read the **Minecraft EULA**.
4. Click **Create Server**. It installs everything on its own: extracts the
   modpack, downloads mods and the server jar (Modrinth packs) or copies the
   server files in (CurseForge packs), detects which Java version it needs,
   and sets up the server files.
5. Done — you're back on the main screen and your new server is selected.
   Click **Start Server** (see the section below).

### Where do I get a modpack file?

**From [Modrinth](https://modrinth.com):**

1. Go to the modpack's page on modrinth.com.
2. Go to the **"Versions"** tab and pick the version you want.
3. Download the file ending in **`.mrpack`** (that's the whole modpack,
   not an individual mod).
4. Drag that file onto the Modpack field, browse for it, or paste the
   direct download link instead.

**From [CurseForge](https://www.curseforge.com):**

1. Go to the modpack's page, the **"Files"** tab, and download the
   **"Server Files"** package for the version you want (not the regular
   modpack download — that's for a client, not a server).
2. Drag that `.zip` onto the Modpack field, or browse for it.

> **Important:** automatic installation currently only works with **Fabric**
> `.mrpack` modpacks. If the `.mrpack` is Forge, Quilt, or NeoForge, it'll
> warn you and point you to creating the server without a modpack instead
> (it can't be auto-installed yet — see "Adding ANOTHER Minecraft modpack"
> below for the manual option). CurseForge `.zip` Server Files are detected
> and copied in automatically for **Forge and Fabric** (and any pack built
> with the ServerPackCreator tool, regardless of loader) — for anything else
> it'll tell you so you can fall back to the manual option.

---

## Starting a server (day-to-day)

1. Double-click `Start.bat`.
2. Pick your server from the dropdown at the top (if you have more than one).
3. Click **Start Server**. The campfire lights up once it's running, and the
   address for your friends appears below it.

---

## Stopping the server (the easy, safe way)

Click **Stop Server** in the same window. That does everything on its own:

- Sends `stop` so the server **saves the world properly**.
- Waits for it to finish closing.
- Closes the **playit.gg tunnel**.

**Avoid closing the app with the X while a server is running** — it now
tries to save on its way out too, but the Stop Server button is the
guaranteed-safe option.

Need to run a raw command (like `list` or `say hi`)? Open **Console** from
the main screen — it shows the live server log and a box to send commands
without needing a second window.

---

## playit.gg — the FIRST time (only once, before inviting friends from outside)

If the address card says **"Same WiFi only (no sharing set up yet)"**,
playit.gg isn't linked to your account yet. Click **Set up sharing** on the
main screen:

1. It'll show you a **link** and open it in your browser on its own.
2. Sign in (create a free account if you don't have one) and click "Allow / Claim".
3. Wait for it to finish linking.
4. Last step (once): go to
   [playit.gg/account/tunnels](https://playit.gg/account/tunnels), "Add Tunnel"
   → type **Minecraft Java** → point it to local port `25565`.

From then on it reconnects on its own, nothing to do. Every time the server's
running you'll see the **address for your friends** (something like
`something.playit.gg`) on the main screen, with a **Copy** button next to it.

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
   `100.x.x.x:25565`. Find your own Tailscale IP in the Tailscale tray
   icon/app on your PC (click your device — no need for a separate script).
3. **If you want to pay and forget about it:** managed hosting (~$20–24/mo) —
   no tunnel, no VPN, 24/7, the best experience for everyone.

---

## Managing worlds

Click **Manage Maps** on the main screen to switch between worlds, create a
new one, import a `.zip`, or send one to the trash (recoverable from
**View trash** until you empty it). The server needs to be stopped first to
make changes.

---

## Adding ANOTHER Minecraft modpack

Easy option (recommended), for Modrinth `.mrpack` files or CurseForge
"Server Files" `.zip` downloads (see "Where do I get a modpack file?" above):

1. Click **New Server** on the main screen.
2. Enter a name and drag the file onto the Modpack field (or browse, or
   paste a link).
3. It extracts/installs everything on its own — mods, server jar, and
   config for `.mrpack`, or the server files themselves for a CurseForge
   `.zip` — detects the Java version it needs, and sets everything up.
4. Start it from the main screen once it's created.

Manual option (for CurseForge packs the auto-detection can't recognize, or
if you'd rather do it by hand):

1. Click **New Server**, enter a name, leave the modpack field blank, and
   check the EULA box — this creates a bare server folder under
   `Minecraft\servers\<Name>\` with the EULA already accepted, no separate
   step needed for that.
2. Copy the modpack's "Server Files" into that new folder.
3. Start it — the app tries to detect the right Java version on its own from
   whatever you copied in (works for Forge and Fabric packs, and for any
   pack built with the ServerPackCreator tool regardless of loader). If it
   can't figure it out, it just uses whatever's in `run.config.ps1`'s
   `$JavaVersion` (defaults to 21) — check the modpack's CurseForge page for
   its Minecraft version and edit that file if the server fails to start.
4. Optional: `user_jvm_args.txt` (memory) usually already comes with a
   working default from the modpack's own installer — only edit it if you
   want a different amount.
5. Start it from the main screen.

---

## Common problems (first time)

**Windows Defender asks "Allow access?" for Java or playit.exe.**
That's normal — the server needs to open a network port. Click **"Allow
access"**. If you close it or say no, the server still runs but friends on
another network won't be able to connect.

**Antivirus deletes or blocks `playit.exe` or `mrpack.exe`.**
These are third-party tools without a digital signature, so some antivirus
software may flag them as suspicious just in case. If server creation fails
saying it can't find `mrpack.exe`/`playit.exe`, check your antivirus's
quarantine/history and restore them (they're safe: they're the same official
tools from Modrinth and playit.gg).

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
`Minecraft\` following the same logic, and the app picks it up on its own.
The playit.gg tunnel (`_shared\tools\playit`) is reused for all of them.
Non-Minecraft games don't get the Console screen yet (it needs each game's
log path and command protocol wired up first).

---

## How it's organized

```text
Firekeep\
  Start.bat                     <- double-click this to open the app
  Start-Gui.ps1                 <- the app itself (Start.bat launches it)
  _shared\
    gui\                        <- the app's screens (XAML)
    scripts\                    <- shared logic behind the screens
    tools\playit\playit.exe    <- playit.gg tunnel (shared)
    tools\mrpack.exe           <- Modrinth modpack installer
  Minecraft\
    tools\java\                <- portable Java versions (download themselves)
    scripts\                   <- install-java.ps1
    servers\
      _template\               <- base template for new servers
      YourModpack\              <- each server you create shows up here
```

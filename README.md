# Firekeep — Quick Guide

This folder lets you run Minecraft servers on your own PC, using **playit.gg**
so people can connect without opening ports on your router. The structure is
organized so it could scale to other games down the road, but right now it's
Minecraft only.

It's all **free** (Adoptium Java + playit.gg) and you don't need to install
anything by hand: Java downloads itself the first time it's needed.

## Download

Grab the latest zip from the
**[Releases page](https://github.com/sebpost2/Firekeep/releases/latest)**,
extract it anywhere, and double-click `Start.bat`.

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

1. Go to the modpack's page, the **"Files"** tab, and download either the
   **"Server Files"** package or the regular modpack download (the one the
   CurseForge app uses) - Firekeep handles both.
2. Drag that `.zip` onto the Modpack field, or browse for it.

   With the regular modpack download, Firekeep downloads every mod itself
   (a few minutes for big packs). If a mod's author doesn't allow that,
   Home shows **Show missing mods** with a link to each one - put those
   files in the server's `mods` folder and press Start. If the server
   refuses to start because of a mod that only works in the game (not on a
   server), Home names it and offers **Move it aside and start again**.
   Only Forge modpacks for Minecraft 1.17 and newer can be imported this way
   for now.

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
timeouts, mod sync cutting out), try this first (free, 2 min): in the
playit.gg panel, set the agent to **IPv4 only** and pick the closest
**region**. This targets a common flaky-IPv6 issue head-on. Nothing changes
for your friends.

---

## Managing worlds

Click **Manage Maps** on the main screen to switch between worlds, create a
new one, import a `.zip`, or send one to the trash (recoverable from
**View trash** until you empty it). The server needs to be stopped first to
make changes.

**Backups happen on their own:** the first time you start a server each day,
its world is zipped into that server's `backups\` folder first (the newest 5
are kept). To go back to one, open **Manage Maps** → **Import** and pick the
zip.

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

## Scope

This is built for **Minecraft only** right now, with no other games planned.
The folder structure happens to be organized by game (`Minecraft\` sits next
to where another game's folder would go), so it's technically extensible,
but that's not an active roadmap item — just how it's laid out.

---

## Using your own port forwarding or a LAN address instead of playit.gg

Don't want to use playit.gg — you've already forwarded a port on your
router, or you only ever play with people on the same network? The
**manual address box** on the main screen (next to the address card) always
overrides playit.gg when it has something in it:

- **Port forwarded?** Enter your public IP (or DNS name) and port there.
- **LAN only?** Enter your local IP (e.g. `192.168.1.x:25565`) to force
  same-network play and skip playit.gg entirely.
- **Want playit.gg back?** Clear the box — it falls back to playit.gg
  automatically, or to your LAN address if playit.gg isn't set up.

---

## Editing server settings after creation

Click **Server Settings** on the main screen (server must be stopped) to
change difficulty, PvP, whitelist, max players, MOTD, spawn protection, and
max memory without hand-editing files. An **advanced** raw-text view covers
anything else in `server.properties`. RCON settings are never shown here —
they're managed by the app for its own use.

---

## Verity AI mod compatibility

If a modpack includes the **Verity** mod (VerityWorld/VerityCraft packs),
the app detects it automatically and shows an AI status panel on the main
screen (Core LLM / Voice out / Voice in). You can run it fully **local**
(free, downloads its own Ollama/Kokoro/Whisper sidecars on first use) or
point it at a **remote** AI provider instead — both are configurable from
the same panel, per server.

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

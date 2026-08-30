# Reforged Break Timer

A WoW addon that pops up a random picture and a countdown the moment your raid's [BigWigs](https://www.curseforge.com/wow/addons/big-wigs) break timer goes off. No setup, no commands to remember — install it once and it just works.

## Install it

1. Download this folder (ask whoever shared it with you for a `.zip`, or download it from wherever you got this link).
2. If it's a `.zip`, right-click it and **Extract All**.
3. Find your WoW AddOns folder. It's usually:

   `World of Warcraft\_retail_\Interface\AddOns\`

4. Drag the whole `ReforgedBreakTimer` folder into that `AddOns` folder, so you end up with:

   `World of Warcraft\_retail_\Interface\AddOns\ReforgedBreakTimer\ReforgedBreakTimer.toc`

5. If WoW was already running, type `/reload` in chat (or just restart WoW).

That's it — no PowerShell, no extra programs to install. You'll see "Reforged Break Timer" in your AddOns list at the character-select screen.

> **Requires [BigWigs](https://www.curseforge.com/wow/addons/big-wigs) to also be installed and enabled.** Reforged Break Timer watches for BigWigs' breaks and shows the popup — it doesn't start or track breaks by itself.

## Using it

There's nothing to turn on. The moment BigWigs calls a break, the popup appears on its own with a random picture and a live countdown, then disappears again when the break ends.

- **Move it**: click and drag anywhere on the popup. It remembers where you leave it.
- **Close it early**: click the × in the corner.
- **Settings**: click the gear icon on the popup, or go to **Game Menu (Esc) → Options → AddOns → Reforged Break Timer**. From there you can:
  - Turn individual pictures on or off (or Select All / Select None).
  - Reset the popup back to the center of the screen if you've lost it.

## Troubleshooting

- **Nothing shows up during a break** — make sure BigWigs is installed and enabled for your character, and that it's actually the one calling the break (not DBM or a manual raid warning).
- **The folder structure looks wrong** — `ReforgedBreakTimer.toc` must sit directly inside `AddOns\ReforgedBreakTimer\`, not nested in an extra folder (e.g. not `AddOns\ReforgedBreakTimer\ReforgedBreakTimer-main\ReforgedBreakTimer.toc`). If you extracted a zip and got an extra layer, move the inner folder's contents up one level.
- **It still doesn't show in your AddOns list** — fully quit and relaunch WoW rather than just `/reload`.

---

## For addon maintainers

The sections below are for whoever curates the pictures or maintains this repo — everyday users don't need any of this.

### Adding pictures

WoW addons run in a locked-down sandbox and can't read a folder's contents at runtime, so there's no "drop a file in and it just appears" — a small script has to regenerate a manifest file (`Images.lua`) instead.

**If your picture is already a `.tga` or `.blp`:**

1. Put it in `images/`.
2. Run `GenerateImages.ps1` (double-click it, or `./GenerateImages.ps1` in a PowerShell terminal here). It scans `images/` and rewrites `Images.lua`, turning `coffee_mug.tga` into the display name "Coffee Mug".
3. In-game: `/reload`, then toggle it on in the options panel if needed.

**If it's a PNG/JPG/BMP/GIF/WEBP instead:**

1. Put it in `images-src/` (not `images/`).
2. Run `./ConvertImages.ps1`. It converts each file to a same-named `.tga` in `images/` — via [ffmpeg](https://ffmpeg.org/) (must be on PATH; `winget install ffmpeg` if missing) — and automatically runs `GenerateImages.ps1` for you.
3. In-game: `/reload`.

`images-src/` is only a staging folder — nothing in it is ever deployed to WoW, so raw source files never bloat the shipped addon. Only `images/` (the `.tga`/`.blp` output) goes out.

Useful `ConvertImages.ps1` flags: `-Force` (reconvert even if a `.tga` already exists), `-DeleteOriginals` (delete the source file from `images-src/` once converted), `-SkipGenerate` (convert only, skip the `Images.lua` refresh).

### How the popup works internally

Reforged Break Timer has no manual controls or slash commands. It polls `BigWigs3DB.breakTime` (the same saved-variable table BigWigs itself writes to) once a second; the instant BigWigs reports an active break, the frame shows a random enabled image and counts down the remaining time, then hides itself the moment the break ends.

### Deploying a local build for testing

`scripts/deploy_to_wow.ps1` copies this repo straight into a WoW install on **your own dev machine** (it has hardcoded local paths — not something an end user should run):

```powershell
./scripts/deploy_to_wow.ps1
```

It runs Lua 5.1 syntax checks and `luacheck` over every `.lua` file first and aborts if either fails, then copies the TOC-listed files plus `images/` into each target and tags the deployed `## Version` with a `-dev` suffix. Flags:

- `-ValidateOnly` — just run the syntax/lint checks, don't copy anything.
- `-NoDevSuffix` — deploy without appending `-dev` to the version.
- `-WowAddonPaths <paths>` — override the default `_retail_`/`_ptr_` AddOns locations.

Requires Lua 5.1 (`lua.exe`/`luac.exe`) and `luacheck.exe` on PATH (or their default install locations).

### Files

| File | Purpose |
| --- | --- |
| `ReforgedBreakTimer.lua` | Core BigWigs-polling logic and the popup frame. |
| `Options.lua` | The in-game options panel (Settings API, with a legacy fallback). |
| `Images.lua` | Auto-generated list of available images — don't hand-edit this. |
| `GenerateImages.ps1` | Scans `images/` and rewrites `Images.lua`. |
| `ConvertImages.ps1` | Converts PNG/JPG/BMP/GIF/WEBP from `images-src/` to `.tga` in `images/`, then runs `GenerateImages.ps1`. |
| `scripts/deploy_to_wow.ps1` | Dev-only: validates and copies the addon into a local WoW AddOns folder. |
| `.luacheckrc` | Lint config (ignores WoW's runtime-provided globals). |
| `images/` | WoW-ready `.tga`/`.blp` files only — this folder is what actually ships. |
| `images-src/` | Drop original PNG/JPG/etc. files here before converting — never deployed. |

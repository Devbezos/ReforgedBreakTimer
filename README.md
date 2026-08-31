# Reforged Break Timer

A WoW addon that pops up a random picture and a countdown the moment your raid's [BigWigs](https://www.curseforge.com/wow/addons/big-wigs) break timer goes off. No setup, no commands to remember — install it once and it just works.

## Install it

1. Download the latest `.zip` from the [Releases page](https://github.com/Devbezos/ReforgedBreakTimer/releases/latest).
2. Right-click the downloaded `.zip` and **Extract All**.
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

## Using your own images

Want the popup to show your own raid's pictures instead of (or alongside) the defaults? There are two ways in, depending on how much you want to change.

### Easiest: swap an existing picture, no tools needed

Every picture the addon knows about is a `.tga` file in the `images/` folder — either in this repo, or inside your installed `...\AddOns\ReforgedBreakTimer\images\` folder. Because the addon just points at that folder by filename, you can replace any of those `.tga` files with your own picture **as long as you keep the exact same filename** — nothing else needs to change, and you don't need PowerShell, ffmpeg, or to touch `Images.lua` at all.

1. Pick an existing image to replace, e.g. `images\macro2.tga`, and note its exact filename.
2. Convert your picture to `.tga` (any free online PNG/JPG-to-TGA converter works, or use the included `ConvertImages.ps1` script described further down if you'd rather).
3. Rename your converted file to match exactly, e.g. `macro2.tga`, and overwrite the original with it.
4. In-game, type `/reload` (or relaunch WoW) — your picture shows up in its place immediately, no other steps required.

This only works for *replacing* one of the existing pictures — the picture count and display names in the options panel stay the same. To add more pictures than currently exist, or remove some entirely, see below.

### Adding or removing pictures (needs this source repo + PowerShell)

WoW addons run in a locked-down sandbox and can't read a folder's contents at runtime, so changing *how many* pictures there are (not just swapping one out) means regenerating a manifest file (`Images.lua`) with a script — which means working from this source repo, not just a downloaded release zip.

**If your picture is already a `.tga` or `.blp`:**

1. Put it in `images/` (or delete a file from there to remove that picture).
2. Run `GenerateImages.ps1` (double-click it, or `./GenerateImages.ps1` in a PowerShell terminal here). It scans `images/` and rewrites `Images.lua` to match, turning `coffee_mug.tga` into the display name "Coffee Mug".
3. In-game: `/reload`, then toggle it on in the options panel if needed.

**If it's a PNG/JPG/BMP/GIF/WEBP instead — converting a batch of pictures:**

1. Put it in `images-src/` (not `images/`).
2. Run `./ConvertImages.ps1`. It converts each file to a same-named `.tga` in `images/` — via [ffmpeg](https://ffmpeg.org/) (must be on PATH; `winget install ffmpeg` if missing) — and automatically runs `GenerateImages.ps1` for you.
3. In-game: `/reload`.

`images-src/` is only a staging folder — nothing in it is ever deployed to WoW, so raw source files never bloat the shipped addon. Only `images/` (the `.tga`/`.blp` output) goes out.

Useful `ConvertImages.ps1` flags: `-Force` (reconvert even if a `.tga` already exists), `-DeleteOriginals` (delete the source file from `images-src/` once converted), `-SkipGenerate` (convert only, skip the `Images.lua` refresh).

Once you're happy with the picture set, either run `scripts/deploy_to_wow.ps1` to test it locally, or push a version tag (see [Releasing a new version](#releasing-a-new-version) below) to have GitHub build a new zip anyone can download.

## For addon maintainers

The sections below are for whoever maintains this repo — everyday users don't need any of this.

### How the popup works internally

Reforged Break Timer has no manual controls or slash commands. Its primary detection path hooks BigWigs' own `BigWigs_StartBreak`/`BigWigs_StopBreak` AceEvent-3.0 messages — the same ones BigWigs' own break bar reacts to, fired the instant a break starts or ends with full `GetTime()` precision — so the popup's countdown starts in step with BigWigs' own bar, not a poll cycle behind it.

As a safety net (in case AceEvent-3.0 isn't available yet, or our addon registers its listener after BigWigs already fired the message for an in-progress break), it also polls `BigWigs3DB.breakTime` — the same saved-variable table BigWigs itself writes to — 5 times a second. That fallback path can still trail BigWigs' own bar by up to ~1 second, because `BigWigs3DB.breakTime` only stores whole-second precision (`time()`, not `GetTime()`); that's a limit of the fallback's source data, not something pollable away. In the normal case where the message hook connects (BigWigs installed and loaded, which the `## OptionalDeps: BigWigs` in the `.toc` ensures happens before we do), the fallback should rarely if ever be the one that fires.

While a break is active, the picture cycles through every enabled image roughly once: the switch interval is the break's total length divided by the number of enabled pictures (minimum 2 seconds, so a huge picture list on a short break doesn't flicker). With only one picture enabled, it just stays put.

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

### Releasing a new version

A GitHub Actions workflow ([`.github/workflows/release.yml`](.github/workflows/release.yml)) handles versioning and builds the downloadable `.zip` — there's no manual tagging and nobody needs to zip anything by hand.

**Releasing is automatic: every push to `main` ships a release.**

1. Merge or push your change to `main`.
2. GitHub Actions syntax-checks and lints every `.lua` file. If that fails, nothing further happens — no version bump, no release.
3. It looks up the most recently published release, **bumps the PATCH version by one** (e.g. `1.2.3` → `1.2.4`), commits that new `## Version:` into `ReforgedBreakTimer.toc` on `main` (as `github-actions[bot]`, tagged `[skip ci]` so it doesn't loop), and tags it.
4. It packages the `.toc` + the files it lists + `images/` (never `images-src/`, `scripts/`, or other repo tooling) into `ReforgedBreakTimer-<version>.zip`, and publishes a GitHub Release with that zip attached. That's the file end users download and drag into their AddOns folder.

Because every push to `main` bumps and releases, keep `main` protected/reviewed — a typo fix merged straight to `main` ships a new patch version just like a real feature would. Want a specific major or minor bump instead of the automatic patch bump? Edit `## Version:` in `ReforgedBreakTimer.toc` yourself in the same push — the workflow only auto-bumps when it doesn't find a newer version already staged... actually it always computes from the latest **published release**, not the `.toc`, so to jump to e.g. `2.0.0` you'd currently need to publish that release manually via the GitHub UI first, then subsequent auto-bumps continue from there. (If you want on-demand major/minor control built into the workflow itself, ask — it's a small addition.)

**To sanity-check a build without releasing it:** go to the repo's **Actions** tab → **Release** → **Run workflow** on the branch you want to test. It previews the same next-patch-version number (or an exact version you type in) and uploads the zip as a workflow artifact instead of publishing a Release or touching `main` — nothing gets committed, tagged, or made public.

### Files

| File | Purpose |
| --- | --- |
| `ReforgedBreakTimer.lua` | Core BigWigs-polling logic and the popup frame. |
| `Options.lua` | The in-game options panel (Settings API, with a legacy fallback). |
| `Images.lua` | Auto-generated list of available images — don't hand-edit this. |
| `GenerateImages.ps1` | Scans `images/` and rewrites `Images.lua`. |
| `ConvertImages.ps1` | Converts PNG/JPG/BMP/GIF/WEBP from `images-src/` to `.tga` in `images/`, then runs `GenerateImages.ps1`. |
| `scripts/deploy_to_wow.ps1` | Dev-only: validates and copies the addon into a local WoW AddOns folder. |
| `.github/workflows/release.yml` | CI: validates the addon and builds/publishes the release `.zip` (see [Releasing a new version](#releasing-a-new-version)). |
| `.luacheckrc` | Lint config (ignores WoW's runtime-provided globals). |
| `images/` | WoW-ready `.tga`/`.blp` files only — this folder is what actually ships. |
| `images-src/` | Drop original PNG/JPG/etc. files here before converting — never deployed. |

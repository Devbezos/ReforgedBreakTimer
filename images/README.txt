This folder holds the WoW-ready images the addon actually loads at runtime.
Everything in here gets deployed straight into your WoW AddOns folder. Two
kinds of things belong here:

  - A static picture: a plain .tga/.blp file directly in this folder.
  - An animated picture (from a GIF): a same-named SUBFOLDER holding numbered
    frame files (0001.tga, 0002.tga, ...) plus a delay.txt with the per-frame
    delay in seconds. The addon cycles through the frames in a loop while
    it's on screen -- it actually animates, not just a static first frame.
    ConvertImages.ps1 produces this layout for you from a source GIF; you
    don't need to build one by hand unless you're doing something unusual.

Got a PNG/JPG/BMP/GIF/WEBP instead? Don't drop it in here -- put it in
..\images-src\ and run ..\ConvertImages.ps1, which converts it (via ffmpeg,
must be on PATH) into this folder for you -- a same-named .tga for a still
image, or a same-named frame subfolder for an animated GIF -- and then runs
GenerateImages.ps1 automatically.

Already have a .tga/.blp, or a pre-made frame subfolder? You can drop it
straight in here.

WoW addons run in a sandbox and can't read a folder's contents at runtime,
so there's no way for the addon to "see" a new file by itself. Instead:

1. Get your images into this folder (directly, or via ..\images-src\ +
   ConvertImages.ps1 as above).
2. Run ..\GenerateImages.ps1 (double-click it, or run it from a terminal).
   It scans this folder and rewrites ..\Images.lua for you.
3. In-game, type /reload (or fully relaunch WoW).
4. Open the options panel (Game Menu (Esc) -> Options -> AddOns -> Reforged
   Break Timer) to enable/disable individual images -- everything is
   enabled by default.

That script is the closest thing to "dynamic" folder loading that a WoW
addon can do: no manual editing of Lua paths required, just re-run it
whenever you add or remove pictures.

This folder holds the WoW-ready .tga/.blp images the addon actually loads
at runtime. Everything in here gets deployed straight into your WoW AddOns
folder, so keep it limited to .tga/.blp files.

Got a PNG/JPG/BMP/GIF/WEBP instead? Don't drop it in here -- put it in
..\images-src\ and run ..\ConvertImages.ps1, which converts it to a
same-named .tga in this folder for you (via ffmpeg, must be on PATH) and
then runs GenerateImages.ps1 automatically.

Already have a .tga or .blp? You can drop it straight in here.

WoW addons run in a sandbox and can't read a folder's contents at runtime,
so there's no way for the addon to "see" a new file by itself. Instead:

1. Get your .tga/.blp files into this folder (directly, or via
   ..\images-src\ + ConvertImages.ps1 as above).
2. Run ..\GenerateImages.ps1 (double-click it, or run it from a terminal).
   It scans this folder and rewrites ..\Images.lua for you.
3. In-game, type /reload (or fully relaunch WoW).
4. Open the options panel (gear icon on the frame) to enable/disable
   individual images -- everything is enabled by default.

That script is the closest thing to "dynamic" folder loading that a WoW
addon can do: no manual editing of Lua paths required, just re-run it
whenever you add or remove pictures.

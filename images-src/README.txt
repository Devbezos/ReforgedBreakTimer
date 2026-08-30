Drop your original pictures here -- .png, .jpg/.jpeg, .bmp, .gif, or .webp.

This folder is just a staging area. It is NOT deployed to WoW and nothing
in here is read by the addon at runtime; it exists so raw source images
have somewhere to live without ending up shipped alongside the game-ready
files.

Workflow:

1. Drop your images in this folder.
2. Run ..\ConvertImages.ps1 from a PowerShell terminal (or double-click it).
   It converts each one to a WoW-ready .tga in ..\images\ (via ffmpeg, must
   be on PATH) and then runs GenerateImages.ps1 for you automatically.
3. In-game, type /reload (or fully relaunch WoW).
4. Open the options panel (gear icon on the frame) to enable/disable
   individual images -- everything is enabled by default.

Already have .tga or .blp files? Skip this folder entirely and drop them
straight into ..\images\ instead -- see the README.txt there.

Add -DeleteOriginals when running ConvertImages.ps1 if you'd rather it
remove the source file here once the .tga has been written.

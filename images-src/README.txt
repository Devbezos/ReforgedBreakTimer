Drop your original pictures here -- .png, .jpg/.jpeg, .bmp, .gif, or .webp.

This folder is just a staging area. It is NOT deployed to WoW and nothing
in here is read by the addon at runtime; it exists so raw source images
have somewhere to live without ending up shipped alongside the game-ready
files.

Workflow:

1. Drop your images in this folder.
2. Run ..\ConvertImages.ps1 from a PowerShell terminal (or double-click it).
   It converts each one (via ffmpeg, must be on PATH) into ..\images\ --
   a same-named .tga for a still image, or a same-named subfolder of
   numbered frames for an animated GIF (which the addon actually plays back
   in a loop, not just a static first frame) -- and then runs
   GenerateImages.ps1 for you automatically.
3. In-game, type /reload (or fully relaunch WoW).
4. Open the options panel (Game Menu (Esc) -> Options -> AddOns -> Reforged
   Break Timer) to enable/disable individual images -- everything is
   enabled by default.

Already have .tga/.blp files, or a pre-made frame subfolder? Skip this
folder entirely and drop them straight into ..\images\ instead -- see the
README.txt there.

Add -DeleteOriginals when running ConvertImages.ps1 if you'd rather it
remove the source file here once conversion succeeds. Add -MaxFrames to
change how many frames a long/high-fps GIF gets thinned down to (default
60, keeping the same overall playback duration).

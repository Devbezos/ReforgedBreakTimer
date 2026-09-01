This folder holds WoW-ready .tga/.blp assets for the addon's own UI chrome --
distinct from images\, which holds the rotating pictures. Everything in
here gets deployed straight into your WoW AddOns folder.

  - logo.tga: shown in the top-left corner of the popup.
  - next_image.tga: the "show a different image" rotate button's icon,
    beside the close button. White on transparent so it reads against the
    popup's dark background and can be tinted (e.g. its pushed state uses
    the accent green) via SetVertexColor.

Got a PNG/JPG/BMP/GIF/WEBP instead? Don't drop it in here -- put it in
..\textures-src\ and convert it with ffmpeg, e.g.:

    ffmpeg -y -i ..\textures-src\logo.png -pix_fmt bgra -rle 0 logo.tga

There's no automated script for this folder (unlike images\, which has
ConvertImages.ps1/GenerateImages.ps1) since it's not something that grows
or needs a generated file list -- just replace the .tga directly and
/reload in-game.

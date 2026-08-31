<#
.SYNOPSIS
    Converts PNG/JPG/BMP/GIF/WEBP files from images-src\ into WoW-ready .tga files in
    images\, regenerates Images.lua, then deploys the addon to your local WoW install.

.DESCRIPTION
    WoW's texture loader wants 32-bit TGA (or BLP), not the formats a screenshot or a
    downloaded picture usually comes in. This script finds any image in images-src\ (a
    staging folder that is never deployed to WoW) and converts it into images\ with
    ffmpeg: 32-bit BGRA, uncompressed (no RLE) -- the safest, most compatible TGA variant
    for the game client. Keeping originals out of images\ means only game-ready .tga/.blp
    files ever get copied into your WoW AddOns folder.

    Oversized source pictures (screenshots, downloads, etc.) are also downscaled to fit
    within the addon's on-screen image box (178x178, see -MaxDimension) before being
    written as .tga, keeping file sizes down. Images already at or below that size are
    left alone -- this never upscales.

    .gif files are treated specially: since a WoW texture can't itself be animated, an
    animated GIF is instead decomposed into a same-named subfolder of numbered frame
    .tga files (e.g. images\wave\0001.tga, 0002.tga, ...) plus a delay.txt recording the
    (uniform) per-frame delay in seconds, and the addon cycles through them at runtime to
    play it back. A GIF with more than -MaxFrames frames is thinned down to fit, since
    every frame is a separate file shipped with the addon. A non-animated (single-frame)
    GIF converts to a plain .tga like any other format instead.

    Workflow:
      1. Drop .png/.jpg/.jpeg/.bmp/.gif/.webp files into images-src\.
      2. Run this script. Each one becomes a same-named .tga (or, for an animated GIF, a
         same-named subfolder of frames) in images\, GenerateImages.ps1 runs automatically
         afterward to refresh Images.lua, and scripts/deploy_to_wow.ps1 runs after that to
         copy the updated addon into your local WoW AddOns folder(s).
      3. In-game, type /reload (or fully relaunch WoW).
      4. Open the options panel (Game Menu (Esc) -> Options -> AddOns -> Reforged
         Break Timer) to enable/disable individual images.

    Requires ffmpeg AND ffprobe on PATH (https://ffmpeg.org/download.html, or
    `winget install ffmpeg` -- both ship together in every standard build).

.PARAMETER DeleteOriginals
    Delete the source file (the .png/.jpg/etc. in images-src\) after a successful
    conversion. Off by default so nothing is destroyed without asking.

.PARAMETER Force
    Re-convert and overwrite a .tga (or frame subfolder) even if one already exists for
    that source file.

.PARAMETER SkipGenerate
    Don't automatically run GenerateImages.ps1 afterward. Implies -SkipDeploy, since
    deployment relies on GenerateImages.ps1 having already run.

.PARAMETER SkipDeploy
    Don't automatically run scripts/deploy_to_wow.ps1 after regenerating Images.lua.

.PARAMETER MaxDimension
    Largest width/height (in pixels) a converted image (or GIF frame) is allowed to
    keep, preserving aspect ratio. Defaults to 178, matching the addon's on-screen image
    box. Only ever shrinks -- an image already smaller than this is left at its original
    size.

.PARAMETER MaxFrames
    Largest number of frames an animated GIF is allowed to keep. Defaults to 60. A GIF
    with more frames than this is evenly thinned down (its overall playback duration is
    preserved, just at a lower frame rate) since every frame ships as its own file.

.EXAMPLE
    ./ConvertImages.ps1

.EXAMPLE
    ./ConvertImages.ps1 -DeleteOriginals -Force
#>

[CmdletBinding()]
param(
    [switch]$DeleteOriginals,
    [switch]$Force,
    [switch]$SkipGenerate,
    [switch]$SkipDeploy,
    [int]$MaxDimension = 178,
    [int]$MaxFrames = 60
)

$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourceDir  = Join-Path $scriptRoot 'images-src'
$imagesDir  = Join-Path $scriptRoot 'images'
$sourceExtensions = '.png', '.jpg', '.jpeg', '.bmp', '.gif', '.webp'

if (-not (Test-Path $sourceDir)) {
    New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
}
if (-not (Test-Path $imagesDir)) {
    New-Item -ItemType Directory -Path $imagesDir -Force | Out-Null
}

$ffmpeg = Get-Command 'ffmpeg' -ErrorAction SilentlyContinue
if (-not $ffmpeg) {
    throw "ffmpeg was not found on PATH. Install it (e.g. 'winget install ffmpeg' or " +
          "https://ffmpeg.org/download.html) and try again."
}
$ffprobe = Get-Command 'ffprobe' -ErrorAction SilentlyContinue
if (-not $ffprobe) {
    throw "ffprobe was not found on PATH (it's needed to detect animated GIFs). It " +
          "ships alongside ffmpeg in every standard build -- reinstall ffmpeg if you're " +
          "missing it."
}

# Converts a single still image (any non-GIF format, or a non-animated GIF) to a
# same-named .tga, downscaled to fit MaxDimension x MaxDimension.
function Convert-StaticImage {
    param($SourceFile, $DestPath)

    # Downscale-only, aspect-preserving fit within MaxDimension x MaxDimension:
    # min(iw,N)/min(ih,N) leaves already-small images untouched, and
    # force_original_aspect_ratio=decrease keeps the smaller of the two scale
    # factors so the image never gets stretched or cropped.
    $scaleFilter = "scale='min(iw,$MaxDimension)':'min(ih,$MaxDimension)':force_original_aspect_ratio=decrease"
    & $ffmpeg.Source -y -i $SourceFile.FullName -vf $scaleFilter -pix_fmt bgra -rle 0 $DestPath -loglevel error
    return $LASTEXITCODE -eq 0
}

# Decomposes an animated GIF into DestDir\0001.tga, 0002.tga, ... plus a delay.txt
# holding the (uniform) per-frame delay in seconds. Returns $false (and cleans up
# after itself) if ffmpeg/ffprobe couldn't get usable frames out of it.
function Convert-AnimatedGif {
    param($SourceFile, $DestDir)

    if (Test-Path -LiteralPath $DestDir) {
        Remove-Item -LiteralPath $DestDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $DestDir -Force | Out-Null

    $duration = [double](& $ffprobe.Source -v error -show_entries format=duration -of csv=p=0 $SourceFile.FullName)
    if (-not ($duration -gt 0)) {
        $duration = 1
    }
    $frameCount = [int](& $ffprobe.Source -v error -count_frames -select_streams v:0 -show_entries stream=nb_read_frames -of csv=p=0 $SourceFile.FullName)

    $scaleFilter = "scale='min(iw,$MaxDimension)':'min(ih,$MaxDimension)':force_original_aspect_ratio=decrease"
    $videoFilter = $scaleFilter
    if ($frameCount -gt $MaxFrames) {
        # Thin the frame rate down so MaxFrames spans the same overall duration,
        # rather than just truncating the tail end of the animation.
        $targetFps = [Math]::Max(1, [Math]::Floor($MaxFrames / $duration))
        $videoFilter = "fps=$targetFps,$scaleFilter"
    }

    $framePattern = Join-Path $DestDir '%04d.tga'
    & $ffmpeg.Source -y -i $SourceFile.FullName -vsync 0 -vf $videoFilter -pix_fmt bgra -rle 0 $framePattern -loglevel error
    if ($LASTEXITCODE -ne 0) {
        Remove-Item -LiteralPath $DestDir -Recurse -Force
        return $false
    }

    $writtenFrames = @(Get-ChildItem -LiteralPath $DestDir -Filter '*.tga')
    if ($writtenFrames.Count -eq 0) {
        Remove-Item -LiteralPath $DestDir -Recurse -Force
        return $false
    }

    # Only a single frame came out -- this wasn't actually an animated GIF.
    # Fall back to treating it as a plain static picture instead of shipping
    # a one-file "animation" folder.
    if ($writtenFrames.Count -eq 1) {
        $tgaPath = "$DestDir.tga"
        Move-Item -LiteralPath $writtenFrames[0].FullName -Destination $tgaPath -Force
        Remove-Item -LiteralPath $DestDir -Recurse -Force
        return $true
    }

    $delaySeconds = $duration / $writtenFrames.Count
    if (-not ($delaySeconds -gt 0)) {
        $delaySeconds = 0.1
    }
    $delayText = $delaySeconds.ToString([System.Globalization.CultureInfo]::InvariantCulture)
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText((Join-Path $DestDir 'delay.txt'), $delayText, $utf8NoBom)

    return $true
}

$sourceFiles = Get-ChildItem -Path $sourceDir -File |
    Where-Object { $_.Extension.ToLowerInvariant() -in $sourceExtensions } |
    Sort-Object Name

if ($sourceFiles.Count -eq 0) {
    Write-Host "No .png/.jpg/.jpeg/.bmp/.gif/.webp files found in $sourceDir -- nothing to convert." -ForegroundColor Yellow
} else {
    $converted = 0
    $skipped = 0

    foreach ($file in $sourceFiles) {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        $isGif = $file.Extension.ToLowerInvariant() -eq '.gif'

        # An animated GIF's destination is a folder; everything else is a single
        # .tga. (A non-animated GIF only reveals that once Convert-AnimatedGif has
        # run, so its "already exists" check covers both possible outcomes.)
        $tgaPath = Join-Path $imagesDir ($baseName + '.tga')
        $frameDir = Join-Path $imagesDir $baseName
        $alreadyExists = if ($isGif) {
            (Test-Path -LiteralPath $tgaPath -PathType Leaf) -or (Test-Path -LiteralPath $frameDir -PathType Container)
        } else {
            Test-Path -LiteralPath $tgaPath -PathType Leaf
        }

        if ($alreadyExists -and -not $Force) {
            Write-Host "  [skip] $($file.Name) -> $baseName already exists (use -Force to overwrite)" -ForegroundColor DarkGray
            $skipped++
            continue
        }

        $ok = $false
        if ($isGif) {
            # Force may be overwriting a previous conversion that took the other
            # branch (folder vs. single .tga) -- clear both before converting.
            if (Test-Path -LiteralPath $tgaPath) { Remove-Item -LiteralPath $tgaPath -Force }
            if (Test-Path -LiteralPath $frameDir) { Remove-Item -LiteralPath $frameDir -Recurse -Force }

            Write-Host "  $($file.Name) -> $baseName\ (animated, up to $MaxFrames frames)"
            $ok = Convert-AnimatedGif -SourceFile $file -DestDir $frameDir
            if (-not $ok) {
                Write-Warning "ffmpeg/ffprobe couldn't extract frames from $($file.Name); leaving it alone."
            }
        } else {
            Write-Host "  $($file.Name) -> $baseName.tga"
            $ok = Convert-StaticImage -SourceFile $file -DestPath $tgaPath
            if (-not $ok) {
                Write-Warning "ffmpeg failed to convert $($file.Name); leaving it alone."
            }
        }

        if (-not $ok) {
            continue
        }

        $converted++
        if ($DeleteOriginals) {
            Remove-Item -LiteralPath $file.FullName -Force
        }
    }

    Write-Host ""
    Write-Host "Converted $converted image(s), skipped $skipped existing." -ForegroundColor Green
}

if (-not $SkipGenerate) {
    Write-Host ""
    & (Join-Path $scriptRoot 'GenerateImages.ps1')

    if (-not $SkipDeploy) {
        Write-Host ""
        & (Join-Path $scriptRoot 'scripts\deploy_to_wow.ps1')
    }
}

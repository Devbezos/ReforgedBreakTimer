<#
.SYNOPSIS
    Converts PNG/JPG/BMP/GIF/WEBP files from images-src\ into WoW-ready .tga files in
    images\, then regenerates Images.lua.

.DESCRIPTION
    WoW's texture loader wants 32-bit TGA (or BLP), not the formats a screenshot or a
    downloaded picture usually comes in. This script finds any image in images-src\ (a
    staging folder that is never deployed to WoW) and converts it into images\ with
    ffmpeg: 32-bit BGRA, uncompressed (no RLE) -- the safest, most compatible TGA variant
    for the game client. Keeping originals out of images\ means only game-ready .tga/.blp
    files ever get copied into your WoW AddOns folder.

    Workflow:
      1. Drop .png/.jpg/.jpeg/.bmp/.gif/.webp files into images-src\.
      2. Run this script. Each one becomes a same-named .tga in images\, and
         GenerateImages.ps1 runs automatically afterward to refresh Images.lua.
      3. In-game, type /reload (or fully relaunch WoW).
      4. Open the options panel (gear icon on the frame) to enable/disable individual images.

    Requires ffmpeg on PATH (https://ffmpeg.org/download.html, or `winget install ffmpeg`).

.PARAMETER DeleteOriginals
    Delete the source file (the .png/.jpg/etc. in images-src\) after a successful
    conversion. Off by default so nothing is destroyed without asking.

.PARAMETER Force
    Re-convert and overwrite a .tga even if one already exists for that source file.

.PARAMETER SkipGenerate
    Don't automatically run GenerateImages.ps1 afterward.

.EXAMPLE
    ./ConvertImages.ps1

.EXAMPLE
    ./ConvertImages.ps1 -DeleteOriginals -Force
#>

[CmdletBinding()]
param(
    [switch]$DeleteOriginals,
    [switch]$Force,
    [switch]$SkipGenerate
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

$sourceFiles = Get-ChildItem -Path $sourceDir -File |
    Where-Object { $_.Extension.ToLowerInvariant() -in $sourceExtensions } |
    Sort-Object Name

if ($sourceFiles.Count -eq 0) {
    Write-Host "No .png/.jpg/.jpeg/.bmp/.gif/.webp files found in $sourceDir -- nothing to convert." -ForegroundColor Yellow
} else {
    $converted = 0
    $skipped = 0

    foreach ($file in $sourceFiles) {
        $tgaPath = Join-Path $imagesDir ([System.IO.Path]::GetFileNameWithoutExtension($file.Name) + '.tga')

        if ((Test-Path -LiteralPath $tgaPath) -and -not $Force) {
            Write-Host "  [skip] $($file.Name) -> $(Split-Path -Leaf $tgaPath) already exists (use -Force to overwrite)" -ForegroundColor DarkGray
            $skipped++
            continue
        }

        Write-Host "  $($file.Name) -> $(Split-Path -Leaf $tgaPath)"
        & $ffmpeg.Source -y -i $file.FullName -pix_fmt bgra -rle 0 $tgaPath -loglevel error
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "ffmpeg failed to convert $($file.Name); leaving it alone."
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
}

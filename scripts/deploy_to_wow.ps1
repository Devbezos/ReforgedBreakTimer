# deploy_to_wow.ps1
# Copies the addon source into a local World of Warcraft AddOns folder.
#
# The deployed TOC gets a "-dev" suffix so version broadcasts from local test
# builds do not look like public release versions to other players.
#
# Modeled on Larias-Weekly-Midnight-Checklist/scripts/deploy_to_wow.ps1.

[CmdletBinding()]
param(
    [string[]]$WowAddonPaths = @(
        "D:\Battle.NET\World Of Warcraft\_retail_\Interface\AddOns\ReforgedBreakTimer",
        "D:\Battle.NET\World Of Warcraft\_ptr_\Interface\AddOns\ReforgedBreakTimer"
    ),
    [switch]$NoDevSuffix,
    [switch]$ValidateOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot   = Split-Path -Parent $scriptRoot
$tocPath    = Join-Path $repoRoot "ReforgedBreakTimer.toc"

if (-not (Test-Path -LiteralPath $tocPath -PathType Leaf)) {
    throw "Could not find ReforgedBreakTimer.toc at $tocPath"
}

function Get-Lua51Executable {
    $candidates = @()
    $luaCommand = Get-Command "lua.exe" -ErrorAction SilentlyContinue
    if ($luaCommand) { $candidates += $luaCommand.Source }
    if ($env:ProgramFiles) { $candidates += (Join-Path $env:ProgramFiles "Lua\5.1\lua.exe") }
    if (${env:ProgramFiles(x86)}) {
        $candidates += (Join-Path ${env:ProgramFiles(x86)} "Lua\5.1\lua.exe")
    }

    foreach ($candidate in $candidates | Select-Object -Unique) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $candidate
        $startInfo.Arguments = "-v"
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true

        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        try {
            [void]$process.Start()
            $versionText = ($process.StandardOutput.ReadToEnd() + $process.StandardError.ReadToEnd()).Trim()
            $process.WaitForExit()
            if ($process.ExitCode -eq 0 -and $versionText -match '^Lua 5\.1(?:\.|\s)') {
                return $candidate
            }
        } finally {
            $process.Dispose()
        }
    }
    return $null
}

function Get-LuacheckExecutable {
    $candidates = @()
    $command = Get-Command "luacheck.exe" -ErrorAction SilentlyContinue
    if ($command) { $candidates += $command.Source }
    if ($env:LOCALAPPDATA) {
        $candidates += (Join-Path $env:LOCALAPPDATA "Programs\Luacheck\luacheck.exe")
    }

    foreach ($candidate in $candidates | Select-Object -Unique) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    return $null
}

function Get-ValidationLuaFiles {
    Get-ChildItem -LiteralPath $repoRoot -File -Filter "*.lua"
}

function Invoke-AddonValidation {
    $luaExecutable = Get-Lua51Executable
    if (-not $luaExecutable) {
        throw "Lua 5.1 is required for local deployment. Install it before deploying."
    }
    $luacExecutable = Join-Path (Split-Path -Parent $luaExecutable) "luac.exe"
    if (-not (Test-Path -LiteralPath $luacExecutable -PathType Leaf)) {
        throw "Lua 5.1 compiler not found beside $luaExecutable."
    }
    $luacheckExecutable = Get-LuacheckExecutable
    if (-not $luacheckExecutable) {
        throw "Luacheck is required for local deployment. Install it before deploying."
    }

    Write-Host "Running local Lua validation..."
    Push-Location $repoRoot
    try {
        foreach ($luaFile in Get-ValidationLuaFiles) {
            & $luacExecutable -p $luaFile.FullName
            if ($LASTEXITCODE -ne 0) {
                throw "Lua syntax validation failed for $($luaFile.FullName)."
            }
        }

        & $luacheckExecutable "Images.lua" "ReforgedBreakTimer.lua" "Options.lua"
        if ($LASTEXITCODE -ne 0) {
            throw "Luacheck failed with exit code $LASTEXITCODE. Deployment aborted."
        }
    } finally {
        Pop-Location
    }
    Write-Host "Lua syntax and lint checks passed." -ForegroundColor Green
    Write-Host ""
}

function Get-TocAddonFiles {
    param([string]$Path)

    Get-Content -LiteralPath $Path |
        ForEach-Object { $_.Trim() } |
        Where-Object {
            $_ -and
            -not $_.StartsWith("#") -and
            -not $_.StartsWith("##")
        } |
        ForEach-Object { $_ -replace '/', '\' }
}

function Copy-RepoFile {
    param(
        [string]$RelativePath,
        [string]$DestinationRoot
    )

    $src = Join-Path $repoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) {
        Write-Warning "Skipping missing TOC entry: $RelativePath"
        return
    }

    $dest = Join-Path $DestinationRoot $RelativePath
    $destDir = Split-Path -Parent $dest
    if (-not (Test-Path -LiteralPath $destDir -PathType Container)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    Copy-Item -LiteralPath $src -Destination $dest -Force
}

function Copy-RepoDirectory {
    param(
        [string]$RelativePath,
        [string]$DestinationRoot
    )

    $src = Join-Path $repoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $src -PathType Container)) {
        return
    }

    $dest = Join-Path $DestinationRoot $RelativePath
    if (-not (Test-Path -LiteralPath $dest -PathType Container)) {
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
    }

    Get-ChildItem -LiteralPath $src -Recurse -File | ForEach-Object {
        $relativeChild = $_.FullName.Substring($src.Length).TrimStart('\', '/')
        $target = Join-Path $dest $relativeChild
        $targetDir = Split-Path -Parent $target
        if (-not (Test-Path -LiteralPath $targetDir -PathType Container)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }
        Copy-Item -LiteralPath $_.FullName -Destination $target -Force
    }
}

Invoke-AddonValidation
if ($ValidateOnly) { return }

foreach ($wowAddonPath in $WowAddonPaths) {
    $rootAddonsDir = Split-Path -Parent $wowAddonPath
    if (-not (Test-Path -LiteralPath $rootAddonsDir -PathType Container)) {
        Write-Host "  [skip] $rootAddonsDir not found"
        continue
    }

    if (-not (Test-Path -LiteralPath $wowAddonPath -PathType Container)) {
        New-Item -ItemType Directory -Path $wowAddonPath -Force | Out-Null
    }

    Write-Host "Deploying Reforged Break Timer to:"
    Write-Host "  $wowAddonPath"

    Copy-RepoFile -RelativePath "ReforgedBreakTimer.toc" -DestinationRoot $wowAddonPath
    foreach ($relativePath in Get-TocAddonFiles -Path $tocPath) {
        Copy-RepoFile -RelativePath $relativePath -DestinationRoot $wowAddonPath
    }

    # images/ holds the .tga/.blp textures referenced by absolute path at
    # runtime -- they're not "loadable" TOC entries, so copy the folder directly.
    # images-src/ (raw PNG/JPG/etc. before conversion) is intentionally NOT
    # copied -- it's a local staging folder only, never shipped to WoW.
    Copy-RepoDirectory -RelativePath "images" -DestinationRoot $wowAddonPath

    if (-not $NoDevSuffix) {
        $destToc = Join-Path $wowAddonPath "ReforgedBreakTimer.toc"
        $tocText = Get-Content -Raw -LiteralPath $destToc
        $updated = $tocText -replace '(?m)^(##\s*Version:\s*)([^\r\n]+?)(-dev)?\s*$', '$1$2-dev'
        # -Encoding UTF8 on Windows PowerShell prepends a BOM, which can make
        # WoW misread the "## Interface:" directive on the first line. Write
        # plain UTF-8 without one instead.
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($destToc, $updated, $utf8NoBom)
    }

    Write-Host "Deploy complete." -ForegroundColor Green
}

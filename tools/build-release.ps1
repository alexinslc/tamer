#Requires -Version 7.0
<#
.SYNOPSIS
    Builds the zip to share: the addon.
.DESCRIPTION
    Leaves out every file in .gitignore, and removes them
    from the zip's .toc too. Works on Windows and macOS.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$addon = Join-Path $root 'addon' 'Tamer'
$toc = Join-Path $addon 'Tamer.toc'
$version = ((Get-Content -LiteralPath $toc | Where-Object { $_ -match '^## Version:' }) -replace '^## Version:\s*', '').Trim()

Push-Location $root
try {
    $files = @(git ls-files --cached --others --exclude-standard -- 'addon/Tamer')
    if ($LASTEXITCODE -ne 0 -or -not $files) { throw 'git could not list the addon files.' }
    $files = @($files | Where-Object { Test-Path -LiteralPath $_ })   # Skips files deleted but not yet committed.
}
finally { Pop-Location }

$stage = Join-Path ([IO.Path]::GetTempPath()) "tamer-$([guid]::NewGuid())"
$folder = Join-Path $stage 'Tamer'
try {
    foreach ($file in $files) {
        $relative = $file.Substring('addon/Tamer/'.Length)
        $target = Join-Path $folder $relative
        New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
        Copy-Item -LiteralPath (Join-Path $root $file) -Destination $target
    }

    # A shared copy's .toc lists only the files it has.
    $stageToc = Join-Path $folder 'Tamer.toc'
    $kept = Get-Content -LiteralPath $stageToc | Where-Object {
        $_ -notmatch '\.lua$' -or (Test-Path -LiteralPath (Join-Path $folder $_))
    }
    [IO.File]::WriteAllLines($stageToc, [string[]]$kept)

    $dist = Join-Path $root 'dist'
    New-Item -ItemType Directory -Force -Path $dist | Out-Null
    $zip = Join-Path $dist "Tamer-$version.zip"
    Compress-Archive -Path $folder -DestinationPath $zip -Force
    Write-Host "Built $zip with $($files.Count) files."
}
finally {
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
}

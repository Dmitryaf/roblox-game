param([Parameter(Mandatory=$true)][string]$StudioExe)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path $PSScriptRoot -Parent
if (-not (Test-Path -LiteralPath $StudioExe)) { throw 'Studio executable not found' }
$taskContent = Join-Path (Split-Path $StudioExe -Parent) 'content'
if (-not (Test-Path -LiteralPath (Join-Path $taskContent 'textures'))) { throw 'Studio content/textures not found' }
# Keep the original slice fixture audible too. No account or uploaded assets are involved.
& (Join-Path $PSScriptRoot 'install_studio_audio.ps1') -StudioExe $StudioExe
foreach ($taskGroup in @(
    @{ Source='assets/audio/warlock-art-v1'; Target='sounds/warlock-art-v1'; Files=@('charge.wav','launch.wav','impact.wav','teleport.wav') },
    @{ Source='assets/audio/warlock-art-v2'; Target='sounds/warlock-art-v2'; Files=@('charge.wav','impact.wav') },
    @{ Source='assets/textures/warlock-art-v1'; Target='textures/warlock-art-v1'; Files=@('flame.png','smoke.png') }
)) {
    $taskDestination = Join-Path $taskContent $taskGroup.Target
    New-Item -ItemType Directory -Force -Path $taskDestination | Out-Null
    foreach ($taskName in $taskGroup.Files) {
        Copy-Item -LiteralPath (Join-Path $taskRoot (Join-Path $taskGroup.Source $taskName)) -Destination (Join-Path $taskDestination $taskName)
    }
    Write-Output "Local Studio art installed: $taskDestination"
}

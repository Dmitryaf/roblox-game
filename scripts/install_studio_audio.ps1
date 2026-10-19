param([Parameter(Mandatory=$true)][string]$StudioExe)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path $PSScriptRoot -Parent
if (-not (Test-Path -LiteralPath $StudioExe)) { throw 'Studio executable not found' }
$taskContent = Join-Path (Split-Path $StudioExe -Parent) 'content/sounds'
if (-not (Test-Path -LiteralPath $taskContent)) { throw 'Studio content/sounds not found' }
$taskAudio = Join-Path $taskContent 'warlock-slice-v1'
New-Item -ItemType Directory -Force $taskAudio | Out-Null
foreach ($taskName in @('charge', 'launch', 'impact', 'teleport')) {
    Copy-Item -LiteralPath (Join-Path $taskRoot "assets/audio/$taskName.wav") -Destination (Join-Path $taskAudio "$taskName.wav")
}
Write-Output "Local Studio audio installed: $taskAudio"

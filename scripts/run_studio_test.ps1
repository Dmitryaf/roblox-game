param(
    [Parameter(Mandatory=$true)][string]$StudioExe,
    [switch]$Multiplayer,
    [switch]$Match,
    [switch]$Hands,
    [switch]$Warrior,
    [switch]$Dash,
    [switch]$Contact,
    [switch]$Heavy,
    [switch]$Mixed,
    [switch]$Feedback,
    [switch]$FeedbackBaseline,
    [switch]$Transfer,
    [switch]$Arena,
    [switch]$ArenaStaged,
    [switch]$Overlap,
    [ValidateSet(2,4,6)][int]$Clients = 2,
    [ValidateRange(0,500)][int]$LagMs = 0
)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
if (-not (Test-Path -LiteralPath $StudioExe)) { throw 'Studio executable not found' }
$taskRobloxRoot = Split-Path (Split-Path (Split-Path $StudioExe -Parent) -Parent) -Parent
$taskPluginDir = Join-Path $taskRobloxRoot 'Plugins'
$taskLogDir = Join-Path $taskRobloxRoot 'logs'
if (([int]$Match.IsPresent + [int]$Multiplayer.IsPresent + [int]$Hands.IsPresent + [int]$Warrior.IsPresent + [int]$Dash.IsPresent + [int]$Contact.IsPresent + [int]$Heavy.IsPresent + [int]$Mixed.IsPresent + [int]$Feedback.IsPresent + [int]$FeedbackBaseline.IsPresent + [int]$Transfer.IsPresent + [int]$Arena.IsPresent + [int]$ArenaStaged.IsPresent + [int]$Overlap.IsPresent) -gt 1) { throw 'Choose one runtime fixture' }
if (($Warrior -or $Dash -or $Contact -or $Heavy -or $Mixed -or $Feedback -or $FeedbackBaseline -or $Transfer) -and $Clients -ne 2) { throw 'Warrior/dash/contact/heavy/mixed fixtures require two clients' }
if (($Arena -or $ArenaStaged) -and $Clients -ne 6) { throw 'Arena combat fixture requires six real clients' }
if ($Overlap -and $Clients -ne 4) { throw 'Overlap fixture requires four real clients' }
if ($Clients -eq 4 -and -not $Overlap) { throw 'Four-client runner currently supports only overlap' }
if ($ArenaStaged) { python scripts/prepare_studio_test.py --arena-staged --clients $Clients --lag-ms $LagMs }
elseif ($FeedbackBaseline) { python scripts/prepare_studio_test.py --feedback-baseline --clients $Clients --lag-ms $LagMs }
elseif ($Arena) { python scripts/prepare_studio_test.py --arena --clients $Clients --lag-ms $LagMs }
elseif ($Transfer) { python scripts/prepare_studio_test.py --transfer --clients $Clients --lag-ms $LagMs }
elseif ($Feedback) { python scripts/prepare_studio_test.py --feedback --clients $Clients --lag-ms $LagMs }
elseif ($Overlap) { python scripts/prepare_studio_test.py --overlap --clients $Clients --lag-ms $LagMs }
elseif ($Mixed) { python scripts/prepare_studio_test.py --mixed --clients $Clients --lag-ms $LagMs }
elseif ($Heavy) { python scripts/prepare_studio_test.py --heavy --clients $Clients --lag-ms $LagMs }
elseif ($Contact) { python scripts/prepare_studio_test.py --contact --clients $Clients --lag-ms $LagMs }
elseif ($Dash) { python scripts/prepare_studio_test.py --dash --clients $Clients --lag-ms $LagMs }
elseif ($Warrior) { python scripts/prepare_studio_test.py --warrior --clients $Clients --lag-ms $LagMs }
elseif ($Hands) { python scripts/prepare_studio_test.py --hands --clients $Clients --lag-ms $LagMs }
elseif ($Match) { python scripts/prepare_studio_test.py --match --clients $Clients --lag-ms $LagMs }
elseif ($Multiplayer) { python scripts/prepare_studio_test.py --multiplayer --lag-ms $LagMs }
else { python scripts/prepare_studio_test.py }
if ($LASTEXITCODE -ne 0) { throw 'Could not prepare Studio test' }
$taskToken = (Get-Content build/studio-test-token.txt).Trim()
$taskPlace = Join-Path (Get-Location) "build/$taskToken.rbxlx"
& .tools/rojo/rojo.exe build build/studio-test.project.json -o $taskPlace
if ($LASTEXITCODE -ne 0) { throw 'Could not build Studio test' }
& .tools/rojo/rojo.exe build build/studio-plugin.project.json -o build/WarlockGeometryTest.rbxmx
if ($LASTEXITCODE -ne 0) { throw 'Could not build test plugin' }
& .tools/rojo/rojo.exe sourcemap build/studio-test.project.json -o build/studio-sourcemap.json
if ($LASTEXITCODE -ne 0) { throw 'Could not map Studio test' }
Push-Location build
try {
    $taskTestSources = if ($Multiplayer -or $Match -or $Hands -or $Warrior -or $Dash -or $Contact -or $Heavy -or $Mixed -or $Feedback -or $FeedbackBaseline -or $Transfer -or $Overlap -or $Arena -or $ArenaStaged) { '../tests/studio' } else { @('../tests/studio/world.luau', '../tests/studio/match_world.luau', '../tests/studio/dash_world.luau', '../tests/studio/movement_contact_world.luau', '../tests/studio/slow_world.luau', '../tests/studio/area_placement_world.luau') }
    & ../.tools/luau-lsp/luau-lsp.exe analyze --platform roblox --sourcemap studio-sourcemap.json --definitions ../.tools/roblox.d.luau $taskTestSources
    if ($LASTEXITCODE -ne 0) { throw 'Studio test type check failed' }
} finally { Pop-Location }
New-Item -ItemType Directory -Force $taskPluginDir | Out-Null
$taskPlugin = Join-Path $taskPluginDir "$taskToken.rbxmx"
if (Test-Path -LiteralPath $taskPlugin) { throw 'Unexpected existing plugin' }
$taskStarted = Get-Date
$taskCompleted = $false
try {
    Copy-Item -LiteralPath build/WarlockGeometryTest.rbxmx -Destination $taskPlugin
    $taskProcess = Start-Process -FilePath $StudioExe -ArgumentList ('"' + $taskPlace + '"') -WindowStyle Hidden -PassThru
    $taskLimit = if ($Arena -or $ArenaStaged) { 300 } elseif (($Match -and $Clients -eq 6) -or $Overlap) { 220 } else { 150 }
    $taskDeadline = (Get-Date).AddSeconds($taskLimit)
    do {
        Start-Sleep -Milliseconds 1000
        $taskMatches = @(Get-ChildItem -LiteralPath $taskLogDir -Filter '*Studio*last.log' |
            Where-Object LastWriteTime -GE $taskStarted | ForEach-Object {
                Select-String -LiteralPath $_.FullName -SimpleMatch "$taskToken RESULT" | ForEach-Object Line
            })
        if ($taskMatches.Count -gt 0) {
            $taskCompleted = $true
            $taskMatches | Tee-Object -FilePath "build/$taskToken-result.txt"
            if ($taskMatches[-1] -notmatch 'RESULT true (true|\{"ok":true\})') { throw 'Studio test failed; see result file' }
            return
        }
        if ($taskProcess.HasExited -and $taskProcess.ExitCode -ne 0) {
            $taskCompleted = $true
            throw "Studio exited with code $($taskProcess.ExitCode) before returning a test result; inspect its crash log"
        }
    } while ((Get-Date) -lt $taskDeadline)
    throw "Studio did not finish within $taskLimit seconds; inspect the test window"
} finally {
    # Remove only this uniquely named plugin created by this invocation.
    if (Test-Path -LiteralPath $taskPlugin) { Remove-Item -LiteralPath $taskPlugin }
    # Only close the process launched for this unique, generated test copy, after its plugin returned.
    # A timeout leaves the window available for diagnosis.
    if ($taskCompleted -and $taskProcess) {
        $taskOwned = Get-CimInstance Win32_Process -Filter "ProcessId=$($taskProcess.Id)" -ErrorAction SilentlyContinue
        if ($taskOwned -and $taskOwned.CommandLine -like "*$taskPlace*") {
            Stop-Process -Id $taskProcess.Id -ErrorAction SilentlyContinue
        }
    }
}

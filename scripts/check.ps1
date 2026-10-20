$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
function Invoke-Check([string]$Executable, [string[]]$Arguments) {
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Check failed: $Executable" }
}
New-Item -ItemType Directory -Force build | Out-Null
Invoke-Check python @('scripts/check_architecture.py')
Invoke-Check python @('-m', 'unittest', 'discover', '-s', 'tests/architecture', '-v')
Invoke-Check '.tools/lune/lune.exe' @('run', 'tests/unit/arrow.luau')
Invoke-Check '.tools/lune/lune.exe' @('run', 'tests/unit/hands.luau')
Invoke-Check '.tools/lune/lune.exe' @('run', 'tests/unit/hands_input.luau')
Invoke-Check '.tools/lune/lune.exe' @('run', 'tests/unit/hands_controller.luau')
Invoke-Check '.tools/lune/lune.exe' @('run', 'tests/unit/hands_gateway.luau')
Invoke-Check '.tools/lune/lune.exe' @('run', 'tests/unit/warlock_combat.luau')
Invoke-Check '.tools/lune/lune.exe' @('run', 'tests/unit/match.luau')
Invoke-Check '.tools/lune/lune.exe' @('run', 'tests/unit/match_requests.luau')
Invoke-Check '.tools/lune/lune.exe' @('run', 'tests/unit/match_controller.luau')
Invoke-Check '.tools/lune/lune.exe' @('run', 'tests/unit/match_gateway.luau')
Invoke-Check '.tools/lune/lune.exe' @('run', 'tests/unit/arrow_pause.luau')
Invoke-Check '.tools/lune/lune.exe' @('run', 'tests/unit/arrow_input.luau')
Invoke-Check '.tools/lune/lune.exe' @('run', 'tests/unit/classes.luau')
Invoke-Check '.tools/lune/lune.exe' @('run', 'tests/unit/class_gateway.luau')
Invoke-Check '.tools/lune/lune.exe' @('run', 'tests/unit/class_controller.luau')
Invoke-Check '.tools/lune/lune.exe' @('run', 'tests/unit/melee_input.luau')
Invoke-Check '.tools/lune/lune.exe' @('run', 'tests/unit/melee_controller.luau')
Invoke-Check '.tools/lune/lune.exe' @('run', 'tests/unit/melee.luau')
Invoke-Check '.tools/lune/lune.exe' @('run', 'tests/unit/melee_motion.luau')
Invoke-Check '.tools/lune/lune.exe' @('run', 'tests/unit/melee_gateway.luau')
Invoke-Check '.tools/lune/lune.exe' @('run', 'tests/unit/class_combat.luau')
Invoke-Check '.tools/rojo/rojo.exe' @('sourcemap', 'default.project.json', '-o', 'build/sourcemap.json')
Invoke-Check '.tools/luau-lsp/luau-lsp.exe' @('analyze', '--platform', 'roblox', '--sourcemap', 'build/sourcemap.json', '--definitions', '.tools/roblox.d.luau', 'src')
Invoke-Check '.tools/rojo/rojo.exe' @('build', 'default.project.json', '-o', 'build/ControlMatch.rbxlx')
# Keep the path used for the first local slice usable as the prototype grows.
Copy-Item -LiteralPath build/ControlMatch.rbxlx -Destination build/WarlockSlice.rbxlx -Force

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
Invoke-Check '.tools/lune/lune.exe' @('run', 'tests/unit/arrow_pause.luau')
Invoke-Check '.tools/lune/lune.exe' @('run', 'tests/unit/arrow_input.luau')
Invoke-Check '.tools/rojo/rojo.exe' @('sourcemap', 'default.project.json', '-o', 'build/sourcemap.json')
Invoke-Check '.tools/luau-lsp/luau-lsp.exe' @('analyze', '--platform', 'roblox', '--sourcemap', 'build/sourcemap.json', '--definitions', '.tools/roblox.d.luau', 'src')
Invoke-Check '.tools/rojo/rojo.exe' @('build', 'default.project.json', '-o', 'build/WarlockSlice.rbxlx')

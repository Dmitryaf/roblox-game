$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
$taskLock = Get-Content tools.lock.json -Raw | ConvertFrom-Json
New-Item -ItemType Directory -Force .tools | Out-Null
foreach ($taskName in @('rojo', 'lune', 'luau-lsp', 'robloxTypes')) {
    $taskTool = $taskLock.$taskName
    $taskFile = if ($taskName -eq 'robloxTypes') { '.tools/roblox.d.luau' } else { ".tools/$taskName.zip" }
    if (-not (Test-Path -LiteralPath $taskFile)) { Invoke-WebRequest $taskTool.url -OutFile $taskFile }
    if ((Get-FileHash -LiteralPath $taskFile -Algorithm SHA256).Hash -ne $taskTool.sha256) {
        throw "Hash mismatch: $taskFile; inspect the downloaded file before retrying"
    }
    if ($taskName -ne 'robloxTypes') { Expand-Archive -LiteralPath $taskFile -DestinationPath ".tools/$taskName" -Force }
}
& .tools/rojo/rojo.exe --version
& .tools/lune/lune.exe --version
& .tools/luau-lsp/luau-lsp.exe --version

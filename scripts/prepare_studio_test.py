"""Create a token-guarded local test place/plugin. Does not install the plugin or launch Studio."""
from pathlib import Path
import json
import uuid
import sys

ROOT = Path(__file__).resolve().parents[1]
token = "warlock-test-" + uuid.uuid4().hex
multiplayer = "--multiplayer" in sys.argv
match = "--match" in sys.argv
hands = "--hands" in sys.argv
warrior = "--warrior" in sys.argv
dash = "--dash" in sys.argv
clients = int(sys.argv[sys.argv.index("--clients") + 1]) if "--clients" in sys.argv else 2
assert clients in (2, 6)
assert not (warrior or dash) or clients == 2, "Warrior/dash fixtures require two clients"
lag_ms = int(sys.argv[sys.argv.index("--lag-ms") + 1]) if "--lag-ms" in sys.argv else 0
project = json.loads((ROOT / "default.project.json").read_text())
project["tree"]["ReplicatedStorage"]["StudioTestToken"] = {
    "$className": "StringValue", "$properties": {"Value": token}
}
project["tree"]["ServerStorage"] = {"StudioWorldTests": {"$path": str(ROOT / "tests/studio/world.luau")}}
project["tree"]["ServerStorage"]["MatchWorldTests"] = {"$path": str(ROOT / "tests/studio/match_world.luau")}
project["tree"]["ServerStorage"]["DashWorldTests"] = {"$path": str(ROOT / "tests/studio/dash_world.luau")}
if not (match or hands or warrior or dash):
    # Preserve the original arrow fixture and expectations as the main place grows.
    project["tree"]["ServerScriptService"]["Game"] = {
        name: {"$path": str(ROOT / "src/server" / name)}
        for name in ("adapters", "application", "config", "domain")
    }
    project["tree"]["ServerScriptService"]["Game"]["Bootstrap"] = {
        "$path": str(ROOT / "tests/fixtures/slice-bootstrap.server.luau")
    }
    project["tree"]["ServerScriptService"]["Game"]["$className"] = "Folder"
if match:
    project["tree"]["ReplicatedStorage"]["WarlockArtTests"] = {"$path": str(ROOT / "tests/studio/warlock_art.luau")}
    project["tree"]["ServerStorage"]["$attributes"] = {"MatchTest": True}
    project["tree"]["ReplicatedStorage"]["MatchTestControl"] = {"$className": "RemoteEvent"}
    project["tree"]["ServerScriptService"]["MatchTest"] = {"$path": str(ROOT / "tests/studio/match.server.luau")}
    project["tree"]["StarterPlayer"]["StarterPlayerScripts"]["MatchTest"] = {"$path": str(ROOT / "tests/studio/match.client.luau")}
elif multiplayer:
    project["tree"]["ReplicatedStorage"]["SliceTestControl"] = {"$className": "RemoteEvent"}
    project["tree"]["ServerScriptService"]["MultiplayerTest"] = {"$path": str(ROOT / "tests/studio/multiplayer.server.luau")}
    project["tree"]["StarterPlayer"]["StarterPlayerScripts"]["MultiplayerTest"] = {"$path": str(ROOT / "tests/studio/multiplayer.client.luau")}
if hands:
    project["tree"]["ServerStorage"]["$attributes"] = {"MatchTest": True, "HandsTest": True}
    project["tree"]["ReplicatedStorage"]["HandsTestControl"] = {"$className": "RemoteEvent"}
    project["tree"]["ServerScriptService"]["HandsTest"] = {"$path": str(ROOT / "tests/studio/hands.server.luau")}
    project["tree"]["StarterPlayer"]["StarterPlayerScripts"]["HandsTest"] = {"$path": str(ROOT / "tests/studio/hands.client.luau")}
if warrior:
    project["tree"]["ServerStorage"]["$attributes"] = {"MatchTest": True, "WarriorTest": True}
    project["tree"]["ReplicatedStorage"]["WarriorTestControl"] = {"$className": "RemoteEvent"}
    project["tree"]["ReplicatedStorage"]["WarriorTestDriver"] = {"$path": str(ROOT / "tests/studio/client/WarriorDriver.luau")}
    project["tree"]["ReplicatedStorage"]["WarriorMotionProbe"] = {"$path": str(ROOT / "tests/studio/client/WarriorMotionProbe.luau")}
    project["tree"]["ServerScriptService"]["WarriorTest"] = {"$path": str(ROOT / "tests/studio/warrior.server.luau")}
    project["tree"]["StarterPlayer"]["StarterPlayerScripts"]["WarriorTest"] = {"$path": str(ROOT / "tests/studio/warrior.client.luau")}
if dash:
    project["tree"]["ServerStorage"]["$attributes"] = {"MatchTest": True, "DashTest": True}
    project["tree"]["ReplicatedStorage"]["DashTestControl"] = {"$className": "RemoteEvent"}
    project["tree"]["ReplicatedStorage"]["DashTestDriver"] = {"$path": str(ROOT / "tests/studio/client/DashDriver.luau")}
    project["tree"]["ServerScriptService"]["DashTest"] = {"$path": str(ROOT / "tests/studio/dash.server.luau")}
    project["tree"]["StarterPlayer"]["StarterPlayerScripts"]["DashTest"] = {"$path": str(ROOT / "tests/studio/dash.client.luau")}
# This project lives in build/, so resolve source paths before writing it.
def absolute_paths(value):
    if isinstance(value, dict):
        for key, item in value.items():
            if key == "$path":
                value[key] = str((ROOT / item).resolve())
            else:
                absolute_paths(item)
absolute_paths(project)
(ROOT / "build/studio-test.project.json").write_text(json.dumps(project), encoding="utf-8")
runtime_test = multiplayer or match or hands or warrior or dash
test_expression = f'game:GetService("StudioTestService"):ExecuteMultiplayerTestAsync({clients}, {{ lagMs = {lag_ms}, clients = {clients} }})' if runtime_test else '(function() assert(require(game:GetService("ServerStorage"):WaitForChild("StudioWorldTests", 10))); assert(require(game:GetService("ServerStorage"):WaitForChild("MatchWorldTests", 10))); return require(game:GetService("ServerStorage"):WaitForChild("DashWorldTests", 10)) end)()'
plugin = f'''--!strict
task.defer(function()
    -- A freshly created test server/client can load plugins before simulation starts.
    -- IsRunning alone does not distinguish that runtime DataModel from the editor.
    if not game:GetService("StudioTestService").EditModeActive then return end
    local token = game:GetService("ReplicatedStorage"):FindFirstChild("StudioTestToken")
    if not token or not token:IsA("StringValue") or token.Value ~= "{token}" then return end
    print("{token} START")
    local network = settings().Network
    local previous = {{}}
    local values = {{ InboundNetworkMinDelayMs = {lag_ms}, OutboundNetworkMinDelayMs = {lag_ms},
        InboundNetworkJitterMs = 0, OutboundNetworkJitterMs = 0,
        InboundNetworkLossPercent = 0, OutboundNetworkLossPercent = 0 }}
    local ok, result = xpcall(function()
        if {str(runtime_test).lower()} then
            for key, value in values do previous[key] = network[key]; network[key] = value end
        end
        return {test_expression}
    end, debug.traceback)
    for key, value in previous do network[key] = value end
    print("{token} network settings restored")
    print("{token} RESULT " .. tostring(ok) .. " " .. (if type(result) == "table" then game:GetService("HttpService"):JSONEncode(result) else tostring(result)))
end)
'''
(ROOT / "build/StudioTestPlugin.server.luau").write_text(plugin, encoding="utf-8")
(ROOT / "build/studio-plugin.project.json").write_text(json.dumps({
    "name": "WarlockGeometryTest", "tree": {"$path": "StudioTestPlugin.server.luau"}
}), encoding="utf-8")
(ROOT / "build/studio-test-token.txt").write_text(token)
print(token)

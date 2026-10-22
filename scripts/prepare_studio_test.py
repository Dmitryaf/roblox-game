"""Create a token-guarded local test place/plugin. Does not install the plugin or launch Studio."""
from pathlib import Path
import json
import uuid
import sys
import shutil
import re

ROOT = Path(__file__).resolve().parents[1]
token = "warlock-test-" + uuid.uuid4().hex
multiplayer = "--multiplayer" in sys.argv
match = "--match" in sys.argv
hands = "--hands" in sys.argv
warrior = "--warrior" in sys.argv
dash = "--dash" in sys.argv
contact = "--contact" in sys.argv
heavy = "--heavy" in sys.argv
feedback_baseline = "--feedback-baseline" in sys.argv
feedback = "--feedback" in sys.argv or feedback_baseline
transfer = "--transfer" in sys.argv
living = "--living" in sys.argv
arena_staged = "--arena-staged" in sys.argv
arena = "--arena" in sys.argv or arena_staged
mixed = "--mixed" in sys.argv
overlap = "--overlap" in sys.argv
clients = int(sys.argv[sys.argv.index("--clients") + 1]) if "--clients" in sys.argv else 2
assert clients in (2, 4, 6)
assert sum([mixed, overlap, feedback, transfer, arena, living]) <= 1, "Choose one combat fixture"
assert not overlap or clients == 4, "Overlap fixture requires four real clients"
assert not arena or clients == 6, "Arena combat fixture requires six real clients"
assert clients != 4 or overlap, "Four-client runner currently supports only overlap"
assert not (warrior or dash or contact or heavy or mixed or feedback or transfer or living) or clients == 2, "Warrior/dash/contact/heavy/mixed fixtures require two clients"
lag_ms = int(sys.argv[sys.argv.index("--lag-ms") + 1]) if "--lag-ms" in sys.argv else 0
project = json.loads((ROOT / "default.project.json").read_text())
project["tree"]["ReplicatedStorage"]["StudioTestToken"] = {
    "$className": "StringValue", "$properties": {"Value": token}
}
project["tree"]["ServerStorage"] = {"StudioWorldTests": {"$path": str(ROOT / "tests/studio/world.luau")}}
project["tree"]["ServerStorage"]["MatchWorldTests"] = {"$path": str(ROOT / "tests/studio/match_world.luau")}
project["tree"]["ServerStorage"]["DashWorldTests"] = {"$path": str(ROOT / "tests/studio/dash_world.luau")}
project["tree"]["ServerStorage"]["MovementContactWorldTests"] = {"$path": str(ROOT / "tests/studio/movement_contact_world.luau")}
project["tree"]["ServerStorage"]["SlowWorldTests"] = {"$path": str(ROOT / "tests/studio/slow_world.luau")}
project["tree"]["ServerStorage"]["AreaPlacementWorldTests"] = {"$path": str(ROOT / "tests/studio/area_placement_world.luau")}
if not (match or hands or warrior or dash or contact or heavy or mixed or overlap or feedback or transfer or arena or living):
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
if contact:
    project["tree"]["ServerStorage"]["$attributes"] = {"MatchTest": True, "ContactTest": True}
    project["tree"]["ReplicatedStorage"]["ContactTestControl"] = {"$className": "RemoteEvent"}
    project["tree"]["ReplicatedStorage"]["ContactClassDriver"] = {"$path": str(ROOT / "tests/studio/client/DashDriver.luau")}
    project["tree"]["ReplicatedStorage"]["ContactTestDriver"] = {"$path": str(ROOT / "tests/studio/client/ContactDriver.luau")}
    project["tree"]["ServerScriptService"]["ContactTest"] = {"$path": str(ROOT / "tests/studio/contact.server.luau")}
    project["tree"]["StarterPlayer"]["StarterPlayerScripts"]["ContactTest"] = {"$path": str(ROOT / "tests/studio/contact.client.luau")}
if heavy:
    project["tree"]["ServerStorage"]["$attributes"] = {"MatchTest": True, "HeavyTest": True}
    project["tree"]["ReplicatedStorage"]["HeavyTestControl"] = {"$className": "RemoteEvent"}
    project["tree"]["ReplicatedStorage"]["HeavyClassDriver"] = {"$path": str(ROOT / "tests/studio/client/DashDriver.luau")}
    project["tree"]["ReplicatedStorage"]["HeavyTestDriver"] = {"$path": str(ROOT / "tests/studio/client/HeavyDriver.luau")}
    project["tree"]["ServerScriptService"]["HeavyTest"] = {"$path": str(ROOT / "tests/studio/heavy.server.luau")}
    project["tree"]["StarterPlayer"]["StarterPlayerScripts"]["HeavyTest"] = {"$path": str(ROOT / "tests/studio/heavy.client.luau")}
if mixed or overlap or transfer or arena or living:
    project["tree"]["ServerStorage"]["$attributes"] = {"MatchTest": True, "MixedTest": mixed, "OverlapTest": overlap, "TransferTest": transfer, "ArenaTest": arena, "StagedArenaTest": arena_staged}
    project["tree"]["ReplicatedStorage"]["MixedTestControl"] = {"$className": "RemoteEvent"}
    project["tree"]["ReplicatedStorage"]["MixedClassDriver"] = {"$path": str(ROOT / "tests/studio/client/DashDriver.luau")}
    project["tree"]["ReplicatedStorage"]["MixedTestDriver"] = {"$path": str(ROOT / "tests/studio/client/MixedDriver.luau")}
    project["tree"]["ServerScriptService"]["MixedTest"] = {"$path": str(ROOT / "tests/studio/arena.server.luau" if arena else "tests/studio/transfer.server.luau" if transfer else "tests/studio/overlap.server.luau" if overlap else "tests/studio/mixed.server.luau")}
    project["tree"]["StarterPlayer"]["StarterPlayerScripts"]["MixedTest"] = {"$path": str(ROOT / "tests/studio/mixed.client.luau")}
if living:
    project["tree"]["ReplicatedStorage"]["LivingNativePoseTests"] = {"$path": str(ROOT / "tests/studio/living_magic/native_pose.luau")}
    project["tree"]["ReplicatedStorage"]["LivingNativeObserver"] = {"$path": str(ROOT / "tests/studio/living_magic/native_observer.luau")}
    project["tree"]["ReplicatedStorage"]["NativeCombatClips"] = {
        "$className": "Folder",
        "WarriorStrike": {"$path": "assets/animations/WarriorStrike_Draft03.rbxmx"},
        "WarlockCast": {"$path": "assets/animations/WarlockCast_Draft02.rbxmx"},
    }
    project["tree"]["ServerStorage"]["$attributes"].update({"MixedTest": True, "LivingMagicExperiment": True})
    project["tree"]["ServerStorage"]["LivingCoverWorldTests"] = {"$path": str(ROOT / "tests/studio/living_magic/cover_world.luau")}
    project["tree"]["ServerScriptService"]["MixedTest"] = {"$path": str(ROOT / "tests/studio/living_magic/experiment.server.luau")}
    project["tree"]["StarterPlayer"]["StarterPlayerScripts"]["MixedTest"] = {"$path": str(ROOT / "tests/studio/living_magic/experiment.client.luau")}
if arena_staged:
    project["tree"]["ServerScriptService"]["StagedPlayers"] = {"$path": str(ROOT / "tests/studio/staged_players.server.luau")}
if feedback:
    project["tree"]["ServerStorage"]["$attributes"] = {"MatchTest": True, "FeedbackTest": True, "FeedbackBaseline": feedback_baseline}
    project["tree"]["ReplicatedStorage"]["FeedbackTestControl"] = {"$className": "RemoteEvent"}
    project["tree"]["ReplicatedStorage"]["MixedClassDriver"] = {"$path": str(ROOT / "tests/studio/client/DashDriver.luau")}
    project["tree"]["ReplicatedStorage"]["MixedTestDriver"] = {"$path": str(ROOT / "tests/studio/client/MixedDriver.luau")}
    project["tree"]["ReplicatedStorage"]["FeedbackTestDriver"] = {"$path": str(ROOT / "tests/studio/client/MixedDriver.luau")}
    project["tree"]["ReplicatedStorage"]["FeedbackProbe"] = {"$path": str(ROOT / "tests/studio/client/FeedbackProbe.luau")}
    project["tree"]["ReplicatedStorage"]["MixedTestControl"] = {"$className": "RemoteEvent"}
    project["tree"]["ServerScriptService"]["FeedbackTest"] = {"$path": str(ROOT / "tests/studio/feedback.server.luau")}
    project["tree"]["StarterPlayer"]["StarterPlayerScripts"]["FeedbackTest"] = {"$path": str(ROOT / "tests/studio/feedback.client.luau")}
if feedback_baseline:
    shadow = ROOT / "build/feedback-baseline-client"
    shutil.copytree(ROOT / "src/client", shadow, dirs_exist_ok=True)
    for name in ["MeleeEffects", "ArrowEffects", "DashEffects"]:
        path = shadow / "presentation" / (name + ".luau")
        source = path.read_text(encoding="utf-8")
        source, count = re.subn(
            r"^([ \t]*)(function effects\.preview\([^\n]+\n).*?^\1end\b",
            # A no-op presentation must preserve the accepted-input path. Dash
            # treats false as a local action conflict and would never send E.
            lambda match: match[1] + match[2] + match[1] + "    return true\n" + match[1] + "end",
            source, flags=re.S | re.M,
        )
        assert count == 1, "Expected exactly one explicit preview hook in " + name
        path.write_text(source, encoding="utf-8")
    project["tree"]["StarterPlayer"]["StarterPlayerScripts"]["Game"] = {"$path": str(shadow)}
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
runtime_test = multiplayer or match or hands or warrior or dash or contact or heavy or mixed or overlap or feedback or transfer or arena or living
initial_clients = 2 if arena_staged else clients
test_expression = f'game:GetService("StudioTestService"):ExecuteMultiplayerTestAsync({initial_clients}, {{ lagMs = {lag_ms}, clients = {clients} }})' if runtime_test else '(function() assert(require(game:GetService("ServerStorage"):WaitForChild("StudioWorldTests", 10))); assert(require(game:GetService("ServerStorage"):WaitForChild("MatchWorldTests", 10))); assert(require(game:GetService("ServerStorage"):WaitForChild("DashWorldTests", 10))); assert(require(game:GetService("ServerStorage"):WaitForChild("MovementContactWorldTests", 10)).run()); assert(require(game:GetService("ServerStorage"):WaitForChild("SlowWorldTests", 10))); assert(require(game:GetService("ServerStorage"):WaitForChild("AreaPlacementWorldTests", 10))); return true end)()'
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
            print("{token} previous network delay", previous.InboundNetworkMinDelayMs, previous.OutboundNetworkMinDelayMs)
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

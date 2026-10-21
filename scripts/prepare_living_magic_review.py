"""Build isolated local baseline/authoring projects. Never uploads or launches Studio.

The baseline uses existing production code and real input in two Studio clients.
The authoring stage deliberately has no generated animation or combat replacement.
"""
from pathlib import Path
import argparse
import json
import shutil
import uuid
import subprocess

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--authoring', action='store_true')
parser.add_argument('--native', action='store_true', help='Review the opt-in experiment with native combat clips')
parser.add_argument('--auto', action='store_true', help='Advance comparison scenes automatically and return a Studio test result')
args = parser.parse_args()
assert not (args.authoring and args.native), 'Choose authoring or native combat review'
assert not (args.authoring and args.auto), 'Authoring is an interactive scene'
token = 'living-review-' + uuid.uuid4().hex
out = ROOT / 'build/living-magic' / token
out.mkdir(parents=True)

def absolute(value):
    if isinstance(value, dict):
        for key, item in value.items():
            if key == '$path': value[key] = str((ROOT / item).resolve())
            else: absolute(item)

if args.authoring:
    project = {'name': 'LivingMagicAuthoring', 'tree': {
        '$className': 'DataModel',
        'Workspace': {'$className': 'Workspace', 'AuthoringFloor': {
            '$className': 'Part', '$properties': {
                'Anchored': True, 'Size': [48, 1, 48], 'Position': [0, -0.5, 0],
                'Color': [0.55, 0.57, 0.6], 'Material': 'Concrete'}}},
        'Lighting': {'$properties': {'ClockTime': 13, 'Brightness': 2,
            'Ambient': [0.5, 0.5, 0.5], 'OutdoorAmbient': [0.6, 0.6, 0.6]}},
        'ServerStorage': {'AnimationSources': {'$className': 'Folder'}},
    }}
else:
    project = json.loads((ROOT / 'default.project.json').read_text(encoding='utf-8'))
    project['tree']['ReplicatedStorage'].update({
        'StudioTestToken': {'$className': 'StringValue', '$properties': {'Value': token}},
        'LivingReviewControl': {'$className': 'RemoteEvent'},
        'MixedTestDriver': {'$path': 'tests/studio/client/MixedDriver.luau'},
        'MixedClassDriver': {'$path': 'tests/studio/client/DashDriver.luau'},
    })
    project['tree']['ServerStorage'] = {'$attributes': {'MatchTest': True, 'ArenaTest': True}}
    project['tree']['ServerStorage']['$attributes']['LivingReviewAuto'] = args.auto
    if args.native:
        project['tree']['ServerStorage']['$attributes']['LivingMagicExperiment'] = True
        project['tree']['ReplicatedStorage']['NativeCombatClips'] = {
            '$className': 'Folder',
            'WarriorStrike': {'$path': 'assets/animations/WarriorStrike_Draft02.rbxmx'},
            'WarlockCast': {'$path': 'assets/animations/WarlockCast_Draft01.rbxmx'},
        }
    project['tree']['ServerScriptService']['LivingReview'] = {'$path': 'tests/studio/living_magic/baseline.server.luau'}
    project['tree']['StarterPlayer']['StarterPlayerScripts']['LivingReview'] = {'$path': 'tests/studio/living_magic/baseline.client.luau'}
    absolute(project)
    # A review waits for a human/observer between cases. Extend only the isolated
    # ArenaTest clock, never production match rules or gameplay timings.
    shadow = out / 'server'
    shutil.copytree(ROOT / 'src/server', shadow)
    fixture = shadow / 'adapters/runtime/StudioMatchFixture.luau'
    fixture_source = fixture.read_text(encoding='utf-8')
    assert fixture_source.count('duration = 240') == 1
    fixture.write_text(fixture_source.replace('duration = 240', 'duration = 1800'), encoding='utf-8')
    project['tree']['ServerScriptService']['Game'] = {'$path': str(shadow)}
    plugin = '''--!strict
task.defer(function()
    if not game:GetService("StudioTestService").EditModeActive then return end
    local token = game:GetService("ReplicatedStorage"):FindFirstChild("StudioTestToken")
    if not token or not token:IsA("StringValue") or token.Value ~= "TOKEN" then return end
    print("TOKEN START")
    local ok, result = pcall(function()
        return game:GetService("StudioTestService"):ExecuteMultiplayerTestAsync(2, { review = true })
    end)
    print("TOKEN RESULT", ok, game:GetService("HttpService"):JSONEncode(result))
end)
'''.replace('TOKEN', token)
    (out / 'plugin.server.luau').write_text(plugin, encoding='utf-8')
    (out / 'plugin.project.json').write_text(json.dumps({'name': token, 'tree': {'$path': 'plugin.server.luau'}}), encoding='utf-8')

(out / 'review.project.json').write_text(json.dumps(project), encoding='utf-8')
metadata = {'token': token, 'mode': 'authoring' if args.authoring else 'native' if args.native else 'baseline', 'auto': args.auto,
    'directory': str(out), 'project': str(out / 'review.project.json'),
    'place': str(out / ('Authoring.rbxlx' if args.authoring else 'NativeReview.rbxlx' if args.native else 'Baseline.rbxlx')),
    'sourceHead': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
    'sourceDirty': bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True).strip()),
    'verdict': 'not reviewed; a playable comparison fixture is not acceptance'}
(ROOT / ('build/living-authoring.json' if args.authoring else 'build/living-native-review.json' if args.native else 'build/living-baseline.json')).write_text(json.dumps(metadata, indent=2), encoding='utf-8')
print(json.dumps(metadata))

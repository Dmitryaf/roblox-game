"""Build a local two-client Living Magic episode. Does not install or launch anything."""
from pathlib import Path
import argparse
import json
import shutil
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--auto', action='store_true', help='Run the examples and return a Studio test result')
args = parser.parse_args()
token = 'living-episode-' + uuid.uuid4().hex
out = ROOT / 'build/living-magic' / token
out.mkdir(parents=True)
project = json.loads((ROOT / 'default.project.json').read_text(encoding='utf-8'))
project['name'] = 'LivingMagicEpisode'
# A little neutral fill keeps both dark costumes readable under the broken arch.
# This presentation scene does not change the comparison match's lighting.
project['tree']['Lighting']['$properties'].update({
    'Ambient': [0.32, 0.35, 0.36], 'OutdoorAmbient': [0.44, 0.47, 0.48],
    'ExposureCompensation': 0.15,
})
project['tree']['ReplicatedStorage'].update({
    'StudioTestToken': {'$className': 'StringValue', '$properties': {'Value': token}},
    'LivingEpisodeControl': {'$className': 'RemoteEvent'},
    'MixedTestDriver': {'$path': 'tests/studio/client/MixedDriver.luau'},
    'MixedClassDriver': {'$path': 'tests/studio/client/DashDriver.luau'},
    'NativeCombatClips': {
        '$className': 'Folder',
        'WarriorStrike': {'$path': 'assets/animations/WarriorStrike_Draft03.rbxmx'},
        'WarlockCast': {'$path': 'assets/animations/WarlockCast_Draft02.rbxmx'},
    },
})
project['tree']['ServerStorage'] = {'$attributes': {
    'MatchTest': True, 'ArenaTest': True, 'LivingMagicExperiment': True,
    'LivingEpisodeAuto': args.auto,
}}
project['tree']['ServerScriptService']['LivingEpisode'] = {'$path': 'tests/studio/living_magic/episode.server.luau'}
project['tree']['StarterPlayer']['StarterPlayerScripts']['LivingEpisode'] = {'$path': 'tests/studio/living_magic/episode.client.luau'}


def absolute(value):
    if isinstance(value, dict):
        for key, item in value.items():
            if key == '$path':
                value[key] = str((ROOT / item).resolve())
            else:
                absolute(item)


absolute(project)
# Keep the comparison session open for free play. Only this private fixture copy
# changes the review clock; live match timings and scoring are untouched.
shadow = out / 'server'
shutil.copytree(ROOT / 'src/server', shadow)
fixture = shadow / 'adapters/runtime/StudioMatchFixture.luau'
source = fixture.read_text(encoding='utf-8')
assert source.count('duration = 240') == 1
fixture.write_text(source.replace('duration = 240', 'duration = 1800'), encoding='utf-8')
project['tree']['ServerScriptService']['Game'] = {'$path': str(shadow)}
(out / 'episode.project.json').write_text(json.dumps(project, indent=2), encoding='utf-8')
plugin = '''--!strict
task.defer(function()
    local studio = game:GetService("StudioTestService")
    if not studio.EditModeActive then return end
    local token = game:GetService("ReplicatedStorage"):FindFirstChild("StudioTestToken")
    if not token or not token:IsA("StringValue") or token.Value ~= "TOKEN" then return end
    print("TOKEN START")
    local ok, result = pcall(function() return studio:ExecuteMultiplayerTestAsync(2, { episode = true }) end)
    print("TOKEN RESULT", ok, game:GetService("HttpService"):JSONEncode(result))
end)
'''.replace('TOKEN', token)
(out / 'plugin.server.luau').write_text(plugin, encoding='utf-8')
(out / 'plugin.project.json').write_text(json.dumps({'name': token, 'tree': {'$path': 'plugin.server.luau'}}), encoding='utf-8')
place = ROOT / 'build/LivingMagicEpisode.rbxlx'
if args.auto:
    place = out / 'EpisodeAuto.rbxlx'
subprocess.run([str(ROOT / '.tools/rojo/rojo.exe'), 'build', str(out/'episode.project.json'), '-o', str(place)], check=True)
metadata = {
    'token': token, 'auto': args.auto, 'directory': str(out),
    'project': str(out/'episode.project.json'), 'place': str(place),
    'pluginProject': str(out/'plugin.project.json'),
    'sourceHead': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
    'sourceDirty': bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True).strip()),
    'verdict': 'not run; scripted alternatives do not prove balance or player interest',
}
(ROOT / ('build/living-episode-auto.json' if args.auto else 'build/living-episode.json')).write_text(json.dumps(metadata, indent=2), encoding='utf-8')
print(json.dumps(metadata))

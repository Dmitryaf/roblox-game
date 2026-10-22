"""Build the opt-in local experiment from the same source as the comparison match."""
from pathlib import Path
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]
project = json.loads((ROOT / "default.project.json").read_text(encoding="utf-8"))
project["name"] = "LivingMagic"
project["tree"]["ServerStorage"] = {"$className": "ServerStorage", "$attributes": {"LivingMagicExperiment": True}}
project["tree"]["ReplicatedStorage"]["NativeCombatClips"] = {
    "$className": "Folder",
    "WarriorStrike": {"$path": "assets/animations/WarriorStrike_Draft03.rbxmx"},
    "WarlockCast": {"$path": "assets/animations/WarlockCast_Draft02.rbxmx"},
}

def absolute_paths(value):
    if isinstance(value, dict):
        for key, item in value.items():
            if key == "$path":
                value[key] = str((ROOT / item).resolve())
            else:
                absolute_paths(item)

absolute_paths(project)
(ROOT / "build").mkdir(exist_ok=True)
path = ROOT / "build/living-magic.project.json"
path.write_text(json.dumps(project, indent=2), encoding="utf-8")
subprocess.run([str(ROOT / ".tools/rojo/rojo.exe"), "build", str(path), "-o", str(ROOT / "build/LivingMagic.rbxlx")], check=True)

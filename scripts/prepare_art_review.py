"""Build a local-only art review place from the production project; never launches Studio."""
from pathlib import Path
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def absolute_paths(value):
    if isinstance(value, dict):
        for key, item in value.items():
            if key == "$path":
                value[key] = str((ROOT / item).resolve())
            else:
                absolute_paths(item)


def main():
    project = json.loads((ROOT / "default.project.json").read_text(encoding="utf-8"))
    project["name"] = "WarlockArtReview"
    tree = project["tree"]
    tree["ReplicatedStorage"]["StudioTestToken"] = {
        "$className": "StringValue", "$properties": {"Value": "art-review-local"}
    }
    tree["ReplicatedStorage"]["ArtReviewControl"] = {"$className": "RemoteEvent"}
    tree["ReplicatedStorage"]["WarlockArtTests"] = {"$path": "tests/studio/warlock_art.luau"}
    tree.setdefault("ServerStorage", {}).setdefault("$attributes", {})["MatchTest"] = True
    tree["ServerScriptService"]["ArtReview"] = {"$path": "tests/studio/art_review.server.luau"}
    tree["StarterPlayer"]["StarterPlayerScripts"]["ArtReview"] = {
        "$path": "tests/studio/art_review.client.luau"
    }
    absolute_paths(project)
    build = ROOT / "build"
    build.mkdir(exist_ok=True)
    project_path, place_path = build / "WarlockArtReview.project.json", build / "WarlockArtReview.rbxlx"
    project_path.write_text(json.dumps(project, ensure_ascii=False, indent=2), encoding="utf-8")
    rojo = ROOT / ".tools/rojo/rojo.exe"
    if not rojo.is_file():
        raise FileNotFoundError("Install the pinned local Rojo tool before preparing the art review.")
    subprocess.run([str(rojo), "build", str(project_path), "-o", str(place_path)],
                   check=True, cwd=ROOT)
    print(f"Local art review ready: {place_path}")


if __name__ == "__main__":
    main()

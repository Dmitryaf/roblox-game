"""Check the project's explicitly supported static require syntax; stage identical modules for Lune."""
from pathlib import Path
import os
import re

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
REQUIRE = re.compile(r'require\((script(?:\.[A-Za-z_][\w]*)+|game:GetService\("ReplicatedStorage"\)(?:\.[A-Za-z_][\w]*)+)\)')


def resolve(source, expression):
    if expression.startswith("script."):
        result = source.removesuffix(".luau").removesuffix(".server").removesuffix(".client").split("/")
        for segment in expression.split(".")[1:]:
            if segment == "Parent":
                if not result:
                    raise ValueError("require outside source tree")
                result.pop()
            else:
                result.append(segment)
        return "/".join(result) + ".luau"
    tail = expression.split(").", 1)[1].split(".")
    if tail[0] != "Shared":
        raise ValueError("ReplicatedStorage requires must start at Shared")
    return "/".join(["shared", *tail[1:]]) + ".luau"


def allowed(source, target):
    if target.endswith((".server.luau", ".client.luau")) or "Bootstrap" in target:
        return False
    if source.startswith("shared/"):
        return target.startswith("shared/")
    if source.startswith("client/"):
        return target.startswith(("client/", "shared/"))
    if not target.startswith(("server/", "shared/")):
        return False
    if source.startswith("server/domain/"):
        return target.startswith(("server/domain/", "shared/contracts/"))
    if source.startswith("server/application/"):
        return target.startswith(("server/application/", "server/domain/", "shared/contracts/"))
    if source.startswith("server/adapters/"):
        return target.startswith(("server/adapters/", "server/domain/", "shared/contracts/"))
    return True


def graph_for(sources):
    graph = {}
    for name, code in sources.items():
        if not code.startswith("--!strict"):
            raise ValueError(f"{name}: missing strict mode")
        # This project uses line comments, no long strings/comments around imports.
        clean = re.sub(r"--[^\n]*", "", code)
        matches = list(REQUIRE.finditer(clean))
        if len(re.findall(r"\brequire\s*\(", clean)) != len(matches):
            raise ValueError(f"{name}: unsupported require; aliases and dynamic imports are forbidden")
        if name.startswith(("server/domain/", "server/application/")) and re.search(r'\b(game|workspace|Instance)\b', clean):
            raise ValueError(f"{name}: direct engine access in inner layer")
        graph[name] = []
        for match in matches:
            target = resolve(name, match[1])
            if target not in sources or not allowed(name, target):
                raise ValueError(f"forbidden/unresolved require: {name} -> {target}")
            graph[name].append(target)
    done, active = set(), set()

    def visit(node):
        if node in active:
            raise ValueError(f"require cycle: {node}")
        if node in done:
            return
        active.add(node)
        for target in graph[node]:
            visit(target)
        active.remove(node)
        done.add(node)

    for name in graph:
        visit(name)
    return graph


def stage(sources):
    destination = ROOT / "build/test-source"
    for name, code in sources.items():
        def replace(match):
            target = resolve(name, match[1])
            relative = os.path.relpath(target.removesuffix(".luau"), Path(name).parent).replace("\\", "/")
            if not relative.startswith("."):
                relative = "./" + relative
            return f'require("{relative}")'
        output = destination / name
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(REQUIRE.sub(replace, code), encoding="utf-8")


if __name__ == "__main__":
    sources = {p.relative_to(SRC).as_posix(): p.read_text(encoding="utf-8") for p in SRC.rglob("*.luau")}
    if not sources:
        raise SystemExit("No source modules to check")
    graph = graph_for(sources)
    stage(sources)
    print(f"Architecture OK: {len(graph)} modules, {sum(map(len, graph.values()))} real require edges; test modules staged")

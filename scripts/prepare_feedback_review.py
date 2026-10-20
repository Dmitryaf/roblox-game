"""Prepare a private single-player review place/plugin; never installs or starts Studio.

python scripts/prepare_feedback_review.py [--auto]
Build the printed project and plugin with Rojo, then use the existing token runner.
Decode its own PNG log transport with --decode-log PATH --token feedback-review-HEX.
Capture uses documented PluginSecurity APIs, no uploads, gallery or HTTP.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import struct
import uuid

ROOT = Path(__file__).resolve().parents[1]
TOKEN_PATTERN = re.compile(r"feedback-review-[0-9a-f]{32}\Z")
MAX_BYTES = 786432

SERVER = r'''--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local control = ReplicatedStorage:WaitForChild("FeedbackReviewControl") :: RemoteFunction
local token = ReplicatedStorage:WaitForChild("StudioTestToken") :: StringValue
assert(game:GetService("RunService"):IsStudio() and token.Value == "__TOKEN__")
local bridge = game:GetService("ServerStorage"):WaitForChild("MatchTestBridge", 30) :: BindableFunction
control.OnServerInvoke = function(player: Player, action: string, position: Vector3?, report: any?)
    assert(#Players:GetPlayers() == 1, "Review fixture requires exactly one player")
    if action == "place" then
        assert(typeof(position) == "Vector3" and position.X == 230 and position.Y == 3 and position.Z >= -30 and position.Z <= 40,
            "Review placement outside its training lane")
        return bridge:Invoke("place", player.UserId, position)
    elseif action == "finish" then
        task.defer(function() game:GetService("StudioTestService"):EndTest(report) end)
        return true
    end
    error("Unknown review fixture action")
end
'''

PLUGIN = r'''--!strict
-- This coroutine retains plugin identity. The client requests through local attributes,
-- rather than assuming privileged Bindable callbacks inherit plugin security.
task.defer(function()
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local StudioTestService = game:GetService("StudioTestService")
    local token = ReplicatedStorage:WaitForChild("StudioTestToken", 10)
    if not token or not token:IsA("StringValue") or token.Value ~= "__TOKEN__" then return end
    local HttpService = game:GetService("HttpService")
    if StudioTestService.EditModeActive then
        print("__TOKEN__ START")
        local ok, result = xpcall(function() return StudioTestService:ExecutePlayModeAsync({ review = true }) end, debug.traceback)
        print("__TOKEN__ RESULT " .. tostring(ok) .. " " .. (if type(result) == "table" then HttpService:JSONEncode(result) else tostring(result)))
        return
    end
    local Players = game:GetService("Players")
    local deadline = os.clock() + 30
    while not Players.LocalPlayer and os.clock() < deadline do task.wait(0.05) end
    if not Players.LocalPlayer then return end
    local mailbox = ReplicatedStorage:WaitForChild("FeedbackReviewCapture", 30)
    if not mailbox then return end
    local captureService: any = nil
    local found, service = pcall(function() return game:GetService("StudioCaptureService") end)
    if found then captureService = service end
    local frame, lastId = 0, 0
    local function perform(action: string, label: string): any
        if not captureService then return { ok = false, status = "api_unavailable" } end
        if action == "permission" then
            -- Only an explicit review button invokes this potentially interactive method.
            local permitted = captureService:RequestScreenshotPermissionAsync()
            return { ok = permitted, status = if permitted then "permission_granted" else "permission_denied" }
        end
        local canCapture = captureService:CanCaptureScreenshot()
        if action == "preflight" then return { ok = canCapture, status = if canCapture then "available" else "permission_or_active_viewport_required" } end
        if action ~= "capture" or not canCapture then return { ok = false, status = "capture_unavailable" } end
        if frame >= 24 then return { ok = false, status = "frame_limit_24" } end
        local camera = workspace.CurrentCamera
        if not camera or camera.ViewportSize.X <= 0 or camera.ViewportSize.Y <= 0 then return { ok = false, status = "viewport_absent" } end
        local size = camera.ViewportSize
        local scale = math.min(1, 960 / size.X, 540 / size.Y)
        local capture = captureService:CaptureScreenshot({ Format = Enum.StudioCaptureScreenshotFormat.PNG,
            Position = Vector2.zero, CaptureSize = size, OutputSize = Vector2.new(math.floor(size.X * scale), math.floor(size.Y * scale)),
            ResampleMode = Enum.ResamplerMode.Default, UICaptureMode = Enum.UICaptureMode.All })
        local untilAt = os.clock() + 8
        while capture.BufferStatus ~= Enum.StudioCaptureBufferStatus.Ready and capture.BufferStatus ~= Enum.StudioCaptureBufferStatus.Error
            and os.clock() < untilAt do task.wait(0.02) end
        if capture.BufferStatus ~= Enum.StudioCaptureBufferStatus.Ready then
            return { ok = false, status = tostring(capture.BufferStatus), errors = tostring(capture:GetErrors()) }
        end
        local bytes = buffer.tostring(capture:GetBuffer())
        if #bytes > 786432 then return { ok = false, status = "png_too_large", bytes = #bytes } end
        if bytes:sub(1, 8) ~= "\137PNG\13\10\26\10" then return { ok = false, status = "not_png" } end
        frame += 1
        local total = math.ceil(#bytes / 384)
        local metadata = { frame = frame, label = label:sub(1, 80), bytes = #bytes, chunks = total, at = workspace:GetServerTimeNow(),
            width = capture.Resolution.X, height = capture.Resolution.Y }
        print("__TOKEN__ PNG_META " .. HttpService:JSONEncode(metadata))
        for index = 1, total do
            local raw = bytes:sub((index - 1) * 384 + 1, index * 384)
            local hex = raw:gsub(".", function(char) return string.format("%02x", string.byte(char)) end)
            print("__TOKEN__ PNG_CHUNK " .. frame .. " " .. index .. " " .. hex)
        end
        print("__TOKEN__ PNG_END " .. frame)
        return { ok = true, status = "png_in_local_log", frame = frame, label = label, bytes = #bytes }
    end
    mailbox:SetAttribute("BridgeReady", true)
    while mailbox.Parent do
        local id = mailbox:GetAttribute("RequestId")
        if type(id) == "number" and id > lastId then
            lastId = id
            local ok, result = pcall(perform, mailbox:GetAttribute("Action"), mailbox:GetAttribute("Label") or "frame")
            local response = if ok then result else { ok = false, status = "api_error", error = tostring(result) }
            print("__TOKEN__ CAPTURE_STATUS " .. HttpService:JSONEncode(response))
            mailbox:SetAttribute("Response", HttpService:JSONEncode(response)); mailbox:SetAttribute("DoneId", id)
        end
        task.wait(0.03)
    end
end)
'''


def decode_log(path: Path, token: str) -> list[dict]:
    if not TOKEN_PATTERN.fullmatch(token):
        raise ValueError("Invalid review token")
    frames: dict[int, dict] = {}
    prefix = token + " "
    with path.open(encoding="utf-8", errors="replace") as stream:
        for line in stream:
            if prefix not in line:
                continue
            line = line.split(prefix, 1)[1].strip()
            if line.startswith("PNG_META "):
                meta = json.loads(line[len("PNG_META "):])
                frame = meta["frame"]
                if not isinstance(frame, int) or not 1 <= frame <= 24 or not 0 < meta["bytes"] <= MAX_BYTES:
                    raise ValueError("PNG metadata exceeds bounds")
                if meta["chunks"] != (meta["bytes"] + 383) // 384:
                    raise ValueError("PNG chunk count mismatch")
                if frame in frames:
                    raise ValueError("Duplicate PNG metadata")
                frames[frame] = {"meta": meta, "parts": {}, "ended": False}
            elif line.startswith("PNG_CHUNK "):
                _, raw_frame, raw_index, hex_value = line.split(" ", 3)
                frame, index = int(raw_frame), int(raw_index)
                item = frames[frame]
                if index in item["parts"] or not 1 <= index <= item["meta"]["chunks"] or len(hex_value) > 768:
                    raise ValueError("Invalid/duplicate PNG chunk")
                item["parts"][index] = bytes.fromhex(hex_value)
            elif line.startswith("PNG_END "):
                frames[int(line.split()[1])]["ended"] = True
    destination = (ROOT / "build/captures" / token).resolve()
    destination.relative_to((ROOT / "build").resolve())
    manifest = []
    for frame, item in sorted(frames.items()):
        meta, parts = item["meta"], item["parts"]
        if not item["ended"] or len(parts) != meta["chunks"]:
            raise ValueError(f"Incomplete PNG frame {frame}; no visual PASS can be inferred")
        png = b"".join(parts[i] for i in range(1, meta["chunks"] + 1))
        if len(png) != meta["bytes"] or png[:8] != b"\x89PNG\r\n\x1a\n" or png[12:16] != b"IHDR":
            raise ValueError("Invalid PNG signature/length")
        width, height = struct.unpack(">II", png[16:24])
        if not 0 < width <= 960 or not 0 < height <= 540 or (width, height) != (meta["width"], meta["height"]):
            raise ValueError("PNG dimensions mismatch")
        destination.mkdir(parents=True, exist_ok=True)
        output = destination / f"{frame:02}.png"
        output.write_bytes(png)
        manifest.append({**meta, "path": str(output), "sha256": hashlib.sha256(png).hexdigest()})
    if not manifest:
        raise ValueError("No complete PNG frames; capture may be unavailable")
    (destination / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    return manifest


def prepare(automatic: bool = False) -> dict:
    token = "feedback-review-" + uuid.uuid4().hex
    output = ROOT / "build/feedback-review" / token
    output.mkdir(parents=True)
    project = json.loads((ROOT / "default.project.json").read_text(encoding="utf-8"))
    tree = project["tree"]
    tree["ReplicatedStorage"].update({
        "StudioTestToken": {"$className": "StringValue", "$properties": {"Value": token}},
        "FeedbackReviewControl": {"$className": "RemoteFunction"},
        "FeedbackProbe": {"$path": str(ROOT / "tests/studio/client/FeedbackProbe.luau")},
        "MixedClassDriver": {"$path": str(ROOT / "tests/studio/client/DashDriver.luau")},
        "MixedTestDriver": {"$path": str(ROOT / "tests/studio/client/MixedDriver.luau")},
        "$attributes": {"FeedbackReviewAuto": automatic},
    })
    tree["ServerStorage"] = {"$attributes": {"MatchTest": True}}
    tree["ServerScriptService"]["FeedbackReviewFixture"] = {"$path": str(output / "fixture.server.luau")}
    tree["StarterPlayer"]["StarterPlayerScripts"]["FeedbackReview"] = {"$path": str(ROOT / "tests/studio/feedback_review.client.luau")}

    def absolute_paths(value):
        if isinstance(value, dict):
            for key, item in value.items():
                if key == "$path":
                    value[key] = str((ROOT / item).resolve())
                else:
                    absolute_paths(item)
    absolute_paths(project)
    (output / "review.project.json").write_text(json.dumps(project, indent=2), encoding="utf-8")
    (output / "fixture.server.luau").write_text(SERVER.replace("__TOKEN__", token), encoding="utf-8")
    (output / "capture.plugin.server.luau").write_text(PLUGIN.replace("__TOKEN__", token), encoding="utf-8")
    (output / "plugin.project.json").write_text(json.dumps({"name": "FeedbackReviewCapture", "tree": {"$path": "capture.plugin.server.luau"}}), encoding="utf-8")
    result = {"token": token, "project": str(output / "review.project.json"), "pluginProject": str(output / "plugin.project.json"),
              "automatic": automatic, "capture": "preflight only; permission prompt requires explicit review button", "visualVerdict": "unreviewed"}
    (output / "manifest.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--auto", action="store_true")
    parser.add_argument("--decode-log", type=Path)
    parser.add_argument("--token")
    args = parser.parse_args()
    if args.decode_log and not args.token:
        parser.error("--decode-log requires --token")
    print(json.dumps(decode_log(args.decode_log, args.token) if args.decode_log else prepare(args.auto), indent=2, ensure_ascii=False))

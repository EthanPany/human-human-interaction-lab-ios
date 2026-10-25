#!/usr/bin/env python3
"""Exports the screenshot attachments of an .xcresult as <name>.png files.
Usage: export-screenshots.py Results.xcresult out_dir"""
import json, os, re, shutil, subprocess, sys, tempfile

result, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
if not os.path.exists(result):
    sys.exit(f"{result} missing (tests did not run)")
tmp = tempfile.mkdtemp()
subprocess.check_call(["xcrun", "xcresulttool", "export", "attachments", "--path", result, "--output-path", tmp])
with open(os.path.join(tmp, "manifest.json")) as f:
    manifest = json.load(f)
for test in manifest:
    for a in test.get("attachments", []):
        src = os.path.join(tmp, a["exportedFileName"])
        human = a.get("suggestedHumanReadableName") or a["exportedFileName"]
        # "01-sign-in_0_<UUID>.png" -> "01-sign-in.png"
        name = re.sub(r"_\d+_[0-9A-Fa-f-]{36}", "", os.path.splitext(human)[0])
        # Failure attachments carry names like `"Phone number" TextField`; the
        # artifact upload rejects quotes, colons and the like in file names.
        name = re.sub(r'[\\/:*?"<>|\r\n`]+', "_", name).strip(" _") or "attachment"
        shutil.copy(src, os.path.join(out, name + os.path.splitext(src)[1]))
        print(os.path.join(out, name))

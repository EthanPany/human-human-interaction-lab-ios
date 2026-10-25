#!/usr/bin/env python3
"""Prints IPHONE_ID/IPHONE_NAME/IPAD_ID/IPAD_NAME for the newest iOS runtime's
preferred simulators (CI writes them to $GITHUB_ENV)."""
import json, re, subprocess

data = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))

def version(runtime):
    m = re.search(r"iOS-(\d+)-(\d+)", runtime)
    return (int(m.group(1)), int(m.group(2))) if m else None

ios = sorted(((version(r), devs) for r, devs in data["devices"].items() if version(r)), key=lambda x: x[0], reverse=True)

def pick(preferred, prefix):
    for _, devs in ios:
        names = {d["name"]: d for d in devs}
        for name in preferred:
            if name in names:
                return names[name]
        for d in devs:
            if d["name"].startswith(prefix):
                return d
    raise SystemExit(f"no {prefix} simulator")

iphone = pick(["iPhone 17 Pro", "iPhone 16 Pro", "iPhone 17"], "iPhone")
ipad = pick(["iPad Pro 13-inch (M5)", "iPad Pro 11-inch (M5)", "iPad Pro 13-inch (M4)", "iPad Air 13-inch (M3)"], "iPad")
safe = lambda s: re.sub(r"[^A-Za-z0-9]+", "-", s).strip("-")
print(f"IPHONE_ID={iphone['udid']}\nIPHONE_NAME={safe(iphone['name'])}")
print(f"IPAD_ID={ipad['udid']}\nIPAD_NAME={safe(ipad['name'])}")

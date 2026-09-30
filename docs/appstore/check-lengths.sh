#!/bin/zsh
# Zkontroluje délky polí v metadata-*.md proti limitům App Store Connect (počítá znaky, ne bajty).
cd "$(dirname "$0")"
python3 - <<'PY'
import re, pathlib, sys
limits = {"Name": 30, "Název": 30, "Subtitle": 30, "Podtitul": 30, "Promotional Text": 170, "Propagační text": 170,
          "Description": 4000, "Popis": 4000, "Keywords": 100, "Klíčová slova": 100,
          "What's New in This Version": 4000, "Co je nového": 4000}
bad = 0
for f in sorted(pathlib.Path(".").glob("metadata-*.md")):
    text = f.read_text(encoding="utf-8")
    for m in re.finditer(r"^## (.+?)(?: \(max[^)]*\))?\n\n```\n(.*?)\n```", text, re.S | re.M):
        field, body = m.group(1).strip(), m.group(2)
        lim = limits.get(field)
        if lim is None: continue
        n = len(body)
        ok = n <= lim and not (field.startswith(("Keywords", "Klíčová")) and ", " in body)
        bad += not ok
        print(f"{'OK ' if ok else 'ERR'} {f.name:16} {field:28} {n:5}/{lim}")
sys.exit(1 if bad else 0)
PY

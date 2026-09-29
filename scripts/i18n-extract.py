#!/usr/bin/env python3
# Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
"""Vytáhne klíče L("…") ze Sources a doplní je do jazykových souborů (cs.json: hodnota = klíč, ostatní prázdné).

  scripts/i18n-extract.py            # vypíše chybějící a nepoužívané klíče v Resources/Languages/*.json
  scripts/i18n-extract.py --update   # doplní chybějící klíče (prázdná hodnota) a smaže nepoužívané
"""
import json, pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
KEY = re.compile(r'\bL\("((?:[^"\\]|\\.)*)"')

def unescape(s):
    return s.replace('\\"', '"').replace('\\\\', '\\')

def keys():
    out = set()
    for f in (ROOT / "Sources").rglob("*.swift"):
        for m in KEY.finditer(f.read_text(encoding="utf-8")):
            out.add(unescape(m.group(1)))
    return out

def main():
    update = "--update" in sys.argv
    ks = keys()
    print(f"{len(ks)} klíčů v kódu")
    for p in sorted((ROOT / "Resources/Languages").glob("*.json")):
        d = json.loads(p.read_text(encoding="utf-8"))
        st = d.setdefault("strings", {})
        missing = sorted(k for k in ks if not st.get(k))
        stale = sorted(k for k in st if k not in ks)
        print(f"{p.name}: chybí {len(missing)}, nepoužívané {len(stale)}")
        for k in missing: print("  + " + k)
        for k in stale: print("  - " + k)
        if update:
            for k in missing: st[k] = k if d.get("code") == "cs" else ""   # čeština: text = klíč
            for k in stale: del st[k]
            p.write_text(json.dumps(d, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")

main()

#!/usr/bin/env python3
"""Controllo degli aggiornamenti delle immagini Docker fissate nei compose (sostituisce Watchtower, 14/10/2026).

Watchtower confronta il digest con cui gira il container: con le immagini fissate `repo:tag@sha256:...` non
vede mai niente. Questo script, per ogni riga `image:` dei docker-compose del repo:
  - rebuild: lo stesso tag nel registro ha un digest diverso da quello fissato (correzioni di sistema/sicurezza)
  - patch / minor / major: esiste un tag più recente con lo stesso schema (es. 3.2.1 -> 3.2.2 / 3.3.0 / 4.0.0)
Scrive il risultato in JSON (nessuna notifica: lo legge il DELL, che avvisa e aggiorna, vedi image-updates-watch).

Uso: image_updates_check.py [--out FILE]   (default /mnt/external_drive/utility/logs/image_updates_latest.json)
Richiede skopeo (install.sh). Gli aggiornamenti da non segnalare stanno in image_updates_ignore.txt. Salta le immagini locali (senza registro) e quelle con i prefissi in IMAGE_UPDATES_SKIP_PREFIX, es. le proprie immagini su ghcr.io (le gestiscono
i progetti con le loro build).
"""
import json
import os
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
OUT = Path(sys.argv[sys.argv.index("--out") + 1]) if "--out" in sys.argv else Path("/mnt/external_drive/utility/logs/image_updates_latest.json")
IMAGE_RE = re.compile(r"^\s*image:\s*['\"]?([^'\"\s#]+)['\"]?")
ERA_RE = re.compile(r"\(era ([^)\s]+)\)")  # commento delle immagini fissate il 29/09: "(era repo:tag-mobile)"
TAG_RE = re.compile(r"^(v?)(\d+(?:\.\d+)*)(.*)$")
PRERELEASE = re.compile(r"(alpha|beta|rc|dev|nightly|preview|test)", re.I)
SKIP_PREFIX = tuple(p for p in os.environ.get("IMAGE_UPDATES_SKIP_PREFIX", "").split(",") if p)  # es. ghcr.io/<utente>/
IGNORE_FILE = Path(__file__).resolve().parent / "image_updates_ignore.txt"


def load_ignore():
    """{(cartella, immagine): {tipi}} da image_updates_ignore.txt (aggiornamenti che l utente ha deciso di non fare)."""
    ign = {}
    if IGNORE_FILE.exists():
        for line in IGNORE_FILE.read_text().splitlines():
            parts = line.split("#", 1)[0].split()
            if len(parts) == 3:
                ign.setdefault((parts[0], parts[1]), set()).update(parts[2].split(","))
    return ign


def skopeo(*args, timeout=60):
    r = subprocess.run(["skopeo", *args], capture_output=True, text=True, timeout=timeout, check=False)
    if r.returncode != 0:
        raise RuntimeError((r.stderr or r.stdout).strip().splitlines()[-1][:200] if (r.stderr or r.stdout) else "errore skopeo")
    return r.stdout


def split_ref(ref):
    """repo:tag@sha256:x -> (repo, tag, digest)."""
    digest = None
    if "@" in ref:
        ref, digest = ref.split("@", 1)
    repo, tag = ref, "latest"
    if ":" in ref.rsplit("/", 1)[-1]:
        repo, tag = ref.rsplit(":", 1)
    return repo, tag, digest


def remote_digest(repo, tag):
    raw = skopeo("inspect", "--raw", f"docker://{repo}:{tag}")
    r = subprocess.run(["skopeo", "manifest-digest", "/dev/stdin"], input=raw, capture_output=True, text=True, check=True)
    return r.stdout.strip()


def newer_tags(repo, tag):
    """Tag più recenti con lo stesso schema (prefisso, numero di parti, suffisso). -> {kind: tag più alto}."""
    m = TAG_RE.match(tag)
    if not m:
        return {}
    pre, nums, suf = m.group(1), tuple(int(x) for x in m.group(2).split(".")), m.group(3)
    if PRERELEASE.search(suf):
        return {}
    tags = json.loads(skopeo("list-tags", f"docker://{repo}", timeout=120)).get("Tags", [])
    best = {}
    for t in tags:
        mt = TAG_RE.match(t)
        if not mt or mt.group(1) != pre or mt.group(3) != suf:
            continue
        n = tuple(int(x) for x in mt.group(2).split("."))
        if len(n) != len(nums) or n <= nums:
            continue
        if nums[0] >= 1000 and len(str(n[0])) != len(str(nums[0])):
            continue  # tag a data (es. photoprism 260919): non confrontare con lo schema vecchio 20220121
        kind = "major" if n[0] != nums[0] else "minor" if len(n) > 1 and n[1] != nums[1] else "patch"
        if kind not in best or n > best[kind][0]:
            best[kind] = (n, t)
    return {k: v[1] for k, v in best.items()}


def main():
    items, errors = [], []
    seen = set()
    ignore = load_ignore()
    for compose in sorted(REPO.glob("*/docker-compose*.yml")):
        for line in compose.read_text().splitlines():
            mi = IMAGE_RE.match(line)
            if not mi:
                continue
            ref = mi.group(1)
            if "${" in ref or ref.startswith(SKIP_PREFIX) or ("/" not in ref and ":" not in ref and "@" not in ref):
                continue  # variabili, immagini nostre, immagini locali (scanner-buttons, ups-notify)
            key = (compose.parent.name, ref)
            if key in seen:
                continue
            seen.add(key)
            repo, tag, pinned = split_ref(ref)
            entry = {"service": compose.parent.name, "compose": str(compose.relative_to(REPO)), "image": repo, "tag": tag,
                     "pinned": bool(pinned), "updates": {}}
            try:
                cur = None
                for t in dict.fromkeys([tag, tag[1:] if tag.startswith("v") else "v" + tag]):
                    try:
                        cur, tag_ok = remote_digest(repo, t), t
                        break
                    except RuntimeError:
                        continue
                if cur is not None:
                    if pinned and cur != pinned:
                        entry["updates"]["rebuild"] = {"tag": tag_ok, "digest": cur}
                    for kind, t in newer_tags(repo, tag_ok).items():
                        entry["updates"][kind] = {"tag": t}
                else:
                    # tag non presente nel registro (nome scelto al fissaggio): confronto con il tag mobile di origine
                    era = ERA_RE.search(line)
                    erepo, etag, _ = split_ref(era.group(1)) if era else (repo, "latest", None)
                    cur = remote_digest(erepo, etag)
                    if pinned and cur != pinned:
                        entry["updates"]["reference"] = {"tag": etag, "digest": cur,
                                                         "note": f"il tag {tag} non esiste nel registro; {erepo}:{etag} è cambiato"}
            except Exception as e:  # noqa: BLE001 - un registro che non risponde non deve fermare gli altri
                errors.append(f"{compose.parent.name}: {repo}:{tag}: {e}")
                continue
            for kind in ignore.get((compose.parent.name, repo), ()):
                entry["updates"].pop(kind, None)
            if entry["updates"]:
                items.append(entry)
    result = {"date": datetime.now().strftime("%Y-%m-%d %H:%M"), "checked": len(seen), "updates": items, "errors": errors}
    OUT.parent.mkdir(parents=True, exist_ok=True)
    tmp = OUT.with_suffix(".tmp")
    tmp.write_text(json.dumps(result, indent=1, ensure_ascii=False))
    os.replace(tmp, OUT)
    print(f"{result['date']}: {len(seen)} immagini, {len(items)} con aggiornamenti, {len(errors)} errori")
    for it in items:
        print(f"  {it['service']}: {it['image']}:{it['tag']} -> " + ", ".join(f"{k} {v['tag']}" for k, v in it["updates"].items()))
    for e in errors:
        print("  ERRORE " + e)


if __name__ == "__main__":
    main()

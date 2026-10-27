#!/usr/bin/env python3
"""Applica da solo gli aggiornamenti "sicuri" trovati da image_updates_check.py (dal 14/10/2026, richiesta dell'utente).

Sicuri = stessa versione ricostruita (rebuild) o patch di un'app che non è un database, fuori dai servizi critici.
Le stesse regole stanno in classify() di image-updates-watch sul DELL: se ne cambi una, cambia anche l'altra.
Per ogni aggiornamento sicuro:
  1. se l'immagine è un database (solo rebuild), dump di tutti i database in /mnt/external_drive/image-updates/dumps/DATA/
  2. pull del nuovo tag, digest letto dall'immagine scaricata
  3. riga image: del compose -> repo:TAG@sha256:NUOVO, con commento datato
  4. docker compose up -d e controllo: container in esecuzione (e healthy se ha un healthcheck), nessun riavvio in 45 s
  5. se il controllo fallisce: compose ripristinato, docker compose up -d, esito "failed"
Alla fine un solo commit sul repo con gli aggiornamenti riusciti. Esito in /mnt/external_drive/image-updates/applied_latest.json
(lo legge image-updates-watch sul DELL, che avvisa in caso di errori). Dump più vecchi di 7 giorni cancellati.

Uso (cron utente pi alle 07:30, dopo il controllo): image_updates_apply.py [--dry-run]
     image_updates_apply.py --approve KEY [KEY ...]   applica (con le stesse garanzie) solo gli aggiornamenti approvati
                                                      dall'utente, chiavi come in `image-updates-watch --plan`
"""
import json
import os
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CHECK = Path("/mnt/external_drive/utility/logs/image_updates_latest.json")
WORK = Path("/mnt/external_drive/image-updates")
# servizi del repo che girano su ALTRI host: qui non si applicano mai (docker compose up li avvierebbe sul .30)
REMOTE = {"rpi-backup"}  # RPi4 del backup offsite: aggiornamento a mano dal router (19/10/2026)
CRITICAL = {"nextcloud", "mailserver", "nginx-proxy-manager", "vaultwarden", "pihole"}
DB_IMAGES = ("postgres", "mariadb", "mysql", "redis", "valkey", "mongo", "jc21/mariadb-aria")
DRY = "--dry-run" in sys.argv
# dati piccoli da copiare prima di un aggiornamento approvato (oltre ai database dello stesso compose)
DATA_TAR = {"vaultwarden": "/data"}
APPROVED = set(sys.argv[sys.argv.index("--approve") + 1:]) if "--approve" in sys.argv else set()


def run(cmd, cwd=None, timeout=900, inp=None):
    r = subprocess.run(cmd, shell=True, cwd=cwd, capture_output=True, text=True, timeout=timeout, input=inp, check=False)
    return r.returncode, r.stdout.strip(), r.stderr.strip()


def is_db(image):
    name = image if image.startswith("jc21/") else image.rsplit("/", 1)[-1]
    return any(name.startswith(d) for d in DB_IMAGES)


def safe(service, image, kind):
    return service not in CRITICAL and (kind == "rebuild" or (kind == "patch" and not is_db(image)))


def block_of(lines, idx):
    """container_name e nome del servizio compose del blocco che contiene la riga idx."""
    indent = len(lines[idx]) - len(lines[idx].lstrip())
    svc = cname = None
    for j in range(idx, -1, -1):
        ln = lines[j]
        if ln.strip() and (len(ln) - len(ln.lstrip())) < indent and ln.rstrip().endswith(":"):
            svc = ln.strip()[:-1].strip("'\"")
            start = j
            break
    else:
        return None, None
    for ln in lines[start + 1:]:
        if ln.strip() and (len(ln) - len(ln.lstrip())) <= len(lines[start]) - len(lines[start].lstrip()):
            break
        m = re.match(r"\s*container_name:\s*['\"]?([\w.-]+)", ln)
        if m:
            cname = m.group(1)
    return svc, cname


def dump_db(cname, image, dest):
    dest.mkdir(parents=True, exist_ok=True)
    out = dest / f"{cname}.sql"
    if "postgres" in image:
        cmd = f"docker exec {cname} sh -c 'pg_dumpall -U \"$POSTGRES_USER\"'"
    elif "redis" in image or "valkey" in image:
        return None  # cache/broker: niente dati da salvare
    else:
        cmd = (f"docker exec {cname} sh -c 'mariadb-dump -uroot -p\"${{MARIADB_ROOT_PASSWORD:-$MYSQL_ROOT_PASSWORD}}\" "
               "--all-databases --single-transaction'")
    rc, so, se = run(cmd + f" > {out}")
    if rc != 0 or out.stat().st_size < 1000:
        raise RuntimeError(f"dump di {cname} fallito: {se[:200]}")
    out.chmod(0o600)
    return out


def pre_backup(svc_dir, lines, dest):
    """Aggiornamento approvato di un'app (dal 21/10/2026, tasto "Aggiorna immagini" del bot): prima dump dei database
    dello stesso compose (una migrazione dello schema non torna indietro col rollback dell'immagine) e copia dei dati
    piccoli (DATA_TAR). -> elenco dei file creati."""
    made = []
    for i, ln in enumerate(lines):
        m = re.match(r"\s*image:\s*['\"]?([^\s'\"@:]+(?::\d+/[^\s'\"@:]+)?)", ln)
        if m and is_db(m.group(1)):
            _, cname = block_of(lines, i)
            if cname:
                d = dump_db(cname, m.group(1), dest)
                if d:
                    made.append(str(d))
    if svc_dir in DATA_TAR:
        dest.mkdir(parents=True, exist_ok=True)
        out = dest / f"{svc_dir}-data.tgz"
        rc, _, se = run(f"docker exec {svc_dir} tar czf - -C {DATA_TAR[svc_dir]} . > {out}")
        if rc != 0 or out.stat().st_size < 1000:
            raise RuntimeError(f"copia dei dati di {svc_dir} fallita: {se[:200]}")
        out.chmod(0o600)
        made.append(str(out))
    return made


def healthy(cname, wait=180):
    t0 = time.time()
    while time.time() - t0 < wait:
        fmt = "{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}} {{.RestartCount}}"
        rc, so, _ = run(f"docker inspect {cname} --format '{fmt}'")
        if rc == 0:
            st, hs, rcount = so.split()
            if st == "running" and hs in ("healthy", "none"):
                time.sleep(45)
                rc2, so2, _ = run(f"docker inspect {cname} --format '{{{{.State.Status}}}} {{{{.RestartCount}}}}'")
                return rc2 == 0 and so2.split() == ["running", rcount]
            if st in ("exited", "dead") or hs == "unhealthy":
                return False
        time.sleep(5)
    return False


def main():
    data = json.loads(CHECK.read_text())
    today = datetime.now()
    results, applied_msgs = [], []
    dumps = WORK / "dumps" / today.strftime("%Y-%m-%d")
    for it in data.get("updates", []):
        svc_dir, image, cur_tag = it["service"], it["image"], it["tag"]
        if svc_dir in REMOTE:
            continue
        def key(k, v, svc_dir=svc_dir, image=image):
            return f"{svc_dir}|{image}|{k}|{v.get('digest') or v['tag']}"
        if APPROVED:
            ups = {k: v for k, v in it["updates"].items() if key(k, v) in APPROVED}
        else:
            ups = {k: v for k, v in it["updates"].items() if safe(svc_dir, image, k)}
        if not ups:
            continue
        kind = next(k for k in ("major", "minor", "patch", "rebuild", "reference") if k in ups)
        target = ups[kind]["tag"]
        keys = [key(k, v) for k, v in ups.items()]
        res = {"keys": keys, "service": svc_dir, "image": image, "from": cur_tag, "to": target, "kind": kind,
               "at": today.strftime("%Y-%m-%d %H:%M")}
        compose = REPO / it["compose"]
        original = compose.read_text()
        lines = original.splitlines()
        idx = next((i for i, ln in enumerate(lines) if re.match(rf"\s*image:\s*['\"]?{re.escape(image)}:{re.escape(cur_tag)}(@sha256:|['\"]?(\s|$))", ln)), None)
        if idx is None:
            results.append({**res, "result": "failed", "note": "riga image: non trovata nel compose"})
            continue
        svc, cname = block_of(lines, idx)
        if not cname:
            results.append({**res, "result": "failed", "note": "container_name non trovato"})
            continue
        if DRY:
            results.append({**res, "result": "dry-run", "note": f"container {cname}" + (" + dump" if is_db(image) else "")})
            continue
        try:
            if is_db(image):
                d = dump_db(cname, image, dumps)
                res["dump"] = str(d) if d else None
            elif APPROVED:
                res["backup"] = pre_backup(svc_dir, lines, dumps)
            rc, _, se = run(f"docker pull -q {image}:{target}")
            if rc != 0:
                raise RuntimeError(f"pull fallito: {se[:200]}")
            # digest del tag nel registro (l'immagine locale può avere più RepoDigests, anche quello vecchio)
            rc, raw, se = run(f"skopeo inspect --raw docker://{image}:{target}")
            rc2, dig, _ = run("skopeo manifest-digest /dev/stdin", inp=raw) if rc == 0 else (1, "", "")
            if rc2 != 0 or not dig.startswith("sha256:"):
                raise RuntimeError(f"digest del registro non leggibile: {se[:150]}")
            rc, so, _ = run(f"docker image inspect {image}:{target} --format '{{{{json .RepoDigests}}}}'")
            if dig not in [d.split("@", 1)[1] for d in json.loads(so or "[]")]:
                raise RuntimeError("l'immagine scaricata non corrisponde al digest del registro")
            if kind in ("rebuild", "reference") and ups[kind].get("digest") and ups[kind]["digest"] != dig:
                raise RuntimeError("il digest del registro è cambiato dopo il controllo: riprovo domani")
            old = lines[idx]
            ind = old[: len(old) - len(old.lstrip())]
            m = re.search(r"@sha256:([0-9a-f]{12})", old)
            prev = f"{cur_tag}@{m.group(1)}…" if m else f"{cur_tag}, senza digest"
            lines[idx] = f"{ind}image: {image}:{target}@{dig}  # aggiornata in automatico il {today:%d/%m/%Y} (era {prev})"
            compose.write_text("\n".join(lines) + "\n")
            rc, _, se = run("docker compose up -d", cwd=compose.parent)
            _, running, _ = run(f"docker inspect {cname} --format '{{{{.Config.Image}}}}'")
            if rc == 0 and not running.endswith(dig):
                rc, se = 1, f"il container gira ancora con {running[-20:]}"
            if rc != 0 or not healthy(cname):
                compose.write_text(original)
                run("docker compose up -d", cwd=compose.parent)
                raise RuntimeError("servizio non sano dopo l'aggiornamento: ripristinata la versione precedente" + (f" ({se[:150]})" if rc else ""))
            res.update(result="applied", note=f"{cur_tag} -> {target}", digest=dig)
            applied_msgs.append(f"{svc_dir}: {image} {cur_tag} -> {target}" + (" (ricostruita)" if kind == "rebuild" else ""))
        except Exception as e:  # noqa: BLE001 - un aggiornamento fallito non deve fermare gli altri
            if compose.read_text() != original:
                compose.write_text(original)
                run("docker compose up -d", cwd=compose.parent)
            res.update(result="failed", note=str(e)[:300])
        results.append(res)
    if applied_msgs and not DRY:
        msg = ("aggiornamenti delle immagini approvati dall'utente" if APPROVED else "aggiornamenti automatici delle immagini (rebuild/patch)")
        msg += "\n\n" + "\n".join(applied_msgs)
        msg += "\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
        run("git add -A " + " ".join(sorted({str(REPO / r["service"]) for r in results if r["result"] == "applied"})), cwd=REPO)
        rc, _, se = run("git commit -q -F -", cwd=REPO, inp=msg)
        if rc == 0:
            rc, _, se = run("git push -q", cwd=REPO, timeout=120)
        if rc != 0:
            results.append({"keys": [], "service": "git", "result": "failed", "note": f"commit/push: {se[:200]}",
                            "at": today.strftime("%Y-%m-%d %H:%M")})
    WORK.mkdir(parents=True, exist_ok=True)
    out = {"date": today.strftime("%Y-%m-%d %H:%M"), "check_date": data.get("date"), "dry_run": DRY, "results": results}
    tmp = WORK / "applied_latest.tmp"
    tmp.write_text(json.dumps(out, indent=1, ensure_ascii=False))
    name = "applied_dryrun.json" if DRY else f"approved_{today:%Y%m%d_%H%M%S}.json" if APPROVED else "applied_latest.json"
    os.replace(tmp, WORK / name)
    for old in (WORK / "dumps").glob("20*") if (WORK / "dumps").exists() else []:
        if (today - datetime.strptime(old.name, "%Y-%m-%d")).days > 7:
            shutil.rmtree(old, ignore_errors=True)
    for r in results:
        print(f"{r['result']:8} {r['service']}: {r.get('image', '')} {r.get('from', '')} -> {r.get('to', '')} {r.get('note', '')}")


if __name__ == "__main__":
    main()

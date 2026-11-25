#!/usr/bin/env python3
"""Sincronizza Nextcloud → Documents con Paperless (lanciato ogni notte da daily_backup.sh).

- file nuovo → copiato nella cartella consume di Paperless (la prima cartella diventa un tag: "Documenti_Banche" → "Banche");
- file modificato → il documento vecchio va nel cestino di Paperless, la versione nuova entra al suo posto;
- file cancellato in Nextcloud → il suo documento va nel cestino di Paperless (recuperabile per 30 giorni).
I file restano in Nextcloud. Paperless non viene mai toccato per documenti che non arrivano da qui (es. posta elettronica).
Collegamento file ↔ documento tramite SHA-256 (checksum di Paperless). Stato in /mnt/external_drive/paperless/sync_state.json.
Sicurezze: se la cartella sorgente manca o risultano cancellati troppi file in una volta, non cancella nulla ed esce con errore.
Esclusi: note Joplin, .md/.sql e formati che Paperless non legge. Token API: PAPERLESS_TOKEN (scripts/.env).
Uso: paperless_sync.py          sincronizza
     paperless_sync.py --seed   collega i file già importati ai documenti, senza copiare né cancellare
"""
import hashlib, http.client, json, os, shutil, sys, time, urllib.error, urllib.request

USER = os.environ["NEXTCLOUD_USER"]
TOKEN = os.environ.get("PAPERLESS_TOKEN", "")
API = os.environ.get("PAPERLESS_API", "http://localhost:8010/api")
SRC = f"/mnt/external_drive/nextcloud/nextcloud_data/data/{USER}/files/Documents"
BASE = "/mnt/external_drive/paperless"
STATE, CONSUME, STAGING = f"{BASE}/sync_state.json", f"{BASE}/consume", f"{BASE}/staging_sync"
EXT = {".pdf", ".jpg", ".jpeg", ".png", ".tif", ".tiff", ".webp", ".txt", ".doc", ".docx", ".xls", ".xlsx",
       ".odt", ".ods", ".rtf", ".eml"}
SKIP_DIRS = ("Documenti_Joplin",)
UID = GID = 1000            # USERMAP_UID/GID di Paperless
MAX_DELETE = 20             # oltre questo numero di cancellazioni in una notte: nessuna cancellazione, errore
SEED = "--seed" in sys.argv

def api(path, method="GET", tries=6):
    # Più tentativi solo sugli errori di connessione: di notte l'aggiornamento di Docker (apt nel backup) può riavviare
    # Paperless poco prima di questo script, che altrimenti trova la connessione chiusa (17/11/2026).
    r = urllib.request.Request(API + path, method=method, headers={"Authorization": "Token " + TOKEN, "Accept": "application/json"})
    for n in range(tries):
        try:
            with urllib.request.urlopen(r, timeout=60) as resp:
                body = resp.read()
            return json.loads(body) if body else None
        except urllib.error.HTTPError:
            raise
        except (urllib.error.URLError, http.client.HTTPException, ConnectionError, TimeoutError):
            if n == tries - 1:
                raise
            time.sleep(30)

def doc_by_sha(sha):
    r = api(f"/documents/?checksum__iexact={sha}&fields=id")["results"]
    return r[0]["id"] if r else None

def sha256(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""): h.update(b)
    return h.hexdigest()

def tag_dir(top):
    return top[len("Documenti_"):] if top.startswith("Documenti_") else top

def trash(entry, rel, state, why):
    doc = entry.get("doc")
    if not doc: return
    if any(e.get("doc") == doc for k, e in state.items() if k != rel):
        print(f"  (documento {doc} usato anche da un altro file: lo tengo)"); return
    try:
        api(f"/documents/{doc}/", "DELETE"); print(f"🗑  {why}: {rel} (documento {doc} nel cestino di Paperless)")
    except urllib.error.HTTPError as e:
        if e.code != 404: raise

if not TOKEN: sys.exit("PAPERLESS_TOKEN mancante in scripts/.env")
state = json.load(open(STATE)) if os.path.exists(STATE) else {}
state = {k: (v if isinstance(v, dict) else {"sig": v}) for k, v in state.items()}   # vecchio formato [dim, mtime]
if not os.path.isdir(SRC) or (state and not any(os.scandir(SRC))):
    sys.exit(f"ERRORE: {SRC} non trovata o vuota: niente sincronizzazione")

cur = {}
for root, dirs, files in os.walk(SRC):
    rel_root = os.path.relpath(root, SRC)
    if rel_root.split(os.sep)[0].startswith(SKIP_DIRS): dirs[:] = []; continue
    dirs[:] = [d for d in dirs if not d.startswith(".")]
    for fn in files:
        if fn.startswith(".") or os.path.splitext(fn)[1].lower() not in EXT: continue
        p = os.path.join(root, fn)
        try: st = os.stat(p)
        except OSError: continue
        cur[os.path.relpath(p, SRC)] = [st.st_size, int(st.st_mtime)]

sent = replaced = linked = deleted = 0; errors = []
for rel, sig in sorted(cur.items()):
    old = state.get(rel)
    if old and old.get("sig") == sig and old.get("sha"):
        if not old.get("doc"):                        # consumato dopo l'ultima notte: collego il documento
            old["doc"] = doc_by_sha(old["sha"]); linked += bool(old["doc"])
        continue
    p = os.path.join(SRC, rel); sha = sha256(p)
    if old and old.get("sha") == sha:                 # solo la data è cambiata
        old["sig"] = sig; old["doc"] = old.get("doc") or doc_by_sha(sha); continue
    if old and old.get("sha") and not SEED:
        trash(old, rel, state, "modificato"); replaced += 1
    doc = doc_by_sha(sha)
    if doc is None and not SEED:
        parts = rel.split(os.sep)
        dest_rel = os.path.join(tag_dir(parts[0]), *parts[1:]) if len(parts) > 1 else os.path.join("Documents", parts[0])
        tmp, dst = os.path.join(STAGING, dest_rel), os.path.join(CONSUME, dest_rel)
        os.makedirs(os.path.dirname(tmp), exist_ok=True); shutil.copy2(p, tmp)
        os.makedirs(os.path.dirname(dst), exist_ok=True); os.replace(tmp, dst)
        for d in (os.path.dirname(dst), dst):
            try: os.chown(d, UID, GID)
            except OSError: pass
        print("→", dest_rel); sent += 1
    state[rel] = {"sig": sig, "sha": sha, "doc": doc}
    linked += bool(doc and SEED)

gone = [rel for rel in state if rel not in cur]
if gone and not SEED:
    if len(gone) > MAX_DELETE:
        errors.append(f"{len(gone)} file risultano cancellati da Nextcloud (limite {MAX_DELETE}): NON cancello nulla in Paperless, controlla a mano")
    else:
        for rel in gone:
            trash(state[rel], rel, state, "cancellato in Nextcloud"); del state[rel]; deleted += 1

tmp = STATE + ".tmp"; json.dump(state, open(tmp, "w")); os.replace(tmp, STATE)
shutil.rmtree(STAGING, ignore_errors=True)
print(f"Paperless: {sent} nuovi, {replaced} sostituiti, {deleted} cancellati, {linked} collegati · file seguiti {len(state)}")
for e in errors: print("ERRORE", e)
sys.exit(1 if errors else 0)

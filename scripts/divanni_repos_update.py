#!/usr/bin/env python3
"""Refreshes the website's Portfolio data every night (stars, forks, watchers, descriptions, languages, topics).

Same logic as tools/update_portfolio.py in the public repo aledv/divanni.me, using the public GitHub API with
no token (60 requests/hour per IP; it needs 1 + one per repository). Writes repos.json to OUT_DIR, mounted in
the website container as /usr/share/nginx/html/data (see website/docker-compose.yml), so the site updates
without a new image. Atomic write, only when the data changes; if GitHub does not answer the file is left as
it is and the script exits with 1 (the cron line sends a notification).
"""

import json
import os
import sys
import tempfile
import urllib.request
from pathlib import Path

USER = "aledv"
EXCLUDE = set()  # repo da non mostrare (tenere allineato con tools/update_portfolio.py)
OUT_DIR = Path(os.environ.get("DIVANNI_DATA_DIR", "/mnt/external_drive/website-data"))
URL = f"https://api.github.com/users/{USER}/repos?per_page=100&type=owner"


def _get(url: str):
    req = urllib.request.Request(url, headers={"Accept": "application/vnd.github+json", "User-Agent": "divanni-portfolio"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.load(resp)


def fetch() -> list:
    return _get(URL)


def watchers(full_name: str) -> int:
    # i "watch" veri (subscribers_count) ci sono solo nel dettaglio del repo: una richiesta in piu per repo
    return _get(f"https://api.github.com/repos/{full_name}")["subscribers_count"]


def build(repos: list) -> list:
    items = [
        {
            "name": r["name"],
            "description": r["description"] or "",
            "language": r["language"] or "",
            "topics": r.get("topics", []),
            "stars": r["stargazers_count"],
            "forks": r["forks_count"],
            "watchers": watchers(r["full_name"]),
            "url": r["html_url"],
        }
        for r in repos
        if not r["fork"] and not r["archived"] and not r["private"] and r["name"] not in EXCLUDE
    ]
    items.sort(key=lambda r: (-r["stars"], r["name"].lower()))
    return items


def main() -> int:
    try:
        items = build(fetch())
    except Exception as e:
        print(f"GitHub non raggiungibile o risposta inattesa: {type(e).__name__}: {e}", file=sys.stderr)
        return 1
    if not items:
        print("Nessun repo nella risposta: file lasciato com era", file=sys.stderr)
        return 1
    text = json.dumps(items, indent=2, ensure_ascii=False) + "\n"
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out = OUT_DIR / "repos.json"
    if out.exists() and out.read_text(encoding="utf-8") == text:
        print(f"{len(items)} repo, nessuna modifica")
        return 0
    fd, tmp = tempfile.mkstemp(dir=OUT_DIR, prefix=".repos-", suffix=".json")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(text)
    os.chmod(tmp, 0o644)
    os.replace(tmp, out)  # la cartella e montata, non il file: il rename si vede subito nel container
    print(f"{len(items)} repo, repos.json aggiornato: " + ", ".join(f"{i['name']} {i['stars']}" for i in items))
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/bin/bash
# Aggiorna l'app sull'iPod all'ULTIMA VERSIONE PUBBLICATA su GitHub, senza compilare nulla.
# Uso:  app/scripts/aggiorna.sh                 (iPod collegato con il cavo)
#       IPOD_HOST=<ip> app/scripts/aggiorna.sh   (iPod in Wi-Fi)
#       app/scripts/aggiorna.sh utente/repo      (le versioni di un altro repository, per esempio una copia del progetto)
# Di serie usa il repository da cui hai scaricato questa cartella (git remote "origin"), altrimenti quello originale.
# Serve una volta sola, per la prima installazione o se l'app è più vecchia della 0.4.0: da lì in poi l'app
# si aggiorna anche dal telefono (console › Scenario › Aggiornamento dell'app).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
die() { echo "ERRORE: $*" >&2; exit 1; }
REPO="${1:-$(git -C "$ROOT" remote get-url origin 2>/dev/null | sed -E 's#(\.git)?$##; s#^.*github\.com[:/]##' || true)}"
[ -n "$REPO" ] || REPO="Franz8787/similfranz-saturimetro"
echo "== ultima versione pubblicata su $REPO"
JSON="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest")" || die "nessuna versione pubblicata su github.com/$REPO (o internet assente)"
read -r TAG URL < <(python3 -c 'import json,sys; r=json.load(sys.stdin); d=[a["browser_download_url"] for a in r.get("assets",[]) if a["name"].endswith(".deb")]; print(r["tag_name"], d[0] if d else "")' <<<"$JSON")
[ -n "$URL" ] || die "la versione $TAG non contiene un pacchetto .deb"
mkdir -p "$ROOT/dist"; DEB="$ROOT/dist/$(basename "$URL")"
echo "== scarico $TAG"
curl -fsSL "$URL" -o "$DEB" || die "download non riuscito"
touch "$DEB"                                    # install.sh prende il .deb più recente in dist/
"$ROOT/scripts/install.sh"
"$ROOT/scripts/ipod-ssh.sh" 'uiopen simulafranz-saturimetro://' >/dev/null 2>&1 || true
echo "OK: iPod aggiornato a $TAG"

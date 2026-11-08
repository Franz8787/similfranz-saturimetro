#!/bin/bash
# Installa dist/*.deb sull'iPod touch CON JAILBREAK via USB (iproxy + SSH) oppure via Wi-Fi con IPOD_HOST=<ip>.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEB="$(ls -t "$ROOT"/dist/it.simulafranz.saturimetro_*_iphoneos-arm.deb 2>/dev/null | head -1)"
die() { echo "ERRORE: $*" >&2; exit 1; }
[ -f "$DEB" ] || die "nessun .deb in dist/: eseguire scripts/build.sh && scripts/package.sh"
if [ -z "${IPOD_HOST:-}" ]; then command -v iproxy >/dev/null || die "iproxy assente (brew install libimobiledevice)"; idevice_id -l | grep -q . || die "iPod non rilevato via USB (oppure usa IPOD_HOST=<ip> per il Wi-Fi)"; fi
echo "== copia $(basename "$DEB")"
"$ROOT/scripts/ipod-scp.sh" "$DEB" ipod:/tmp/saturimetro.deb
echo "== installazione"
"$ROOT/scripts/ipod-ssh.sh" 'killall SimulaFranz_Saturimetro 2>/dev/null; dpkg -i /tmp/saturimetro.deb && rm -f /tmp/saturimetro.deb && dpkg -s it.simulafranz.saturimetro | grep -E "^(Status|Version)"'
echo "OK: SimulaFranz_Saturimetro installato (avvio: scripts/ipod-ssh.sh 'uiopen simulafranz-saturimetro://')"

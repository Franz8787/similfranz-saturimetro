#!/bin/bash
# Copia file da/verso l'iPod via USB. Uso: scripts/ipod-scp.sh <src> <dst>   (un lato può essere ipod:/percorso)
if [ -n "${IPOD_HOST:-}" ]; then PORT=22; HOST="$IPOD_HOST"; else PORT=2222; HOST=127.0.0.1; pgrep -f "iproxy $PORT" >/dev/null || { iproxy $PORT 22 >/dev/null 2>&1 & sleep 1; }; fi
export A="${1/ipod:/root@$HOST:}" B="${2/ipod:/root@$HOST:}" PORT
expect -c '
set timeout 180
spawn scp -O -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o HostKeyAlgorithms=+ssh-rsa,ssh-dss -o PubkeyAcceptedAlgorithms=+ssh-rsa -P $env(PORT) $env(A) $env(B)
expect {
  -re {[Pp]assword:} { send "alpine\r"; exp_continue }
  eof
}
' >/dev/null

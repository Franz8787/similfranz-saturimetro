#!/bin/bash
# Esegue un comando sull'iPod come root via USB (iproxy 2222 -> 22). Password root: predefinita (scelta dell'utente).
# Uso: scripts/ipod-ssh.sh 'comando'     Variabile TMO = timeout in secondi (default 60)
# Con IPOD_HOST=<ip> va via Wi-Fi (porta 22) invece che via USB.
if [ -n "${IPOD_HOST:-}" ]; then PORT=22; HOST="$IPOD_HOST"; else PORT=2222; HOST=127.0.0.1; pgrep -f "iproxy $PORT" >/dev/null || { iproxy $PORT 22 >/dev/null 2>&1 & sleep 1; }; fi
export CMD="$1" PORT HOST
exec expect -c '
set timeout [expr {[info exists env(TMO)] ? $env(TMO) : 60}]
log_user 1
spawn ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o HostKeyAlgorithms=+ssh-rsa,ssh-dss -o PubkeyAcceptedAlgorithms=+ssh-rsa -p $env(PORT) root@$env(HOST) $env(CMD)
expect {
  -re {[Pp]assword:} { send "alpine\r"; exp_continue }
  eof
}
' | sed -e '1,2d' -e 's/\r$//'

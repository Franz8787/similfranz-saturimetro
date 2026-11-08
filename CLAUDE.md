# Istruzioni per Claude Code

Questo progetto è un saturimetro **simulato** per la formazione sanitaria che gira su un iPod touch 4
(iOS 6.1.x) con jailbreak. Rispondi all'utente in italiano, con passi semplici: spesso non è uno sviluppatore.

## Se l'utente chiede di installare l'app

1. Verifica gli strumenti sul Mac: `iproxy` e `idevice_id` (`brew install libimobiledevice`), `expect`.
2. Verifica che l'iPod sia collegato via USB: `idevice_id -l`. Se non c'è, chiedi di collegarlo e sbloccarlo.
3. Serve un `.deb` in `app/dist/`: se manca, chiedi di scaricarlo dalla pagina Releases
   (o compila con `app/scripts/build.sh` + `package.sh` se l'utente ha l'SDK, vedi `docs/sviluppo.md`).
4. Esegui `app/scripts/install.sh` (via Wi-Fi: `IPOD_HOST=<ip>`). La password di root è quella
   predefinita del jailbreak, già negli script (`app/scripts/ipod-ssh.sh`); se l'utente l'ha cambiata, chiediglielo.
5. Se SSH non risponde: probabilmente manca OpenSSH, va installato da Cydia sull'iPod (passaggio manuale).

## Regole

- Il jailbreak e i passaggi fisici (modalità DFU, tocchi sullo schermo, Wi-Fi) li fa l'utente:
  guidalo con [docs/01-jailbreak.md](docs/01-jailbreak.md), non scaricare né ridistribuire file di Apple.
- Non presentare mai il progetto come dispositivo medico.
- Test di logica sul Mac: `app/scripts/test-mac.sh` (devono passare tutti prima di modificare e reinstallare).

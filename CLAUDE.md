# Istruzioni per Claude Code

Questo progetto è un saturimetro **simulato** per la formazione sanitaria che gira su un iPod touch 4
(iOS 6.1.x) con jailbreak. Rispondi all'utente in italiano, con passi semplici: spesso non è uno sviluppatore.

## Se l'utente chiede di installare l'app

1. Verifica gli strumenti sul Mac: `iproxy` e `idevice_id` (`brew install libimobiledevice`), `expect`.
2. Verifica che l'iPod sia collegato via USB: `idevice_id -l`. Se non c'è, chiedi di collegarlo e sbloccarlo.
3. Esegui `app/scripts/aggiorna.sh`: scarica da GitHub l'ultima versione pubblicata e la installa
   (via Wi-Fi: `IPOD_HOST=<ip>`). Per un `.deb` compilato in locale: `app/scripts/install.sh`.
   La password di root è quella predefinita del jailbreak, già negli script (`app/scripts/ipod-ssh.sh`); se l'utente l'ha cambiata, chiediglielo.
4. Dalla 0.4.0 gli aggiornamenti si fanno dal telefono (console › Scenario › Aggiornamento dell'app).
5. Se SSH non risponde: probabilmente manca OpenSSH, va installato da Cydia sull'iPod (passaggio manuale).

## Regole

- Il jailbreak e i passaggi fisici (modalità DFU, tocchi sullo schermo, Wi-Fi) li fa l'utente:
  guidalo con [docs/01-jailbreak.md](docs/01-jailbreak.md), non scaricare né ridistribuire file di Apple.
- Non presentare mai il progetto come dispositivo medico.
- Test di logica sul Mac: `app/scripts/test-mac.sh` (devono passare tutti prima di modificare e reinstallare).

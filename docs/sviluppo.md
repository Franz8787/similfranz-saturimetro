# Per sviluppatori

Ti piace capire come funzionano le cose? Qui trovi come fare la tua versione (anche senza Mac), come compilare,
come provare sul Mac e come pilotare l'app via API.

## Fai la tua versione (senza Mac)

GitHub può compilare l'app al posto tuo, su un suo Mac in cloud: è gratis per i progetti pubblici.

1. **Copia il progetto**: in alto su GitHub, **Fork**.
2. **Attiva i due servizi** nella tua copia:
   - scheda **Actions** › *I understand my workflows, go ahead and enable them*;
   - **Settings › Pages** › *Deploy from a branch* › `main`, cartella `/docs`.
3. **Fai le tue modifiche**: anche dal browser, con il tasto ✎ su ogni file (o in locale, con git).
4. **Alza il numero di versione** in `app/control` (riga `Version:`), per esempio da `0.4.0` a `0.4.1`.
5. **Pubblica una Release**: **Releases › Draft a new release**, tag `v0.4.1` (uguale alla versione, con la `v`), *Publish*.

Il resto è automatico (workflow `.github/workflows/pubblica.yml`, circa 5 minuti): GitHub prepara l'SDK, esegue i
test, compila, allega il `.deb` alla Release e ne mette una copia sulle Pages. I saturimetri installati dalla tua
copia vedono la nuova versione nella console e si aggiornano dal telefono: l'app sa da quale repository viene
(lo scrive `build.sh` nel pacchetto), quindi segue le **tue** versioni, non quelle originali.

Per provare senza pubblicare nulla: **Actions › Pubblica una versione › Run workflow**. Il `.deb` compilato
resta scaricabile tra gli *artifacts* dell'esecuzione.

La prima installazione su ogni iPod passa da un computer: `app/scripts/aggiorna.sh tuo-utente/tuo-repository`
(vedi [Installa l'app](02-installazione.md)).

## Compilare sul tuo computer

L'app è Objective-C per **iOS 6 (armv7)** e si compila sul Mac con i soli Command Line Tools:

```bash
xcode-select --install          # Command Line Tools
brew install ldid               # firma per dispositivi con jailbreak
cd app
./scripts/setup-sdk.sh          # una volta: scarica e prepara l'SDK in app/sdk/ (da theos/sdks)
export SIMLAB_SDK=$PWD/sdk/theos-sdks/iPhoneOS9.3.sdk
./scripts/build.sh              # compila in build/ (app + aiutante di installazione)
./scripts/package.sh            # crea dist/it.simulafranz.saturimetro_<ver>_iphoneos-arm.deb
./scripts/install.sh            # installa sull'iPod (USB, oppure IPOD_HOST=<ip>)
```

**SDK**: serve l'**iPhoneOS 9.3 SDK**, il più recente che compila ancora per armv7/iOS 6. Non è nel repository
(è materiale Apple): `setup-sdk.sh` lo scarica dalla raccolta pubblica [theos/sdks](https://github.com/theos/sdks)
a un commit fissato e completa i file `.tbd` che il linker moderno pretende (gli header restano quelli 9.3).

Note:
- target `armv7-apple-ios6.0` con `-Werror=unguarded-availability`: qualsiasi API più recente di iOS 6 è un errore
- ARC sì in compilazione, **non** al link (Xcode moderno non ha più `libarclite`; su iOS 6 i simboli ARC ci sono già)
- **aggiornamento dal telefono**: la console invia il `.deb` a `POST /api/v1/update` (protetto dal PIN); l'app
  controlla che sia il pacchetto del saturimetro e lo passa a `/usr/libexec/similfranz-sat-aggiorna`
  (`app/helper/aggiorna.c`, setuid root, installato dal pacchetto), che accetta solo quel file da un percorso fisso,
  lo installa con `dpkg` e riapre l'app.

## Test sul Mac

```bash
cd app
./scripts/test-mac.sh           # 87 test di logica: stato, allarmi, menu, stato locale, server
```

Lo script crea anche `build/mac/mac-oxi-server`: il server dell'iPod che gira sul Mac, per provare
la console web nel browser senza iPod:

```bash
./build/mac/mac-oxi-server 18082 123456 www     # poi apri http://localhost:18082 (PIN 123456)
```

## Comandi utili sull'iPod

```bash
./scripts/ipod-ssh.sh 'uiopen simulafranz-saturimetro://'             # avvia l'app
./scripts/ipod-ssh.sh 'uiopen simulafranz-saturimetro://selftest'     # autotest con screenshot
```

Log: `/var/mobile/Library/Caches/SimulaFranz_Saturimetro.log`.

## API

HTTP/JSON sulla porta della web app (predefinita 8080), autenticazione con l'header
`X-SimulaFranz-Token: <PIN>`. Dopo 5 PIN sbagliati il server si blocca per 30 s.

| Rotta | Metodo | Cosa |
|---|---|---|
| `/api/v1/health` | GET | stato del server (senza PIN) |
| `/api/v1/state` | GET | stato completo del paziente e del saturimetro |
| `/api/v1/command` | POST | `{"command": "...", ...}` |
| `/api/v1/update` | GET | versione installata, repository degli aggiornamenti, aiutante presente |
| `/api/v1/update` | POST | pacchetto `.deb` del saturimetro (corpo binario, fino a 4 MB): risposta 202 e reinstallazione |

Comandi principali: `set_spo2`, `set_pulse_rate`, `set_pulse_present`, `set_cpr_active`,
`set_spo2_signal_valid`, `set_spo2_low_perfusion`, `set_rhythm` (`sinus` / `afib`),
`set_patient_motion` (`off` / `light` / `strong`), `set_simulation_running`,
`set_sensor` (`{"sensor":"oxi","connected":true}`), `set_oximeter` (`power`, `volume`, `mute_s`, `alarm_limits`),
`reset_scenario`. I valori numerici accettano una transizione graduale (`duration_s`).

Esempio:

```bash
curl -H 'X-SimulaFranz-Token: 123456' -d '{"command":"set_spo2","value":88,"duration_s":30}' \
     http://<ip-ipod>:8080/api/v1/command
```

<!-- TODO: verificare nomi e parametri esatti di ogni comando contro src/OxiLocalState.m prima della pubblicazione -->

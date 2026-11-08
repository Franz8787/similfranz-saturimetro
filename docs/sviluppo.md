# Per sviluppatori

Ti piace capire come funzionano le cose? Qui trovi tutto per compilare l'app, provarla sul Mac e pilotarla via API.

## Compilare senza Xcode

L'app è Objective-C per **iOS 6 (armv7)** e si compila sul Mac con i soli Command Line Tools:

```bash
xcode-select --install          # Command Line Tools
brew install ldid               # firma per dispositivi con jailbreak
cd app
./scripts/build.sh              # compila in build/
./scripts/package.sh            # crea dist/it.simulafranz.saturimetro_<ver>_iphoneos-arm.deb
./scripts/install.sh            # installa sull'iPod (USB, oppure IPOD_HOST=<ip>)
```

**SDK**: serve un **iPhoneOS 9.3 SDK** (il più recente che compila ancora per armv7/iOS 6).
Non è incluso perché è materiale Apple: procuratelo da una delle raccolte pubbliche di SDK per Theos
e mettilo in `app/sdk/iPhoneOS9.3.sdk`, oppure indica il percorso con `SIMLAB_SDK=/percorso/iPhoneOS9.3.sdk`.
<!-- TODO: indicare la fonte precisa e le patch eventualmente necessarie -->

Note:
- target `armv7-apple-ios6.0` con `-Werror=unguarded-availability`: qualsiasi API più recente di iOS 6 è un errore
- ARC sì in compilazione, **non** al link (Xcode moderno non ha più `libarclite`; su iOS 6 i simboli ARC ci sono già)

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

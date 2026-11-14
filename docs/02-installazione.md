# 2. Installa l'app

La prima volta serve un computer, per pochi minuti. Dopo, l'app si aggiorna **dal telefono**.

## Prepara il computer (una volta sola)

- **Mac**: con [Homebrew](https://brew.sh) installato, nel Terminale: `brew install libimobiledevice`
- **Linux**: `sudo apt install libimobiledevice-utils expect` (o l'equivalente della tua distribuzione)

Poi scarica questa cartella del progetto: pulsante verde **Code › Download ZIP** su GitHub, oppure `git clone`.

## Installa

Collega l'iPod via USB e sbloccalo. Nel Terminale, dalla cartella del progetto:

```bash
cd app
./scripts/aggiorna.sh
```

Lo script scarica da GitHub **l'ultima versione pubblicata** e la installa: non devi cercare né spostare file.
Quando ha finito, sull'iPod trovi l'icona **similFranzSat**.

**Preferisci il Wi-Fi?** Con l'iPod sulla tua rete e il suo indirizzo IP a portata di mano:
`IPOD_HOST=192.168.x.y ./scripts/aggiorna.sh`

## Aggiornamenti: dal telefono, con un tocco

Dalla versione 0.4.0 il computer non serve più. Apri la console sul telefono, scheda **Scenario ›
Aggiornamento dell'app**: se è uscita una versione nuova la console te lo dice e la installa con un tocco.

Funziona così: l'iPod è troppo vecchio per scaricare da GitHub, il telefono no. La console (che è una pagina
nel browser del telefono) scarica il pacchetto e lo passa all'iPod attraverso il Wi-Fi che già li collega.
L'iPod controlla che sia davvero il saturimetro, si reinstalla e si riapre da solo in pochi secondi.
Il telefono deve avere internet (dati o hotspot): è la stessa rete che usi per la regia.

Se il download automatico non riesce, la console ti dà il link per scaricare il pacchetto `.deb` sul telefono
e un pulsante per sceglierlo: anche così, tutto dal telefono.

## Primo avvio

- L'app parte **spenta**, proprio come uno strumento vero: tieni premuto ⏻ sullo schermo per un secondo e si accende.
- Nel menu **≡ › Informazioni** trovi l'indirizzo della console e il **PIN**: ti serviranno tra poco.
- In **Impostazioni › SIMFranz_Satur** puoi cambiare porta e PIN della console.

Avanti, si passa alla stampante: [3. Stampa e monta il guscio](03-stampa-montaggio.md)

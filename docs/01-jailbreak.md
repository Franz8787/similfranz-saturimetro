# 1. Sblocca l'iPod

Il primo passo è anche quello che fai una volta sola. Dopo, l'iPod è pronto ad accogliere il saturimetro
e resta sbloccato anche quando lo spegni e lo riaccendi.

> Il jailbreak lo fai sul **tuo** dispositivo, sotto la tua responsabilità. Su un iPod del 2010
> la garanzia è scaduta da tempo. Qui usi solo strumenti pubblici e gratuiti.

## Prepara

- l'iPod touch di 4ª generazione: controlla in Impostazioni › Generali › Info che sia il modello **A1367**
  con **iOS 6.1.6** (con una versione precedente, Legacy iOS Kit ti propone la strada adatta)
- un Mac o un PC Linux e il cavo USB a 30 pin
- mezz'ora di tempo: la prima volta è un'avventura, la seconda una formalità

## Procedi

1. **Metti al sicuro quello che ti interessa.** Il jailbreak lascia i dati al loro posto: un backup ti fa lavorare tranquillo.
2. **Scarica [Legacy iOS Kit](https://github.com/LukeZGD/Legacy-iOS-Kit)** e avvialo seguendo le sue istruzioni per il tuo sistema.
3. **Collega l'iPod e scegli il jailbreak.** Per l'iPod touch 4 con iOS 6.1.6 il kit usa il metodo
   *ramdisk* e un jailbreak *untethered*, quello che resta attivo dopo il riavvio. Quando il kit te lo chiede,
   porta l'iPod in **modalità DFU** seguendo le indicazioni a schermo.
4. **Apri Cydia.** Al riavvio la trovi sulla schermata Home: aprila una volta e lasciale completare la preparazione.
5. **Installa OpenSSH da Cydia.** È la porta da cui il Mac installerà l'app.

<!-- TODO: aggiungere screenshot dei passi e i tempi reali -->

## Un consiglio in più

L'accesso amministratore dell'iPod usa la password standard del jailbreak, `alpine`, ed è quella che usano
gli script di installazione. Quando l'iPod vive su reti condivise, cambiala con `passwd` via SSH e aggiornala negli script.

Fatto? Sei pronto per il passo più veloce: [2. Installa l'app](02-installazione.md)

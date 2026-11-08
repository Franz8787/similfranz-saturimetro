# 2. Installa l'app

Un comando dal Mac e l'icona del saturimetro compare sull'iPod.

## Prepara il Mac (una volta sola)

Con [Homebrew](https://brew.sh) installato, apri il Terminale e scrivi:

```bash
brew install libimobiledevice
```

## Installa

1. Scarica dalla pagina **Releases** di questo progetto il file `it.simulafranz.saturimetro_<versione>_iphoneos-arm.deb`
   e mettilo nella cartella `app/dist/`.
2. Collega l'iPod via USB e sbloccalo.
3. Nel Terminale, dalla cartella del progetto:

   ```bash
   cd app
   ./scripts/install.sh
   ```

Quando lo script ha finito, sull'iPod trovi l'icona **similFranzSat**.

**Preferisci il Wi-Fi?** Con l'iPod sulla tua rete e il suo indirizzo IP a portata di mano:

```bash
cd app
IPOD_HOST=192.168.x.y ./scripts/install.sh
```

<!-- TODO: installazione direttamente da Cydia (sorgente su GitHub Pages), da verificare con il Cydia di iOS 6 -->

## Primo avvio

- L'app parte **spenta**, proprio come uno strumento vero: tieni premuto ⏻ sullo schermo per un secondo e si accende.
- Nel menu **≡ › Informazioni** trovi l'indirizzo della console e il **PIN**: ti serviranno tra poco.
- In **Impostazioni › SIMFranz_Satur** puoi cambiare porta e PIN della console.

Avanti, si passa alla stampante: [3. Stampa e monta il guscio](03-stampa-montaggio.md)

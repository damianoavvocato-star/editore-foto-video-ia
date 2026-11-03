# Stato avanzamento — 1 novembre 2026

## Ultimo blocco implementato
- Timeline: aggiunta di `addClip` con ordinamento temporale e protezione da ID duplicati.
- Timeline: aggiunta di `deleteClip` con opzione ripple per chiudere lo spazio lasciato dalla clip eliminata.
- Timeline: operazioni rispettano il blocco della traccia.
- Progetti: `ProjectStore` conserva una copia `.bak` dell'ultima versione precedente dopo un salvataggio riuscito.
- Progetti: `load` tenta il recupero automatico da `.bak` quando il file principale è corrotto e ripristina il JSON recuperato.
- Test Flutter aggiunti per inserimento, duplicati, eliminazione ripple e recupero backup.

## Verifiche eseguite in questo ambiente
- `pytest -q` nel backend: 16 test superati.
- `python -m compileall backend`: superato.
- FFmpeg disponibile.
- Flutter e Dart non disponibili: i nuovi test Dart non sono stati eseguiti e non si può dichiarare compilazione Flutter riuscita.
- Android SDK non disponibile: APK non compilato né installato.

## Limiti ancora aperti
- Provider AI reale non configurato; endpoint AI non esegue inferenza.
- Le nuove operazioni Dart sono funzioni di dominio e test scritti, non ancora verificate su Flutter runtime.
- Non è dimostrata la completa integrazione UI Flutter ↔ backend.

## Blocco 8 — recupero robusto dei progetti (1 novembre 2026)
- `ProjectStore.load` ora tenta il backup anche quando il file principale manca (FileSystemException), non soltanto quando il JSON è malformato.
- Ripristino scritto prima in `.restore` e poi rinominato nel file principale.
- `ProjectStore.delete` rimuove anche i file `.bak`, `.tmp` e `.restore` associati.
- Test Flutter aggiornati: il backup viene creato attraverso due salvataggi reali; aggiunti casi per file principale mancante e pulizia dei sidecar.
- Corretto un duplicato del metodo `setTrackMuted` che impediva la compilazione del file Dart.
- Backend verificato nuovamente: 16 test superati.
- Flutter/Dart non sono presenti nell'ambiente: test Flutter e analisi statica non eseguiti; non si dichiara build Flutter verificata.

## Blocco 9 — predisposizione test Flutter su runner (1 novembre 2026)
- Aggiunto workflow GitHub Actions `.github/workflows/flutter-ci.yml`: provisiona Flutter stable, risolve dipendenze, esegue `flutter analyze` e `flutter test` su runner Ubuntu.
- Aggiunta guida `FLUTTER_TESTING.md` con prerequisiti e comandi locali.
- Questo ambiente non ha Flutter/Dart e non risolve host di download esterni; i test Dart restano **non eseguiti qui**. Il workflow è predisposto ma il risultato remoto resta da ottenere dopo push/avvio su GitHub.

## Versione 19 — validazione importazione media
- Aggiunta validazione centralizzata dei metadati degli asset importati: ID, percorso, tipo, durata, dimensione e coerenza MIME.
- L'inserimento sequenziale rifiuta batch con ID duplicati prima di creare clip.
- Aggiunti test Flutter per dimensione/MIME non validi e ID duplicati.
- La validazione riguarda i metadati dichiarati: l'esistenza e la decodifica effettiva del file richiedono ancora integrazione con il file system/plugin multimediale.

## Versione 20 — compatibilità schema progetti
- Il caricamento riconosce i progetti legacy senza `schemaVersion` come versione 1.
- Le versioni future o malformate dello schema vengono rifiutate esplicitamente, evitando aperture parziali o riscritture con perdita di dati.
- Aggiunti test per schema futuro e compatibilità legacy.
- Verifica backend: `python -m pytest -q backend` — 18 test superati.
- I test Flutter richiedono un ambiente con Flutter SDK e non sono stati eseguiti qui.

## Version 23
- Hardened clip playback-speed editing: finite values are clamped to 0.25x–4x; NaN/infinite inputs fall back to 1x.
- Added tests for lower/upper bounds, non-finite input, and locked tracks.
- Backend test suite: 18 passed in the current environment. Flutter tests still require a Flutter SDK.

### Versione 33
- Gestita l'eccezione sincrona all'avvio del renderer nell'ExportCoordinator.
- Aggiunto test di regressione per verificare che il coordinatore non rimanga bloccato dopo un errore iniziale.
- Il test Flutter è stato aggiunto ma richiede un runner Flutter per essere eseguito.
\n\n## Versione 34 – esito esportazione e archivio\n- Il coordinatore segnala un errore se il backend chiude lo stream senza un evento terminale (completato, fallito o annullato).\n- Aggiunto un test Flutter per la chiusura silenziosa del backend.\n- Versione applicazione: 0.1.0+8.\n
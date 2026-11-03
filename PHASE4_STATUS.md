# Fase 4 — stato

## Verificato
- Backend FFmpeg per rendering di clip e transizioni.
- Tracce audio e mixaggio di base.
- Overlay immagine/video e overlay testo.
- Esportazione nei contenitori MP4, MOV, AVI e WebM nei test backend.
- Upload file con allow-list, limiti dimensione e rifiuto file vuoti.
- API stato job, download output completato e cancellazione cooperativa.
- Suite backend: 16/16 test superati nell'ultima esecuzione.

## Non completato
- Nessun provider AI reale configurato; l'endpoint AI non esegue inferenza.
- Integrazione end-to-end completa tra interfaccia Flutter e backend non verificata.
- Test Flutter non eseguibili in questo ambiente perché Flutter/Dart non sono installati.

La fase 4 resta aperta.

## Revisione 33 – gestione avvio esportazione
- Corretto un caso in cui il backend di rendering poteva lanciare un'eccezione sincrona prima di restituire lo stream: ora il coordinatore emette un evento `failed`, chiude lo stream e libera lo slot di esportazione.
- Aggiunto un test Flutter che verifica sia l'errore di avvio sia la possibilità di riprovare.
- Verifiche locali: backend Python 21/21; YAML workflow valido; Flutter/Dart non installati nell'ambiente, quindi `flutter analyze`, `flutter test` e build APK non eseguiti.

## Version 36 – additional export validation

- Export validation now rejects projects with more than 64 tracks or 500 clips.
- Project frame rate must be between 1 and 120 FPS.
- Track identifiers must be non-empty and unique.
- Added Flutter tests for invalid project FPS, duplicate track IDs, and the track-count limit.
- Backend suite: 21 tests passed in the development environment.
- GitHub Actions YAML parsed successfully; Android build remains gated on Flutter and backend jobs.
- Flutter/Dart analysis and Flutter tests were not run locally because the Flutter/Dart SDK is unavailable.

## Revisione 38 – validazione esportazione
- Limite massimo di risoluzione progetto fissato a 7680×4320 per evitare richieste di rendering fuori scala.
- Gli ID delle tracce e delle clip con spazi esterni vengono rifiutati invece di essere accettati come identificativi ambigui.
- Aggiunti due test Flutter per questi casi.
- Test backend Python: 21 superati nell'ambiente disponibile.
- Flutter analyze/test e build APK: non eseguiti in questo ambiente (SDK Flutter assente); restano demandati a GitHub Actions.

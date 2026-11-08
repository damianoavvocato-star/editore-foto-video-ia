# Flutter, Dart e compilazione Android

Il progetto usa Flutter (che include il Dart SDK). Nell'ambiente di preparazione dell'archivio non sono installati `flutter` e `dart` e non è disponibile un Android SDK: qui non è quindi possibile dichiarare superati i test Flutter né produrre un APK verificato.

## Verifica automatica su GitHub Actions

Il workflow `.github/workflows/flutter-ci.yml` ora esegue tre job:

1. `flutter-test`: installa Flutter stable, esegue `flutter pub get`, `flutter analyze` e `flutter test --reporter expanded`.
2. `backend-test`: installa Python 3.12 e lancia `python -m pytest -q backend`.
3. `android-apk`: installa Java 17 e Flutter stable, genera lo scaffold Android con `flutter create --platforms=android`, ripete analisi e test, compila `flutter build apk --release` e pubblica l'APK come artefatto GitHub Actions.

Il job Android crea lo scaffold sul runner perché il repository sorgente non contiene ancora la cartella `android/`. L'APK è scaricabile dalla sezione **Actions → esecuzione del workflow → Artifacts** solo dopo il completamento verde del job `android-apk`.

## Come avviare la verifica

1. Estrai il contenuto dello ZIP in una cartella.
2. Carica il contenuto della cartella (non lo ZIP) in un repository GitHub.
3. Verifica che `.github/workflows/flutter-ci.yml` sia presente e che GitHub Actions sia abilitato.
4. Esegui push su `main`/`master` oppure apri **Actions → Flutter checks → Run workflow**.
5. Controlla tutti e tre i job. Se un job fallisce, apri il log e correggi il primo errore prima di distribuire l'APK.
6. Se `android-apk` termina correttamente, scarica l'artefatto `editore-foto-video-ia-android-apk`.

## Verifica locale

Con Flutter stable, Java 17 e Android SDK configurati:

```bash
flutter create --platforms=android --org com.editorefoto --project-name editore_foto_video_ia .
flutter pub get
flutter analyze
flutter test --reporter expanded
flutter build apk --release
```

Flutter include Dart: non serve installare Dart separatamente. Per distribuire su iOS serve inoltre macOS con Xcode e una verifica distinta; questo workflow produce solo l'APK Android.

**Importante:** aggiungere la pipeline non equivale a testare il codice. Finché il job remoto non è stato eseguito con esito positivo, test Flutter e APK restano da verificare.

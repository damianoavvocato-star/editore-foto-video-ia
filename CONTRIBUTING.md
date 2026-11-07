# Contribuire e controllare il progetto

## Ambiente principale: GitHub

Il repository GitHub è la fonte ufficiale del codice. Il lavoro ordinario si svolge sul branch
`feature/magiciaedit-cloud-foundation`; non si lavora direttamente su `main`.

- Le modifiche vengono registrate in commit sul branch di lavoro.
- La Pull Request #1 verso `main` resta in bozza e non viene unita senza autorizzazione esplicita.
- Ogni modifica deve essere verificata con GitHub Actions.
- Flutter/Dart e Python non devono essere installati sul telefono per il flusso ordinario.
- Termux è facoltativo e non è richiesto per la procedura standard.
- Segreti, credenziali, token, keystore e dati personali non devono essere inseriti nel repository.

## Controlli automatici

GitHub Actions esegue:
1. `flutter pub get`, `flutter analyze` e `flutter test`;
2. installazione dipendenze e `python -m pytest -q backend`;
3. preflight Android/Gradle senza generare APK.

La build APK è separata, manuale e riservata alla fase 6. Il superamento del preflight
non significa che un APK sia stato generato.

Per controlli locali facoltativi, quando l'ambiente è disponibile:

```bash
flutter pub get
flutter analyze
flutter test
python -m pip install -r backend/requirements.txt pytest
python -m pytest -q backend
```

## Regole di sicurezza del flusso

- Non committare direttamente su `main`.
- Non unire la PR senza autorizzazione esplicita.
- Non generare l'APK prima della fase 6.
- Prima di ogni gruppo di modifiche verificare branch e commit di partenza.
- Dopo ogni gruppo controllare il commit pubblicato e l'esito reale delle Actions.
- Se i controlli falliscono, correggere sullo stesso branch e ripetere la verifica.

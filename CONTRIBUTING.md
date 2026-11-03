# Contribuire e controllare il progetto

Prima di proporre modifiche, esegui localmente quando hai Flutter/Dart installati:

```bash
flutter pub get
flutter analyze
flutter test
python -m pip install -r backend/requirements.txt pytest
python -m pytest -q backend
```

La pipeline GitHub Actions esegue gli stessi controlli e, dopo il loro successo, tenta la build Android release. Non inserire segreti o dati personali nei commit.

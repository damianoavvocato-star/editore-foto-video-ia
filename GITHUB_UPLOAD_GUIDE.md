# Caricare Editore foto e Video IA su GitHub

## 1. Crea il repository
1. Accedi a https://github.com e fai login.
2. Premi **+** > **New repository**.
3. Nome consigliato: `editore-foto-video-ia`.
4. Scegli **Private** (consigliato mentre il progetto è in sviluppo).
5. Non aggiungere README, .gitignore o licenza dal sito: sono già nel progetto.
6. Premi **Create repository**.

## 2. Carica il codice dal sito GitHub
1. Apri il repository appena creato.
2. Seleziona **Add file** > **Upload files**.
3. Estrai sul computer l'archivio del progetto e apri la cartella che contiene direttamente `pubspec.yaml`, `lib/`, `test/`, `backend/` e `.github/`.
4. Seleziona e trascina/carica tutti questi elementi e i file Markdown, incluso `.gitignore` e la cartella `.github`.
   - Attenzione: i file e cartelle che iniziano con `.` possono essere nascosti dal sistema operativo. Assicurati che `.gitignore` e `.github/workflows/flutter-ci.yml` siano inclusi.
   - Se l'interfaccia web non consente di caricare `.github` o troppi file, usa GitHub Desktop oppure Git da computer.
5. Nel campo del messaggio commit scrivi `Caricamento iniziale progetto` e premi **Commit changes**.

## 3. Avvia i controlli
1. Nel repository apri la scheda **Actions**.
2. Apri il workflow **Flutter checks**.
3. Dopo il commit, dovrebbe avviarsi automaticamente. In alternativa scegli **Run workflow**.
4. Attendi i job `flutter-test` e `backend-test`; `android-apk` parte solo se entrambi passano.
5. Se la build APK termina, apri l'esecuzione, sezione **Artifacts**, e scarica `editore-foto-video-ia-android-apk`.

## 4. Se qualcosa fallisce
Apri il job rosso, espandi lo step con la X rossa e copia qui il messaggio d'errore completo (evita di condividere token, password o segreti). Non modificare a caso i file: l'errore di Actions indica quale correzione serve.

## Sicurezza
- Non caricare password, token GitHub, chiavi API, certificati o keystore.
- Mantieni il repository privato durante lo sviluppo se non vuoi pubblicare il codice.
- Il workflow genera lo scaffold Android in CI. Non è ancora una verifica che le funzionalità dell'editor siano tutte complete o pronte per la distribuzione.

# Flusso operativo di sviluppo su GitHub

## Fonte ufficiale
Il repository `damianoavvocato-star/editore-foto-video-ia` è la fonte ufficiale del codice.
Il branch di lavoro corrente è `feature/magiciaedit-cloud-foundation`.

## Ciclo di ogni gruppo
1. Leggere lo stato del branch e verificare il commit HEAD.
2. Esaminare i file e le dipendenze interessati.
3. Preparare modifiche circoscritte, senza includere file locali o segreti.
4. Pubblicare i commit esclusivamente sul branch di lavoro.
5. Attendere GitHub Actions e controllare i job, non solo l'avvio della run.
6. Correggere eventuali errori e ripetere i controlli.
7. Aggiornare questo piano/documentazione quando cambia lo stato reale.

## Ruoli degli strumenti
- GitHub repository: codice, versionamento, branch e Pull Request.
- GitHub Actions: test backend, analisi e test Flutter, preflight Android.
- ChatGPT: analisi, implementazione assistita, revisione e diagnosi CI.
- Termux: non richiesto nel ciclo ordinario; non sincronizzare il dispositivo senza richiesta.

## Protezioni obbligatorie
- `main` non è un branch di sviluppo e non deve ricevere commit diretti.
- PR #1 rimane draft/non unita fino ad autorizzazione esplicita.
- APK disabilitato fino alla fase 6; il preflight non produce un APK.
- Mai inserire token, password, chiavi API, certificati o keystore nei file versionati.
- Non dichiarare completata una funzione finché implementazione, test e collegamento richiesto non sono verificati.

## Limite di automazione
Actions può eseguire codice e test in autonomia, ma non è un agente AI che progetta e modifica
continuamente il progetto. Le modifiche al codice richiedono un agente/strumento di sviluppo
autorizzato o l'intervento assistito di ChatGPT. Non è configurato un agente AI persistente
gratuito e illimitato.

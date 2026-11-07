# Fondazione autenticazione individuale

## Stato

Questa è una base tecnica per gli account individuali, non un sistema multiutente pronto per la produzione. Le API media ora richiedono sessioni individuali e verificano la proprietà di asset, job e output; restano da completare integrazione client, gestione progetti e hardening operativo. Non attivare la registrazione pubblica in produzione finché non sono completati i controlli e la revisione di sicurezza.

## Implementazione presente

- Archivio SQLite dedicato agli account, configurabile con `MEDIA_AUTH_DB`.
- Password memorizzate con hash scrypt e salt casuale; la password originale non viene restituita né recuperata.
- Sessioni bearer opache e casuali: nel database viene memorizzato solo SHA-256 del token.
- Scadenza sessione dopo 30 giorni e revoca lato server al logout.
- Ruoli ammessi: `owner`, `admin`, `support`, `collaborator`, `user`. Le operazioni di creazione, elenco, cambio ruolo, sospensione e riattivazione sono disponibili solo al proprietario; i permessi granulari per singola azione non sono ancora implementati.
- Bootstrap del primo proprietario tramite variabili d'ambiente, senza promuovere account esistenti.
- Limite di 10 tentativi errati in 15 minuti per IP e nome utente; risposte di login generiche.
- Registro audit account SQLite: eventi minimi con attore, azione, obiettivo, timestamp e dettagli limitati; i campi che sembrano contenere password, token, secret, authorization o API key vengono rifiutati.
- Registrazione disattivata per impostazione predefinita.

## Configurazione

- `MEDIA_AUTH_DB`: percorso del database account; default `./media_data/accounts.sqlite3`.
- `MEDIA_ALLOW_REGISTRATION=true`: abilita la registrazione; lasciarla disattivata finché il flusso utente completo non è pronto.
- `MEDIA_OWNER_USERNAME` e `MEDIA_OWNER_PASSWORD`: credenziali iniziali del proprietario. Configurare la password tramite secret manager o ambiente protetto, mai nel repository. La password deve avere almeno 12 caratteri.

## API disponibili

- `POST /v1/auth/register`: crea un account utente se la registrazione è abilitata.
- `POST /v1/auth/login`: verifica credenziali e rilascia token sessione.
- `GET /v1/auth/me`: restituisce l'identità associata al token sessione.
- `DELETE /v1/auth/logout`: revoca la sessione corrente.\n- `GET /v1/owner/audit?limit=50`: consultazione paginata degli eventi audit, esclusivamente per l'account con ruolo `owner`.
- `GET /v1/owner/accounts?limit=100`: elenco dei soli campi pubblici degli account, owner-only.
- `POST /v1/owner/accounts`: creazione owner-only di account `admin`, `support`, `collaborator` o `user`; non consente di creare un secondo proprietario.
- `POST /v1/owner/accounts/{user_id}/reset-password`: genera una password temporanea casuale, la mostra una sola volta nella risposta, revoca le sessioni precedenti e impone il cambio password.
- `POST /v1/auth/change-password`: consente il cambio password autenticato; con credenziale temporanea non richiede la password precedente, mentre per i cambi ordinari la richiede. Le sessioni precedenti vengono revocate e viene restituita una nuova sessione.
- Gli account creati dal proprietario e quelli sottoposti a reset ricevono `mustChangePassword=true`; il middleware blocca le API media e owner con HTTP 428 finché la password non viene cambiata.
- `POST /v1/owner/accounts/{user_id}/role`: modifica del ruolo owner-only (`admin`, `support`, `collaborator`, `user`); non può modificare il proprietario e revoca tutte le sessioni esistenti per applicare i nuovi privilegi al login successivo.
- `POST /v1/owner/accounts/{user_id}/disable` e `/enable`: sospensione/riattivazione owner-only; la sospensione revoca immediatamente tutte le sessioni dell'account.

Le operazioni di creazione, reset password, cambio ruolo, sospensione e riattivazione registrano eventi nel registro audit. La password temporanea iniziale fornita in fase di creazione non viene salvata in chiaro; è memorizzata solo come hash scrypt. L'account deve cambiarla al primo accesso. Il reset genera una credenziale temporanea ad alta entropia, restituita una sola volta, revoca le sessioni precedenti e impone la rotazione. Le sessioni sono revocate anche dopo il cambio password.

Le API account validano il token individuale. Tutte le API media (`/v1/assets`, `/v1/render/jobs`, `/v1/ai/jobs`, `/v1/jobs/{id}` e `/v1/outputs/{id}`) richiedono una sessione account e associano/verificano le risorse lato server. Il vecchio `MEDIA_API_TOKEN` condiviso non è accettato come identità utente: un token condiviso non può garantire isolamento. `MEDIA_ALLOW_INSECURE_LOCAL=true` consente ancora un bypass esclusivamente per connessioni loopback locali; deve restare disattivato in produzione.

## Lavoro bloccante prima dell'uso multiutente

1. Estendere ownership a progetti persistenti, file temporanei, eventuali endpoint asset read/delete e ogni nuova risorsa media.
2. Migrare o isolare i dati preesistenti senza esporli a utenti diversi; le risorse storiche prive di proprietario non devono essere rese visibili automaticamente.
3. Integrare il registro audit nelle future operazioni amministrative; aggiungere reset password verificato, 2FA proprietario, inviti collaboratori e RBAC granulare. Le API `GET /v1/owner/audit` e le operazioni base di creazione/elenco/sospensione account sono esposte solo al ruolo `owner`; non sono ancora collegate a una UI Flutter. Restano da implementare permessi granulari per singola azione, recupero autonomo dell'account e protezione MFA/2FA del proprietario.
4. Aggiungere protezione CSRF se si introducono cookie di sessione, gestione sicura dei token sui client e revoca globale delle sessioni.
5. Eseguire test IDOR, escalation privilegi, session fixation/replay, rate limiting multi-processo, migrazione DB, backup e restore.
6. Integrare il client Flutter con login/logout e gestione scadenza sessione, solo dopo aver definito il contratto API definitivo.
7. Verificare concorrenza e persistenza dei job in un deployment multi-processo: lo stato job attualmente in memoria non è ancora un archivio distribuito.

## Verifiche

I test automatici coprono hashing, login, sessione, revoca, disabilitazione account, bootstrap proprietario e isolamento API tra due account (upload, rendering, stato job, cancellazione e download). Un esito CI positivo è necessario ma non sufficiente per l'attivazione in produzione.

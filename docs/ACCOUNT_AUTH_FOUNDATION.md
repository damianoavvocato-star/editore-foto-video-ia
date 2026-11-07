# Fondazione autenticazione individuale

## Stato

Questa è la prima base tecnica per gli account individuali. Non equivale ancora a un sistema multiutente pronto per la produzione: le API media esistenti continuano a usare il token server condiviso e gli asset, job e output non sono ancora isolati per account. Non attivare la registrazione pubblica in produzione e non distribuire questa autenticazione come login completo dell'app prima della migrazione ownership end-to-end.

## Implementazione presente

- Archivio SQLite dedicato agli account, configurabile con `MEDIA_AUTH_DB`.
- Password memorizzate con hash scrypt e salt casuale; la password originale non viene restituita né recuperata.
- Sessioni bearer opache e casuali: nel database viene memorizzato solo SHA-256 del token.
- Scadenza sessione dopo 30 giorni e revoca lato server al logout.
- Ruoli iniziali ammessi: `owner`, `admin`, `support`, `collaborator`, `user`; le API di gestione privilegi non sono ancora implementate.
- Bootstrap del primo proprietario tramite variabili d'ambiente, senza promuovere account esistenti.
- Limite di 10 tentativi errati in 15 minuti per IP e nome utente; risposte di login generiche.
- Registrazione disattivata per impostazione predefinita.

## Configurazione

- `MEDIA_AUTH_DB`: percorso del database account; default `./media_data/accounts.sqlite3`.
- `MEDIA_ALLOW_REGISTRATION=true`: abilita la registrazione; lasciarla disattivata finché il flusso utente completo non è pronto.
- `MEDIA_OWNER_USERNAME` e `MEDIA_OWNER_PASSWORD`: credenziali iniziali del proprietario. Configurare la password tramite secret manager o ambiente protetto, mai nel repository. La password deve avere almeno 12 caratteri.

## API disponibili

- `POST /v1/auth/register`: crea un account utente se la registrazione è abilitata.
- `POST /v1/auth/login`: verifica credenziali e rilascia token sessione.
- `GET /v1/auth/me`: restituisce l'identità associata al token sessione.
- `DELETE /v1/auth/logout`: revoca la sessione corrente.

Le API account validano il proprio token individuale. Le API media non lo accettano ancora: continuano a richiedere `MEDIA_API_TOKEN` oppure il bypass locale esplicitamente abilitato. Questa separazione è intenzionale per non dichiarare completata una migrazione non ancora effettuata.

## Lavoro bloccante prima dell'uso multiutente

1. Richiedere sessione individuale per ogni endpoint media e amministrativo.
2. Associare asset, progetti, job, output e file temporanei a un proprietario server-side.
3. Applicare controlli ownership ad ogni lettura, modifica, cancellazione, rendering e download; mai fidarsi di user ID dal client.
4. Migrare o isolare i dati esistenti senza esporli a utenti diversi.
5. Aggiungere reset password verificato, 2FA proprietario, inviti collaboratori, RBAC granulare e audit log.
6. Aggiungere protezione CSRF se si introducono cookie di sessione, gestione sicura dei token sui client e revoca globale delle sessioni.
7. Eseguire test IDOR, escalation privilegi, session fixation/replay, rate limiting multi-processo, migrazione DB, backup e restore.
8. Integrare il client Flutter con login/logout e gestione scadenza sessione, solo dopo aver definito il contratto API definitivo.

## Verifiche

I test automatici coprono hashing, login, sessione, revoca, disabilitazione account, bootstrap proprietario, registrazione opt-in e limitazione tentativi. Un esito CI positivo è necessario ma non sufficiente per l'attivazione in produzione.

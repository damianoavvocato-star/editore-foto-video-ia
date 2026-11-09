# Registro maestro delle funzionalità — MagicIAedit

> Registro operativo del branch `feature/magiciaedit-cloud-foundation`. Aggiornato dopo l'audit statico dell'8 novembre 2026. Gli stati descrivono evidenze nel repository, non certificazioni su dispositivi o servizi esterni.
>
> **Regole di completamento:** una voce passa a `done` solo quando implementazione, test automatici, gestione errori, sicurezza/ownership, documentazione e verifica CI sono dimostrati. `partial` non significa disponibile per gli utenti. APK e release sono esclusi fino alla fase 6.

> **Mappa delle decisioni e dell'intero prodotto:** [docs/MASTER_PROJECT_MAP.md](MASTER_PROJECT_MAP.md). Consultarla prima di pianificare nuovi blocchi: raccoglie requisiti, decisioni non modificabili, ruoli, funzioni, sequenza in 6 fasi e regole operative.

## Legenda

- `done`: implementazione e test verificati nel perimetro dichiarato.
- `partial`: base presente, flusso incompleto o verifica mancante.
- `missing`: non trovato nel codice esaminato.
- `blocked`: richiede credenziali/provider, decisione esterna o test su dispositivi reali.
- Priorità: **P0** sicurezza e pannelli operativi; **P1** account, Premium ed editor; **P2** pipeline IA, lingue e media avanzati; **P3** team, marketing e piattaforme.
- Owner = Proprietario; Admin = Amministratore; Support = Assistenza; Collab = Collaboratore; User = utente.

## P0 — Sicurezza e console operative

| ID | Funzionalità | Ruoli | Frontend | Backend | Test/accettazione | Stato |
|---|---|---|---|---|---|---|
| P0-01 | Registro completo e misurabile delle funzioni | Tutti | docs/MASTER_PROJECT_MAP.md e docs/MASTER_FEATURE_REGISTER.md | 57 voci distribuite in P0–P3 con requisiti, ruoli, frontend/backend e criteri di accettazione | Mappa decisioni e roadmap presenti; ogni voce ha ID, stato e criteri di verifica; aggiornamento per ogni batch | done |
| P0-02 | Dashboard autonoma Proprietario | Owner | KPI, navigazione, schede | statistiche aggregate e autorizzate | Owner vede dati reali, altri ruoli 403 | partial |
| P0-03 | Gestione account e ruoli | Owner, Admin limitato | schermata account esistente | API account/permessi | protezione owner e privilege escalation | partial |
| P0-04 | Console autonoma Amministratore | Admin | dashboard con statistiche aggregate e gestione account limitata | endpoint admin-only e permessi server-side | admin non può creare/modificare owner né promuoversi; completare KPI operativi e test UI dedicati | partial |
| P0-05 | Console Assistenza e ticket | Support | apertura ticket, elenco, conversazione, risposta, stato e controlli assegnazione Owner/Admin | storage SQLite, ACL proprietario/staff, assegnazione operatori e audit | isolamento, assegnazione solo a Support attivo, revoca assegnazione e permessi verificati; restano notifiche e supporto media con consenso | partial |
| P0-06 | Console Collaboratore / TeamStudio | Collab | schermata Flutter collegata alla navigazione: inviti, progetti, membri, revoca, commenti e approvazioni; test UI ancora da completare | membership, ACL, elenco membri, commenti, approvazioni e revoca | isolamento tra team, visibilità dei soli membri del progetto, revoca immediata e CI verde | partial |
| P0-07 | Registro audit consultabile e filtrabile | Owner | filtri, pagine, dettaglio | query bounded e autorizzate | filtri data/azione/attore, limiti e 403 | partial |
| P0-08 | Audit log antimanomissione | Owner | endpoint integrità Owner-only | hash chain SHA-256; HMAC-SHA256 opzionale con MEDIA_AUDIT_HMAC_KEY; migrazione eventi legacy e verifica sequenza | alterazione di contenuto o collegamento rilevata dai test; configurare HMAC key persistente in produzione | partial |
| P0-09 | Scadenza credenziali temporanee | Owner, Admin autorizzato, User | messaggio rinnovo/reset | expiry persistente a 24 ore, blocco dopo scadenza | test backend CI superati; database esistenti migrati in modo compatibile | done |
| P0-10 | 2FA per Admin e Support | Admin, Support | setup, recovery, enforcement | policy MFA e recovery | accesso negato senza secondo fattore | partial |
| P0-11 | Backup, restore e retention | Owner | API Owner-only per creazione, elenco, verifica e pulizia retention in anteprima | snapshot SQLite cifrato Fernet con controllo integrità; pulizia per età con soglia minima di backup conservati | test cifratura, chiave obbligatoria, alterazione, anteprima non distruttiva, soglia minima e permessi Owner; restore, media assets e replica remota mancanti | partial |
| P0-12 | Ripresa job dopo riavvio | Owner, User | stato e retry | lease, retry idempotente, recovery e riconciliazione con token | test di riapertura database dopo crash submitter/reconciler e rifiuto token scaduto; recovery operativo end-to-end e UI ancora da completare | partial |
| P0-13 | Isolamento account end-to-end | Tutti | indicatori accesso | asset, progetti, export, storage e download ACL | test cross-account su ogni risorsa | partial |
| P0-14 | Storage privato e cancellazione dati | Owner, User | gestione file/cestino | storage integrato, delete e retention | accesso negato a URL non autorizzati | partial |

## P1 — Account, Premium e funzioni editor

| ID | Funzionalità | Ruoli | Frontend | Backend | Test/accettazione | Stato |
|---|---|---|---|---|---|---|
| P1-01 | Schermata Premium collegata alla navigazione | User | AccountPremiumPage collegata a menu desktop e mobile; saldo crediti, quota mensile e referral code | lettura reale di profilo, entitlement, usage e referrals | stato server verificato e fallback; pagamenti reali ancora assenti | partial |
| P1-02 | Concessione/revoca/estensione Premium | Owner | console grant | grant API e audit | scadenze, revoca e audit verificati | partial |
| P1-03 | Pagamenti reali e store billing | User, Owner | acquisto, restore, ricevute | store validation, webhook, entitlement sync | sandbox Apple/Google/web | missing |
| P1-04 | Matrice Free/Premium e quote | Owner, User | riepilogo account con richieste IA usate, limite, residuo e periodo | quota mensile Free/Premium configurabile e riservazioni atomiche già applicate ai job; endpoint /v1/account/usage | test conteggio, isolamento, esaurimento e API autenticata; matrice per singola feature/paywall ancora da completare | partial |
| P1-05 | Referral bilaterale 1 mese | User | codice personale, copia/condivisione, riscatto e storico | claim univoco per invitato, blocco auto-invito, account attivi, maturazione 7 giorni e grant atomico di 30 giorni a entrambi | test duplicati, account disabilitati, maturazione, idempotenza e API; controlli antifrode avanzati e monitoraggio account multipli ancora da completare | partial |
| P1-06 | Premium famiglia | Owner, User | schermata Account Premium con roster, posti, creazione/copia invito, accettazione, revoca inviti, rimozione membri e uscita | inviti monouso a scadenza, limiti posti, membership e API account | test backend già coprono invito monouso, permessi Owner, revoca, rimozione e uscita; nuova UI collegata, da verificare con test widget e CI | partial |
| P1-07 | Gestione crediti IA e costi | Owner, User | saldo crediti visibile nell'account | ledger SQLite atomico, grant Owner-only, consumo, rimborso limitato al consumo originale, chiavi idempotenti e storico | test saldo non negativo, doppio addebito, rimborso, isolamento e API; collegamento al costo reale dei job/provider ancora da completare | partial |
| P1-08 | Timeline ed editing manuale | User | strumenti e anteprima | modello/render base | test gesture, playback e salvataggio su device | partial |
| P1-09 | Effetti, testo, audio completi | User | pannelli operativi | renderer e asset | nessun pulsante placeholder; export testato | partial |
| P1-10 | Keyframe, curve velocità, maschere e tracking | User | editor avanzato | renderer/engine | progetto riapribile e output coerente | missing |
| P1-11 | Color grading, LUT, HDR, stabilizzazione | User | controlli avanzati | pipeline media | file campione e device reali | missing |
| P1-12 | Player professionale e zoom post-export | User | player e gesture | streaming/file output | pinch zoom durante playback, non solo anteprima | partial |
| P1-13 | Libreria media e scorciatoia ultime 2 foto | User | scorciatoia AppBar per importare fino a 2 immagini; importazione completa resta disponibile | FilePicker image picker e pipeline import condivisa | selezione rapida limitata a due file; ordinamento automatico per data e verifica permessi/device ancora mancanti | partial |
| P1-14 | Formati export e preset | User | preset e compatibilità | FFmpeg codec map | MP4/MOV/AVI/WebM validati con file reali | partial |
| P1-15 | Font, RTL e gestione risorse mancanti | User | lingua araba e Directionality RTL a livello app già presenti | renderer font shaping e fallback font ancora da completare | layout RTL di base disponibile; test di shaping e device con testi arabi lunghi mancanti | partial |

## P2 — MagicIAedit, Studio IA, lingue e strumenti media

| ID | Funzionalità | Ruoli | Frontend | Backend | Test/accettazione | Stato |
|---|---|---|---|---|---|---|
| P2-01 | MagicIAedit analisi, piano e revisione | User | flusso dedicato | piano JSON e apply | test già presenti; completare casi media | partial |
| P2-02 | MagicIAedit trasversale nell'app | User | pulsante persistente nell'AppBar per aprire MagicIAedit dalle altre schermate | riuso della sessione/progetto corrente; orchestrazione contestuale completa ancora da sviluppare | accesso globale alla schermata; suggerimenti automatici per selezione media ancora mancanti | partial |
| P2-03 | Provider IA MagicIAedit reale | Owner, User | stato provider e costi | config server-side e routing | chiamata sandbox/produzione verificata | blocked |
| P2-04 | Generazione da prompt senza media | User | prompt studio | generazione contenuti reale | prompt aperti, non template statico | partial |
| P2-05 | Miniserie completa multi-episodio | User | storyboard e revisione episodi | script, scene, personaggi, voce e render | 10 episodi completi, almeno 1 minuto ciascuno | missing |
| P2-06 | AI Director / MagicIA Brain | User | brief, controllo creativo | planner multi-step e memoria progetto | piano verificabile, modificabile e ripetibile | missing |
| P2-07 | Generazione immagini/video e varianti | User | prompt, varianti e timeline | provider immagini/video | output reali, costi e cancellazione | blocked |
| P2-08 | Universal Studio: script/documenti/slide/avatar | User | bozze e revisione presenti | draft/queue presenti, provider assente | ogni tipo produce un risultato reale | partial |
| P2-09 | Trascrizione ASR e timestamp | User | editor trascrizione | provider ASR | precisione, diarizzazione e retry misurati | missing |
| P2-10 | Traduzione con glossario | User | lingue e glossario | provider traduzione | segmenti sincronizzati e revisione | missing |
| P2-11 | TTS, doppiaggio e voiceover | User | selezione voce | provider TTS e consenso | tracce audio per lingua | missing |
| P2-12 | Lip-sync, speaker e talking photo | User | editor avatar | provider e consensi | sincronizzazione misurata e diritti verificati | missing |
| P2-13 | Sottotitoli SRT/VTT/ASS | User | editor e export | generazione timestamp | import/export e sincronizzazione | partial |
| P2-14 | OCR e sostituzione testi nei video | User | revisione testo | OCR temporale e compositing | testi animati e lingue RTL testati | missing |
| P2-15 | Batch localizzazione 20+ lingue | User | selezione, stato e ZIP | job per lingua, retry e output | isolamento, annullamento e output separati | missing |
| P2-16 | Miglioramento foto | User | restore, colorize, rimozione oggetti, sfondo | modelli/provider | qualità, privacy e undo | missing |
| P2-17 | Miglioramento video | User | denoise, upscale, frame interpolation, scene detect | pipeline media/provider | benchmark qualità e tempi | missing |
| P2-18 | Generazione copertine, titoli e descrizioni | User | editor metadata | AI metadata | revisione prima della pubblicazione | missing |

## P3 — collaborazione, marketing, pubblicazione e multipiattaforma

| ID | Funzionalità | Ruoli | Frontend | Backend | Test/accettazione | Stato |
|---|---|---|---|---|---|---|
| P3-01 | TeamStudio condiviso | Collab, Owner | UI Flutter iniziale integrata; mancano notifiche e flussi media | progetti, inviti, ACL, membri, commenti, approvazioni e audit; versioni non ancora presenti | isolamento, accettazione invito, revoca e approvazione coperti da test backend; UI da verificare in CI | partial |
| P3-02 | AdCreator e materiali promozionali | User, Owner | template e brand kit | rendering e asset | esportazione formati social | missing |
| P3-03 | MultiSocial e pubblicazione | User | canali, anteprima e calendario | OAuth e API social | token sicuri, consenso e retry | missing |
| P3-04 | Analytics con consenso | Owner, User | dashboard e opt-out | eventi minimizzati | privacy e cancellazione | missing |
| P3-05 | Player incorporabile e condivisione | User | link/player | delivery e permessi | scadenza link e privacy | partial |
| P3-06 | E-commerce content e personalizzazione bulk | User | template e CSV | pipeline batch | isolamento dati e output verificati | missing |
| P3-07 | LMS/SCORM e contenuti formativi | User | esportazione pacchetti | generazione SCORM | test con LMS compatibili | missing |
| P3-08 | Build e test iOS | Release | UI iOS | pipeline signing | build e installazione su device | missing |
| P3-09 | Build e test desktop | Release | Windows/macOS/Linux | pipeline per target | installazione e smoke test | missing |
| P3-10 | Android installabile e APK finale | Release | app completa | signing/build | solo fase 6, dopo gate approvato | blocked |

## Gate di rilascio e regole

1. Non modificare `main` e non unire la PR senza autorizzazione esplicita.
2. Tutto il lavoro ordinario resta su `feature/magiciaedit-cloud-foundation`.
3. Non generare APK fino alla fase 6 e al gate finale esplicito.
4. Nessun provider cloud va dichiarato operativo senza credenziali server-side e chiamata di prova.
5. Nessuna schermata è “completa” se usa dati fittizi o controlli non collegati.
6. Ogni modifica backend deve includere test di autorizzazione, isolamento, input non valido e percorso positivo.
7. Ogni modifica Flutter deve includere test widget/unit e verifica `flutter analyze`.
8. Ogni batch termina con CI verificata e aggiornamento di questo registro.

## Prossimo ordine di lavoro

1. Chiudere P0-09: scadenza delle password temporanee, compatibile con i database esistenti.
2. Verificare e completare con test dedicati la UI Proprietario per grant/revoca Premium e registro audit.
3. Completare l'eventuale esportazione audit e la protezione antimanomissione, mantenendo l'accesso Owner-only.
4. Completare dashboard Admin, assegnazione ticket e notifiche; separare la console Collaboratore.
5. Procedere con TeamStudio, accesso ai media con consenso e hardening di storage/job recovery.


## Avanzamento verificato — 8 novembre 2026

- Registro maestro creato e salvato nel branch.
- P0-09 implementato: password temporanee generate alla creazione account o al reset scadono dopo 24 ore; dopo la scadenza l'accesso e il cambio password con la vecchia credenziale sono rifiutati; un nuovo reset riattiva il flusso. La migrazione aggiunge una colonna nullable e non invalida credenziali temporanee preesistenti.
- CI run `42517113363`, commit `04deff5155a11d6816919ac66f955c0bed126955`: backend **300 test superati**; Flutter **139 test superati** e analisi statica superata. Android preflight ancora in corso al momento dell'aggiornamento; APK disabilitato intenzionalmente.


## Avanzamento verificato — 8 novembre 2026, blocco Proprietario Premium e audit

- Collegata la gestione concessioni Premium alla console Proprietario: elenco, concessione individuale/famiglia, durate 30/90/365 giorni o senza scadenza, motivazione e revoca con conferma. Le API server esistenti applicano i permessi e registrano gli eventi.
- Registro sicurezza aggiornato: ricerca testuale, filtro per azione, dettaglio evento e caricamento progressivo delle pagine.
- Backend audit: filtri server-side per azione, attore, destinatario e intervallo temporale; offset/limit bounded e indicatore `hasMore`. Aggiunti test API per filtri, paginazione e intervallo non valido.
- CI run `42519024360` sul commit `873c5917fa00b0fbecf1e29589f66027a53e8712`: **backend-test superato** e **flutter-test superato**; analisi statica Flutter superata. **Android preflight ancora in esecuzione**; non è stato creato alcun APK.
- P0-07 e P1-02 restano `partial`: mancano ancora verifica completa, test UI dedicati e, per P0-07, audit antimanomissione/esportazione.


## Avanzamento verificato — 8 novembre 2026, console Admin e Assistenza

- P0-04 passa a `partial`: dashboard Admin collegata a un endpoint dedicato che restituisce esclusivamente contatori aggregati (account totali/attivi/sospesi, nuovi ultimi 30 giorni e conteggio per ruolo). Il server rifiuta gli altri ruoli; restano KPI operativi più ampi e test UI dedicati.
- P0-05 passa a `partial`: utenti possono aprire ticket e consultare solo i propri; Support/Admin/Owner autorizzati possono consultare la coda, rispondere e aggiornare lo stato. Conversazioni persistite, ownership verificata e azioni registrate nell'audit. Restano assegnazione operatori, notifiche, allegati e assistenza su media privati con consenso esplicito.
- Aggiunti test API per dashboard Admin, autenticazione, isolamento ticket, risposte staff/utente e transizioni di stato.
- CI run `42520069602`, commit `6dc37687515e941b749cf305178a3acb3e38da2a`: backend **304 test superati**; Flutter **139 test superati** e `flutter analyze` senza problemi. Android preflight/validazione Gradle era ancora in esecuzione al momento della registrazione; nessun APK generato.
- Nessun dato personale viene restituito dalla dashboard Admin; gli utenti non possono ottenere dettagli dei ticket altrui.


## Avanzamento verificato — 8 novembre 2026, assegnazione ticket Assistenza

- Aggiunto il campo persistente `assigned_to_user_id` con migrazione compatibile dei database esistenti.
- Nuova API `PUT /v1/support/tickets/{ticket_id}/assignment`: solo Owner/Admin con permesso dedicato possono assegnare o rimuovere l'assegnazione; il destinatario deve essere un account Support attivo.
- L'assegnazione è restituita in elenco e dettaglio ticket e ogni modifica genera un evento audit senza esporre dati non necessari.
- Test API aggiunti per ruolo non autorizzato, assegnatario non valido, assegnazione, revoca e lettura del valore aggiornato. La funzionalità resta `partial`: manca il controllo visuale nella console, oltre a notifiche e supporto media con consenso.
- Modifiche sul branch `feature/magiciaedit-cloud-foundation`; attendere CI prima di considerarle verificate. Nessun APK generato.


## Aggiornamento interfaccia Assistenza — 8 novembre 2026

- La console Owner/Admin include ora un selettore degli operatori Support attivi e l'azione per assegnare o rimuovere l'assegnazione del ticket tramite endpoint protetto.
- La lista ticket indica quando un ticket risulta assegnato.
- La verifica CI successiva alle modifiche UI è in attesa; la modifica non viene conteggiata come completata finché i test non terminano.

## Correzione robustezza assegnazione ticket — 8 novembre 2026

- La console Owner/Admin mantiene ora selezionabile anche l'assegnatario già salvato quando non compare nella prima pagina degli account Support attivi (ad esempio account disattivato o fuori dai primi 100). Viene mostrato come assegnatario attuale non disponibile, così l'operatore può rimuovere l'assegnazione senza crash del menu.
- Modifica UI committata sul branch; la nuova verifica CI è in attesa. P0-05 resta `partial`: notifiche e supporto media con consenso non sono ancora implementati.


## Fondazione TeamStudio — 8 novembre 2026

- Aggiunto archivio SQLite per progetti TeamStudio, inviti a account Collaboratore attivi, accettazione/rifiuto, revoca, commenti e richieste di approvazione.
- Le autorizzazioni sono verificate sul server: il collaboratore vede soltanto i progetti per cui ha accettato l'invito; la revoca elimina immediatamente l'accesso. Le operazioni principali generano eventi nell'audit account.
- Aggiunto permesso `team.manage` per Owner/Admin; Support, Collaborator e User non possono amministrare i team.
- Esposte API protette per creazione/lista progetti, inviti, risposta agli inviti, revoca, commenti e approvazioni.
- Aggiunti test backend per isolamento tra account, invito e accettazione, ruoli, revoca, commenti, approvazione e audit. La CI del commit finale deve ancora confermare il risultato.
- Limite dichiarato: questa prima fondazione conserva metadati e flussi di collaborazione; non sincronizza ancora i file multimediali/progetti locali, non include UI Flutter, notifiche invito, versioni o cronologia delle revisioni.
- P3-01 passa da `missing` a `partial`; nessuna voce è conteggiata come completata. Nessun APK generato.


## Aggiornamento TeamStudio — 8 novembre 2026, visibilità membri e client Flutter

- Corretto il test di autorizzazione dell'invito: un account Collaboratore diverso dal destinatario riceve la risposta generica e sicura "Invito non disponibile", senza rivelare dettagli sull'esistenza di inviti altrui.
- Aggiunto `GET /v1/team/projects/{project_id}/members` e metodo backend `list_members`: restituisce soltanto il proprietario e le membership del progetto (attive, pendenti o revocate), con identificativi e username; l'accesso è limitato a chi può già vedere il progetto.
- Aggiunto test per elenco membri, stati pending/active/revoked e isolamento da account esterni.
- Creato `lib/services/remote_team_api.dart` con chiamate Flutter per progetti, inviti, risposta inviti, membri, revoca, commenti e approvazioni, usando il client account esistente e il token di sessione protetto.
- P0-06 passa da `missing` a `partial`: manca ancora la schermata Flutter collegata alla navigazione e la verifica CI dell'ultimo commit. P3-01 resta `partial`: sincronizzazione dei media, notifiche e versioni/revisioni non sono ancora implementate.
- Stato indicativo del registro: 1 done, 25 partial, 28 missing, 3 blocked su 57 voci; stima uniforme circa 24% (1 + 25×0,5)/57. Nessun APK generato; fase 6 invariata come ultima fase.


## Aggiornamento TeamStudio — 8 novembre 2026, prima console Flutter integrata

- Creata `lib/team/team_studio_screen.dart`: ripristino sessione account protetta, elenco progetti accessibili, inviti personali per Collaboratori, creazione progetti Owner/Admin, invito tramite ID account Collaboratore, visualizzazione membri e stati, revoca con conferma, commenti e flusso di approvazione.
- Integrata la schermata nella navigazione laterale e mobile dell'app (`lib/main.dart`), senza sostituire le pagine esistenti.
- Il client usa `RemoteTeamApi` e il bearer token conservato in secure storage; la schermata non raccoglie né visualizza password o token.
- Dichiarato in UI il limite attuale: i file multimediali e i progetti locali non vengono caricati/sincronizzati. Non si presenta quindi la collaborazione come sincronizzazione cloud già disponibile.
- P0-06 e P3-01 restano `partial` in attesa della CI sul nuovo frontend e di test UI dedicati; restano inoltre da implementare sincronizzazione media, notifiche, versioni e cronologia revisioni.
- Stima del registro invariata: 1 done, 25 partial, 28 missing, 3 blocked su 57; circa 24% con ponderazione uniforme. Nessun APK generato; fase 6 resta l'ultima.


## Aggiornamento Premium — 8 novembre 2026, collegamento entitlement e navigazione

- Aggiunta `AccountPremiumPage`: recupera la sessione da secure storage, verifica il profilo autenticato e legge il piano reale da `GET /v1/account/entitlement`.
- La schermata Premium è raggiungibile dal menu laterale e dalla navigazione mobile. In assenza di configurazione API/sessione mostra lo stato non autenticato; in caso di errore di rete consente un nuovo tentativo.
- Acquisto, ripristino e referral non vengono simulati: la UI dichiara che pagamenti e servizio inviti non sono ancora collegati. Nessun codice invito fittizio e nessuna concessione Premium lato client.
- Aggiunti test widget per stato senza sessione/configurazione e trasparenza sul pagamento non attivo. La modifica resta da confermare con CI.
- P1-01 resta `partial`: la lettura entitlement è collegata, ma mancano flussi di accesso integrati, billing reale e verifica multipiattaforma. P1-03 e P1-05 non avanzano di stato.


## Blocco avanzamento autonomo — referral, quote, crediti e audit — 8 novembre 2026

- **Referral P1-05:** creato codice personale stabile; claim autenticato; auto-invito rifiutato; un solo claim per account invitato; entrambi gli account devono essere attivi. Il premio resta pending per 7 giorni e poi il server assegna in un'unica transazione 30 giorni Premium a invitante e invitato. Maturazione lazy al successivo accesso a entitlement/usage/storico; non è un processo pianificato in background. Restano controlli antifrode avanzati contro multi-account, analisi abuso e notifiche.
- **Quote P1-04:** endpoint autenticato `GET /v1/account/usage` espone periodo, usato, limite e residuo; la schermata Premium visualizza il dato. Si basa sulle prenotazioni mensili già applicate ai job IA. Mancano matrice per funzione, paywall e catalogo completo delle quote.
- **Crediti P1-07:** aggiunto ledger atomico con grant solo Owner, addebito, rimborso non superiore all'addebito originale, chiave idempotente e storico per account. API per saldo/storico e grant Owner; saldo visibile in Premium. I job/provider non consumano ancora questo saldo: non va confuso con la quota mensile esistente.
- **Audit P0-08:** gli eventi nuovi sono concatenati con SHA-256; se configurata `MEDIA_AUDIT_HMAC_KEY`, usano HMAC-SHA256. Migrazione degli eventi legacy, endpoint di verifica Owner-only e test di alterazione. Senza chiave HMAC la catena SHA-256 rileva modifiche accidentali/strutturali ma non è una prova contro un amministratore del database capace di ricalcolare gli hash; configurare una chiave segreta persistente in produzione.
- **MagicIAedit P2-02:** aggiunto un accesso persistente dalla barra superiore, disponibile anche quando si è in altre sezioni. Non equivale ancora all'automazione contestuale di ogni selezione foto/video.
- Tutte queste voci restano `partial` fino a verifica CI e completamento dei limiti elencati. Nessun APK generato.


## Aggiornamento backup, import rapido e RTL — 8 novembre 2026

- **P0-11 Backup:** creato servizio di snapshot SQLite online, cifrato con Fernet e verificabile con controllo `PRAGMA quick_check`; API Owner-only per creare, elencare e verificare. Richiede `MEDIA_BACKUP_ENCRYPTION_KEY`; senza chiave fallisce in modo esplicito. Non include ancora media assets, ripristino, retention automatica o replica remota.
- **P1-13 Media:** aggiunta scorciatoia nell'AppBar per selezionare e importare al massimo due immagini nella pipeline esistente. Il pulsante normale di importazione mantiene la selezione completa di foto/video/audio. L'ordinamento automatico delle due immagini più recenti non è ancora garantito dal provider di selezione.
- **P1-15 Lingue:** riconosciuto il supporto già presente per lingua araba e direzione RTL a livello app. Font shaping, fallback tipografici e test su testi arabi lunghi restano da fare.


### Verifica del registro maestro

- Il registro copre 57 funzionalità con identificativo univoco, priorità, ruoli, stato e criteri di accettazione.
- La mappa generale documenta le decisioni approvate, le piattaforme, il prodotto creativo, i pannelli, la monetizzazione, la sicurezza e le sei fasi.
- P0-01 è quindi considerato completato come deliverable documentale. Il completamento del registro non implica che le 57 funzionalità software siano completate.


## Aggiornamento Premium famiglia — 8 novembre 2026

- Collegata alla schermata Account e Premium una sezione famiglia autenticata: mostra i membri e i posti occupati, permette al titolare di creare un invito monouso e copiarlo, consultare gli inviti, revocare quelli pendenti e rimuovere membri; il membro può accettare un codice o lasciare il gruppo.
- Le operazioni usano le API backend esistenti e rispettano i controlli server-side; i token invito vengono mostrati solo al momento della creazione e non vengono recuperati dallo storico.
- La UI resta `partial` fino a test Flutter dedicati, verifica CI e prova su dispositivo. Il piano famiglia richiede ancora pagamenti reali/store billing e verifica del flusso acquisto.


## Verifica CI Premium famiglia, referral e quota AI — 9 novembre 2026

- CI sul commit `5a167aef59fe32156982abb44a40ced2b003b57e`: run #915 e #914 concluse con esito **success**. In entrambe risultano superati `flutter-test`, `backend-test` e `android-preflight`; `android-apk` è stato intenzionalmente saltato perché la build APK appartiene alla fase 6.
- **P1-06 Premium famiglia:** i test backend e widget presenti sono inclusi nella CI verde. La schermata resta `partial`: non sono ancora verificati acquisto/store billing, notifiche e prova su dispositivi reali.
- **P1-05 Referral:** verificata la corrispondenza del contratto backend/frontend: lo storico restituisce `claims` con `role` (`inviter`/`invitee`), `status` (`pending`/`rewarded`/`rejected`), `claimedAt`, `eligibleAt`, `maturedAt` e `rewardDays`. La UI legge `claims` e presenta stato e premio; test widget incluso nella CI verde. Restano antifrode avanzata e notifiche.
- **P1-04 Quote:** il riepilogo mostra usato, limite e residuo; quando il residuo è zero presenta un avviso esplicito. Il test widget relativo al limite raggiunto è incluso nella CI verde. Restano matrice per singola funzione e paywall.
- Nessuna delle tre voci passa a `done`: i criteri di accettazione complessivi non sono ancora soddisfatti. Registro invariato: **2 done, 31 partial, 21 missing, 3 blocked su 57** (30,7% con ponderazione uniforme).
- Nessun APK creato; `main` non modificato; PR non unita.


## Console backup Owner e test API — 9 novembre 2026

- Aggiunta nella console Proprietario la scheda **Backup e integrità**: caricamento elenco, creazione di snapshot cifrato, aggiornamento elenco e verifica di un backup selezionato.
- La UI esplicita che `MEDIA_BACKUP_ENCRYPTION_KEY` deve essere configurata sul server e non simula un ripristino che il backend non offre ancora.
- Aggiunti test API per creazione/lista/verifica, rifiuto di utente e anonimo e comportamento fail-closed quando manca la chiave di cifratura.
- **P0-11 resta partial**: restore sicuro con staging/rollback, media assets, retention automatica e replica remota non sono implementati.
- La verifica CI della precedente modifica audit sul commit `826f093` ha completato con successo backend e Flutter; Android preflight risultava ancora in esecuzione durante questo batch. La nuova modifica deve essere validata dalla propria CI.

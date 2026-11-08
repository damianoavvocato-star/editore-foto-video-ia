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
| P0-01 | Registro completo e misurabile delle funzioni | Tutti | docs | — | Ogni voce ha ID, stato, criteri | partial |
| P0-02 | Dashboard autonoma Proprietario | Owner | KPI, navigazione, schede | statistiche aggregate e autorizzate | Owner vede dati reali, altri ruoli 403 | partial |
| P0-03 | Gestione account e ruoli | Owner, Admin limitato | schermata account esistente | API account/permessi | protezione owner e privilege escalation | partial |
| P0-04 | Console autonoma Amministratore | Admin | dashboard con statistiche aggregate e gestione account limitata | endpoint admin-only e permessi server-side | admin non può creare/modificare owner né promuoversi; completare KPI operativi e test UI dedicati | partial |
| P0-05 | Console Assistenza e ticket | Support | apertura ticket, elenco, conversazione, risposta e stato | storage SQLite, ACL proprietario/staff, assegnazione operatori e audit | isolamento, assegnazione solo a Support attivo, revoca assegnazione e permessi verificati; restano notifiche e supporto media con consenso | partial |
| P0-06 | Console Collaboratore / TeamStudio | Collab | inviti, incarichi, revisioni | membership, ACL e revoca | isolamento tra team e revoca immediata | missing |
| P0-07 | Registro audit consultabile e filtrabile | Owner | filtri, pagine, dettaglio | query bounded e autorizzate | filtri data/azione/attore, limiti e 403 | partial |
| P0-08 | Audit log antimanomissione | Owner | stato integrità | hash chain o firma, verifica periodica | alterazione/rimozione rilevata | missing |
| P0-09 | Scadenza credenziali temporanee | Owner, Admin autorizzato, User | messaggio rinnovo/reset | expiry persistente a 24 ore, blocco dopo scadenza | test backend CI superati; database esistenti migrati in modo compatibile | done |
| P0-10 | 2FA per Admin e Support | Admin, Support | setup, recovery, enforcement | policy MFA e recovery | accesso negato senza secondo fattore | partial |
| P0-11 | Backup, restore e retention | Owner | console backup | snapshot cifrati, restore verificato | ripristino in ambiente isolato | missing |
| P0-12 | Ripresa job dopo riavvio | Owner, User | stato e retry | lease, retry idempotente, recovery | crash simulato e ripresa senza duplicati | partial |
| P0-13 | Isolamento account end-to-end | Tutti | indicatori accesso | asset, progetti, export, storage e download ACL | test cross-account su ogni risorsa | partial |
| P0-14 | Storage privato e cancellazione dati | Owner, User | gestione file/cestino | storage integrato, delete e retention | accesso negato a URL non autorizzati | partial |

## P1 — Account, Premium e funzioni editor

| ID | Funzionalità | Ruoli | Frontend | Backend | Test/accettazione | Stato |
|---|---|---|---|---|---|---|
| P1-01 | Schermata Premium collegata alla navigazione | User | AccountPremiumScreen e route | entitlement API | raggiungibile da tutte le piattaforme target | partial |
| P1-02 | Concessione/revoca/estensione Premium | Owner | console grant | grant API e audit | scadenze, revoca e audit verificati | partial |
| P1-03 | Pagamenti reali e store billing | User, Owner | acquisto, restore, ricevute | store validation, webhook, entitlement sync | sandbox Apple/Google/web | missing |
| P1-04 | Matrice Free/Premium e quote | Owner, User | paywall e consumi | policy e contatori per feature | enforcement server-side e trasparenza quote | missing |
| P1-05 | Referral bilaterale 1 mese | User | invito, riscatto, storico | attribuzione, antifrode, maturazione e grant | inviter e invitee premiati una sola volta | partial |
| P1-06 | Premium famiglia | Owner, User | gestione membri e posti | inviti e membership di base | UI completa, limiti posti, revoca | partial |
| P1-07 | Gestione crediti IA e costi | Owner, User | saldo e consumi | ledger, limiti, idempotenza | nessun saldo negativo o doppio addebito | missing |
| P1-08 | Timeline ed editing manuale | User | strumenti e anteprima | modello/render base | test gesture, playback e salvataggio su device | partial |
| P1-09 | Effetti, testo, audio completi | User | pannelli operativi | renderer e asset | nessun pulsante placeholder; export testato | partial |
| P1-10 | Keyframe, curve velocità, maschere e tracking | User | editor avanzato | renderer/engine | progetto riapribile e output coerente | missing |
| P1-11 | Color grading, LUT, HDR, stabilizzazione | User | controlli avanzati | pipeline media | file campione e device reali | missing |
| P1-12 | Player professionale e zoom post-export | User | player e gesture | streaming/file output | pinch zoom durante playback, non solo anteprima | partial |
| P1-13 | Libreria media e scorciatoia ultime 2 foto | User | recenti + galleria completa | import e permessi | scorciatoia senza limitare selezione completa | missing |
| P1-14 | Formati export e preset | User | preset e compatibilità | FFmpeg codec map | MP4/MOV/AVI/WebM validati con file reali | partial |
| P1-15 | Font, RTL e gestione risorse mancanti | User | fallback e layout | renderer font shaping | arabo corretto e fallback testati | missing |

## P2 — MagicIAedit, Studio IA, lingue e strumenti media

| ID | Funzionalità | Ruoli | Frontend | Backend | Test/accettazione | Stato |
|---|---|---|---|---|---|---|
| P2-01 | MagicIAedit analisi, piano e revisione | User | flusso dedicato | piano JSON e apply | test già presenti; completare casi media | partial |
| P2-02 | MagicIAedit trasversale nell'app | User | entry point contestuali | orchestrazione condivisa | accessibile da schermate e selezioni rilevanti | missing |
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
| P3-01 | TeamStudio condiviso | Collab, Owner | team, progetti e commenti | ACL, versioni, inviti e audit | approvazione e revoca verificate | missing |
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

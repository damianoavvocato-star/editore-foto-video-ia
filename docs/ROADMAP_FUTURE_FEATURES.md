# Roadmap funzionale estesa — Editore foto e Video IA

> Stato: requisiti pianificati, **non ancora implementati** salvo le componenti già presenti nel codice.
> Ambito: branch `feature/magiciaedit-cloud-foundation`. Non modificare `main`, non unire la PR e non generare APK prima della fase 6.
> Principio: ogni funzione va consegnata per incrementi verificabili, con controlli di sicurezza, costi e test. Nessuna funzione IA va presentata come attiva finché non esiste un provider configurato e testato.

## 1. Nuove funzioni approvate

| Funzione | Obiettivo e dipendenze principali | Sicurezza e privacy | Costi/limiti da valutare | Test e criteri di accettazione |
|---|---|---|---|---|
| **AutoRescue** | Salvataggio automatico, versioni, cestino recuperabile, ripristino dopo crash. Dipende da ProjectStore, coda di salvataggio, storage locale e opzionale cloud. | Cifratura dei backup, isolamento per account, retention configurabile, ripristino esplicito; mai sovrascrivere l'unica copia valida. | Storage, traffico e retention; quote per utente e pulizia controllata. | Kill durante salvataggio, disco pieno, rete assente, file parziale/corrotto, restore e migrazione versioni; verificare che il progetto recuperato sia apribile. |
| **SmartDevice** | Profilo adattivo del dispositivo: memoria disponibile quando esposta, spazio libero, capacità codec, dimensione schermo e segnali termici supportati. Dipende da plugin nativi Android/iOS/desktop e capability probe. | Raccogliere solo metriche tecniche necessarie; nessun fingerprint persistente; permessi minimi. | Implementazione per piattaforma e costo QA su dispositivi diversi; non richiede provider IA. | Simulare memoria bassa, storage insufficiente, codec assenti e segnali termici non disponibili; fallback senza crash e controlli specifici per piattaforma. |
| **VideoDoctor** | Analisi pre-export: durata, stream, audio, aspect ratio, frame neri/sfocati dove tecnicamente fattibile, sottotitoli fuori area e compatibilità. Dipende da FFmpeg/ffprobe e analizzatori locali o backend. | Analisi sul dispositivo ove possibile; upload solo con consenso; non conservare i media oltre il necessario. | Tempo CPU/GPU, eventuale elaborazione cloud; limiti di durata e dimensione. | Fixture video valide e malformate, audio clipping/silenzio, rotazione, frame rate variabile, file grandi; risultati ripetibili e falsi positivi dichiarati. |
| **SmartDirector** | Regia IA che propone storyboard, ordine scene, ritmo, transizioni e stile a partire dai media e dall'obiettivo scelto. Dipende da MagicIAedit, catalogo media, modelli vision e motore timeline. | Consenso prima dell'upload, minimizzazione media, provider allowlist HTTPS, segreti solo server-side; proposta sempre revisionabile, mai applicazione o pubblicazione automatica. | Token/modello vision, upload e rendering; quote, limiti media, stima costo prima di eseguire. | Media misti, pochi/tanti asset, prompt ambigui, provider indisponibile, output schema invalido; approvazione esplicita e timeline valida. |
| **VoiceStudio** | Trascrizione, sottotitoli, traduzione e doppiaggio; pulizia audio e sincronizzazione. Dipende da ASR/TTS/traduzione, gestione audio e licenze delle voci. | Consenso per clonazione/imitazione vocale; vietare impersonificazione non autorizzata; disclosure voce sintetica, protezione registrazioni e cancellazione. | Minuti audio, lingue, TTS/ASR e storage; preventivo/quote e modalità locale quando disponibile. | Accenti/rumore, lingue RTL, timestamp, diarizzazione, sincronizzazione, voce sintetica, cancellazione e rifiuto richieste non autorizzate. |
| **MultiSocial** | Un progetto, preset multipli per aspect ratio, safe area, risoluzioni, sottotitoli e codec per piattaforme. Dipende da export pipeline e preset aggiornabili. | Non richiedere credenziali social; condivisione solo tramite API ufficiali o share sheet e consenso dell'utente. | Rendering multiplo, storage temporaneo e possibili API di terze parti. | Test preset verticali/quadrati/orizzontali, safe area, orientamento, codec e file su dispositivi reali; verificare requisiti piattaforme correnti prima del rilascio. |
| **SmartShield Evolution** | Evoluzione di SmartShield: gestione pressione memoria, frame time, modalità qualità adattiva e protezione del rendering. Dipende da SmartDevice e telemetria locale disponibile. | Metriche minimizzate e preferibilmente locali; niente monitoraggio occulto; controlli di opt-out per telemetria diagnostica. | QA multipiattaforma; costo cloud solo se telemetria remota è opt-in. | Simulare memory pressure, frame drop, app in background, thermal signals disponibili/non disponibili e lifecycle dispose; nessuna callback dopo dispose e degradazione graduale. |
| **CreativeMemory** | Preferenze creative per stili, transizioni, colori e preset; suggerimenti coerenti tra progetti. Dipende da profilo locale e, opzionalmente, sync cloud. | Memoria controllabile dall'utente, visualizzabile, cancellabile ed esportabile; separazione da dati sensibili e nessun uso per training senza consenso. | Storage minimo; eventuale costo sync/AI. | Opt-out, reset, migrazione, conflitti multi-device e verifica che non vengano memorizzati media o dati non richiesti. |
| **SafeMedia** | Cartella privata, PIN/biometria, rimozione metadati GPS, duplicati e avvisi privacy prima della condivisione. Dipende da secure storage e API biometria native. | Cifratura a riposo, chiavi in Keychain/Keystore, protezione backup, autorizzazioni esplicite; biometria non sostituisce autenticazione server. | Storage cifrato e QA piattaforme; nessun costo AI obbligatorio. | Accesso biometrico negato, device lockout, backup/restore, export metadata stripping, file duplicati e test di isolamento. |
| **PhotoMotion** | Animazione foto in clip con movimento camera, profondità o effetti generativi. Dipende da modelli image-to-video, rendering e coda job. | Diritti/consenso sulle immagini, protezione volti e media; niente caricamenti nascosti. | Elevato costo GPU/provider e tempi; limiti per risoluzione/durata, quote e anteprima a bassa qualità. | Foto ritratto/paesaggio, occlusioni, artefatti, volti, cancellazione job, timeout e verifica che il risultato sia etichettato come generato. |
| **ReLight IA** | Correzione/ricostruzione illuminazione di foto e video, con controlli di intensità e confronto prima/dopo. Dipende da modelli image/video enhancement e pipeline colore. | Elaborazione locale preferita; upload esplicito, retention minima e diritti sui contenuti. | GPU, memoria e costo per frame; elaborazione a campioni/preview e limiti clip. | Scene scure/alte luci, tonalità della pelle, flicker tra frame, banding, colori e fallback quando il device non supporta il carico. |
| **TeamStudio** | Collaborazione su progetto: inviti, ruoli, commenti, versioni e approvazioni. Dipende da autenticazione individuale, ownership, storage isolato, sync e conflitti. | Autorizzazione server-side per ogni risorsa, inviti revocabili, audit log, cifratura in transito/a riposo; mai fidarsi di user ID inviati dal client. | Database, storage, banda, sincronizzazione e supporto; quote per team e retention. | Accesso incrociato negato, revoca inviti/sessioni, concorrenza, merge conflitti, commenti, cancellazione team e test di permessi. |
| **Edita con la voce** | Comandi in linguaggio naturale per modificare timeline e impostazioni; preview del piano prima dell'applicazione. Dipende da VoiceStudio (se input vocale), parser intent, schema comandi e API editing. | Conferma per operazioni distruttive; nessun comando che pubblichi/condivida senza conferma; elaborazione vocale solo con consenso. | ASR e chiamate LLM; limiti token/minuti e fallback a comandi testuali. | Rumore, accenti, comandi ambigui, annullamento, undo/redo, comandi non supportati e conferma obbligatoria per delete/export/share. |
| **MemoryRestorer** | Restauro di vecchi filmati: denoise, stabilizzazione, correzione colore e upscaling quando possibile. Dipende da modelli video restoration, FFmpeg e GPU. | Consenso e diritti sui filmati; protezione di volti e contenuti privati; upload esplicito e retention definita. | Tra le funzioni più costose: GPU, durata, risoluzione e storage; job asincroni, preventivo e quote. | Filmati degradati, interlacciati, rumore, stabilizzazione, artefatti, sync audio, timeout e confronto non distruttivo con originale. |
| **AdCreator** | Creazione guidata di video promozionali da media e informazioni prodotto, con storyboard, copy, voiceover e formati social. Dipende da SmartDirector, VoiceStudio, MultiSocial e libreria asset con licenze. | Veridicità delle affermazioni, diritti su marchi/immagini/musiche, disclosure contenuti sintetici; approvazione utente prima della pubblicazione. | Modelli generativi, voce, rendering e asset con licenza; quote e preventivo per campagna. | Test claim non supportati, marchi, licenze, lingue, formati, contenuti vietati e revisione prima dell'export. |

## 2. Moduli proprietario e collaboratori già approvati

Questi requisiti, emersi nella conversazione, vanno integrati nella stessa pianificazione:

### Pannello PROPRIETARIO
- Ruolo proprietario unico e separato dagli amministratori.
- Autenticazione forte, 2FA, ri-autenticazione per operazioni critiche e sessioni revocabili.
- Gestione account, username, abbonamenti, limiti, configurazioni IA, segnalazioni e diagnostica.
- Recupero account assistito dopo verifica dell'identità: password attuali mai leggibili; reset sicuro o password temporanea casuale monouso, mostrata una sola volta, con scadenza e cambio obbligatorio.
- Audit log non alterabile dai ruoli subordinati.
- Accesso Premium omaggio per utenti e collaboratori: durata predefinita o personalizzata, inclusa opzione senza scadenza; revoca, estensione, motivazione e storico. Il regalo azzera il prezzo dell'abbonamento, non i costi di infrastruttura/IA.

### Gestione collaboratori e ruoli
- Il proprietario può creare amministratori, assistenza e collaboratori con permessi granulari.
- Collaboratori non possono modificare il proprietario, elevare autonomamente i propri privilegi o creare altri proprietari.
- Ogni azione è verificata lato server e registrata; revoca immediata di ruolo, inviti e sessioni.
- Il supporto account non dà accesso silenzioso ai progetti privati degli utenti.

### Requisito architetturale bloccante
Prima di TeamStudio e delle funzioni multiutente in cloud, completare autenticazione individuale reale e isolamento end-to-end di account, progetti, asset, job e output. Il bearer token condiviso attualmente previsto per il backend non è sufficiente per un servizio multiutente. Non fidarsi di identificativi utente forniti dal client.

## 3. Dipendenze e ordine consigliato

1. **Fondazioni e sicurezza**: autenticazione individuale, ownership/isolation, autorizzazioni server-side, audit, quote/costi, storage e backup.
2. **Affidabilità locale**: AutoRescue, SmartDevice e SmartShield Evolution.
3. **Qualità media**: VideoDoctor, SafeMedia e MultiSocial.
4. **Intelligenza creativa**: SmartDirector e CreativeMemory, estendendo e testando MagicIAedit.
5. **Audio e interazione**: VoiceStudio ed Edita con la voce.
6. **Modelli video ad alto costo**: PhotoMotion, ReLight IA e MemoryRestorer.
7. **Collaborazione e marketing**: TeamStudio e AdCreator, dopo completamento dell'isolamento multiutente e delle licenze.

L'ordine può essere adattato ai risultati dell'audit, ma le dipendenze di sicurezza non possono essere saltate.

## 4. Controllo dei costi e attivazione

- Separare funzioni locali, funzioni cloud e funzioni che richiedono provider IA.
- Ogni provider deve essere configurato solo sul server tramite segreti; mai includere API key nell'app.
- Prevedere limiti di dimensione, durata, risoluzione, minuti, token e job concorrenti.
- Mostrare stima o fascia di consumo prima delle elaborazioni cloud costose.
- Implementare quote, rate limiting, timeout, cancellazione, retry limitati e protezione da richieste duplicate.
- Disattivare in modo sicuro le funzioni se il provider non è configurato o supera il budget; non simulare risultati reali.
- Le funzioni Premium omaggio non devono disattivare i limiti di costo infrastrutturale.

## 5. Strategia di test e criteri di rilascio

Per ciascun modulo:
- unit test per logica, validazione e limiti;
- integration test per API, storage, autenticazione e provider simulati;
- test di sicurezza per accesso non autorizzato, escalation privilegi, IDOR, abuso di quote e leakage di segreti;
- test di errore: offline, timeout, provider assente, cancellazione, spazio insufficiente, file malformati e crash;
- test Flutter su Android, iOS e desktop dove supportato;
- test manuali su dispositivi reali e file multimediali rappresentativi;
- test accessibilità, localizzazione, RTL arabo e formati social;
- misurazione di memoria, CPU/GPU, batteria, latenza e costo per job.

Una funzione è completata solo quando implementazione, test, documentazione, gestione errori e limiti sono verificati. I test simulati non sostituiscono la verifica con provider reali; i provider reali non vanno attivati senza configurazione e controllo costi.

## 6. Fasi e vincoli di progetto

- Le nuove funzioni ampliano il lavoro residuo e **non devono essere conteggiate come già implementate**.
- Integrare prima le fondazioni e le funzioni locali, poi i servizi IA più costosi e infine la collaborazione.
- Aggiornare la percentuale di avanzamento solo sulla base di codice e test verificati.
- Mantenere le modifiche sul branch `feature/magiciaedit-cloud-foundation` e nella PR draft esistente.
- **Non modificare `main` e non unire la PR senza autorizzazione esplicita.**
- **La creazione dell'APK resta esclusivamente la fase 6 e ultima**, dopo completamento delle implementazioni, test, correzioni, verifiche di sicurezza e controlli multipiattaforma.

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


## 7. Estensione approvata: Universal Video Studio IA e traduzione multilingue

Questa sezione amplia il prodotto prendendo Vidnoz come riferimento funzionale, senza dipendere da esso né copiarne il prodotto. **Le funzioni seguenti sono pianificate, non implementate per effetto della sola documentazione.**

### 7.1 Universal Video Studio IA
Centro unico integrato con MagicIAedit, VoiceStudio, MultiSocial e timeline per traduzione/localizzazione, doppiaggio, sottotitoli, avatar e presentatori virtuali, video da testo/script, video da presentazioni e documenti, corsi, tutorial, presentazioni aziendali e contenuti promozionali. Ogni risultato resta modificabile e revisionabile.

### 7.2 MultiTraduzione IA: batch multilingue
Da un video sorgente l'utente può selezionare più lingue nella stessa operazione (obiettivo architetturale: almeno 20 lingue selezionabili, subordinato a provider, qualità, quote e costi). Il sistema rileva/conferma la lingua sorgente, trascrive con timestamp, separa gli interlocutori, traduce mantenendo contesto e glossario, genera audio e sottotitoli, applica lip-sync quando disponibile e produce **un file video distinto per ciascuna lingua**. Download singolo o ZIP. Ogni lingua ha stato indipendente, retry/cancellazione separati e avanzamento visibile; un errore in una lingua non blocca le altre. Coda asincrona, ripresa dopo interruzione, idempotenza, limiti di concorrenza e stima costi prima dell'avvio.

### 7.3 Funzioni linguistiche
- Universal Voice: trascrizione, traduzione, TTS/doppiaggio, tono/registro, pronuncia e glossari.
- Clonazione vocale solo con consenso verificabile e diritti; disclosure della voce sintetica e protezioni anti-impersonificazione.
- Diarizzazione multi-speaker con tracce vocali distinte; nessuna identificazione personale presunta.
- Lip-sync opzionale con anteprima e indicazione dei limiti qualitativi.
- Sottotitoli generati, tradotti, modificabili e sincronizzati; esportazione SRT, VTT, ASS o incorporamento nel video.
- OCR e traduzione delle scritte visibili nel video, con sostituzione grafica quando possibile e correzione manuale; segnalare testi animati/coperti non ricostruibili.
- Localizzazione RTL per arabo: shaping, punteggiatura, numeri e layout verificati.
- Riassunti, highlight e clip brevi per ciascuna lingua.
- Traduzione di lezioni/corsi, capitoli, glossari e materiali associati.
- Trascrizione completa con timestamp e speaker label.
- Pulizia audio, riduzione rumore, silenzi configurabili, bilanciamento voce/musica e controllo clipping.

### 7.4 Localizzazione MultiSocial
Da un master produrre varianti per lingua e piattaforma: verticale/quadrato/orizzontale, ritaglio intelligente, safe area, durata, ritmo, copertine, titoli, descrizioni, doppiaggio o sottotitoli. Esportazione multipla/ZIP e collegamento master-derivati per aggiornamenti selettivi. Pubblicazione diretta solo tramite API ufficiali e autorizzate, sempre con approvazione esplicita; altrimenti share sheet.

### 7.5 Generazione video e avatar (riferimento Vidnoz)
- Script-to-Video: testo/brief in storyboard, scene, media, narrazione, musica con licenza e montaggio proposto.
- Avatar Studio: avatar predefiniti/personalizzati, presentatori virtuali, sfondi e layout.
- Talking Photo: animazione parlante di foto con diritti e consenso verificati.
- Document-to-Video: trasformazione guidata di documenti/presentazioni in video, con tracciabilità delle fonti.
- AdCreator: campagne, cataloghi e annunci localizzati, controllo delle affermazioni e dei diritti.
- Template e brand kit: loghi, colori, font e modelli con licenze tracciate.

### 7.6 Innovazioni distintive già discusse
- Regista IA/SmartDirector: storyboard narrativo, ordine scene, ritmo e stile in base all'obiettivo.
- VideoDoctor Evolution: diagnosi assistita di sfocatura, tremolio, esposizione, rumore, audio e continuità.
- Privacy Director: rilevamento e oscuramento selettivo di volti, targhe, documenti, indirizzi e dati sensibili.
- CreativeMemory: preferenze creative controllabili, esportabili e cancellabili dall'utente.
- SmartCamera Director: sincronizzazione multi-camera e proposta dell'inquadratura migliore.
- VoiceEdit: comandi vocali/testuali per la timeline, anteprima e conferma per azioni distruttive.
- TeamStudio: commenti, revisioni, versioni, ruoli e approvazioni, dopo isolamento multiutente.
- MemoryRestorer: restauro foto/video con confronto non distruttivo.
- AdCreator: contenuti e campagne commerciali.

### 7.7 Architettura, sicurezza e criteri di completamento
- Modello dati per master, varianti lingua, segmenti temporali, speaker, tracce audio, sottotitoli, job e output.
- Provider intercambiabili per ASR, traduzione, TTS, lip-sync, OCR e generazione; chiavi solo server-side, HTTPS.
- Job asincroni con progressi per lingua, retry limitati, idempotenza, cancellazione, ripresa e pulizia temporanei.
- Preventivo di minuti/crediti/costi, quote per piano, rate limiting e limiti anti-abuso; Premium omaggio non elimina i costi infrastrutturali.
- Consenso per upload cloud, retention chiara, cancellazione e controllo accessi; verifica diritti su voce, volto, musica, immagini, documenti e marchi.
- Test con rumore, accenti, speaker sovrapposti, video lunghi, frame rate variabile, testi animati, arabo RTL, provider indisponibile e fallimenti parziali.
- Revisione umana prima di applicare traduzioni, avatar, lip-sync o pubblicare; nessuna pubblicazione automatica.
- Completamento solo dopo test automatizzati, prove con provider reali autorizzati, valutazione linguistica, test dispositivi e misurazione di costo/tempo. Mock e demo non equivalgono a provider reale.

### 7.8 Priorità
1. Fondazioni: autenticazione/ownership, media storage, job queue, quote, preventivo costi, cancellazione e privacy.
2. Trascrizione, sottotitoli e traduzione con timestamp.
3. Doppiaggio multilingue e batch di file separati.
4. Diarizzazione, glossari, gestione voci e qualità audio.
5. OCR/sostituzione testi e RTL arabo.
6. Lip-sync e clonazione vocale autorizzata.
7. MultiSocial localizzato, riassunti e clip brevi.
8. Script-to-Video, Avatar Studio, Talking Photo e Document-to-Video.
9. Collaborazione e campagne avanzate.

Le nuove attività ampliano il lavoro residuo e non aumentano automaticamente la percentuale completata. Mantenere branch della PR draft; non modificare `main`, non unire la PR e non creare l'APK prima della fase 6.


## 10. Matrice di confronto competitiva e copertura effettiva

La matrice seguente confronta categorie funzionali documentate nei prodotti concorrenti (CapCut, Adobe Premiere, DaVinci Resolve e strumenti specializzati di editing/repurposing). È una guida di prodotto, non una certificazione delle versioni o dei piani: disponibilità, limiti e nomi cambiano per piattaforma, regione e abbonamento. Le fonti consultate includono confronti aggiornati nel 2026 e documentazione dei produttori. Le voci del nostro prodotto sono valutate rispetto all'audit del codice del branch, non rispetto a questa roadmap.

Legenda:
- **Presente (base)**: esiste una parte utilizzabile nel codice attuale.
- **Parziale**: esiste solo una parte del flusso o manca una verifica end-to-end.
- **Assente / pianificato**: non risulta implementato nell'audit.
- **Da verificare**: non è possibile dichiarare copertura senza test dedicati.

| Area funzionale | Presenza nei concorrenti (esempi) | Stato nel progetto secondo audit | Requisito di completamento |
|---|---|---|---|
| Timeline multitraccia e taglio/split/riordino clip | CapCut, Premiere, Resolve | **Presente (base)** | Test UI e round-trip progetto su Android/iOS/desktop; undo/redo e grandi timeline |
| Keyframe per posizione, scala, opacità, audio ed effetti | CapCut, Premiere, Resolve | **Da verificare / pianificato** | Editor keyframe con interpolazione, easing, persistenza e test frame-accurate |
| Speed ramp / curve di velocità | CapCut, Premiere, Resolve | **Parziale / da verificare** | Curve per clip, audio pitch policy, preview e rendering coerente |
| Transizioni ed effetti | Tutti | **Presente (base)** | Catalogo, parametri, preset, compatibilità e test render per transizione |
| Chroma key e rimozione sfondo | CapCut, Premiere, Resolve | **Assente / pianificato** | Keying controllabile, edge refinement, spill suppression e fallback |
| Maschere e tracking oggetti/volti | Premiere, Resolve, CapCut (strumenti variabili per piattaforma) | **Assente / pianificato** | Mask editor, tracking temporale, perdita target e correzione manuale |
| Stabilizzazione video | Premiere, Resolve e app mobile | **Assente / pianificato** | Analisi movimento, crop configurabile, confronto prima/dopo e test rolling shutter |
| Rilevamento scene e clip automatiche | Premiere, Resolve e strumenti AI | **Assente / pianificato** | Scene boundary, soglie configurabili e falsi positivi misurati |
| Editing basato su trascrizione e rimozione silenzi | Descript, Premiere/Resolve con funzioni specifiche | **Assente / pianificato** | ASR con parole/timestamp, selezione testo→timeline, undo e gestione diarizzazione |
| Sottotitoli automatici, traduzione e stili | CapCut, Premiere, Descript e altri | **Assente nel flusso completo** | ASR, editor sottotitoli, traduzione, SRT/VTT/ASS, RTL e controllo sincronizzazione |
| Doppiaggio, TTS, isolamento voce e pulizia rumore | CapCut, Premiere, Resolve, Descript | **Assente / pianificato** | Pipeline ASR/TTS, separazione sorgenti, denoise, consenso e confronto qualità |
| Rilevamento beat e sincronizzazione musica | CapCut, Resolve e strumenti social | **Assente / pianificato** | Beat markers, snap clip, gestione licenze e test su generi/tempi differenti |
| Color grading avanzato, LUT e HDR | Premiere, Resolve | **Parziale / da verificare** | Ruote/curve, LUT, scopes, color management, HDR export verificato |
| Auto Reframe e safe area multi-formato | CapCut, Premiere, altri social editor | **Assente / pianificato** | Tracking soggetto, keyframe override, 9:16/1:1/16:9 e safe-area overlay |
| Ricerca semantica in libreria media | Premiere, Resolve e strumenti AI | **Assente / pianificato** | Indici locali/opt-in, ricerca per oggetti/scene/parole e cancellazione indice |
| Estensione generativa di clip e generazione video | Premiere/Firefly e servizi generativi | **Assente / pianificato** | Provider configurabile, provenienza output, costo stimato e revisione umana |
| Multicam e sincronizzazione sorgenti | Premiere, Resolve | **Assente / pianificato** | Sync audio/timecode, switching, fallback manuale e test drift |
| Proxy e gestione media pesanti | Premiere, Resolve | **Assente / da verificare** | Generazione proxy, relink affidabile, cache e test storage insufficiente |
| Backup/sync cloud e collaborazione | Premiere/Frame.io, Resolve cloud, strumenti team | **Parziale** | Isolamento account, sync conflitti, versioni, inviti, commenti e revoca |
| Export MP4/MOV/AVI/WebM e pipeline server | Editor desktop e servizi online | **Presente lato backend (base)** | Test codec/container reali, compatibilità player, profili e round-trip su device |
| Export 4K/HDR/codec professionali | Premiere, Resolve e alcuni editor social | **Da verificare** | Matrice codec/device, memoria, fps, HDR metadata e test file risultanti |
| Template, asset, brand kit e contenuti social | CapCut, Adobe e piattaforme marketing | **Parziale / pianificato** | Libreria licenze, brand kit, preset localizzati e aggiornamento senza rompere progetti |
| Collaborazione con commenti timecode e approvazioni | Frame.io e piattaforme team | **Pianificato** | TeamStudio dopo isolamento utenti; permessi, audit e test concorrenza |
| Video da testo, avatar e presentatori virtuali | Vidnoz e servizi AI video | **Assente / pianificato** | Script/storyboard, avatar autorizzati, voce, sottotitoli e disclosure sintetico |

### 10.1 Cinque direzioni distintive del prodotto

Non si può garantire che un'idea non sia mai stata realizzata da nessuno. Queste sono proposte di differenziazione attraverso combinazioni e workflow integrati, da validare con utenti e prototipi:

1. **Regista IA con piano spiegabile**: analizza obiettivo, durata, pubblico e media; presenta storyboard, motivazioni dei tagli e piano modificabile prima di applicarlo. Deve mostrare alternative e consentire di bloccare clip o momenti.
2. **VideoDoctor preventivo e riparazione guidata**: controlla qualità tecnica e narrativa prima dell'export; propone interventi con impatto stimato, senza alterare l'originale e con report verificabile.
3. **MultiSocial Universe**: da una timeline master crea versioni per piattaforma, lingua, aspect ratio e durata; mantiene un collegamento tra versioni e segnala cosa è stato adattato.
4. **Privacy Director**: prima di esportare o condividere individua volti, targhe, documenti, coordinate e dati personali; propone blur/redaction e rimozione metadati, con revisione frame-by-frame. Non sostituisce SafeMedia: aggiunge una verifica contestuale del contenuto.
5. **CreativeMemory + Universal Voice**: memorizza solo preferenze creative autorizzate e consente di impartire comandi vocali/testuali per montare, tradurre, correggere e riutilizzare stili; ogni modifica è anteprimabile e annullabile.

### 10.2 Funzioni da esplicitare e non lasciare implicite

- **SmartCamera Director**: assistente alla ripresa, distinto dall'editor. Guida in tempo reale (quando i sistemi lo consentono) su inquadratura, luce, stabilità, orientamento, spazio audio e durata; fornisce checklist e suggerimenti, non registra né carica senza consenso.
- **Privacy Director**: estensione di SafeMedia con rilevamento contestuale e redazione nel video, non solo rimozione metadati.
- **Universal Voice**: ampliare VoiceStudio a input vocale, doppiaggio multi-speaker, dizionario di pronuncia, glossari, voice-over e comandi di editing. Clonazione solo con consenso verificabile e policy anti-impersonificazione.
- **MultiTraduzione batch**: un job per lingua collegato a un job gruppo; file distinti per lingua, ZIP, retry/cancel per singola lingua, glossario, revisione e stato indipendente.
- **Text-based editing**, **beat detection**, **stabilizzazione**, **tracking/mask**, **keyframe/speed curves**, **proxy**, **multicam**, **semantic search** e **LUT/HDR** devono avere ticket e criteri propri, non essere considerati coperti da un generico “editor IA”.

### 10.3 Criteri di accettazione trasversali

Una funzione entra nello stato “completata” solo se:
- è raggiungibile da un flusso UI reale e non solo da un modello/API isolato;
- gestisce input invalidi, annullamento, timeout, rete assente e ripresa quando prevista;
- salva stato e risultati in modo coerente, senza perdere l'originale;
- applica autorizzazioni lato server e isolamento account per ogni asset/job/output cloud;
- espone limiti, stima costi e consenso prima dell'elaborazione remota;
- ha unit, integration, security e regression test automatizzati;
- è verificata su piattaforme dichiarate supportate e con media di test rappresentativi;
- documenta provider, licenze, lingue, limiti e qualità attesa.

### 10.4 Priorità operative e gate

**P0 — prima di ampliare i servizi cloud**
- autenticazione individuale e isolamento account end-to-end;
- storage/job ownership, quote, idempotenza, cancellazione e recovery;
- configurazione provider server-side, secret management, audit e rate limiting;
- coda durevole con resume/retry e pulizia dei file temporanei.

**P1 — valore immediato e rischio controllabile**
- SmartCamera Director (prima versione come guida/checklist);
- VideoDoctor base e Privacy Director;
- sottotitoli/trascrizione e MultiTraduzione batch con provider selezionabile;
- Auto Reframe e preset MultiSocial.

**P2 — editor creativo avanzato**
- keyframe e speed curves, maschere/tracking, stabilizzazione, beat detection;
- editing da trascrizione, pulizia audio e semantic media search;
- proxy e multicam.

**P3 — elaborazioni generative e collaborazione**
- avatar/presentatori, text/document-to-video, PhotoMotion, ReLight IA e MemoryRestorer;
- TeamStudio e AdCreator dopo i gate di sicurezza, licenze e costi.

I livelli indicano priorità, non date o completamento. Una funzione cloud ad alto costo non va attivata in produzione finché preventivo, quote, cancellazione, privacy e provider fallback non superano i test.

---

## 11. Pacchetto approvato — Universal Creative Studio IA (8 novembre 2026)

> **Stato di tutte le voci di questa sezione: REQUISITO APPROVATO / PIANIFICATO.**
> L'inclusione in roadmap non dimostra implementazione, disponibilità di provider, qualità garantita o attivazione in produzione. Le funzioni già presenti mantengono lo stato assegnato nell'audit tecnico; nessuna voce cambia automaticamente stato per effetto di questo addendum.

### 11.1 Visione di prodotto

L'obiettivo è un ambiente creativo multimodale in cui l'utente descrive il risultato con testo, voce, immagini, video o documenti e un agente coordina strumenti fotografici, video, audio, grafici e di distribuzione. Il sistema deve trasformare richieste complesse in piani espliciti, eseguibili per passi, verificabili e annullabili. Non si promette che ogni richiesta sia sempre realizzabile: capacità mancanti, limiti dei modelli, diritti, costi, hardware e dati insufficienti devono essere dichiarati prima dell'esecuzione.

### 11.2 MagicIA Brain e Universal Creative Agent

| Requisito approvato | Specifica da realizzare | Dipendenze e gate |
|---|---|---|
| **MagicIA Brain** | Livello centrale di comprensione multimodale, intent detection, pianificazione, memoria di contesto del progetto e coordinamento dei tool. | Contratti API versionati, catalogo capability, autenticazione/ownership, provider adapter, osservabilità. |
| **Universal Creative Agent** | Scompone richieste articolate in un grafo di attività con input/output tipizzati, dipendenze, stato, progressi, retry e risultati parziali. | Job orchestrator durevole; non deve eseguire codice arbitrario né accedere a risorse non autorizzate. |
| **Selezione automatica modelli** | Router per capacità, qualità attesa, costo stimato, latenza, regione, licenza, privacy e disponibilità; fallback controllato. | Registro provider/modelli con capability dichiarate e health check; segreti solo server-side; test contrattuali e sandbox. |
| **Quality Guarantee Engine** | Verifiche tecniche e semantiche specifiche per tipo di output, soglie configurabili, correzioni consentite e nuovo controllo. | Suite di validator per immagini, video, audio, sottotitoli e pacchetti; report con controlli superati/non verificabili. Non promettere perfezione assoluta. |
| **Creative Memory / Creative DNA** | Preferenze di stile, preset e decisioni che l'utente sceglie di conservare; applicazione suggerita ai progetti futuri. | Memoria opt-in, consultabile, modificabile, esportabile e cancellabile; separazione per account e dispositivo; nessun uso per training senza consenso. |
| **Modalità Fai tutto tu** | Esecuzione end-to-end di un piano approvato, con anteprima, checkpoint, undo e conferma prima di operazioni esterne o irreversibili. | Agent orchestration, quote/costo, job recovery, permessi granulari e audit. |
| **Modalità apprendimento** | Spiegazioni contestuali, tutorial guidati e possibilità di eseguire insieme all'utente. | Tutorial versionati, accessibilità, telemetria opt-in e nessun blocco del flusso editor. |

### 11.3 Fotografia e immagini

| Requisito approvato | Funzioni comprese | Criteri minimi |
|---|---|---|
| Restauro e colorizzazione | Denoise, deblur, scratch/damage repair, recupero dettagli, colorizzazione B/N, upscaling e correzione artefatti. | Originale preservato; confronto prima/dopo; test su scansioni, volti, testo e immagini degradate; dichiarare ricostruzioni sintetiche. |
| Ritocco e generazione | Ritratto, pelle, luce, compositing, generazione da testo e immagini di riferimento. | Maschere modificabili, consistenza, controllo artefatti, provenienza e limiti del modello. |
| Rimozione/sostituzione oggetti | Selezione manuale o assistita, inpainting, outpainting, riempimento e sostituzione sfondo/oggetto. | Maschere e risultato revisionabili; nessuna modifica distruttiva dell'originale; test su occlusioni e bordi. |
| Sfondi, luce e prospettiva | Segmentazione soggetto, relighting, correzione prospettica e geometrica, sfocatura e scenari. | Coerenza ombre/riflessi e bordi; fallback locale/cloud; test su soggetti complessi. |
| Generazione testo/immagine | Text-to-image, image-to-image, varianti, riferimenti, stili e composizioni. | Provider e licenze verificati, disclosure contenuto generato, filtri di sicurezza e stima costo. |
| Foto parlanti e animazione | Photo-to-video, animazione ritratto, voce e movimenti facciali autorizzati. | Consenso verificabile della persona/diritti; etichettatura sintetico; anti-impersonificazione e cancellazione media. |
| Profondità e 3D | Stima profondità, parallax, camera motion e ricostruzione 3D approssimata da immagini multiple. | Dichiarare limiti geometrici; controlli su occlusioni e artefatti; export in formati supportati. |
| Photo Match e archivio | Duplicati/simili, raggruppamento per evento, soggetto e contenuto, ricerca semantica e uniformazione stile. | Indice cancellabile e isolato per account; elaborazione locale ove possibile; indicizzazione remota solo opt-in. |

### 11.4 Video e montaggio

| Requisito approvato | Funzioni comprese | Criteri minimi |
|---|---|---|
| MagicIAedit evoluto | Analisi multimodale più ampia, piano timeline, selezione momenti e proposte modificabili. | Separare piano, applicazione e rendering; supportare preview, undo, cancel e verifica output. |
| Regista IA / montaggio automatico | Storyboard, ritmo, inquadrature, ordine scene, transizioni, musica e varianti per obiettivo/durata. | Motivazioni e alternative visibili; clip bloccabili; timeline valida e sempre modificabile. |
| Generazione testo/immagine/video | Generazione clip e scene, image-to-video, estensione e raccordi generativi. | Provider reale testato, costi/quote, licenze, provenance e limiti durata/risoluzione. |
| Modifica generativa scene | Rimozione/sostituzione elementi, sfondi, condizioni ambientali e riempimento temporale. | Coerenza tra frame, controllo flicker e tracking; confronto con originale e disclosure. |
| Tracking, maschere e rotoscoping | Tracking soggetti/oggetti, maschere temporali, keying e correzione manuale. | Test perdita target, occlusioni, motion blur e correzione frame-by-frame. |
| Stabilizzazione e miglioramento | Stabilizzazione, denoise, deblur, upscaling, frame interpolation e correzione colore. | Test rolling shutter, flicker, frame rate variabile, audio sync e limiti device/GPU. |
| Montaggio da trascrizione | ASR con parole/timestamp, rimozione frasi/silenzi e collegamento testo-timeline. | Timestamp verificabili, diarizzazione opzionale, undo e revisione trascrizione. |
| Multicamera e musica | Sync per audio/timecode, switching multicamera, beat detection e allineamento clip. | Gestione drift, sorgenti mancanti, licenze musicali e fallback manuale. |
| StoryMemory e ricerca | Ricerca semantica di momenti e raggruppamento narrativo di ricordi/eventi. | Indici opt-in, filtri e cancellazione; non dedurre identità o relazioni non verificate. |
| VideoDoctor | Diagnostica tecnica/narrativa, audio, frame, sottotitoli, aspect ratio e compatibilità export. | Report ripetibile con severità, falsi positivi e controlli non verificabili; riparazione solo su copia. |

### 11.5 Voce, audio e lingue

- Riconoscimento vocale, rilevamento lingua, timestamp e diarizzazione multi-speaker.
- Traduzione in più lingue in un singolo batch, con glossari, nomi propri, tono e revisione umana.
- Doppiaggio/TTS, voci selezionabili, dizionari di pronuncia e voice-over.
- Clonazione o imitazione vocale soltanto con consenso verificabile, diritti e protezioni anti-impersonificazione.
- Lip-sync e adattamento temporale del parlato, ove supportati dal provider.
- Pulizia rumore/vento/riverbero, separazione voce/musica/effetti e mix automatico.
- Musica ed effetti sonori generati o selezionati esclusivamente con licenza/diritti verificati.
- Sottotitoli SRT/VTT/ASS, editor sincronizzato, descrizione audio e accessibilità.
- Un output distinto per lingua, più eventuale ZIP, con stato, retry, cancel e download indipendenti per lingua.
- Supporto RTL e shaping arabo nei sottotitoli e nel rendering, verificato con fixture linguistiche reali.

**Gate comune:** pipeline ASR → revisione trascrizione → traduzione → revisione → TTS/doppiaggio → sincronizzazione → rendering per lingua → QA. Nessun job batch deve essere conteggiato o recuperato come se fosse un singolo render indivisibile.

### 11.6 Creatività, lavoro e distribuzione

- **MultiSocial Universe:** timeline master e varianti per piattaforma, rapporto d'aspetto, durata, safe area, lingua, sottotitoli, copertina e metadati.
- **AdCreator:** spot, annunci, storyboard, copy, voice-over e varianti; controllo delle affermazioni commerciali non supportate.
- **E-commerce:** fotografie prodotto, cataloghi, mockup, schede e video dimostrativi.
- **Documenti in video:** PDF, slide e documenti trasformati in storyboard, narrazione e clip, rispettando i diritti dei contenuti.
- **Brand kit e template:** loghi, colori, font, preset e librerie con licenze/attribuzioni verificabili.
- **TeamStudio:** collaborazione, ruoli, commenti timecode, revisioni, approvazioni e conflitti; subordinato a isolamento account e storage autorizzato.
- **Export professionale:** profili container/codec, risoluzioni, frame rate, bitrate, audio, sottotitoli e metadati; supporto dichiarato solo dopo test su file e device.
- **Condivisione assistita:** share sheet o API ufficiali; conferma esplicita prima di pubblicare e nessuna memorizzazione non necessaria di credenziali social.

### 11.7 Innovazione, sicurezza e affidabilità

- **Privacy Director:** rilevamento assistito di volti, targhe, documenti, indirizzi e dati sensibili; blur/redaction e revisione prima dell'export.
- **Creative DNA:** profili creativi separati dai contenuti media, opt-in e pieno controllo dell'utente.
- **Auto-Recovery Engine:** autosave, versioni, checkpoint dei job, retry idempotenti, recupero dopo crash/riavvio e ripristino senza sovrascrivere copie valide.
- **Versioning e backup:** cronologia, backup cifrati, retention, restore verificato e gestione storage.
- **Cost & Quality Optimizer:** stima prima dell'elaborazione di costo, durata, qualità, consumo e alternative; blocco/consenso oltre budget impostato.
- **Copyright e consenso:** provenienza asset, licenze musica/font/template/modelli, consenso per volto/voce e registro delle autorizzazioni necessarie.
- **Accessibilità:** sottotitoli, descrizione audio, contrasto, navigazione accessibile, controlli vocali e localizzazione.
- **Offline compatibile:** editor base, cache, preset, strumenti locali e coda differita; indicare chiaramente quali funzioni richiedono rete/provider.
- **SmartDevice / SmartShield:** adattamento a memoria, storage, codec e capacità del dispositivo; degradazione progressiva e protezione da crash/thermal pressure quando i segnali sono disponibili.

### 11.8 Nuove combinazioni differenzianti da prototipare

Queste idee sono proposte di prodotto da validare, non affermazioni di novità assoluta sul mercato:

1. **Creative Intent Compiler:** converte una richiesta libera in un piano strutturato, con obiettivi, vincoli, asset, operazioni, costo stimato e test di accettazione.
2. **Continuity Guardian:** controlla coerenza tra scene di personaggi, abiti, oggetti, colori, luce e ambientazione; segnala differenze senza correggerle automaticamente senza consenso.
3. **Narrative Repair:** identifica passaggi poco chiari, salti temporali e raccordi mancanti; propone soluzioni e mostra il motivo.
4. **Universal Project Portability:** esporta progetto, media collegati, font/licenze e manifest dei provider in un pacchetto portabile, con verifica dei riferimenti e possibilità di riaprire il progetto su un altro dispositivo.
5. **Creative Simulation Preview:** genera una preview a bassa qualità e stima tempi/costi/spazio prima del rendering completo.
6. **Trust & Provenance Ledger:** registra localmente o nel progetto le trasformazioni, gli asset generati, i provider e le licenze dichiarate, senza esporre segreti o dati privati.
7. **Accessibility Twin:** crea in parallelo versioni accessibili del progetto (sottotitoli, descrizione audio, testo leggibile e lingua semplificata), collegate alla timeline master.
8. **Intent-to-Outcome Test:** prima di esportare, confronta il risultato con l'obiettivo dichiarato dall'utente e segnala requisiti soddisfatti, parziali o non verificabili.

### 11.9 Architettura modulare e contratti obbligatori

Ogni capability deve registrare: identificatore/versione, input e output tipizzati, piattaforme, provider/modello, modalità locale/cloud, requisiti di consenso, licenza, limiti, costo stimato, timeout, retry policy, cancellazione, retention, fallback e test. MagicIA Brain può invocare soltanto capability registrate e autorizzate.

L'orchestratore deve usare job e sotto-job durevoli, lease dei worker, idempotenza per fase, checkpoint, retry selettivo, cancellazione cooperativa e isolamento per account. I risultati intermedi devono essere riutilizzabili senza rielaborare tutto il progetto. Le operazioni distruttive, pubblicazioni, condivisioni, clonazioni vocali e upload remoti richiedono conferma/consenso esplicito.

### 11.10 Sequenza incrementale e protezione della fase APK

1. **Fondazioni P0:** sicurezza account/asset/job, recovery durevole, quote, idempotenza, rate limit, secret management, cancellazione e audit. Non ampliare i provider cloud prima di questo gate.
2. **Fondazioni IA P1:** capability registry, contratti versionati, router provider, planner/validator e job orchestrator; prima versione di MagicIA Brain senza dichiarare autonomia illimitata.
3. **Valore locale P2:** VideoDoctor tecnico, Photo Match locale, preset MultiSocial, accessibilità e Auto-Recovery per funzioni compatibili senza dipendenza cloud.
4. **Provider P3:** selezione e prova di provider immagine/video/ASR/TTS/traduzione; sandbox, test contrattuali, privacy, licenze, costi e fallback.
5. **Workflow P4:** Regista IA, batch multi-lingua, generazione/ritocco, audio, AdCreator, TeamStudio e funzioni generative in moduli separati.
6. **QA e release gate:** test unitari, integrazione, sicurezza, carico, regressione, dispositivi reali e verifica dei costi; solo dopo i gate si autorizza la fase 6.
7. **Fase 6:** build APK release, firma configurata in modo sicuro, installazione e smoke test su dispositivo; nessuna build APK prima di questa fase.

Ogni incremento deve mantenere main intatto, lavorare sul branch feature e usare aggiornamenti non-forzati con expected SHA. Se una funzione nuova rompe test o stabilità, il modulo viene isolato/disattivato o corretto prima di proseguire; non si riduce artificialmente la percentuale delle parti già verificate e non si aumenta la percentuale per requisiti solo pianificati.

### 11.11 Definizione di “completata”

Una capability è “completata” solo quando esiste un flusso UI/API reale, il provider o il motore locale è effettivamente configurato, input/output sono verificati, autorizzazioni e consenso sono testati, cancellazione/timeout/fallback funzionano, test automatici passano, il risultato è collaudato su media rappresentativi e limiti/costi/licenze sono documentati. In caso contrario lo stato resta **pianificata**, **parziale**, **bloccata da provider/configurazione** o **non verificata**.

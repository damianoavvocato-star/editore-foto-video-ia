# Audit funzionale e tecnico — 8 novembre 2026

> Audit statico del branch `feature/magiciaedit-cloud-foundation`. Le etichette descrivono ciò che è riscontrabile nel codice esaminato; non equivalgono a una certificazione su dispositivi reali o con provider cloud reali.

## Esito sintetico

Il progetto possiede già una base reale di editor, timeline, rendering backend FFmpeg, account e controlli di utilizzo. Non è corretto descriverlo come una semplice interfaccia o come un progetto privo di motore multimediale.

La nuova suite Universal Video Studio IA, invece, è pianificata ma non implementata. In particolare, non esiste ancora una pipeline end-to-end di trascrizione, traduzione, doppiaggio e generazione di file distinti per lingua. Non è stato trovato un provider ASR/traduzione/TTS/lip-sync configurato.

## Matrice verificata

| Area | Stato | Evidenza e limiti |
|---|---|---|
| Modello progetto e timeline multitraccia | PARZIALE/BASE PRESENTE | `EditorProject`, `EditorTrack`, `EditorClip`; timeline selezionabile e playhead. La UI della timeline non dimostra da sola un editor completo con tutte le funzioni professionali. |
| Operazioni di montaggio | PRESENTE A LIVELLO MODELLO | Operazioni pure per spostamento, taglio, divisione, duplicazione, eliminazione, velocità e transizioni; verificare ergonomia e anteprima su dispositivo. |
| Rendering video server | PRESENTE | Backend FFmpeg genera segmenti, concatena/transizioni, applica trasformazioni, audio, overlay e testo, produce output scaricabile. Non è un renderer locale Flutter. |
| Formati di esportazione | PARZIALE/PRESENTE | Backend accetta MP4, MOV, AVI e WebM con codec mappati; qualità e compatibilità vanno testate con file reali e dispositivi/piattaforme di destinazione. |
| Audio su timeline | PRESENTE A LIVELLO BACKEND | Mix di tracce audio, volume, fade e ritardo; non equivale a pulizia vocale IA o separazione voce/musica. |
| Overlay e testo | PRESENTE, LIMITATO | Overlay immagine/video/testo. Il rendering usa un font DejaVu predefinito: shaping, impaginazione e direzione RTL dell'arabo richiedono un lavoro specifico e test dedicati. |
| UI multilingue | PARZIALE | La timeline contiene stringhe per italiano, inglese, francese, spagnolo e arabo. Non è prova di localizzazione completa di tutta l'app. |
| MagicIAedit | PARZIALE | Il backend campiona pochi fotogrammi video e immagini e chiede a un provider compatibile un piano JSON di montaggio. Non esegue montaggio/rendering finale autonomo, analisi completa del parlato o comprensione audio. |
| Provider MagicIAedit | NON CONFIGURATO/DA VERIFICARE | Il codice richiede MAGICIA_API_BASE_URL, MAGICIA_API_KEY e MAGICIA_MODEL; l'health check espone se la configurazione esiste, ma non è stata verificata una chiamata riuscita a un provider reale. |
| Traduzione video/ASR | ASSENTE | Nessuna pipeline verificata per speech-to-text, rilevamento lingua, traduzione segmentata o timestamp parlati. |
| Doppiaggio/TTS e clonazione vocale | ASSENTE | Nessuna pipeline TTS/voice cloning verificata; consenso e diritti dovranno essere implementati prima di abilitare la funzione. |
| Diarizzazione multi-speaker | ASSENTE | Non è presente un servizio verificato di separazione/attribuzione dei turni vocali. |
| Lip-sync | ASSENTE | Nessun servizio o modello di sincronizzazione labiale verificato. |
| OCR e traduzione del testo nel video | ASSENTE | Non è presente una pipeline OCR temporale con ricostruzione/sostituzione del testo. |
| Batch multi-lingua (20+) | ASSENTE | Il backend AI attuale accetta solo MagicIAedit e fino a 20 asset per richiesta; non accetta una lista di lingue né crea output per lingua. Il limite asset non è un limite o supporto di traduzione. |
| Job e quote | PRESENTE, NON SUFFICIENTE PER BATCH | Job persistenti, ownership e quote mensili esistono. I worker attivi al riavvio vengono marcati falliti: la ripresa effettiva del lavoro non è implementata. |
| Sicurezza account/media | BASE PRESENTE | Sessioni account, ownership risorse, autorizzazioni, audit e quote sono presenti; l'estensione a batch e storage derivati deve mantenere isolamento per proprietario. |
| Avatar, talking photo, script/document-to-video | ASSENTE | Presenti solo come requisiti di roadmap, non come flussi operativi. |

## Rilievi tecnici prioritari

1. **Non confondere il render con il doppiaggio.** Il renderer FFmpeg può già comporre tracce audio e video; manca il livello che produce audio tradotto, sottotitoli e sincronizzazione.
2. **Il limite attuale del backend AI è specifico di MagicIAedit.** `POST /v1/ai/jobs` rifiuta task diversi da MagicIAedit; `RemoteAiBackend` invia un singolo job AI. Occorre introdurre un dominio separato per localizzazione e batch, senza sovraccaricare MagicIAedit.
3. **La coda attuale non riprende i job dopo un riavvio.** `JobRegistry` marca come falliti i job che erano attivi. Per file lunghi e 20+ lingue servirà un worker durevole con lease, retry idempotenti e stato per lingua.
4. **La localizzazione araba non è dimostrata.** La direzione RTL è applicata alla UI della timeline, ma il renderer del testo non dimostra shaping e layout arabo corretti.
5. **La qualità deve essere misurabile.** Servono test con rumore, accenti, sovrapposizione delle voci, musica, video lunghi, frame rate variabile, testi animati e revisione umana.
6. **Provider reali e costi.** Nessun segreto va inserito nel client. Ogni provider deve essere configurato sul server, testato, con preventivo/quote, cancellazione e retention.

## Sequenza di implementazione proposta

### Blocco 1 — fondazione Universal Video Studio
- Contratti dati versionati per sorgente, lingua, segmento temporale, speaker, traccia audio, sottotitoli, variante e output.
- Validazione delle lingue (codici normalizzati, deduplicazione, sorgente esclusa dalle destinazioni, limite configurabile fino ad almeno 20).
- Job batch con uno stato indipendente per lingua: queued, transcribing, translating, synthesizing, rendering, completed, failed, cancelled.
- Isolamento account per batch, asset, output e download.
- Idempotenza, retry per singola lingua, annullamento e pulizia sicura.

### Blocco 2 — prima pipeline utile
- Trascrizione con timestamp e revisione.
- Traduzione con glossario e segmenti sincronizzati.
- Generazione sottotitoli SRT/VTT/ASS.
- TTS/doppiaggio tramite provider configurato.
- Rendering di un file per lingua con mantenimento della musica/ambiente quando tecnicamente possibile.
- Download singolo e archivio ZIP.

### Blocco 3 — funzioni avanzate
- Diarizzazione e voci distinte.
- Clonazione vocale con consenso verificabile.
- Lip-sync, OCR e sostituzione delle scritte.
- Localizzazione RTL, avatar, talking photo e generazione da script/documenti.

### Blocco 4 — collaudo e rilascio
- Test automatici, integrazione provider sandbox e test con provider reale autorizzato.
- Verifiche Android, iOS e desktop su dispositivi e file reali.
- Verifica costi, privacy, sicurezza e cancellazione dei dati.

## Verifica CI e vincoli di progetto

- Ultimo workflow run verificato: [`42473184516`](https://github.com/damianoavvocato-star/editore-foto-video-ia/actions/runs/42473184516), commit `1f5151788f115bf0d6be120f289652785033298c`.
- `backend-test`: SUCCESS — **176 test superati**, con un solo warning di deprecazione Starlette/httpx.
- `flutter-test`: SUCCESS — `flutter analyze` senza problemi e **128 test Flutter superati**.
- `android-preflight`: SUCCESS — `./gradlew --no-daemon help` completato con BUILD SUCCESSFUL; è stata verificata la configurazione Gradle, non compilato un APK.
- `changes`: SUCCESS.
- La job `android-apk` resta intenzionalmente disabilitata fino alla fase 6; nessun APK è stato generato.
- PR #1 resta aperta e non unita; le modifiche restano sul branch `feature/magiciaedit-cloud-foundation`.
- SHA di `main` verificato: `93870b529d2244f4efd4e25a5108ae00375b37ca`; nessuna modifica a `main`.
- Il run ha conclusione complessiva SUCCESS.

## Criterio di avanzamento

Una funzione sarà dichiarata completata solo quando codice, test, gestione degli errori, documentazione e verifica delle dipendenze reali sono presenti. Le voci della roadmap non sono conteggiate come implementazione.


## Aggiornamento Synthesia Studio IA — fondazione iniziale

Nel branch è stato aggiunto un primo livello di codice, distinto dalla roadmap delle funzioni complete:

- backend/studio.py: schema di richiesta provider-neutral, validazione task, massimo 20 lingue, deduplicazione, consenso esplicito per avatar personale e voice cloning, archivio SQLite privato delle bozze.
- backend/server.py: endpoint autenticati per capabilities, creazione/lista/lettura/eliminazione bozze Studio; ownership per account e chiave idempotenza.
- backend/test_studio.py: test di validazione, persistenza, replay idempotente, isolamento utenti e lifecycle API.
- lib/models/studio_job.dart, lib/services/remote_studio_api.dart e lib/studio/synthesia_studio_screen.dart: modello Flutter, client API e schermata raggiungibile dalla sidebar.
- La schermata permette di preparare una bozza da script, selezionare lingue e configurare modalità avatar/voce con consenso.

**Limite dichiarato:** le bozze sono salvate, ma non vengono ancora generate immagini, video, avatar, voci, traduzioni o output. Il backend espone esplicitamente generationAvailable=false e providerState=not_configured. Non è configurato né verificato un provider video reale; documenti/slide, caricamento da CSV, editing di avatar, lip-sync, streaming interattivo e pubblicazione restano da implementare. La sola presenza dei campi di richiesta non equivale a una funzione disponibile.

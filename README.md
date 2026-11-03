# Editore Foto e Video IA — starter

Progetto Flutter iniziale multipiattaforma per Android, iOS, Windows, macOS e Linux (la compatibilità effettiva dipende dai plugin e dall'ambiente di build).

## Cosa contiene questo primo prototipo

- Home studio creativa responsive.
- Selettore file multimediali.
- Anteprima di immagini.
- Riproduzione video locale con `video_player`.
- Zoom interattivo nell'anteprima.
- Menu lingua con italiano, inglese, francese, spagnolo e arabo (layout RTL).
- Punti d'ingresso UI per timeline, effetti, testo, audio, AI, esportazione, inviti e Premium.

## Avvio

1. Installa Flutter SDK e configura Android Studio/Xcode o il toolchain desktop.
2. Estrai il progetto.
3. Dalla cartella del progetto esegui:

```bash
flutter pub get
flutter run
```

Per desktop:
- Windows: `flutter run -d windows`
- macOS: `flutter run -d macos`
- Linux: `flutter run -d linux`

Per iOS è necessario macOS con Xcode. Per Android, configura Android SDK.

## Stato e limiti

Questo è un **prototipo funzionante di base**, non un clone completo di CapCut e non ancora pronto per la pubblicazione.
Il rendering/export, editing non distruttivo, timeline multitraccia, condivisione nativa, account, cloud, IA generativa, pagamenti e referral sono punti di sviluppo successivi. I pulsanti non ancora implementati mostrano messaggi informativi, per non fingere funzioni che non esistono.

## Architettura raccomandata per la versione completa

- `presentation/`: schermate, editor, timeline, pannelli strumenti.
- `domain/`: modelli progetto, clip, effetti e casi d'uso.
- `data/`: repository locali e cloud.
- `media_engine/`: adapter per rendering nativo/FFmpeg e pipeline export.
- `ai/`: provider IA tramite interfacce, con gestione costi/limiti e consenso.
- `auth/`, `billing/`, `referrals/`, `sharing/`: moduli separati.
- `l10n/`: cataloghi traduzione e supporto RTL.

### Roadmap suggerita

1. Stabilizzare import e preview multipiattaforma.
2. Modello progetto JSON e timeline con clip/tracce.
3. Editing base non distruttivo e rendering MP4.
4. Foto: crop, rotate, adjust, layers, text.
5. Condivisione nativa e formati export aggiuntivi.
6. Account, cloud projects e sincronizzazione.
7. IA: sottotitoli, rimozione sfondo, miglioramento e generazione.
8. Premium, referral e protezione anti-abuso.
9. QA, accessibilità, privacy, licenze e pubblicazione store.


## Step 2 — project model and timeline scaffold

Added:
- `lib/models/editor_project.dart`: serializable project/track/clip data structures.
- `lib/editor/timeline_panel.dart`: initial timeline UI with clip selection and playhead slider.

These modules are deliberately engine-agnostic. The next implementation step is connecting
the timeline to imported media, adding clip trim/move actions, then implementing export.


## Step 3 — non-destructive editing operations

Added `lib/editor/editing_operations.dart` with pure project operations:
- Move clips on a track (negative positions clamp to zero).
- Trim clip duration/start (duration has a one-frame minimum).
- Split a clip at an absolute timeline position.
- Change playback speed (metadata range 0.25x–4x).
- Mute and lock tracks.
- Locked tracks reject editing operations.

Added `test/editing_operations_test.dart` for core timing behavior.
These manipulate timeline metadata only; actual pixel/audio processing and export
require the rendering engine integration in a later phase.

Run checks with:

```bash
flutter test
```

## Passo 5 — pannello impostazioni export

Aggiunto `ExportSettingsPanel`, con selezione di contenitore, risoluzione, codec,
FPS, bitrate e audio. Il widget restituisce ogni modifica via callback. È un
pannello di configurazione, non un encoder: la codifica reale va collegata al
motore di rendering multimediale e validata sui dispositivi target.

## Passo 6 — flusso di esportazione

Aggiunto un contratto `MediaRenderBackend`, `ExportRequest`, progress phases,
validazione della timeline e coordinatore con cancellazione. Il renderer concreto
non è incluso: deve essere implementato tramite una libreria/integrazione nativa
compatibile con i target e i relativi requisiti di licenza. Sono stati aggiunti
test di validazione, non eseguiti in questo ambiente.

## Passo 7 — orchestrazione delle funzioni IA

Aggiunto un contratto provider-indipendente per rimozione sfondo, miglioramento
foto/video, sottotitoli automatici, rilevamento scene e smart crop. La struttura
gestisce stati/progresso/cancellazione dei job e controlla input e ID duplicati.
Non include modelli IA né invia contenuti a un servizio: per questo serve scegliere
un backend reale, definire privacy/consenso e verificare costi e licenze.

## Passo 8 — account, Premium e referral

Aggiunti modelli di entitlement e claim referral, più un contratto backend per
leggere lo stato Premium, creare codici, riscattare inviti e ripristinare acquisti.
Il client non concede mai Premium direttamente. La logica server deve attribuire
un mese di ricompensa a inviter e invitee solo dopo controlli atomici e antifrode,
e integrare gli store mobile per gli acquisti. Backend, login e billing non sono
ancora collegati; test aggiunti ma non eseguiti.

## Passo 9 — schermata Account e Premium

Aggiunta una schermata Flutter presentazionale con stato account, CTA Premium,
ripristino acquisti, codice referral, condivisione e inserimento codice. Le azioni
sono callback fornite dal livello app: autenticazione, store e backend non sono
simulati e vanno collegati a implementazioni reali.

## Passo 10 — localizzazione e condivisione file

Aggiunti testi iniziali IT/EN/FR/ES/AR con fallback inglese e direzione RTL per
l’arabo, oltre a un servizio che verifica il file esportato e delega la condivisione
al sistema operativo. L’implementazione concreta dello share sheet richiede un
plugin nativo e il collegamento della lingua alla MaterialApp. Nessun link app è
inserito automaticamente nel testo di condivisione.

## Passo 11 — libreria progetti

`ProjectStore` ora può elencare e cancellare progetti locali salvati. Aggiunta
una schermata libreria con stato vuoto, elenco, conteggio clip, apertura,
eliminazione e creazione tramite callback. La schermata va collegata al router
e alla directory app-specifica selezionata dal livello applicativo.

## Passo 12 — sessione editor e undo/redo

Aggiunto `EditorSession`, un ChangeNotifier per stato progetto, selezione clip,
playhead, operazioni di spostamento/taglio/split/velocità e cronologia undo/redo
limitata. Test di sessione scritti. Va collegato a TimelinePanel e al widget editor;
gli interventi modificano il modello temporale, non ancora i fotogrammi esportati.


## Passo 13 — Timeline collegata alla sessione

- Aggiunto `SessionTimelineEditor`, che collega selezione clip, playhead, split, durata, velocità e undo/redo a `EditorSession`.
- Il widget notifica il progetto aggiornato al genitore tramite `onProjectChanged`, così l'app può salvarlo con `ProjectStore`.
- Aggiunto `replaceProject` alla sessione per caricare un nuovo progetto azzerando cronologia e selezione.
- Sistemata la selezione durante undo quando la clip selezionata non esiste più.

La timeline è ora un componente integrato a livello di sessione; l'inserimento definitivo nella schermata principale e il rendering/esportazione effettiva dei media restano passaggi successivi. Non è stato possibile eseguire `flutter test` in questo ambiente.


## Passo 14 — Integrazione nella schermata principale e autosalvataggio

- La schermata principale crea una timeline di progetto quando viene importata una foto o un video.
- `SessionTimelineEditor` viene montato nell'editor e le modifiche sono inoltrate al `ProjectStore`.
- Il progetto viene salvato nella directory di supporto dell'app tramite `path_provider`, senza chiedere accesso generale ai file.
- L'esportazione resta esplicitamente non attiva: non viene mostrato un falso completamento.

Nota: l'autosalvataggio è un primo collegamento locale. La riapertura/selezione dei progetti dalla libreria sarà realizzata separatamente; non sono stati eseguiti `flutter pub get`, `flutter analyze` o test in questo ambiente.

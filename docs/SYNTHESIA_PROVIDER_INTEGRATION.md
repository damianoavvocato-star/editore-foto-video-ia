# Synthesia Video API — integrazione controllata

## Fonti ufficiali consultate

- [Video API Quickstart](https://developers.synthesia.io/docs/synthesia-api-quickstart)
- [Create a video](https://developers.synthesia.io/docs/video-api-reference/videos/create-a-video)
- [Retrieve a video](https://developers.synthesia.io/docs/video-api-reference/videos/retrieve-a-video)
- [Video API introduction, access and rate limits](https://developers.synthesia.io/docs/video-api-introduction)
- [Webhook events](https://developers.synthesia.io/docs/webhook-events)

## Contratto verificato

- Base URL Video API v2: `https://api.synthesia.io/v2`.
- Creazione: `POST /videos`; il body contiene una lista `input` di clip, ciascuna con script/avatar/background.
- Recupero: `GET /videos/{video_id}`; lo stato può essere `in_progress`, `complete`, `error` o `rejected`.
- Il link MP4 e le caption sono disponibili solo quando il video è completo e il link di download è temporaneo.
- L'API key deve avere scope **Legacy (v2)**. La chiave è mostrata una sola volta da Synthesia e va custodita come segreto server-side.
- La Video API è disponibile sui piani Pro o superiori. I test video sono limitati a 30 al giorno; i costi/crediti e i limiti variano in base al piano.
- I webhook ufficiali documentano gli eventi `video.completed` e `video.failed`.

## Codice consegnato

`backend/studio_provider.py` introduce un adapter HTTP isolato e testabile:
- non effettua chiamate di rete finché non viene invocato;
- richiede credenziale e avatar predefinito configurati lato server;
- invia i video come privati e, per impostazione predefinita, in modalità test con watermark;
- al momento supporta solo script-to-video e avatar-video con uno script;
- consente di interrogare lo stato e restituisce il link temporaneo fornito dal provider;
- non espone la chiave nei messaggi d'errore.

I test usano `httpx.MockTransport`: non consumano crediti Synthesia e non richiedono una chiave reale.

## Non ancora abilitato nell'app

L'adapter non è collegato agli endpoint pubblici di Studio. Prima dell'attivazione servono: segreto configurato nell'ambiente server, verifica del piano/consenso e delle quote, job worker durevole con retry/idempotenza, gestione dei webhook firmati, download sicuro dei file e test sandbox autorizzato. Document-to-video, slide-to-video, localizzazione, clonazione vocale e avatar interattivi non sono implementati da questo adapter.

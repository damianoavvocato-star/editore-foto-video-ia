# Synthesia Video API — integrazione controllata

## Fonti ufficiali consultate

- [Video API Quickstart](https://developers.synthesia.io/docs/synthesia-api-quickstart)
- [Create a video](https://developers.synthesia.io/docs/video-api-reference/videos/create-a-video)
- [Create a video from a template](https://developers.synthesia.io/docs/video-api-reference/videos/create-a-video-from-a-template)
- [Retrieve a video](https://developers.synthesia.io/docs/video-api-reference/videos/retrieve-a-video)
- [Video API introduction, access and rate limits](https://developers.synthesia.io/docs/video-api-introduction)
- [Webhook events](https://developers.synthesia.io/docs/webhook-events)

## Contratto verificato

- Base URL Video API v2: `https://api.synthesia.io/v2`.
- Creazione da script: `POST /videos`; la richiesta include clip con `scriptText`, avatar e background.
- Creazione da template: `POST /videos/fromTemplate`, con `templateId` UUID e `templateData` con chiavi sensibili alle maiuscole/minuscole.
- Recupero: `GET /videos/{video_id}`; stati previsti: `in_progress`, `complete`, `error`, `rejected`. La revisione di moderazione può mantenere lo stato `in_progress` anche dopo il rendering.
- Il link MP4 e le caption sono disponibili quando il video è completo e il link di download è temporaneo.
- L'API key deve avere scope **Legacy (v2)** e va custodita come segreto server-side.
- La Video API è disponibile sui piani Pro o superiori. I test video non consumano quota ma hanno watermark e sono limitati a 30 al giorno.
- I webhook documentano gli eventi `video.completed` e `video.failed`.

## Codice consegnato

`backend/studio_provider.py` fornisce un adapter HTTP isolato:
- legge `SYNTHESIA_API_KEY` e `SYNTHESIA_DEFAULT_AVATAR_ID` solo dall'ambiente server;
- resta in modalità test per impostazione predefinita;
- rifiuta la modalità a pagamento senza il doppio opt-in esplicito `SYNTHESIA_TEST_MODE=false` e `SYNTHESIA_ALLOW_PAID_GENERATION=true`;
- supporta creazione da script/avatar e personalizzazione da template;
- verifica formato UUID e stati del provider;
- mantiene i video privati e non espone la chiave nei messaggi d'errore.

I test usano `httpx.MockTransport`: non consumano crediti Synthesia e non richiedono una chiave reale.

## Non ancora abilitato nell'app

L'adapter non è collegato agli endpoint pubblici di Studio. Prima dell'attivazione servono: segreto configurato nell'ambiente server, verifica di piano/consenso/quote, job worker durevole con retry e idempotenza, gestione autenticata dei webhook, download sicuro dei file e test sandbox autorizzato. Document-to-video, slide-to-video, localizzazione, clonazione vocale e avatar interattivi non sono implementati da questo adapter.

# Backend media — Editore foto e Video IA

## Avvio locale

```bash
python -m venv .venv
. .venv/bin/activate
pip install -r backend/requirements.txt
MEDIA_API_TOKEN='inserire-un-segreto-lungo' uvicorn backend.server:app --host 127.0.0.1 --port 8080

# Solo per prove locali isolate, senza token (mai esporre in rete):
MEDIA_ALLOW_INSECURE_LOCAL=true uvicorn backend.server:app --host 127.0.0.1 --port 8080
```

Installare FFmpeg e ffprobe sul server. `FFMPEG_PATH` e `FFPROBE_PATH` permettono di indicare i binari; `MEDIA_DATA_DIR` indica la directory persistente per asset, lavori e output. `/health` è pubblico e segnala `aiProvider: true` solo quando sono configurate tutte le variabili cloud richieste.

### MagicIAedit cloud

MagicIAedit usa un endpoint vision compatibile con l'API Chat Completions. Configurare **solo sul server** (mai nell'app mobile) le variabili `MAGICIA_API_BASE_URL` (URL HTTPS del provider, senza `/chat/completions`), `MAGICIA_MODEL` e `MAGICIA_API_KEY`. Il servizio invia immagini ridimensionate e fino a tre fotogrammi campionati per ciascun video, quindi valida il piano ricevuto contro gli asset caricati. Le chiavi non vengono restituite dall'API. Limiti attuali della richiesta AI: massimo 20 media, immagini fino a 20 MB ciascuna, video fino a 100 MB ciascuno e 400 MB complessivi. I limiti sono applicati sul server prima dell'inferenza; l'app dovrà inoltre controllare dimensioni e memoria disponibili sul dispositivo prima di caricare i file. Senza tutte e tre le variabili il job risponde 503 e `/health` mantiene `aiProvider: false`. Il provider, il modello, i costi, la conservazione dei dati e i limiti di utilizzo devono essere scelti e verificati prima dell'attivazione pubblica.

## API disponibili

- `GET /health`: stato servizio e disponibilità FFmpeg.
- `POST /v1/assets`: upload di immagini, video e audio consentiti; nome file sostituito con UUID generato dal server; limite upload 1 GiB e rifiuto file vuoti.
- `POST /v1/render/jobs`: avvia un job di rendering.
- `GET /v1/jobs/{job_id}`: stato e progresso del job.
- `DELETE /v1/jobs/{job_id}`: richiede annullamento cooperativo.
- `GET /v1/outputs/{job_id}`: download consentito solo dopo stato `completed`.
- `POST /v1/ai/jobs`: crea un job MagicIAedit con da 1 a 20 `assetIds`; il risultato strutturato è restituito nel campo `result` di `GET /v1/jobs/{job_id}`. Supporta immagini e video (campionamento di fotogrammi).

Per impostazione predefinita, se `MEDIA_API_TOKEN` non è configurato, tutte le route tranne `/health` rifiutano le richieste con HTTP 503 (fail closed). Quando il token è configurato, tutte le route tranne `/health` richiedono `Authorization: Bearer <token>`; il confronto del token usa una funzione constant-time. L'accesso senza token è consentito soltanto con `MEDIA_ALLOW_INSECURE_LOCAL=true`, esclusivamente per prove locali su loopback: non attivare questa opzione su server esposti a Internet. Gli ID job sono validati come UUID esadecimali; output parziali o job non completati non vengono scaricati.

## Rendering attualmente supportato

- Sequenza di clip immagine/video, taglio sorgente (`sourceStartMs`), durata e FPS.
- Transizioni tra clip: fade, wipe, slide, circle e dissolve.
- Tracce audio multiple: offset, durata, trim sorgente, volume, fade-in e fade-out; opzione `includeAudio`.
- Overlay di immagini, video e testo; coordinate, dimensioni, opacità, rotazione e dissolvenze overlay.
- Correzione base di luminosità, contrasto e saturazione; rotazione delle clip.
- Contenitori MP4, MOV, AVI e WebM con scelta codec limitata a H.264, H.265 e VP9 (compatibilità dipende dal contenitore e dalla build FFmpeg).

## Limiti e requisiti prima della produzione

Il renderer è un backend di riferimento e non è ancora collegato e collaudato end-to-end nell'interfaccia Flutter. Il provider cloud MagicIAedit è predisposto ma non è attivo finché le credenziali e il modello non vengono configurati sul server. I job e gli asset sono conservati in memoria/directory locale, senza coda persistente né proprietà per utente. Prima dell'esposizione pubblica servono autenticazione individuale, autorizzazione per asset/job/output, HTTPS, rate limiting, quote, scansione/validazione contenuti, retention e pulizia automatica, coda persistente e test di carico.

## Test

Dalla radice del progetto:

```bash
pytest -q backend
```

I test usano FFmpeg/ffprobe per verificare i file prodotti e TestClient per le API. Alcuni test di rendering sono saltati automaticamente se FFmpeg/ffprobe non sono disponibili.

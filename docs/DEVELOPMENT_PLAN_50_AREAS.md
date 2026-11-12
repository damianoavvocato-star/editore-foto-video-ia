# Piano operativo: 50 aree di lavoro coordinate

Questo piano raggruppa le attività in 10 domini e 50 aree verificabili. Gli elementi indicati come fondazioni non sono considerati funzionalità di produzione finché non risultano collegati, testati e documentati.

## Identità e sicurezza account
1. Hash password scrypt e migrazioni account.
2. Sessioni bearer opache con scadenza e revoca.
3. Rate limit login per account e IP.
4. Cambio password e rotazione obbligatoria delle credenziali temporanee.
5. Reset password monouso con revoca sessioni.
6. 2FA TOTP: enrollment, conferma, login challenge.
7. Cifratura dei segreti 2FA con chiave esterna al database.
8. Codici di recupero monouso e revocabili.
9. Notifiche di accesso sospetto e nuove sessioni.
10. Audit trail con dati sensibili esclusi.

## Ruoli, permessi e console proprietario
11. Ruoli owner/admin/support/collaborator/user.
12. Catalogo permessi centralizzato.
13. Principio del minimo privilegio per ruolo.
14. Override allow/deny per singolo account.
15. Elenco dei permessi effettivi e degli override.
16. Middleware API che applica i permessi server-side.
17. Protezione dell'account proprietario da modifica o sospensione.
18. Console Flutter per elenco e ricerca account.
19. Console Flutter per creazione, modifica e sospensione.
20. Recupero account e reset credenziali dalla console.

## Premium, famiglia e referral
21. Registro persistente delle concessioni Premium.
22. Scadenze, revoche e storico delle concessioni.
23. Piani famiglia con titolare immutabile.
24. Limite posti famiglia configurato sul piano.
25. Invito, rimozione e uscita membri famiglia.
26. Calcolo dell'entitlement individuale e familiare.
27. Collegamento a provider di pagamento e webhook verificati.
28. Rinnovi, cancellazioni, rimborsi e contestazioni.
29. Referral con attribuzione antifrode e premi bilaterali.
30. Controllo costi IA/storage per promozioni e omaggi.

## Editor, timeline e media
31. Importazione media con validazione MIME, estensione e dimensione.
32. Limite e gestione degli ultimi media selezionati.
33. Timeline multitraccia con undo/redo.
34. Operazioni clip e protezione tracce bloccate.
35. Anteprima con zoom e decodifica adattiva.
36. Rendering backend con aspect ratio e pulizia output parziali.
37. Coda export, annullamento e recupero dei job.
38. Preset export e verifica codec/formato.
39. Condivisione sicura e gestione permessi file.
40. Pulizia asset orfani e retention configurabile.

## IA, esperienza, affidabilità e distribuzione
41. MagicIAedit con proposta approvata dall'utente.
42. Limiti, timeout e budget per provider IA.
43. SafeMedia: scansione e isolamento dei contenuti caricati.
44. SmartShield: gestione pressione memoria e degrado controllato.
45. AutoRescue: salvataggio e recupero progetti.
46. Localizzazione completa e RTL arabo.
47. Accessibilità, layout responsive e test device.
48. Telemetria privacy-preserving e diagnostica crash.
49. CI completa: backend, Flutter, analisi, Android preflight e security checks.
50. Fase 6: build APK release, firma, artifact e verifica installazione.

## Regole di avanzamento
- Ogni area passa da pianificata a implementata, testata e verificata; non basta la presenza di un file.
- Le aree che toccano autenticazione, pagamenti o media privati richiedono test negativi e controllo autorizzazioni.
- La build APK rimane bloccata fino alla fase 6.
- Il branch di lavoro resta `feature/magiciaedit-cloud-foundation`; `main` non viene modificato né la PR unita senza autorizzazione esplicita.

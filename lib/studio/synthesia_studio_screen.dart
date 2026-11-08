import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/remote_media_api.dart';
import '../models/studio_job.dart';
import '../services/account_api.dart';
import '../services/remote_studio_api.dart';

class SynthesiaStudioScreen extends StatefulWidget {
  const SynthesiaStudioScreen({super.key, required this.apiBaseUrl});
  final String apiBaseUrl;
  @override
  State<SynthesiaStudioScreen> createState() => _SynthesiaStudioScreenState();
}

class _SynthesiaStudioScreenState extends State<SynthesiaStudioScreen> {
  final _sessions = const AccountSessionStore();
  final _title = TextEditingController(text: 'Nuovo video IA');
  final _script = TextEditingController();
  final _languages = TextEditingController(text: 'it-IT');
  RemoteStudioApi? _studio;
  RemoteMediaApi? _mediaApi;
  final List<String> _sourceAssetIds = [];
  final List<String> _sourceNames = [];
  Map<String, dynamic> _capabilities = const {};
  List<StudioJobDraft> _drafts = const [];
  StudioTask _task = StudioTask.scriptToVideo;
  String _avatarMode = 'none';
  String _voiceMode = 'synthetic';
  bool _avatarConsent = false, _voiceConsent = false, _busy = false;
  String? _message;

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() {
    _title.dispose(); _script.dispose(); _languages.dispose(); _studio?.close(); _mediaApi?.close();
    super.dispose();
  }

  Future<void> _load() async {
    final base = Uri.tryParse(widget.apiBaseUrl.trim());
    if (base == null || !base.hasAuthority) {
      setState(() => _message = 'Configura MEDIA_API_URL per collegare il server.');
      return;
    }
    try {
      final token = await _sessions.readToken();
      if (token == null || token.isEmpty) {
        setState(() => _message = 'Accedi dalla sezione Impostazioni per usare Synthesia Studio.');
        return;
      }
      final studio = RemoteStudioApi(RemoteAccountApi(baseUri: base, bearerToken: token));
      final mediaApi = RemoteMediaApi(baseUri: base, bearerToken: token);
      final capabilities = await studio.capabilities();
      final drafts = await studio.listDrafts();
      if (!mounted) { studio.close(); mediaApi.close(); return; }
      setState(() { _studio = studio; _mediaApi = mediaApi; _capabilities = capabilities; _drafts = drafts; _message = null; });
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    }
  }

  Future<void> _pickAndUploadSource() async {
    final api = _mediaApi;
    if (api == null || _busy) return;
    if (_sourceAssetIds.length >= 20) {
      setState(() => _message = 'Puoi aggiungere al massimo 20 file sorgente.');
      return;
    }
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'pdf', 'docx', 'pptx', 'txt', 'md', 'rtf',
        'jpg', 'jpeg', 'png', 'webp', 'mp4', 'mov', 'avi', 'webm', 'm4v',
      ],
      withData: false,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.single;
    final path = file.path;
    if (path == null || path.isEmpty) {
      setState(() => _message = 'Il percorso del file selezionato non è disponibile.');
      return;
    }
    setState(() { _busy = true; _message = 'Caricamento protetto del file…'; });
    try {
      final assetId = await api.uploadFile(path);
      if (!mounted) return;
      setState(() {
        _sourceAssetIds.add(assetId);
        _sourceNames.add(file.name);
        _message = 'File caricato e associato al tuo account.';
      });
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createDraft() async {
    final studio = _studio;
    if (studio == null || _busy) return;
    final languages = _languages.text.split(',').map((v) => v.trim()).where((v) => v.isNotEmpty).toList();
    setState(() { _busy = true; _message = null; });
    try {
      final draft = await studio.createDraft(StudioJobRequest(
        task: _task, title: _title.text, script: _script.text,
        targetLanguages: languages, sourceAssetIds: List.unmodifiable(_sourceAssetIds), avatarMode: _avatarMode,
        avatarConsent: _avatarConsent, voiceMode: _voiceMode, voiceConsent: _voiceConsent,
      ));
      final drafts = await studio.listDrafts();
      if (!mounted) return;
      setState(() {
        _drafts = drafts;
        _message = 'Bozza salvata: ${draft.jobId}. La generazione richiede ancora un provider video autorizzato.';
      });
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteDraft(StudioJobDraft draft) async {
    final studio = _studio;
    if (studio == null) return;
    try {
      await studio.deleteDraft(draft.jobId);
      final drafts = await studio.listDrafts();
      if (mounted) setState(() => _drafts = drafts);
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    }
  }

  Future<void> _confirmAndEnqueueDraft(StudioJobDraft draft) async {
    final studio = _studio;
    if (studio == null || _busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Conferma progetto'),
        content: Text(
          'Vuoi confermare “${draft.request['title'] ?? 'Video IA'}” e inserirlo nella coda? '
          'Questa operazione salva la richiesta, ma non genera ancora il video: '
          'il provider video non è collegato.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Rivedi più tardi'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Conferma e accoda'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() { _busy = true; _message = null; });
    try {
      final result = await studio.enqueueDraft(draft.jobId);
      if (!mounted) return;
      setState(() {
        _message = result['message']?.toString() ??
            'Richiesta salvata nella coda. La generazione video non è stata avviata.';
      });
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _capabilities['generationAvailable'] == true;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Synthesia Studio IA', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      const Text('Crea progetti video da script, presentatori virtuali e contenuti multilingue. Le bozze sono private e modificabili.'),
      const SizedBox(height: 12),
      Card(child: ListTile(
        leading: Icon(ready ? Icons.cloud_done : Icons.cloud_off),
        title: Text(ready ? 'Provider video collegato' : 'Generazione video non ancora attiva'),
        subtitle: Text(ready ? 'Il servizio segnala il provider disponibile.' : 'Puoi preparare e salvare progetti; non vengono simulati video.'),
      )),
      if (_message != null) Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(_message!))),
      const SizedBox(height: 12),
      Text('Nuovo progetto', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _busy || _mediaApi == null ? null : _pickAndUploadSource,
        icon: const Icon(Icons.upload_file),
        label: const Text('Importa documento, foto o video'),
      ),
      if (_sourceNames.isNotEmpty)
        ..._sourceNames.asMap().entries.map((entry) => ListTile(
          dense: true,
          leading: const Icon(Icons.attach_file),
          title: Text(entry.value, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: IconButton(
            tooltip: 'Rimuovi file dalla bozza',
            icon: const Icon(Icons.close),
            onPressed: _busy ? null : () => setState(() {
              _sourceNames.removeAt(entry.key);
              _sourceAssetIds.removeAt(entry.key);
            }),
          ),
        )),

      const SizedBox(height: 8),
      TextField(controller: _title, maxLength: 120, decoration: const InputDecoration(labelText: 'Titolo', border: OutlineInputBorder())),
      const SizedBox(height: 8),
      DropdownButtonFormField<StudioTask>(
        initialValue: _task,
        decoration: const InputDecoration(labelText: 'Tipo di progetto', border: OutlineInputBorder()),
        items: StudioTask.values.map((task) => DropdownMenuItem(value: task, child: Text(task.label))).toList(),
        onChanged: (value) => setState(() => _task = value ?? _task),
      ),
      const SizedBox(height: 8),
      TextField(controller: _script, minLines: 4, maxLines: 8, maxLength: 30000,
        decoration: const InputDecoration(labelText: 'Testo o copione', hintText: 'Scrivi il testo che il presentatore IA dovrà raccontare…', border: OutlineInputBorder())),
      const SizedBox(height: 8),
      TextField(controller: _languages, decoration: const InputDecoration(
        labelText: 'Lingue di destinazione (massimo 20)', hintText: 'it-IT, en-US, fr-FR, es-ES',
        helperText: 'Inserisci codici lingua separati da virgole.', border: OutlineInputBorder())),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        initialValue: _avatarMode, decoration: const InputDecoration(labelText: 'Presentatore', border: OutlineInputBorder()),
        items: const [
          DropdownMenuItem(value: 'none', child: Text('Nessun avatar')),
          DropdownMenuItem(value: 'stock', child: Text('Avatar della libreria')),
          DropdownMenuItem(value: 'generated', child: Text('Avatar generato')),
          DropdownMenuItem(value: 'personal', child: Text('Avatar personale autorizzato')),
        ],
        onChanged: (value) => setState(() => _avatarMode = value ?? 'none')),
      if (_avatarMode == 'personal') CheckboxListTile(
        value: _avatarConsent, onChanged: (value) => setState(() => _avatarConsent = value ?? false),
        title: const Text('Confermo di avere il consenso per usare questo volto.'),
        controlAffinity: ListTileControlAffinity.leading),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        initialValue: _voiceMode, decoration: const InputDecoration(labelText: 'Voce', border: OutlineInputBorder()),
        items: const [
          DropdownMenuItem(value: 'synthetic', child: Text('Voce sintetica')),
          DropdownMenuItem(value: 'licensed', child: Text('Voce con licenza')),
          DropdownMenuItem(value: 'clone', child: Text('Clonazione della propria voce')),
        ],
        onChanged: (value) => setState(() => _voiceMode = value ?? 'synthetic')),
      if (_voiceMode == 'clone') CheckboxListTile(
        value: _voiceConsent, onChanged: (value) => setState(() => _voiceConsent = value ?? false),
        title: const Text('Confermo di avere i diritti e il consenso per clonare questa voce.'),
        controlAffinity: ListTileControlAffinity.leading),
      const SizedBox(height: 8),
      FilledButton.icon(
        onPressed: _busy || _studio == null ? null : _createDraft,
        icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined),
        label: const Text('Salva bozza privata')),
      const SizedBox(height: 20),
      Text('Le tue bozze', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      if (_drafts.isEmpty) const Text('Non hai ancora creato bozze Studio.')
      else ..._drafts.map((draft) => Card(child: ListTile(
        leading: const Icon(Icons.video_library_outlined),
        title: Text(draft.request['title']?.toString() ?? 'Video IA'),
        subtitle: Text('${draft.state} · ${draft.providerState}'),
        trailing: Wrap(
          spacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton(
              tooltip: 'Conferma e inserisci in coda',
              icon: const Icon(Icons.playlist_add_check),
              onPressed: _busy ? null : () => _confirmAndEnqueueDraft(draft),
            ),
            IconButton(
              tooltip: 'Elimina bozza',
              icon: const Icon(Icons.delete_outline),
              onPressed: _busy ? null : () => _deleteDraft(draft),
            ),
          ],
        ),
      ))),
    ]);
  }
}

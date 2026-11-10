import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/account_api.dart';
import '../services/magiclink_api.dart';

class MagicLinkScreen extends StatefulWidget {
  const MagicLinkScreen({
    super.key,
    required this.apiBaseUrl,
    required this.onImportAuthorizedMedia,
  });

  final String apiBaseUrl;
  final Future<void> Function() onImportAuthorizedMedia;

  @override
  State<MagicLinkScreen> createState() => _MagicLinkScreenState();
}

class _MagicLinkScreenState extends State<MagicLinkScreen> {
  final _sessions = const AccountSessionStore();
  final _url = TextEditingController();
  final _instruction = TextEditingController(
    text: 'Traduci tutte le puntate in italiano',
  );
  RemoteMagicLinkApi? _api;
  Map<String, dynamic>? _result;
  final List<String> _episodeUrls = [];
  final Map<String, Map<String, dynamic>> _episodeResults = {};
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _url.dispose();
    _instruction.dispose();
    _api?.close();
    super.dispose();
  }

  Future<void> _connect() async {
    final base = Uri.tryParse(widget.apiBaseUrl.trim());
    if (base == null || !base.hasAuthority) {
      setState(() => _message = 'Il server MagicLink non è configurato (MEDIA_API_URL).');
      return;
    }
    try {
      final token = await _sessions.readToken();
      if (token == null || token.isEmpty) {
        setState(() => _message = 'Accedi al tuo account per utilizzare MagicLink IA.');
        return;
      }
      final api = RemoteMagicLinkApi(
        RemoteAccountApi(baseUri: base, bearerToken: token),
      );
      final capabilities = await api.capabilities();
      if (!mounted) {
        api.close();
        return;
      }
      _api?.close();
      setState(() {
        _api = api;
        _result = capabilities;
        _message = null;
      });
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    }
  }

  Future<void> _pasteLink() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final value = data?.text?.trim() ?? '';
    if (value.isEmpty) {
      setState(() => _message = 'Gli appunti non contengono un collegamento testuale.');
      return;
    }
    _url.text = value;
    setState(() => _message = 'Collegamento incollato. Ora puoi analizzarlo.');
  }

  Future<void> _importAuthorizedMedia() async {
    if (_busy) return;
    await widget.onImportAuthorizedMedia();
  }

  void _addEpisode() {
    final value = _url.text.trim();
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasAuthority ||
        !{'http', 'https'}.contains(uri.scheme.toLowerCase())) {
      setState(() => _message = 'Inserisci un link HTTP o HTTPS valido prima di aggiungerlo.');
      return;
    }
    if (_episodeUrls.contains(value)) {
      setState(() => _message = 'Questo collegamento è già presente nella serie.');
      return;
    }
    if (_episodeUrls.length >= 50) {
      setState(() => _message = 'Una serie può contenere al massimo 50 collegamenti per raccolta.');
      return;
    }
    setState(() {
      _episodeUrls.add(value);
      _message = 'Episodio aggiunto alla raccolta. Puoi aggiungere altri link.';
      _url.clear();
    });
  }

  void _removeEpisode(String value) {
    setState(() {
      _episodeUrls.remove(value);
      _episodeResults.remove(value);
    });
  }

  Future<void> _analyzeSeries() async {
    final api = _api;
    if (api == null || _busy || _episodeUrls.isEmpty) return;
    setState(() {
      _busy = true;
      _message = 'Analisi dei collegamenti in corso…';
    });
    final results = <String, Map<String, dynamic>>{};
    try {
      for (final url in List<String>.from(_episodeUrls)) {
        try {
          results[url] = await api.analyze(
            url: url,
            instruction: _instruction.text,
          );
        } catch (error) {
          results[url] = {
            'platform': 'unknown',
            'contentAccess': 'not_fetched',
            'providerState': 'not_configured',
            'message': error.toString(),
          };
        }
        if (!mounted) return;
        setState(() {
          _episodeResults
            ..clear()
            ..addAll(results);
        });
      }
      if (mounted) {
        setState(() => _message =
            'Riconoscimento completato per ${results.length} collegamenti. I contenuti remoti non sono stati scaricati.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _analyze() async {
    final api = _api;
    if (api == null || _busy) return;
    setState(() {
      _busy = true;
      _message = null;
      _result = null;
    });
    try {
      final result = await api.analyze(
        url: _url.text,
        instruction: _instruction.text,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _message = result['message']?.toString();
      });
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _episodeSubtitle(String url) {
    final result = _episodeResults[url];
    if (result == null) return 'In attesa di riconoscimento';
    final platform = result['platform']?.toString() ?? 'Sito web';
    return '$platform · contenuto non scaricato';
  }

  String _platformLabel(String? value) {
    switch (value) {
      case 'tiktok': return 'TikTok';
      case 'youtube': return 'YouTube';
      case 'instagram': return 'Instagram';
      case 'facebook': return 'Facebook';
      case 'x': return 'X';
      case 'vimeo': return 'Vimeo';
      case 'website': return 'Sito web';
      default: return value ?? 'Non riconosciuta';
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final platform = result?['platform']?.toString();
    final extractionAvailable = result?['contentAccess'] == 'available';
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text('MagicLink IA', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 6),
        Text(
          'Incolla un link, descrivi cosa vuoi ottenere e prepara il contenuto per MagicTranslate, MagicVoice e MagicIAedit.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.link, color: Color(0xFFB9ADFF)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Collegamento da analizzare',
                        style: Theme.of(context).textTheme.titleMedium),
                    ),
                    TextButton.icon(
                      onPressed: _busy ? null : _pasteLink,
                      icon: const Icon(Icons.content_paste, size: 18),
                      label: const Text('Incolla'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _url,
                  keyboardType: TextInputType.url,
                  maxLength: 2048,
                  decoration: const InputDecoration(
                    hintText: 'https://…',
                    helperText: 'TikTok, YouTube, Instagram, Vimeo e siti web supportati',
                    border: OutlineInputBorder(),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _busy ? null : _addEpisode,
                    icon: const Icon(Icons.playlist_add),
                    label: const Text('Aggiungi alla serie'),
                  ),
                ),
                const SizedBox(height: 10),
                Text('Che cosa vuoi che faccia l’IA?',
                  style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                TextField(
                  controller: _instruction,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 1000,
                  decoration: const InputDecoration(
                    hintText: 'Es. Traduci tutta la serie in italiano e crea sottotitoli',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : (_api == null ? _connect : _analyze),
                  icon: _busy
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(_api == null ? Icons.lock_open : Icons.auto_awesome),
                  label: Text(_api == null ? 'Collega MagicLink' : 'Analizza collegamento'),
                ),
                if (_api != null)
                  TextButton(
                    onPressed: _busy ? null : _connect,
                    child: const Text('Aggiorna connessione'),
                  ),
              ],
            ),
          ),
        ),
        if (_episodeUrls.isNotEmpty) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.video_library_outlined,
                        color: Color(0xFF55D5C9)),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          'Raccolta episodi (${_episodeUrls.length}/50)',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      TextButton(
                        onPressed: _busy || _api == null ? null : _analyzeSeries,
                        child: const Text('Analizza serie'),
                      ),
                    ],
                  ),
                  const Text(
                    'Aggiungi manualmente i collegamenti degli episodi nell’ordine desiderato. '
                    'Questa raccolta organizza e riconosce i link: non estrae né riproduce i video.',
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  for (var index = 0; index < _episodeUrls.length; index++)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 14,
                        child: Text('${index + 1}',
                          style: const TextStyle(fontSize: 11)),
                      ),
                      title: Text(
                        _episodeUrls[index],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(_episodeSubtitle(_episodeUrls[index])),
                      trailing: IconButton(
                        tooltip: 'Rimuovi episodio',
                        onPressed: _busy
                            ? null
                            : () => _removeEpisode(_episodeUrls[index]),
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
        if (_message != null) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(_message!),
            ),
          ),
        ],
        if (result != null && platform != null) ...[
          const SizedBox(height: 16),
          Text('Risultato del riconoscimento',
            style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.public, color: Color(0xFFB9ADFF)),
                      const SizedBox(width: 10),
                      Text(_platformLabel(platform),
                        style: Theme.of(context).textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Accesso ai contenuti: ${result['contentAccess'] ?? 'non verificato'}'),
                  Text('Provider: ${result['providerState'] ?? 'non configurato'}'),
                  const SizedBox(height: 12),
                  const Text('Operazioni previste'),
                  const SizedBox(height: 8),
                  const _ActionTile(icon: Icons.closed_caption, title: 'Trascrizione e sottotitoli'),
                  const _ActionTile(icon: Icons.translate, title: 'Traduzione in italiano e altre lingue'),
                  const _ActionTile(icon: Icons.record_voice_over, title: 'Doppiaggio IA'),
                  const _ActionTile(icon: Icons.video_library, title: 'Serie, episodi e montaggio MagicIAedit'),
                  const SizedBox(height: 10),
                  if (!extractionAvailable)
                    const Text(
                      'Questa versione riconosce il link ma non scarica né legge ancora il contenuto remoto. Puoi importare un file che sei autorizzato a utilizzare. I connettori e i provider di elaborazione saranno collegati in una fase successiva.',
                    ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.folder_open_outlined,
                      color: Color(0xFF55D5C9)),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        'Hai già il file o il permesso di utilizzarlo?',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                const Text(
                  'Puoi importare direttamente foto, video o audio dal dispositivo. '
                  'Il contenuto verrà aggiunto alla timeline dell’editor: MagicLink '
                  'non scarica automaticamente i video dai siti esterni.',
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _importAuthorizedMedia,
                    icon: const Icon(Icons.add_to_photos_outlined),
                    label: const Text('Importa file autorizzati nell’editor'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'MagicLink rispetta i permessi e le limitazioni dei siti. Non aggira login, DRM, paywall o protezioni tecniche.',
          style: TextStyle(color: Colors.white60, fontSize: 12),
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon, color: const Color(0xFFB9ADFF)),
    title: Text(title),
    trailing: const Icon(Icons.lock_outline, size: 16),
  );
}

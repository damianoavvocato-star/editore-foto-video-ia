import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import '../models/editor_project.dart';
import '../models/magiciaedit_plan.dart';
import '../services/ai_processing_service.dart';
import '../services/magiciaedit_workflow.dart';
import '../services/remote_media_api.dart';
import '../services/account_api.dart';

/// Review-first MagicIAedit UI. The AI proposal is never applied automatically.
class MagicIAeditPanel extends StatefulWidget {
  const MagicIAeditPanel({
    super.key,
    required this.project,
    required this.onProjectChanged,
    required this.onMessage,
    required this.onImportMedia,
  });

  final EditorProject project;
  final Future<bool> Function(EditorProject) onProjectChanged;
  final ValueChanged<String> onMessage;
  final Future<void> Function() onImportMedia;

  @override
  State<MagicIAeditPanel> createState() => _MagicIAeditPanelState();
}

class _MagicIAeditPanelState extends State<MagicIAeditPanel> {
  final _endpointController = TextEditingController();
  final _ideaController = TextEditingController();
  int _episodeCount = 10;
  int _episodeDurationSeconds = 60;
  String _ideaGenre = 'Romantico';
  final _selectedPaths = <String>{};
  MagicIAeditWorkflow? _workflow;
  MagicIAeditPlan? _plan;
  String? _jobId;
  String? _error;
  String _progressMessage = '';
  double _progress = 0;
  bool _busy = false;
  String _style = 'balanced';
  String _pace = 'balanced';
  String _aspectRatio = '9:16';
  int _targetDurationSeconds = 30;

  List<EditorClip> get _availableMedia {
    final clips = widget.project.tracks
        .where((track) => track.kind == MediaKind.image || track.kind == MediaKind.video)
        .expand((track) => track.clips)
        .toList()
      ..sort((a, b) => a.startMs.compareTo(b.startMs));
    return clips;
  }

  @override
  void initState() {
    super.initState();
    _selectAvailableMedia();
  }

  @override
  void didUpdateWidget(covariant MagicIAeditPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.project != widget.project) {
      _plan = null;
      final previousPaths = oldWidget.project.tracks
          .where((track) => track.kind == MediaKind.image || track.kind == MediaKind.video)
          .expand((track) => track.clips)
          .map((clip) => clip.source)
          .toSet();
      if (oldWidget.project.id != widget.project.id) {
        _selectedPaths.clear();
        _selectAvailableMedia();
      } else {
        for (final clip in _availableMedia) {
          if (!previousPaths.contains(clip.source) && _selectedPaths.length < 20) {
            _selectedPaths.add(clip.source);
          }
        }
      }
    }
  }

  void _selectAvailableMedia() {
    for (final clip in _availableMedia.take(20)) {
      _selectedPaths.add(clip.source);
    }
  }

  String _newJobId() {
    final random = Random.secure();
    return List<int>.generate(16, (_) => random.nextInt(256))
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  Uri? _validatedEndpoint() {
    final uri = Uri.tryParse(_endpointController.text.trim());
    if (uri == null || !uri.hasAuthority || uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty || uri.fragment.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      return null;
    }
    final localHttp = uri.scheme == 'http' &&
        {'localhost', '127.0.0.1', '10.0.2.2'}.contains(uri.host);
    if (uri.scheme != 'https' && !localHttp) return null;
    return uri.replace(path: '');
  }

  Future<void> _prepareIdeaOutline() async {
    final idea = _ideaController.text.trim();
    if (idea.length < 12) {
      setState(() => _error = 'Descrivi l’idea con almeno 12 caratteri.');
      return;
    }
    final beats = <String>[
      'Presentazione dei protagonisti e del mondo della storia',
      'Primo incontro e nascita del conflitto',
      'Un ostacolo mette alla prova i protagonisti',
      'Un segreto cambia il rapporto tra i personaggi',
      'Una scelta difficile aumenta la tensione',
      'Un evento inatteso cambia la direzione della storia',
      'I protagonisti affrontano le conseguenze',
      'La verità viene finalmente rivelata',
      'Confronto decisivo e svolta emotiva',
      'Conclusione dell’arco narrativo e apertura al seguito',
    ];
    final episodes = List<String>.generate(
      _episodeCount,
      (index) => 'Episodio ${index + 1}: ${beats[index % beats.length]}',
    );
    if (!mounted) return;
    setState(() => _error = null);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Scaletta iniziale del progetto'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Genere: $_ideaGenre · $_episodeCount episodi · almeno $_episodeDurationSeconds secondi ciascuno'),
                const SizedBox(height: 10),
                Text('Idea: $idea'),
                const SizedBox(height: 12),
                ...episodes.asMap().entries.map((entry) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(child: Text('${entry.key + 1}')),
                  title: Text(entry.value),
                  subtitle: Text('Durata minima: $_episodeDurationSeconds secondi'),
                )),
                const SizedBox(height: 8),
                const Text(
                  'Questa è una bozza strutturale locale, non un video generato. La scrittura creativa completa e la generazione di immagini, voci e video richiedono un provider IA collegato al server.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Chiudi'),
          ),
        ],
      ),
    );
  }

  Future<void> _generate() async {
    if (_busy) return;
    final endpoint = _validatedEndpoint();
    if (endpoint == null) {
      setState(() => _error =
          'Inserisci un indirizzo API HTTPS valido. HTTP è consentito solo per localhost o 10.0.2.2.');
      return;
    }
    final paths = _selectedPaths.toList(growable: false);
    if (paths.isEmpty || paths.length > 20) {
      setState(() => _error = 'Seleziona da 1 a 20 foto o video.');
      return;
    }
    for (final path in paths) {
      final exists = await File(path).exists();
      if (!mounted) return;
      if (!exists) {
        setState(() => _error = 'Un file selezionato non è più disponibile: ${path.split(Platform.pathSeparator).last}');
        return;
      }
    }

    final sessionToken = await const AccountSessionStore().readToken();
    if (!mounted) return;
    if (sessionToken == null || sessionToken.isEmpty) {
      setState(() => _error =
          'Accedi prima dalla sezione Impostazioni: MagicIAedit richiede una sessione personale protetta.');
      return;
    }

    final api = RemoteMediaApi(
      baseUri: endpoint,
      bearerToken: sessionToken,
    );
    final workflow = MagicIAeditWorkflow(
      AiProcessingService(RemoteAiBackend(api)),
    );
    final jobId = _newJobId();
    setState(() {
      _busy = true;
      _error = null;
      _plan = null;
      _progress = 0;
      _progressMessage = 'Preparazione dei media…';
      _jobId = jobId;
      _workflow = workflow;
    });

    try {
      final plan = await workflow.generate(
        jobId: jobId,
        mediaPaths: paths,
        options: {
          'style': _style,
          'pace': _pace,
          'aspectRatio': _aspectRatio,
          'targetDurationSeconds': _targetDurationSeconds,
          'language': Localizations.localeOf(context).languageCode,
        },
        onProgress: (event) {
          if (!mounted) return;
          setState(() {
            _progress = event.fraction.clamp(0.0, 1.0);
            _progressMessage = event.message.isNotEmpty
                ? event.message
                : switch (event.state) {
                    AiJobState.queued => 'In coda…',
                    AiJobState.running => 'Analisi e composizione in corso…',
                    AiJobState.succeeded => 'Piano pronto.',
                    AiJobState.failed => 'Elaborazione non riuscita.',
                    AiJobState.cancelled => 'Elaborazione annullata.',
                  };
          });
        },
      );
      if (mounted) {
        setState(() {
          _plan = plan;
          _progress = 1;
          _progressMessage = 'Proposta pronta: controllala prima di applicarla.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      api.close();
      if (mounted) {
        setState(() {
          _busy = false;
          _workflow = null;
          _jobId = null;
        });
      }
    }
  }

  Future<void> _cancel() async {
    final workflow = _workflow;
    final jobId = _jobId;
    if (workflow == null || jobId == null) return;
    try {
      await workflow.cancel(jobId);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Non è stato possibile confermare subito l’annullamento.');
      }
    }
  }

  Future<void> _applyPlan() async {
    final plan = _plan;
    if (plan == null) return;
    try {
      final saved = await widget.onProjectChanged(plan.applyTo(widget.project));
      if (!mounted) return;
      if (!saved) {
        setState(() => _error = 'Il montaggio è stato preparato, ma il salvataggio non è riuscito. Riprova prima di uscire.');
        return;
      }
      setState(() => _plan = null);
      widget.onMessage('Piano MagicIAedit applicato alla timeline e salvato.');
    } catch (error) {
      if (mounted) setState(() => _error = 'Piano non applicabile: $error');
    }
  }

  @override
  void dispose() {
    // Leaving the AI screen must not leave a cloud job running unattended.
    final workflow = _workflow;
    final jobId = _jobId;
    if (workflow != null && jobId != null) {
      unawaited(workflow.cancel(jobId).catchError((Object _) {}));
    }
    // The API is closed by _generate in its finally block.
    _endpointController.dispose();
    _ideaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = _availableMedia;
    final plan = _plan;
    return Card(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text('MagicIAedit',
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              Chip(label: Text('${_selectedPaths.length}/20 media')),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Prima aggiungi le tue foto e i tuoi video. Poi scegli i contenuti e lascia che MagicIAedit prepari un montaggio da rivedere e approvare.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                colors: [Color(0xFF29204D), Color(0xFF172B48)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: const Color(0x665E9BFF)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  const Icon(Icons.photo_library_outlined, color: Color(0xFF8FE8FF)),
                  const SizedBox(width: 9),
                  Expanded(child: Text(
                    '1. Aggiungi foto e video',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  )),
                ]),
                const SizedBox(height: 6),
                Text(
                  media.isEmpty
                      ? 'La galleria è vuota. Tocca qui sotto per scegliere fino a 20 elementi.'
                      : '${media.length} elementi disponibili · puoi aggiungerne altri.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : widget.onImportMedia,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('Aggiungi foto e video dalla galleria'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF6857D8),
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '2. Seleziona i contenuti qui sotto · massimo 20 per ogni proposta IA.',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: const Color(0xFFB8DFFF)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                colors: [Color(0xFF321B58), Color(0xFF142E50)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: const Color(0x887B65E8)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  const Icon(Icons.lightbulb_outline, color: Color(0xFFB9A5FF)),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Crea partendo da un’idea',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                ]),
                const SizedBox(height: 6),
                const Text('Non hai foto o video? Descrivi un film, una serie, un cartone, un documentario o un video social. Puoi partire completamente da zero.'),
                const SizedBox(height: 10),
                TextField(
                  controller: _ideaController,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 3000,
                  decoration: const InputDecoration(
                    labelText: 'Che cosa vuoi creare?',
                    hintText: 'Esempio: crea una miniserie romantica di 10 puntate, ambientata a Parigi, con episodi di almeno un minuto...',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 4),
                DropdownButtonFormField<String>(
                  initialValue: _ideaGenre,
                  decoration: const InputDecoration(labelText: 'Genere / formato'),
                  items: const [
                    DropdownMenuItem(value: 'Romantico', child: Text('Romantico')),
                    DropdownMenuItem(value: 'Azione e avventura', child: Text('Azione e avventura')),
                    DropdownMenuItem(value: 'Commedia', child: Text('Commedia')),
                    DropdownMenuItem(value: 'Horror e mistero', child: Text('Horror e mistero')),
                    DropdownMenuItem(value: 'Documentario', child: Text('Documentario')),
                    DropdownMenuItem(value: 'Animazione', child: Text('Animazione')),
                    DropdownMenuItem(value: 'Social / pubblicità', child: Text('Social / pubblicità')),
                    DropdownMenuItem(value: 'Personalizzato', child: Text('Personalizzato')),
                  ],
                  onChanged: (value) => setState(() { if (value != null) _ideaGenre = value; }),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: DropdownButtonFormField<int>(
                    initialValue: _episodeCount,
                    decoration: const InputDecoration(labelText: 'Episodi'),
                    items: [1, 3, 5, 10, 15, 20, 30].map((value) => DropdownMenuItem(value: value, child: Text('$value'))).toList(),
                    onChanged: (value) => setState(() { if (value != null) _episodeCount = value; }),
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: DropdownButtonFormField<int>(
                    initialValue: _episodeDurationSeconds,
                    decoration: const InputDecoration(labelText: 'Durata minima'),
                    items: [30, 60, 90, 120, 180, 300, 600].map((value) => DropdownMenuItem(value: value, child: Text('${value >= 60 ? '${value ~/ 60} min' : '$value sec'}'))).toList(),
                    onChanged: (value) => setState(() { if (value != null) _episodeDurationSeconds = value; }),
                  )),
                ]),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _prepareIdeaOutline,
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Prepara la scaletta del progetto'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                ),
                const SizedBox(height: 4),
                Text('Puoi creare anche senza importare alcun media. La scaletta è una bozza iniziale; la generazione audiovisiva completa sarà attivata collegando i provider IA.',
                  style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _endpointController,
            enabled: !_busy,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Indirizzo del server MagicIAedit',
              hintText: 'https://api.tuodominio.it',
              border: OutlineInputBorder(),
              helperText: 'Il provider IA e la chiave API restano configurati sul server.',
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'MagicIAedit usa la sessione personale salvata in modo protetto dopo l’accesso. Non inserire o condividere token manualmente.',
            style: TextStyle(fontSize: 12),
          ),

          const SizedBox(height: 14),
          Text('Direzione creativa', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _style,
            decoration: const InputDecoration(labelText: 'Stile del montaggio', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'balanced', child: Text('Equilibrato')),
              DropdownMenuItem(value: 'cinematic', child: Text('Cinematografico')),
              DropdownMenuItem(value: 'travel', child: Text('Viaggio')),
              DropdownMenuItem(value: 'family', child: Text('Famiglia e ricordi')),
              DropdownMenuItem(value: 'social_short', child: Text('Social breve')),
              DropdownMenuItem(value: 'product', child: Text('Prodotto')),
              DropdownMenuItem(value: 'storytelling', child: Text('Racconto')),
              DropdownMenuItem(value: 'dynamic', child: Text('Dinamico')),
            ],
            onChanged: _busy ? null : (value) => setState(() { if (value != null) { _style = value; _plan = null; } }),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _pace,
                  decoration: const InputDecoration(labelText: 'Ritmo', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'slow', child: Text('Calmo')),
                    DropdownMenuItem(value: 'balanced', child: Text('Medio')),
                    DropdownMenuItem(value: 'fast', child: Text('Veloce')),
                  ],
                  onChanged: _busy ? null : (value) => setState(() { if (value != null) { _pace = value; _plan = null; } }),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _aspectRatio,
                  decoration: const InputDecoration(labelText: 'Formato', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: '9:16', child: Text('Verticale 9:16')),
                    DropdownMenuItem(value: '16:9', child: Text('Orizzontale 16:9')),
                    DropdownMenuItem(value: '1:1', child: Text('Quadrato 1:1')),
                    DropdownMenuItem(value: '4:5', child: Text('Ritratto 4:5')),
                  ],
                  onChanged: _busy ? null : (value) => setState(() { if (value != null) { _aspectRatio = value; _plan = null; } }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: _targetDurationSeconds,
            decoration: const InputDecoration(labelText: 'Durata obiettivo', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 15, child: Text('15 secondi')),
              DropdownMenuItem(value: 30, child: Text('30 secondi')),
              DropdownMenuItem(value: 60, child: Text('60 secondi')),
              DropdownMenuItem(value: 90, child: Text('90 secondi')),
              DropdownMenuItem(value: 120, child: Text('120 secondi')),
            ],
            onChanged: _busy ? null : (value) => setState(() { if (value != null) { _targetDurationSeconds = value; _plan = null; } }),
          ),
          const SizedBox(height: 12),
          Text('Media disponibili', style: Theme.of(context).textTheme.titleMedium),
          if (media.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('Nessun contenuto ancora. Usa il pulsante “Aggiungi foto e video dalla galleria” qui sopra.'),
            )
          else
            ...media.map((clip) {
              final selected = _selectedPaths.contains(clip.source);
              final canSelect = selected || _selectedPaths.length < 20;
              return CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: selected,
                onChanged: _busy || !canSelect
                    ? null
                    : (value) => setState(() {
                          if (value == true) {
                            _selectedPaths.add(clip.source);
                          } else {
                            _selectedPaths.remove(clip.source);
                          }
                          _plan = null;
                        }),
                secondary: Icon(clip.kind == MediaKind.video
                    ? Icons.movie_outlined
                    : Icons.image_outlined),
                title: Text(clip.title.isEmpty
                    ? clip.source.split(Platform.pathSeparator).last
                    : clip.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(clip.kind == MediaKind.video ? 'Video' : 'Foto'),
              );
            }),
          const SizedBox(height: 12),
          if (_busy) ...[
            LinearProgressIndicator(value: _progress > 0 ? _progress : null),
            const SizedBox(height: 8),
            Text(_progressMessage),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: _cancel,
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Annulla'),
              ),
            ),
          ] else
            FilledButton.icon(
              onPressed: media.isEmpty || _selectedPaths.isEmpty ? null : _generate,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Crea proposta automatica'),
            ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          if (plan != null) ...[
            const Divider(height: 28),
            Text(plan.title, style: Theme.of(context).textTheme.titleMedium),
            if (plan.description.isNotEmpty) Text(plan.description),
            const SizedBox(height: 6),
            Text('Durata stimata: ${(plan.durationMs / 1000).toStringAsFixed(1)} s · ${plan.clips.length} clip'),
            const SizedBox(height: 8),
            ...plan.clips.asMap().entries.map((entry) {
              final clip = entry.value;
              final source = plan.sourcePaths[clip.assetId] ?? '';
              return ListTile(
                dense: true,
                leading: CircleAvatar(child: Text('${entry.key + 1}')),
                title: Text(source.split(Platform.pathSeparator).last,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(clip.reason.isEmpty
                    ? '${(clip.startMs / 1000).toStringAsFixed(1)} s · ${(clip.durationMs / 1000).toStringAsFixed(1)} s'
                    : clip.reason),
              );
            }),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _applyPlan,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Approva e applica alla timeline'),
            ),
            TextButton(
              onPressed: () => setState(() => _plan = null),
              child: const Text('Rifiuta proposta'),
            ),
          ],
          const SizedBox(height: 12),
          const Text(
            'Nota: il servizio cloud non è attivo finché il server non viene configurato con un provider IA. L’URL e il token inseriti qui non vengono salvati dall’app.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

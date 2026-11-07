import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import '../models/editor_project.dart';
import '../models/magiciaedit_plan.dart';
import '../services/ai_processing_service.dart';
import '../services/magiciaedit_workflow.dart';
import '../services/remote_media_api.dart';

/// Review-first MagicIAedit UI. The AI proposal is never applied automatically.
class MagicIAeditPanel extends StatefulWidget {
  const MagicIAeditPanel({
    super.key,
    required this.project,
    required this.onProjectChanged,
    required this.onMessage,
  });

  final EditorProject project;
  final ValueChanged<EditorProject> onProjectChanged;
  final ValueChanged<String> onMessage;

  @override
  State<MagicIAeditPanel> createState() => _MagicIAeditPanelState();
}

class _MagicIAeditPanelState extends State<MagicIAeditPanel> {
  final _endpointController = TextEditingController();
  final _tokenController = TextEditingController();
  final _selectedPaths = <String>{};
  MagicIAeditWorkflow? _workflow;
  MagicIAeditPlan? _plan;
  String? _jobId;
  String? _error;
  String _progressMessage = '';
  double _progress = 0;
  bool _busy = false;
  bool _showToken = false;

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
    if (oldWidget.project.id != widget.project.id) {
      _selectedPaths.clear();
      _selectAvailableMedia();
      _plan = null;
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
      if (!await File(path).exists()) {
        setState(() => _error = 'Un file selezionato non è più disponibile: ${path.split(Platform.pathSeparator).last}');
        return;
      }
    }

    final api = RemoteMediaApi(
      baseUri: endpoint,
      bearerToken: _tokenController.text.trim().isEmpty
          ? null
          : _tokenController.text.trim(),
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
      _api = api;
      _workflow = workflow;
    });

    try {
      final plan = await workflow.generate(
        jobId: jobId,
        mediaPaths: paths,
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

  void _applyPlan() {
    final plan = _plan;
    if (plan == null) return;
    try {
      widget.onProjectChanged(plan.applyTo(widget.project));
      setState(() => _plan = null);
      widget.onMessage('Piano MagicIAedit applicato alla timeline. Il progetto è stato salvato.');
    } catch (error) {
      setState(() => _error = 'Piano non applicabile: $error');
    }
  }

  @override
  void dispose() {
    // The workflow owns an active request until it reaches its cancellation
    // path. The API is closed by _generate in its finally block.
    _endpointController.dispose();
    _tokenController.dispose();
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
          const Text(
            'Seleziona le foto e i video già importati. L’IA prepara una proposta; nessuna modifica viene applicata finché non la approvi.',
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
          TextField(
            controller: _tokenController,
            enabled: !_busy,
            obscureText: !_showToken,
            decoration: InputDecoration(
              labelText: 'Token di accesso del server (facoltativo)',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                onPressed: () => setState(() => _showToken = !_showToken),
                icon: Icon(_showToken ? Icons.visibility_off : Icons.visibility),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('Media disponibili', style: Theme.of(context).textTheme.titleMedium),
          if (media.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('Importa prima almeno una foto o un video nell’editor.'),
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

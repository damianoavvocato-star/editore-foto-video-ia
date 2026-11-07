import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/editor_project.dart';
import '../models/export_settings.dart';
import '../services/export_coordinator.dart';
import '../services/remote_media_api.dart';
import 'export_settings_panel.dart';

/// Remote export UI. It saves the rendered file in app documents and offers
/// the native share sheet; it never reports success before a verified download.
class RemoteExportPanel extends StatefulWidget {
  const RemoteExportPanel({
    super.key,
    required this.project,
    required this.onClose,
    required this.onMessage,
  });

  final EditorProject project;
  final VoidCallback onClose;
  final ValueChanged<String> onMessage;

  @override
  State<RemoteExportPanel> createState() => _RemoteExportPanelState();
}

class _RemoteExportPanelState extends State<RemoteExportPanel> {
  final _endpointController = TextEditingController();
  final _tokenController = TextEditingController();
  ExportSettings _settings = const ExportSettings();
  ExportCoordinator? _coordinator;
  RemoteMediaApi? _api;
  String? _outputPath;
  String? _error;
  String _message = '';
  double _progress = 0;
  bool _busy = false;
  bool _completed = false;
  bool _showToken = false;

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

  String _safeFileName(String name) {
    final safe = name.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_');
    return safe.isEmpty ? 'editore_video' : safe.substring(0, safe.length.clamp(1, 64));
  }

  Future<void> _startExport() async {
    if (_busy) return;
    final endpoint = _validatedEndpoint();
    if (endpoint == null) {
      setState(() => _error =
          'Inserisci un indirizzo API HTTPS valido. HTTP è consentito solo per localhost o 10.0.2.2.');
      return;
    }
    try {
      final directory = await getApplicationDocumentsDirectory();
      final extension = _settings.container.name;
      final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
      final output = '${directory.path}/${_safeFileName(widget.project.name)}_$stamp.$extension';
      final api = RemoteMediaApi(
        baseUri: endpoint,
        bearerToken: _tokenController.text.trim().isEmpty
            ? null
            : _tokenController.text.trim(),
      );
      final coordinator = ExportCoordinator(RemoteRenderBackend(api));
      setState(() {
        _busy = true;
        _completed = false;
        _error = null;
        _progress = 0;
        _message = 'Preparazione del progetto…';
        _outputPath = output;
        _api = api;
        _coordinator = coordinator;
      });

      await for (final event in coordinator.start(ExportRequest(
        project: widget.project,
        settings: _settings,
        outputPath: output,
      ))) {
        if (!mounted) continue;
        setState(() {
          _progress = event.fraction.clamp(0.0, 1.0);
          _message = event.message;
          if (event.phase == ExportPhase.failed) {
            _error = event.message.isEmpty
                ? 'Esportazione non riuscita.'
                : event.message;
          }
          if (event.phase == ExportPhase.completed) {
            _completed = File(output).existsSync() &&
                File(output).lengthSync() > 0;
            if (!_completed) {
              _error = 'Il server ha completato il rendering ma il file scaricato non è valido.';
            } else {
              _message = 'Esportazione completata e file verificato.';
            }
          }
          if (event.phase == ExportPhase.cancelled) {
            _message = 'Esportazione annullata.';
          }
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'Esportazione non riuscita: $error');
    } finally {
      _api?.close();
      if (mounted) {
        setState(() {
          _busy = false;
          _api = null;
          _coordinator = null;
        });
      }
    }
  }

  Future<void> _cancel() async {
    try {
      await _coordinator?.cancel();
    } catch (error) {
      if (mounted) setState(() => _error = 'Errore durante l’annullamento: $error');
    }
  }

  Future<void> _shareOutput() async {
    final path = _outputPath;
    if (!_completed || path == null || !await File(path).exists()) return;
    try {
      await Share.shareXFiles(
        [XFile(path)],
        text: 'Video creato con Editore Foto e Video IA',
      );
    } catch (error) {
      if (mounted) setState(() => _error = 'Condivisione non riuscita: $error');
    }
  }

  @override
  void dispose() {
    final coordinator = _coordinator;
    if (coordinator != null) {
      unawaited(coordinator.cancel().catchError((Object _) {}));
    }
    // The active export closes its HTTP client in _startExport's finally block.
    _endpointController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              const Icon(Icons.file_upload_outlined, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Esporta progetto',
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              IconButton(
                tooltip: 'Chiudi',
                onPressed: widget.onClose,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const Text(
            'Il rendering viene eseguito dal server configurato. Il file finale viene scaricato sul dispositivo prima di dichiarare completata l’esportazione.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _endpointController,
            enabled: !_busy,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Indirizzo del server media',
              hintText: 'https://api.tuodominio.it',
              border: OutlineInputBorder(),
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
          ExportSettingsPanel(
            initial: _settings,
            onChanged: (value) => setState(() => _settings = value),
          ),
          const SizedBox(height: 12),
          if (_busy) ...[
            LinearProgressIndicator(value: _progress > 0 ? _progress : null),
            const SizedBox(height: 8),
            Text(_message),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: _cancel,
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Annulla'),
              ),
            ),
          ] else ...[
            FilledButton.icon(
              onPressed: widget.project.tracks.any((track) => track.clips.isNotEmpty)
                  ? _startExport
                  : null,
              icon: const Icon(Icons.rocket_launch_outlined),
              label: const Text('Avvia esportazione'),
            ),
          ],
          if (_completed && !_busy) ...[
            const SizedBox(height: 10),
            const ListTile(
              leading: Icon(Icons.check_circle, color: Colors.green),
              title: Text('File esportato e verificato'),
              subtitle: Text('Salvato nella cartella documenti dell’app.'),
            ),
            FilledButton.icon(
              onPressed: _shareOutput,
              icon: const Icon(Icons.share),
              label: const Text('Condividi video'),
            ),
          ],
          if (_message.isNotEmpty && !_busy) Text(_message),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 8),
          const Text(
            'Il server deve avere FFmpeg/ffprobe installati. Per l’uso pubblico servono autenticazione personale e autorizzazioni per i file.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

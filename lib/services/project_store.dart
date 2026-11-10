import 'dart:convert';
import 'dart:io';

import '../models/editor_project.dart';

/// Local project persistence. The caller chooses a writable app-specific directory
/// (for example Application Support); this class does not request broad storage access.
class ProjectStore {
  const ProjectStore();

  Future<void> save(EditorProject project, Directory directory) async {
    await directory.create(recursive: true);
    final file = File('${directory.path}/${_safeName(project.id)}.editproj');
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(project.encode(), flush: true);
    final backup = File('${file.path}.bak');
    try {
      if (await backup.exists()) await backup.delete();
      if (await file.exists()) await file.rename(backup.path);
      await temporary.rename(file.path);
    } catch (_) {
      if (!await file.exists() && await backup.exists()) {
        await backup.rename(file.path);
      }
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  Future<EditorProject> load(String projectId, Directory directory) async {
    final file = File('${directory.path}/${_safeName(projectId)}.editproj');
    final backup = File('${file.path}.bak');
    try {
      final project = await _readProject(file);
      if (project.id != projectId) {
        throw const FormatException('ID progetto non corrispondente al file.');
      }
      return project;
    } on FormatException {
      return _recoverFromBackup(projectId, file, backup);
    } on TypeError {
      // JSON can be syntactically valid while containing fields of the wrong
      // type. Treat that primary file as corrupt and attempt the last backup.
      return _recoverFromBackup(projectId, file, backup);
    } on FileSystemException {
      // The primary file may have been lost after a crash; try the backup too.
      return _recoverFromBackup(projectId, file, backup);
    }
  }

  Future<EditorProject> _recoverFromBackup(
    String projectId,
    File file,
    File backup,
  ) async {
    if (!await backup.exists()) {
      throw FileSystemException('Progetto e backup non disponibili.', file.path);
    }
    final recovered = await _readProject(backup);
    if (recovered.id != projectId) {
      throw const FormatException('ID progetto del backup non corrispondente.');
    }
    final restore = File('${file.path}.restore');
    await restore.writeAsString(recovered.encode(), flush: true);
    if (await file.exists()) await file.delete();
    await restore.rename(file.path);
    return recovered;
  }

  Future<bool> exists(String projectId, Directory directory) =>
      File('${directory.path}/${_safeName(projectId)}.editproj').exists();

  Future<List<EditorProject>> listProjects(Directory directory) async {
    if (!await directory.exists()) return const [];
    final files = await directory
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.editproj'))
        .cast<File>()
        .toList();
    final projects = <({EditorProject project, DateTime modifiedAt})>[];
    for (final file in files) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, dynamic>) {
          final project = EditorProject.fromJson(decoded);
          // A renamed/copied file must not appear under a misleading identity.
          // The canonical filename is derived from the project's own ID.
          final expectedName = '${_safeName(project.id)}.editproj';
          if (file.uri.pathSegments.isNotEmpty &&
              file.uri.pathSegments.last == expectedName) {
            projects.add((
              project: project,
              modifiedAt: await file.lastModified(),
            ));
          }
        }
      } on FormatException {
        // Ignore corrupted/partial project files; preserve them for diagnostics.
      } on TypeError {
        // Valid JSON can still have an invalid shape or field type. One bad
        // project must not prevent the library screen from listing the others.
      } on ArgumentError {
        // Reject unsafe IDs (including path traversal attempts) without
        // allowing one malformed file to break the entire library screen.
      } on FileSystemException {
        // A file may be removed while the directory is being scanned.
      }
    }
    // The library is a recent-projects view: last edited first, with a stable
    // name tie-breaker when multiple files share the same timestamp.
    projects.sort((a, b) {
      final byDate = b.modifiedAt.compareTo(a.modifiedAt);
      return byDate != 0
          ? byDate
          : a.project.name.toLowerCase().compareTo(b.project.name.toLowerCase());
    });
    return projects.map((entry) => entry.project).toList();
  }

  Future<void> delete(String projectId, Directory directory) async {
    final file = File('${directory.path}/${_safeName(projectId)}.editproj');
    for (final suffix in ['', '.bak', '.tmp', '.restore']) {
      final candidate = File('${file.path}$suffix');
      if (await candidate.exists()) await candidate.delete();
    }
  }

  Future<EditorProject> _readProject(File file) async {
    final raw = await file.readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Il file progetto non contiene un oggetto JSON.');
    }
    return EditorProject.fromJson(decoded);
  }

  String _safeName(String value) {
    // Reject unsafe IDs instead of silently rewriting them: rewriting can make
    // distinct project IDs resolve to the same on-disk file (for example,
    // `my/project` and `my_project`).
    if (value.isEmpty || !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(value)) {
      throw ArgumentError.value(
        value,
        'projectId',
        'Use only letters, numbers, hyphens, and underscores.',
      );
    }
    return value;
  }
}

/// Serializes writes for the same project so rapid timeline edits cannot race
/// while replacing the primary, temporary, and backup files.
class ProjectSaveQueue {
  ProjectSaveQueue({ProjectStore store = const ProjectStore()}) : _store = store;

  final ProjectStore _store;
  final Map<String, Future<void>> _pending = {};

  Future<void> save(EditorProject project, Directory directory) {
    final key = '${directory.absolute.path}/${project.id}';
    return _enqueue(key, () => _store.save(project, directory));
  }

  /// Serializes deletion after any pending save for the same project.
  /// This prevents an in-flight autosave from recreating a project just
  /// after the user has confirmed its deletion.
  Future<void> delete(String projectId, Directory directory) {
    final key = '${directory.absolute.path}/$projectId';
    return _enqueue(key, () => _store.delete(projectId, directory));
  }

  Future<void> _enqueue(String key, Future<void> Function() operation) {
    final previous = _pending[key] ?? Future<void>.value();
    final next = previous.then(
      (_) => operation(),
      onError: (Object _, StackTrace __) => operation(),
    );
    _pending[key] = next;
    return next.whenComplete(() {
      if (identical(_pending[key], next)) _pending.remove(key);
    });
  }
}

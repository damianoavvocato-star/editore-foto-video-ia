import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:editore_foto_video_ia/models/editor_project.dart';
import 'package:editore_foto_video_ia/services/project_store.dart';
import 'package:editore_foto_video_ia/models/export_settings.dart';

void main() {
  test('project store saves and reloads project metadata and clips', () async {
    final directory = await Directory.systemTemp.createTemp('editor_project_test');
    addTearDown(() => directory.delete(recursive: true));
    const project = EditorProject(
      id: 'demo-project',
      name: 'Demo',
      tracks: [
        EditorTrack(
          id: 'video-1',
          name: 'Video',
          kind: MediaKind.video,
          clips: [
            EditorClip(
              id: 'clip-1',
              source: '/media/sample.mp4',
              kind: MediaKind.video,
              startMs: 120,
              durationMs: 3400,
            ),
          ],
        ),
      ],
    );
    const store = ProjectStore();
    await store.save(project, directory);
    final restored = await store.load(project.id, directory);
    expect(restored.name, 'Demo');
    expect(restored.tracks.single.clips.single.durationMs, 3400);
  });

  test('project store recovers a corrupted current file from backup', () async {
    final directory = await Directory.systemTemp.createTemp('editor_project_recovery');
    addTearDown(() => directory.delete(recursive: true));
    const project = EditorProject(id: 'recover-me', name: 'Last good copy');
    const store = ProjectStore();
    await store.save(project, directory);
    await store.save(project.copyWith(name: 'Newer version'), directory);
    final file = File('${directory.path}/recover-me.editproj');
    await file.writeAsString('{ broken json');
    final restored = await store.load(project.id, directory);
    expect(restored.name, 'Last good copy');
    expect(await file.readAsString(), project.encode());
  });

  test('project store recovers from valid JSON with invalid field types', () async {
    final directory = await Directory.systemTemp.createTemp('editor_project_bad_primary');
    addTearDown(() => directory.delete(recursive: true));
    const project = EditorProject(id: 'bad-primary', name: 'Last valid backup');
    const store = ProjectStore();
    await store.save(project, directory);
    await store.save(project.copyWith(name: 'New primary'), directory);
    final file = File('${directory.path}/bad-primary.editproj');
    await file.writeAsString('{"schemaVersion":1,"id":42,"name":"Broken"}');

    final restored = await store.load(project.id, directory);
    expect(restored.name, 'Last valid backup');
    expect(await file.readAsString(), project.encode());
  });

  test('project store recovers when primary file is missing', () async {
    final directory = await Directory.systemTemp.createTemp('editor_project_missing');
    addTearDown(() => directory.delete(recursive: true));
    const project = EditorProject(id: 'missing-me', name: 'Backup copy');
    const store = ProjectStore();
    await store.save(project, directory);
    final file = File('${directory.path}/missing-me.editproj');
    await file.rename('${file.path}.bak');
    final restored = await store.load(project.id, directory);
    expect(restored.name, 'Backup copy');
    expect(await file.exists(), isTrue);
  });

  test('project save queue serializes rapid writes to the same project', () async {
    final directory = await Directory.systemTemp.createTemp('editor_project_queue');
    addTearDown(() => directory.delete(recursive: true));
    final queue = ProjectSaveQueue();
    const initial = EditorProject(id: 'queued-project', name: 'Version 1');
    final second = initial.copyWith(name: 'Version 2');
    final third = initial.copyWith(name: 'Version 3');

    await Future.wait([
      queue.save(initial, directory),
      queue.save(second, directory),
      queue.save(third, directory),
    ]);

    final restored = await const ProjectStore().load(initial.id, directory);
    expect(restored.name, 'Version 3');
    expect(await File('${directory.path}/queued-project.editproj.bak').exists(), isTrue);
  });

  test('delete removes project and sidecar files', () async {
    final directory = await Directory.systemTemp.createTemp('editor_project_delete');
    addTearDown(() => directory.delete(recursive: true));
    const project = EditorProject(id: 'delete-me', name: 'Delete');
    const store = ProjectStore();
    await store.save(project, directory);
    await File('${directory.path}/delete-me.editproj.bak').writeAsString('backup');
    await File('${directory.path}/delete-me.editproj.tmp').writeAsString('tmp');
    await store.delete(project.id, directory);
    expect(await File('${directory.path}/delete-me.editproj').exists(), isFalse);
    expect(await File('${directory.path}/delete-me.editproj.bak').exists(), isFalse);
    expect(await File('${directory.path}/delete-me.editproj.tmp').exists(), isFalse);
  });


  test('project listing ignores files whose contents have a different ID', () async {
    final directory = await Directory.systemTemp.createTemp('editor_project_mismatch');
    addTearDown(() => directory.delete(recursive: true));
    const store = ProjectStore();
    const project = EditorProject(id: 'actual-id', name: 'Wrong filename');
    await File('${directory.path}/different-id.editproj')
        .writeAsString(project.encode());

    final listed = await store.listProjects(directory);
    expect(listed, isEmpty);
  });


  test('project listing skips projects with unsafe IDs', () async {
    final directory = await Directory.systemTemp.createTemp('editor_project_unsafe_id');
    addTearDown(() => directory.delete(recursive: true));
    const store = ProjectStore();
    const valid = EditorProject(id: 'valid-project', name: 'Valid');
    await File('${directory.path}/valid-project.editproj').writeAsString(valid.encode());
    await File('${directory.path}/unsafe.editproj').writeAsString(
      '{\"schemaVersion\":1,\"id\":\"../outside\",\"name\":\"Unsafe\"}',
    );

    final listed = await store.listProjects(directory);
    expect(listed.map((project) => project.id), ['valid-project']);
  });

  test('project listing skips valid JSON with invalid field types', () async {
    final directory = await Directory.systemTemp.createTemp('editor_project_bad_shape');
    addTearDown(() => directory.delete(recursive: true));
    const store = ProjectStore();
    const valid = EditorProject(id: 'valid-project', name: 'Valid project');
    await File('${directory.path}/broken-project.editproj').writeAsString(
      '{\"schemaVersion\":1,\"id\":42,\"name\":\"Broken\"}',
    );
    await store.save(valid, directory);

    final listed = await store.listProjects(directory);
    expect(listed.map((project) => project.id), ['valid-project']);
  });

  test('project store rejects unsafe IDs instead of colliding on disk', () async {
    final directory = await Directory.systemTemp.createTemp('editor_project_ids');
    addTearDown(() => directory.delete(recursive: true));
    const store = ProjectStore();
    const unsafeProject = EditorProject(id: 'project/one', name: 'Unsafe');
    expect(() => store.save(unsafeProject, directory), throwsArgumentError);
    expect(() => store.exists('project/one', directory), throwsArgumentError);
  });

  test('export settings map resolution and clamp fps/bitrate', () {
    final settings = const ExportSettings().copyWith(
      resolution: ExportResolution.p2160,
      framesPerSecond: 999,
      bitrateMbps: 0,
    );
    expect(settings.width, 3840);
    expect(settings.height, 2160);
    expect(settings.framesPerSecond, 120);
    expect(settings.bitrateMbps, 1);
  });
}

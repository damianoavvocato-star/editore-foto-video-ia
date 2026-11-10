import 'package:flutter_test/flutter_test.dart';
import 'package:editore_foto_video_ia/models/studio_job.dart';

void main() {
  test('Studio request serializes video creation options', () {
    final request = StudioJobRequest(
      task: StudioTask.scriptToVideo, title: 'Presentazione',
      script: 'Benvenuti', targetLanguages: const ['it-IT', 'en-US', 'fr-FR'],
    );
    request.validate();
    expect(request.toJson()['task'], 'script_to_video');
    expect(request.toJson()['targetLanguages'], ['it-IT', 'en-US', 'fr-FR']);
  });

  test('Studio language parser normalizes casing and removes duplicates in order', () {
    expect(
      parseStudioLanguageCodes('it-it, EN-us, en-US, fr-FR, , es-es'),
      ['it-IT', 'en-US', 'fr-FR', 'es-ES'],
    );
  });

  test('Studio language parser preserves invalid tokens for validation', () {
    final languages = parseStudioLanguageCodes('it-IT, en_US');
    expect(languages, ['it-IT', 'en_US']);
    expect(
      () => StudioJobRequest(
        task: StudioTask.scriptToVideo,
        script: 'Hello',
        targetLanguages: languages,
      ).validate(),
      throwsArgumentError,
    );
  });

  test('Studio request rejects more than twenty target languages', () {
    final request = StudioJobRequest(
      task: StudioTask.scriptToVideo, script: 'Hello',
      targetLanguages: List.generate(21, (index) => 'x${index.toString().padLeft(2, '0')}'),
    );
    expect(request.validate, throwsArgumentError);
  });

  test('personal avatar and cloned voice require consent', () {
    expect(() => StudioJobRequest(
      task: StudioTask.avatarVideo, script: 'Hello', avatarMode: 'personal',
    ).validate(), throwsArgumentError);
    expect(() => StudioJobRequest(
      task: StudioTask.scriptToVideo, script: 'Hello', voiceMode: 'clone',
    ).validate(), throwsArgumentError);
  });

  test('document projects require a source asset', () {
    expect(() => StudioJobRequest(task: StudioTask.documentToVideo).validate(), throwsArgumentError);
  });

  test('draft parser rejects malformed job identifiers', () {
    expect(() => StudioJobDraft.fromJson({
      'jobId': '../unsafe', 'state': 'draft', 'request': <String, dynamic>{},
    }), throwsFormatException);
  });
}

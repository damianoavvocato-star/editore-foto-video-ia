import 'package:flutter/foundation.dart';

const _studioLanguagePattern = r'^[a-z]{2,3}(-[A-Z][a-z]{3})?(-([A-Z]{2}|[0-9]{3}))?

/// Parses comma-separated BCP-47 language codes, normalizing language/region
/// casing and removing duplicates while preserving the user's chosen order.
/// Invalid tokens are preserved so StudioJobRequest.validate can reject them.
List<String> parseStudioLanguageCodes(String input) {
  final result = <String>[];
  final seen = <String>{};
  final codePattern = RegExp(r'^([A-Za-z]{2,3})(?:-([A-Za-z]{4}))?(?:-([A-Za-z]{2}|[0-9]{3}))?
  for (final part in input.split(',')) {
    final token = part.trim();
    if (token.isEmpty) continue;
    final match = codePattern.firstMatch(token);
    final String normalized;
    if (match == null) {
      normalized = token;
    } else {
      final language = match.group(1)!.toLowerCase();
      final region = match.group(2);
      normalized = region == null ? language : language + '-' + region.toUpperCase();
    }
    if (seen.add(normalized.toLowerCase())) result.add(normalized);
  }
  return List.unmodifiable(result);
}

enum StudioTask {
  scriptToVideo('script_to_video', 'Video da testo'),
  documentToVideo('document_to_video', 'Video da documento'),
  slidesToVideo('slides_to_video', 'Video da presentazione'),
  avatarVideo('avatar_video', 'Presentatore IA'),
  talkingPhoto('talking_photo', 'Foto parlante'),
  translateDub('translate_dub', 'Traduzione e doppiaggio'),
  interactiveVideo('interactive_video', 'Video interattivo'),
  bulkPersonalization('bulk_personalization', 'Video personalizzati'),
  screenExplainer('screen_explainer', 'Video tutorial schermo');

  const StudioTask(this.apiValue, this.label);
  final String apiValue;
  final String label;
}

@immutable
class StudioJobRequest {
  const StudioJobRequest({
    required this.task,
    this.title = 'Nuovo video IA',
    this.script = '',
    this.sourceAssetIds = const [],
    this.sourceLanguage,
    this.targetLanguages = const ['it-IT'],
    this.avatarMode = 'none',
    this.avatarConsent = false,
    this.voiceMode = 'synthetic',
    this.voiceConsent = false,
    this.interactive = false,
    this.templateId,
    this.variables = const {},
  });

  final StudioTask task;
  final String title;
  final String script;
  final List<String> sourceAssetIds;
  final String? sourceLanguage;
  final List<String> targetLanguages;
  final String avatarMode;
  final bool avatarConsent;
  final String voiceMode;
  final bool voiceConsent;
  final bool interactive;
  final String? templateId;
  final Map<String, String> variables;

  void validate() {
    if (title.trim().isEmpty || title.length > 120) {
      throw ArgumentError('Inserisci un titolo da 1 a 120 caratteri.');
    }
    if (script.length > 30000) {
      throw ArgumentError('Lo script supera il limite di 30.000 caratteri.');
    }
    if (sourceAssetIds.length > 20 ||
        sourceAssetIds.toSet().length != sourceAssetIds.length) {
      throw ArgumentError('Seleziona al massimo 20 file senza duplicati.');
    }
    if (targetLanguages.isEmpty ||
        targetLanguages.length > 20 ||
        targetLanguages.toSet().length != targetLanguages.length) {
      throw ArgumentError('Seleziona da 1 a 20 lingue senza duplicati.');
    }
    final language = RegExp(_studioLanguagePattern);
    if (targetLanguages.any((value) => !language.hasMatch(value)) ||
        (sourceLanguage != null && !language.hasMatch(sourceLanguage!))) {
      throw ArgumentError('Uno o più codici lingua non sono validi.');
    }
    if (sourceLanguage != null && targetLanguages.contains(sourceLanguage)) {
      throw ArgumentError('La lingua sorgente non può essere anche una destinazione.');
    }
    if (avatarMode == 'personal' && !avatarConsent) {
      throw ArgumentError('Serve il consenso verificato per usare un avatar personale.');
    }
    if (voiceMode == 'clone' && !voiceConsent) {
      throw ArgumentError('Serve il consenso verificato per clonare una voce.');
    }
    if (task == StudioTask.interactiveVideo && !interactive) {
      throw ArgumentError('Attiva la modalità video interattivo.');
    }
    if ({
          StudioTask.documentToVideo,
          StudioTask.slidesToVideo,
          StudioTask.talkingPhoto,
          StudioTask.translateDub,
          StudioTask.screenExplainer,
        }.contains(task) &&
        sourceAssetIds.isEmpty) {
      throw ArgumentError('Questa attività richiede un file sorgente.');
    }
    if ({
          StudioTask.scriptToVideo,
          StudioTask.avatarVideo,
        }.contains(task) &&
        script.trim().isEmpty &&
        sourceAssetIds.isEmpty) {
      throw ArgumentError('Inserisci uno script o seleziona un file sorgente.');
    }
    if (variables.length > 100 ||
        variables.entries.any((entry) =>
            entry.key.trim().isEmpty || entry.key.length > 80 || entry.value.length > 2000)) {
      throw ArgumentError('Le variabili del modello non sono valide.');
    }
  }

  Map<String, Object?> toJson() => {
        'task': task.apiValue,
        'title': title.trim(),
        'script': script,
        'sourceAssetIds': sourceAssetIds,
        'sourceLanguage': sourceLanguage,
        'targetLanguages': targetLanguages,
        'avatarMode': avatarMode,
        'avatarConsent': avatarConsent,
        'voiceMode': voiceMode,
        'voiceConsent': voiceConsent,
        'interactive': interactive,
        'templateId': templateId,
        'variables': variables,
      };
}

@immutable
class StudioJobDraft {
  const StudioJobDraft({
    required this.jobId,
    required this.state,
    required this.request,
    required this.providerState,
    required this.createdAt,
  });

  final String jobId;
  final String state;
  final Map<String, dynamic> request;
  final String providerState;
  final double createdAt;

  factory StudioJobDraft.fromJson(Map<String, dynamic> json) {
    final id = json['jobId'];
    final state = json['state'];
    final request = json['request'];
    if (id is! String || id.length != 32 || state is! String || request is! Map) {
      throw const FormatException('Bozza Studio non valida.');
    }
    return StudioJobDraft(
      jobId: id,
      state: state,
      request: Map<String, dynamic>.from(request),
      providerState: json['providerState']?.toString() ?? 'unknown',
      createdAt: (json['createdAt'] as num?)?.toDouble() ?? 0,
    );
  }
}
;

/// Parses comma-separated BCP-47 language codes, normalizing language/region
/// casing and removing duplicates while preserving the user's chosen order.
/// Invalid tokens are preserved so StudioJobRequest.validate can reject them.
List<String> parseStudioLanguageCodes(String input) {
  final result = <String>[];
  final seen = <String>{};
  final codePattern = RegExp(r'^([A-Za-z]{2,3})(?:-([A-Za-z]{2}))?$');
  for (final part in input.split(',')) {
    final token = part.trim();
    if (token.isEmpty) continue;
    final match = codePattern.firstMatch(token);
    final String normalized;
    if (match == null) {
      normalized = token;
    } else {
      final language = match.group(1)!.toLowerCase();
      final region = match.group(2);
      normalized = region == null ? language : language + '-' + region.toUpperCase();
    }
    if (seen.add(normalized.toLowerCase())) result.add(normalized);
  }
  return List.unmodifiable(result);
}

enum StudioTask {
  scriptToVideo('script_to_video', 'Video da testo'),
  documentToVideo('document_to_video', 'Video da documento'),
  slidesToVideo('slides_to_video', 'Video da presentazione'),
  avatarVideo('avatar_video', 'Presentatore IA'),
  talkingPhoto('talking_photo', 'Foto parlante'),
  translateDub('translate_dub', 'Traduzione e doppiaggio'),
  interactiveVideo('interactive_video', 'Video interattivo'),
  bulkPersonalization('bulk_personalization', 'Video personalizzati'),
  screenExplainer('screen_explainer', 'Video tutorial schermo');

  const StudioTask(this.apiValue, this.label);
  final String apiValue;
  final String label;
}

@immutable
class StudioJobRequest {
  const StudioJobRequest({
    required this.task,
    this.title = 'Nuovo video IA',
    this.script = '',
    this.sourceAssetIds = const [],
    this.sourceLanguage,
    this.targetLanguages = const ['it-IT'],
    this.avatarMode = 'none',
    this.avatarConsent = false,
    this.voiceMode = 'synthetic',
    this.voiceConsent = false,
    this.interactive = false,
    this.templateId,
    this.variables = const {},
  });

  final StudioTask task;
  final String title;
  final String script;
  final List<String> sourceAssetIds;
  final String? sourceLanguage;
  final List<String> targetLanguages;
  final String avatarMode;
  final bool avatarConsent;
  final String voiceMode;
  final bool voiceConsent;
  final bool interactive;
  final String? templateId;
  final Map<String, String> variables;

  void validate() {
    if (title.trim().isEmpty || title.length > 120) {
      throw ArgumentError('Inserisci un titolo da 1 a 120 caratteri.');
    }
    if (script.length > 30000) {
      throw ArgumentError('Lo script supera il limite di 30.000 caratteri.');
    }
    if (sourceAssetIds.length > 20 ||
        sourceAssetIds.toSet().length != sourceAssetIds.length) {
      throw ArgumentError('Seleziona al massimo 20 file senza duplicati.');
    }
    if (targetLanguages.isEmpty ||
        targetLanguages.length > 20 ||
        targetLanguages.toSet().length != targetLanguages.length) {
      throw ArgumentError('Seleziona da 1 a 20 lingue senza duplicati.');
    }
    final language = RegExp(_studioLanguagePattern);
    if (targetLanguages.any((value) => !language.hasMatch(value)) ||
        (sourceLanguage != null && !language.hasMatch(sourceLanguage!))) {
      throw ArgumentError('Uno o più codici lingua non sono validi.');
    }
    if (sourceLanguage != null && targetLanguages.contains(sourceLanguage)) {
      throw ArgumentError('La lingua sorgente non può essere anche una destinazione.');
    }
    if (avatarMode == 'personal' && !avatarConsent) {
      throw ArgumentError('Serve il consenso verificato per usare un avatar personale.');
    }
    if (voiceMode == 'clone' && !voiceConsent) {
      throw ArgumentError('Serve il consenso verificato per clonare una voce.');
    }
    if (task == StudioTask.interactiveVideo && !interactive) {
      throw ArgumentError('Attiva la modalità video interattivo.');
    }
    if ({
          StudioTask.documentToVideo,
          StudioTask.slidesToVideo,
          StudioTask.talkingPhoto,
          StudioTask.translateDub,
          StudioTask.screenExplainer,
        }.contains(task) &&
        sourceAssetIds.isEmpty) {
      throw ArgumentError('Questa attività richiede un file sorgente.');
    }
    if ({
          StudioTask.scriptToVideo,
          StudioTask.avatarVideo,
        }.contains(task) &&
        script.trim().isEmpty &&
        sourceAssetIds.isEmpty) {
      throw ArgumentError('Inserisci uno script o seleziona un file sorgente.');
    }
    if (variables.length > 100 ||
        variables.entries.any((entry) =>
            entry.key.trim().isEmpty || entry.key.length > 80 || entry.value.length > 2000)) {
      throw ArgumentError('Le variabili del modello non sono valide.');
    }
  }

  Map<String, Object?> toJson() => {
        'task': task.apiValue,
        'title': title.trim(),
        'script': script,
        'sourceAssetIds': sourceAssetIds,
        'sourceLanguage': sourceLanguage,
        'targetLanguages': targetLanguages,
        'avatarMode': avatarMode,
        'avatarConsent': avatarConsent,
        'voiceMode': voiceMode,
        'voiceConsent': voiceConsent,
        'interactive': interactive,
        'templateId': templateId,
        'variables': variables,
      };
}

@immutable
class StudioJobDraft {
  const StudioJobDraft({
    required this.jobId,
    required this.state,
    required this.request,
    required this.providerState,
    required this.createdAt,
  });

  final String jobId;
  final String state;
  final Map<String, dynamic> request;
  final String providerState;
  final double createdAt;

  factory StudioJobDraft.fromJson(Map<String, dynamic> json) {
    final id = json['jobId'];
    final state = json['state'];
    final request = json['request'];
    if (id is! String || id.length != 32 || state is! String || request is! Map) {
      throw const FormatException('Bozza Studio non valida.');
    }
    return StudioJobDraft(
      jobId: id,
      state: state,
      request: Map<String, dynamic>.from(request),
      providerState: json['providerState']?.toString() ?? 'unknown',
      createdAt: (json['createdAt'] as num?)?.toDouble() ?? 0,
    );
  }
}
);
  for (final part in input.split(',')) {
    final token = part.trim();
    if (token.isEmpty) continue;
    final match = codePattern.firstMatch(token);
    final String normalized;
    if (match == null) {
      normalized = token;
    } else {
      final language = match.group(1)!.toLowerCase();
      final region = match.group(2);
      normalized = region == null ? language : language + '-' + region.toUpperCase();
    }
    if (seen.add(normalized.toLowerCase())) result.add(normalized);
  }
  return List.unmodifiable(result);
}

enum StudioTask {
  scriptToVideo('script_to_video', 'Video da testo'),
  documentToVideo('document_to_video', 'Video da documento'),
  slidesToVideo('slides_to_video', 'Video da presentazione'),
  avatarVideo('avatar_video', 'Presentatore IA'),
  talkingPhoto('talking_photo', 'Foto parlante'),
  translateDub('translate_dub', 'Traduzione e doppiaggio'),
  interactiveVideo('interactive_video', 'Video interattivo'),
  bulkPersonalization('bulk_personalization', 'Video personalizzati'),
  screenExplainer('screen_explainer', 'Video tutorial schermo');

  const StudioTask(this.apiValue, this.label);
  final String apiValue;
  final String label;
}

@immutable
class StudioJobRequest {
  const StudioJobRequest({
    required this.task,
    this.title = 'Nuovo video IA',
    this.script = '',
    this.sourceAssetIds = const [],
    this.sourceLanguage,
    this.targetLanguages = const ['it-IT'],
    this.avatarMode = 'none',
    this.avatarConsent = false,
    this.voiceMode = 'synthetic',
    this.voiceConsent = false,
    this.interactive = false,
    this.templateId,
    this.variables = const {},
  });

  final StudioTask task;
  final String title;
  final String script;
  final List<String> sourceAssetIds;
  final String? sourceLanguage;
  final List<String> targetLanguages;
  final String avatarMode;
  final bool avatarConsent;
  final String voiceMode;
  final bool voiceConsent;
  final bool interactive;
  final String? templateId;
  final Map<String, String> variables;

  void validate() {
    if (title.trim().isEmpty || title.length > 120) {
      throw ArgumentError('Inserisci un titolo da 1 a 120 caratteri.');
    }
    if (script.length > 30000) {
      throw ArgumentError('Lo script supera il limite di 30.000 caratteri.');
    }
    if (sourceAssetIds.length > 20 ||
        sourceAssetIds.toSet().length != sourceAssetIds.length) {
      throw ArgumentError('Seleziona al massimo 20 file senza duplicati.');
    }
    if (targetLanguages.isEmpty ||
        targetLanguages.length > 20 ||
        targetLanguages.toSet().length != targetLanguages.length) {
      throw ArgumentError('Seleziona da 1 a 20 lingue senza duplicati.');
    }
    final language = RegExp(_studioLanguagePattern);
    if (targetLanguages.any((value) => !language.hasMatch(value)) ||
        (sourceLanguage != null && !language.hasMatch(sourceLanguage!))) {
      throw ArgumentError('Uno o più codici lingua non sono validi.');
    }
    if (sourceLanguage != null && targetLanguages.contains(sourceLanguage)) {
      throw ArgumentError('La lingua sorgente non può essere anche una destinazione.');
    }
    if (avatarMode == 'personal' && !avatarConsent) {
      throw ArgumentError('Serve il consenso verificato per usare un avatar personale.');
    }
    if (voiceMode == 'clone' && !voiceConsent) {
      throw ArgumentError('Serve il consenso verificato per clonare una voce.');
    }
    if (task == StudioTask.interactiveVideo && !interactive) {
      throw ArgumentError('Attiva la modalità video interattivo.');
    }
    if ({
          StudioTask.documentToVideo,
          StudioTask.slidesToVideo,
          StudioTask.talkingPhoto,
          StudioTask.translateDub,
          StudioTask.screenExplainer,
        }.contains(task) &&
        sourceAssetIds.isEmpty) {
      throw ArgumentError('Questa attività richiede un file sorgente.');
    }
    if ({
          StudioTask.scriptToVideo,
          StudioTask.avatarVideo,
        }.contains(task) &&
        script.trim().isEmpty &&
        sourceAssetIds.isEmpty) {
      throw ArgumentError('Inserisci uno script o seleziona un file sorgente.');
    }
    if (variables.length > 100 ||
        variables.entries.any((entry) =>
            entry.key.trim().isEmpty || entry.key.length > 80 || entry.value.length > 2000)) {
      throw ArgumentError('Le variabili del modello non sono valide.');
    }
  }

  Map<String, Object?> toJson() => {
        'task': task.apiValue,
        'title': title.trim(),
        'script': script,
        'sourceAssetIds': sourceAssetIds,
        'sourceLanguage': sourceLanguage,
        'targetLanguages': targetLanguages,
        'avatarMode': avatarMode,
        'avatarConsent': avatarConsent,
        'voiceMode': voiceMode,
        'voiceConsent': voiceConsent,
        'interactive': interactive,
        'templateId': templateId,
        'variables': variables,
      };
}

@immutable
class StudioJobDraft {
  const StudioJobDraft({
    required this.jobId,
    required this.state,
    required this.request,
    required this.providerState,
    required this.createdAt,
  });

  final String jobId;
  final String state;
  final Map<String, dynamic> request;
  final String providerState;
  final double createdAt;

  factory StudioJobDraft.fromJson(Map<String, dynamic> json) {
    final id = json['jobId'];
    final state = json['state'];
    final request = json['request'];
    if (id is! String || id.length != 32 || state is! String || request is! Map) {
      throw const FormatException('Bozza Studio non valida.');
    }
    return StudioJobDraft(
      jobId: id,
      state: state,
      request: Map<String, dynamic>.from(request),
      providerState: json['providerState']?.toString() ?? 'unknown',
      createdAt: (json['createdAt'] as num?)?.toDouble() ?? 0,
    );
  }
}
;

/// Parses comma-separated BCP-47 language codes, normalizing language/region
/// casing and removing duplicates while preserving the user's chosen order.
/// Invalid tokens are preserved so StudioJobRequest.validate can reject them.
List<String> parseStudioLanguageCodes(String input) {
  final result = <String>[];
  final seen = <String>{};
  final codePattern = RegExp(r'^([A-Za-z]{2,3})(?:-([A-Za-z]{2}))?$');
  for (final part in input.split(',')) {
    final token = part.trim();
    if (token.isEmpty) continue;
    final match = codePattern.firstMatch(token);
    final String normalized;
    if (match == null) {
      normalized = token;
    } else {
      final language = match.group(1)!.toLowerCase();
      final region = match.group(2);
      normalized = region == null ? language : language + '-' + region.toUpperCase();
    }
    if (seen.add(normalized.toLowerCase())) result.add(normalized);
  }
  return List.unmodifiable(result);
}

enum StudioTask {
  scriptToVideo('script_to_video', 'Video da testo'),
  documentToVideo('document_to_video', 'Video da documento'),
  slidesToVideo('slides_to_video', 'Video da presentazione'),
  avatarVideo('avatar_video', 'Presentatore IA'),
  talkingPhoto('talking_photo', 'Foto parlante'),
  translateDub('translate_dub', 'Traduzione e doppiaggio'),
  interactiveVideo('interactive_video', 'Video interattivo'),
  bulkPersonalization('bulk_personalization', 'Video personalizzati'),
  screenExplainer('screen_explainer', 'Video tutorial schermo');

  const StudioTask(this.apiValue, this.label);
  final String apiValue;
  final String label;
}

@immutable
class StudioJobRequest {
  const StudioJobRequest({
    required this.task,
    this.title = 'Nuovo video IA',
    this.script = '',
    this.sourceAssetIds = const [],
    this.sourceLanguage,
    this.targetLanguages = const ['it-IT'],
    this.avatarMode = 'none',
    this.avatarConsent = false,
    this.voiceMode = 'synthetic',
    this.voiceConsent = false,
    this.interactive = false,
    this.templateId,
    this.variables = const {},
  });

  final StudioTask task;
  final String title;
  final String script;
  final List<String> sourceAssetIds;
  final String? sourceLanguage;
  final List<String> targetLanguages;
  final String avatarMode;
  final bool avatarConsent;
  final String voiceMode;
  final bool voiceConsent;
  final bool interactive;
  final String? templateId;
  final Map<String, String> variables;

  void validate() {
    if (title.trim().isEmpty || title.length > 120) {
      throw ArgumentError('Inserisci un titolo da 1 a 120 caratteri.');
    }
    if (script.length > 30000) {
      throw ArgumentError('Lo script supera il limite di 30.000 caratteri.');
    }
    if (sourceAssetIds.length > 20 ||
        sourceAssetIds.toSet().length != sourceAssetIds.length) {
      throw ArgumentError('Seleziona al massimo 20 file senza duplicati.');
    }
    if (targetLanguages.isEmpty ||
        targetLanguages.length > 20 ||
        targetLanguages.toSet().length != targetLanguages.length) {
      throw ArgumentError('Seleziona da 1 a 20 lingue senza duplicati.');
    }
    final language = RegExp(_studioLanguagePattern);
    if (targetLanguages.any((value) => !language.hasMatch(value)) ||
        (sourceLanguage != null && !language.hasMatch(sourceLanguage!))) {
      throw ArgumentError('Uno o più codici lingua non sono validi.');
    }
    if (sourceLanguage != null && targetLanguages.contains(sourceLanguage)) {
      throw ArgumentError('La lingua sorgente non può essere anche una destinazione.');
    }
    if (avatarMode == 'personal' && !avatarConsent) {
      throw ArgumentError('Serve il consenso verificato per usare un avatar personale.');
    }
    if (voiceMode == 'clone' && !voiceConsent) {
      throw ArgumentError('Serve il consenso verificato per clonare una voce.');
    }
    if (task == StudioTask.interactiveVideo && !interactive) {
      throw ArgumentError('Attiva la modalità video interattivo.');
    }
    if ({
          StudioTask.documentToVideo,
          StudioTask.slidesToVideo,
          StudioTask.talkingPhoto,
          StudioTask.translateDub,
          StudioTask.screenExplainer,
        }.contains(task) &&
        sourceAssetIds.isEmpty) {
      throw ArgumentError('Questa attività richiede un file sorgente.');
    }
    if ({
          StudioTask.scriptToVideo,
          StudioTask.avatarVideo,
        }.contains(task) &&
        script.trim().isEmpty &&
        sourceAssetIds.isEmpty) {
      throw ArgumentError('Inserisci uno script o seleziona un file sorgente.');
    }
    if (variables.length > 100 ||
        variables.entries.any((entry) =>
            entry.key.trim().isEmpty || entry.key.length > 80 || entry.value.length > 2000)) {
      throw ArgumentError('Le variabili del modello non sono valide.');
    }
  }

  Map<String, Object?> toJson() => {
        'task': task.apiValue,
        'title': title.trim(),
        'script': script,
        'sourceAssetIds': sourceAssetIds,
        'sourceLanguage': sourceLanguage,
        'targetLanguages': targetLanguages,
        'avatarMode': avatarMode,
        'avatarConsent': avatarConsent,
        'voiceMode': voiceMode,
        'voiceConsent': voiceConsent,
        'interactive': interactive,
        'templateId': templateId,
        'variables': variables,
      };
}

@immutable
class StudioJobDraft {
  const StudioJobDraft({
    required this.jobId,
    required this.state,
    required this.request,
    required this.providerState,
    required this.createdAt,
  });

  final String jobId;
  final String state;
  final Map<String, dynamic> request;
  final String providerState;
  final double createdAt;

  factory StudioJobDraft.fromJson(Map<String, dynamic> json) {
    final id = json['jobId'];
    final state = json['state'];
    final request = json['request'];
    if (id is! String || id.length != 32 || state is! String || request is! Map) {
      throw const FormatException('Bozza Studio non valida.');
    }
    return StudioJobDraft(
      jobId: id,
      state: state,
      request: Map<String, dynamic>.from(request),
      providerState: json['providerState']?.toString() ?? 'unknown',
      createdAt: (json['createdAt'] as num?)?.toDouble() ?? 0,
    );
  }
}

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:video_player/video_player.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import 'models/editor_project.dart';
import 'account/account_security_screen.dart';
import 'account/account_premium_page.dart';
import 'services/project_store.dart';
import 'services/smart_shield_manager.dart';
import 'editor/session_timeline_editor.dart';
import 'editor/magiciaedit_panel.dart';
import 'editor/remote_export_panel.dart';
import 'studio/synthesia_studio_screen.dart';
import 'studio/magiclink_screen.dart';
import 'studio/home_dashboard.dart';
import 'team/team_studio_screen.dart';

void main() => runApp(const EditoreApp());

enum AppLanguage { it, en, fr, es, ar }

class EditoreApp extends StatefulWidget {
  const EditoreApp({super.key});

  @override
  State<EditoreApp> createState() => _EditoreAppState();
}

class _EditoreAppState extends State<EditoreApp> {
  AppLanguage language = AppLanguage.it;
  late final SmartShieldManager _smartShield;

  @override
  void initState() {
    super.initState();
    _smartShield = SmartShieldManager()..start();
  }

  @override
  void dispose() {
    _smartShield.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MagicIAedit – AI Photo & Video Studio',
      locale: Locale(language.name),
      supportedLocales: const [
        Locale('it'),
        Locale('en'),
        Locale('fr'),
        Locale('es'),
        Locale('ar'),
      ],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF9B8CFF),
          brightness: Brightness.dark,
          surface: const Color(0xFF191A24),
        ),
        scaffoldBackgroundColor: const Color(0xFF10111A),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF10111A),
          foregroundColor: Color(0xFFF5F3FF),
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1A1B27),
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(22)),
            side: BorderSide(color: Color(0x22B9ADFF)),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF171823),
          indicatorColor: const Color(0xFF393253),
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              color: states.contains(WidgetState.selected)
                  ? const Color(0xFFE9E3FF)
                  : const Color(0xFF9B9BAA),
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF7565C9),
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF20212E),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0x223D3B50)),
          ),
        ),
        dividerColor: const Color(0x223D3B50),
      ),
      home: HomePage(
        language: language,
        smartShield: _smartShield,
        onLanguageChanged: (value) => setState(() => language = value),
      ),
    );
  }
}

class Copy {
  static const Map<AppLanguage, Map<String, String>> strings = {
    AppLanguage.it: {
      'app': 'MagicIAedit',
      'subtitle': 'Il tuo studio creativo',
      'newProject': 'Nuovo progetto',
      'import': 'Importa foto o video',
      'recent': 'I tuoi strumenti',
      'video': 'Editor video',
      'photo': 'Editor foto',
      'ai': 'Studio IA',
      'templates': 'Modelli',
      'invite': 'Invita amici',
      'premium': 'Premium',
      'settings': 'Impostazioni',
      'choose': 'Scegli un file multimediale per iniziare.',
      'unsupported': 'Formato non supportato o file non selezionato.',
      'preview': 'Anteprima progetto',
      'timeline': 'Timeline',
      'export': 'Esporta',
      'share': 'Condividi',
      'effects': 'Effetti',
      'text': 'Testo',
      'audio': 'Audio',
      'trim': 'Taglia',
      'aiComing': 'Gli strumenti IA si collegheranno qui: sottotitoli, rimozione sfondo, generazione e miglioramento.',
      'free': 'Gratuito',
      'language': 'Lingua',
      'zoom': 'Zoom anteprima',
      'noMedia': 'Importa un video o una foto per vedere l’anteprima.',
      'exportNote': 'Esportazione/rendering: da collegare al motore video nella prossima fase.',
      'shareNote': 'La condivisione di sistema sarà collegata dopo l’esportazione.',
      'savedProjects': 'Progetti salvati',
      'noSavedProjects': 'Nessun progetto salvato.',
      'renameProject': 'Rinomina',
      'deleteProject': 'Elimina',
      'renameProjectTitle': 'Rinomina progetto',
      'deleteProjectTitle': 'Elimina progetto',
      'deleteProjectQuestion': 'Vuoi eliminare definitivamente questo progetto e i suoi backup?',
      'cancel': 'Annulla',
      'save': 'Salva',
    },
    AppLanguage.en: {
      'app': 'MagicIAedit',
      'subtitle': 'Your creative studio',
      'newProject': 'New project',
      'import': 'Import photo or video',
      'recent': 'Your tools',
      'video': 'Video editor',
      'photo': 'Photo editor',
      'ai': 'AI Studio',
      'templates': 'Templates',
      'invite': 'Invite friends',
      'premium': 'Premium',
      'settings': 'Settings',
      'choose': 'Choose media to get started.',
      'unsupported': 'Unsupported format or no file selected.',
      'preview': 'Project preview',
      'timeline': 'Timeline',
      'export': 'Export',
      'share': 'Share',
      'effects': 'Effects',
      'text': 'Text',
      'audio': 'Audio',
      'trim': 'Trim',
      'aiComing': 'AI tools will connect here: captions, background removal, generation and enhancement.',
      'free': 'Free',
      'language': 'Language',
      'zoom': 'Preview zoom',
      'noMedia': 'Import a video or photo to preview it.',
      'exportNote': 'Export/rendering will be connected to the media engine in the next phase.',
      'shareNote': 'System sharing will be connected after export.',
      'savedProjects': 'Saved projects',
      'noSavedProjects': 'No saved projects yet.',
      'renameProject': 'Rename',
      'deleteProject': 'Delete',
      'renameProjectTitle': 'Rename project',
      'deleteProjectTitle': 'Delete project',
      'deleteProjectQuestion': 'Permanently delete this project and its backups?',
      'cancel': 'Cancel',
      'save': 'Save',
    },
    AppLanguage.fr: {
      'app': 'MagicIAedit',
      'subtitle': 'Votre studio créatif',
      'newProject': 'Nouveau projet',
      'import': 'Importer photo ou vidéo',
      'recent': 'Vos outils',
      'video': 'Éditeur vidéo',
      'photo': 'Éditeur photo',
      'ai': 'Studio IA',
      'templates': 'Modèles',
      'invite': 'Inviter des amis',
      'premium': 'Premium',
      'settings': 'Paramètres',
      'choose': 'Choisissez un média pour commencer.',
      'unsupported': 'Format non pris en charge ou aucun fichier sélectionné.',
      'preview': 'Aperçu du projet',
      'timeline': 'Timeline',
      'export': 'Exporter',
      'share': 'Partager',
      'effects': 'Effets',
      'text': 'Texte',
      'audio': 'Audio',
      'trim': 'Rogner',
      'aiComing': 'Les outils IA seront connectés ici : sous-titres, suppression d’arrière-plan, génération et amélioration.',
      'free': 'Gratuit',
      'language': 'Langue',
      'zoom': 'Zoom aperçu',
      'noMedia': 'Importez une vidéo ou une photo pour l’aperçu.',
      'exportNote': 'Le rendu sera connecté au moteur média dans la prochaine étape.',
      'shareNote': 'Le partage système sera connecté après l’export.',
      'savedProjects': 'Projets enregistrés',
      'noSavedProjects': 'Aucun projet enregistré.',
      'renameProject': 'Renommer',
      'deleteProject': 'Supprimer',
      'renameProjectTitle': 'Renommer le projet',
      'deleteProjectTitle': 'Supprimer le projet',
      'deleteProjectQuestion': 'Supprimer définitivement ce projet et ses sauvegardes ?',
      'cancel': 'Annuler',
      'save': 'Enregistrer',
    },
    AppLanguage.es: {
      'app': 'MagicIAedit',
      'subtitle': 'Tu estudio creativo',
      'newProject': 'Nuevo proyecto',
      'import': 'Importar foto o vídeo',
      'recent': 'Tus herramientas',
      'video': 'Editor de vídeo',
      'photo': 'Editor de fotos',
      'ai': 'Estudio IA',
      'templates': 'Plantillas',
      'invite': 'Invitar amigos',
      'premium': 'Premium',
      'settings': 'Ajustes',
      'choose': 'Elige un archivo multimedia para empezar.',
      'unsupported': 'Formato no compatible o archivo no seleccionado.',
      'preview': 'Vista previa del proyecto',
      'timeline': 'Línea de tiempo',
      'export': 'Exportar',
      'share': 'Compartir',
      'effects': 'Efectos',
      'text': 'Texto',
      'audio': 'Audio',
      'trim': 'Recortar',
      'aiComing': 'Aquí se conectarán las herramientas IA: subtítulos, quitar fondo, generación y mejora.',
      'free': 'Gratis',
      'language': 'Idioma',
      'zoom': 'Zoom de vista previa',
      'noMedia': 'Importa un vídeo o una foto para previsualizarlo.',
      'exportNote': 'El renderizado se conectará al motor multimedia en la siguiente fase.',
      'shareNote': 'El uso compartido del sistema se conectará después de exportar.',
      'savedProjects': 'Proyectos guardados',
      'noSavedProjects': 'Todavía no hay proyectos guardados.',
      'renameProject': 'Renombrar',
      'deleteProject': 'Eliminar',
      'renameProjectTitle': 'Renombrar proyecto',
      'deleteProjectTitle': 'Eliminar proyecto',
      'deleteProjectQuestion': '¿Eliminar definitivamente este proyecto y sus copias de seguridad?',
      'cancel': 'Cancelar',
      'save': 'Guardar',
    },
    AppLanguage.ar: {
      'app': 'MagicIAedit',
      'subtitle': 'استوديو الإبداع الخاص بك',
      'newProject': 'مشروع جديد',
      'import': 'استيراد صورة أو فيديو',
      'recent': 'أدواتك',
      'video': 'محرر الفيديو',
      'photo': 'محرر الصور',
      'ai': 'استوديو الذكاء الاصطناعي',
      'templates': 'القوالب',
      'invite': 'دعوة الأصدقاء',
      'premium': 'بريميوم',
      'settings': 'الإعدادات',
      'choose': 'اختر ملف وسائط للبدء.',
      'unsupported': 'تنسيق غير مدعوم أو لم يتم اختيار ملف.',
      'preview': 'معاينة المشروع',
      'timeline': 'الخط الزمني',
      'export': 'تصدير',
      'share': 'مشاركة',
      'effects': 'التأثيرات',
      'text': 'نص',
      'audio': 'الصوت',
      'trim': 'قص',
      'aiComing': 'ستتوفر هنا أدوات الذكاء الاصطناعي: الترجمة وإزالة الخلفية والتوليد والتحسين.',
      'free': 'مجاني',
      'language': 'اللغة',
      'zoom': 'تكبير المعاينة',
      'noMedia': 'استورد فيديو أو صورة لمعاينتها.',
      'exportNote': 'سيتم ربط التصدير بمحرك الوسائط في المرحلة التالية.',
      'shareNote': 'ستتم إضافة المشاركة بعد التصدير.',
      'savedProjects': 'المشاريع المحفوظة',
      'noSavedProjects': 'لا توجد مشاريع محفوظة بعد.',
      'renameProject': 'إعادة تسمية',
      'deleteProject': 'حذف',
      'renameProjectTitle': 'إعادة تسمية المشروع',
      'deleteProjectTitle': 'حذف المشروع',
      'deleteProjectQuestion': 'هل تريد حذف هذا المشروع ونسخه الاحتياطية نهائياً؟',
      'cancel': 'إلغاء',
      'save': 'حفظ',
    },
  };

  static String get(AppLanguage language, String key) =>
      strings[language]?[key] ?? strings[AppLanguage.en]![key] ?? key;
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.language,
    required this.smartShield,
    required this.onLanguageChanged,
  });

  final AppLanguage language;
  final SmartShieldManager smartShield;
  final ValueChanged<AppLanguage> onLanguageChanged;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  PlatformFile? media;

  @override
  void initState() {
    super.initState();
    widget.smartShield.addListener(_handleSmartShieldChange);
    _refreshSavedProjects();
  }

  void _handleSmartShieldChange() {
    if (widget.smartShield.isInBackground) {
      // Stop decoders and audio output while the app is not visible.
      videoController?.pause();
      audioController?.pause();
    }
    if (mounted) setState(() {});
  }
  VideoPlayerController? videoController;
  AudioPlayer? audioController;
  double zoom = 1;
  int selectedTab = 11;
  EditorProject project = const EditorProject(id: 'draft', name: 'Nuovo progetto');
  List<EditorProject> savedProjects = const [];
  bool _loadingSavedProjects = true;
  final ProjectSaveQueue _projectSaveQueue = ProjectSaveQueue();

  Future<void> _refreshSavedProjects() async {
    try {
      final directory = await getApplicationSupportDirectory();
      final projects = await const ProjectStore().listProjects(
        Directory('${directory.path}/editore_progetti'),
      );
      if (!mounted) return;
      setState(() => savedProjects = projects);
    } catch (error) {
      if (mounted) _message('Impossibile caricare i progetti salvati: $error');
    } finally {
      if (mounted) setState(() => _loadingSavedProjects = false);
    }
  }

  void _upsertSavedProject(EditorProject updated) {
    final projects = [...savedProjects]
      ..removeWhere((item) => item.id == updated.id)
      ..insert(0, updated);
    // Keep the in-memory dashboard aligned with ProjectStore.listProjects:
    // every successful save moves that project to the recent-first position.
    setState(() => savedProjects = projects);
  }

  Future<bool> _persistProject(EditorProject updated) async {
    try {
      final directory = await getApplicationSupportDirectory();
      await _projectSaveQueue.save(
        updated,
        Directory('${directory.path}/editore_progetti'),
      );
      if (mounted) _upsertSavedProject(updated);
      return true;
    } catch (error) {
      if (mounted) _message('Salvataggio progetto non riuscito: $error');
      return false;
    }
  }

  Future<void> _renameSavedProject(EditorProject saved) async {
    final controller = TextEditingController(text: saved.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t('renameProjectTitle')),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(t('save')),
          ),
        ],
      ),
    );
    controller.dispose();
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty || trimmed == saved.name) return;
    final updated = saved.copyWith(name: trimmed);
    if (await _persistProject(updated) && mounted && project.id == updated.id) {
      setState(() => project = updated);
    }
  }

  Future<void> _deleteSavedProject(EditorProject saved) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t('deleteProjectTitle')),
        content: Text(t('deleteProjectQuestion')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(t('deleteProject')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final directory = await getApplicationSupportDirectory();
      await _projectSaveQueue.delete(
        saved.id,
        Directory('${directory.path}/editore_progetti'),
      );
      if (!mounted) return;
      final wasOpen = project.id == saved.id;
      final oldVideo = wasOpen ? videoController : null;
      final oldAudio = wasOpen ? audioController : null;
      setState(() {
        savedProjects = savedProjects.where((item) => item.id != saved.id).toList();
        if (wasOpen) {
          project = const EditorProject(id: 'draft', name: 'Nuovo progetto');
          media = null;
          videoController = null;
          audioController = null;
          selectedTab = 0;
        }
      });
      await oldVideo?.dispose();
      await oldAudio?.dispose();
      if (mounted) _message('Progetto eliminato.');
    } catch (error) {
      if (mounted) _message('Eliminazione progetto non riuscita: $error');
    }
  }

  Future<void> _activateSavedProject({
    required EditorProject saved,
    PlatformFile? preview,
    VideoPlayerController? nextVideo,
    AudioPlayer? nextAudio,
    required String message,
  }) async {
    if (!mounted) {
      await nextVideo?.dispose();
      await nextAudio?.dispose();
      return;
    }
    final oldVideo = videoController;
    final oldAudio = audioController;
    setState(() {
      project = saved;
      media = preview;
      videoController = nextVideo;
      audioController = nextAudio;
      selectedTab = 0;
      zoom = 1;
    });
    await oldVideo?.dispose();
    await oldAudio?.dispose();
    if (mounted) _message(message);
  }

  Future<void> _openSavedProject(EditorProject saved) async {
    final clips = saved.tracks
        .expand((track) => track.clips)
        .where((clip) => clip.kind != MediaKind.text)
        .toList()
      ..sort((a, b) => a.startMs.compareTo(b.startMs));

    if (clips.isEmpty) {
      await _activateSavedProject(
        saved: saved,
        message: 'Progetto caricato. Non contiene ancora file multimediali.',
      );
      return;
    }

    final source = File(clips.first.source);
    if (!await source.exists()) {
      await _activateSavedProject(
        saved: saved,
        message: 'Progetto aperto, ma il file sorgente non è disponibile.',
      );
      return;
    }

    VideoPlayerController? nextVideo;
    AudioPlayer? nextAudio;
    try {
      if (clips.first.kind == MediaKind.video) {
        nextVideo = VideoPlayerController.file(source);
        await nextVideo.initialize();
      } else if (clips.first.kind == MediaKind.audio) {
        nextAudio = AudioPlayer();
        await nextAudio.setFilePath(source.path);
      }
      final preview = PlatformFile(
        name: source.uri.pathSegments.last,
        size: await source.length(),
        path: source.path,
      );
      await _activateSavedProject(
        saved: saved,
        preview: preview,
        nextVideo: nextVideo,
        nextAudio: nextAudio,
        message: 'Progetto caricato.',
      );
    } catch (error) {
      await nextVideo?.dispose();
      await nextAudio?.dispose();
      if (mounted) _message('Impossibile aprire il progetto: $error');
    }
  }

  void _handleProjectChanged(EditorProject updated) {
    if (!mounted) return;
    setState(() => project = updated);
    _persistProject(updated);
  }

  Future<bool> _applyMagicIAeditProject(EditorProject updated) async {
    final saved = await _persistProject(updated);
    if (!saved || !mounted) return false;
    setState(() => project = updated);
    return true;
  }

  String t(String key) => Copy.get(widget.language, key);

  Future<void> _startNewProject() async {
    final oldVideo = videoController;
    final oldAudio = audioController;
    setState(() {
      project = EditorProject(
        id: 'project_${DateTime.now().millisecondsSinceEpoch}',
        name: 'Nuovo progetto',
      );
      media = null;
      videoController = null;
      audioController = null;
      zoom = 1;
      selectedTab = 0;
    });
    await oldVideo?.dispose();
    await oldAudio?.dispose();
  }

  Future<void> importMedia({bool photosOnly = false, int? maxFiles}) async {
    final result = await FilePicker.platform.pickFiles(
      type: photosOnly ? FileType.image : FileType.custom,
      allowedExtensions: photosOnly ? null : [
        'mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v',
        'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp',
        'mp3', 'm4a', 'aac', 'wav', 'ogg', 'opus', 'flac', 'aiff', 'wma',
      ],
      allowMultiple: true,
      withData: false,
    );

    if (result == null || result.files.isEmpty) return;
    final selectedFiles = maxFiles == null
        ? result.files
        : result.files.take(maxFiles).toList();
    if (photosOnly && result.files.length > selectedFiles.length && mounted) {
      _message('Per l’importazione rapida vengono utilizzate solo le prime ${selectedFiles.length} foto selezionate.');
    }

    var updatedProject = project;
    var importedCount = 0;
    PlatformFile? lastImported;
    VideoPlayerController? previewController;
    AudioPlayer? previewAudioPlayer;

    final hasExistingClips =
        updatedProject.tracks.any((track) => track.clips.isNotEmpty);

    if (!hasExistingClips) {
      updatedProject = EditorProject(
        id: 'project_${DateTime.now().millisecondsSinceEpoch}',
        name: 'Nuovo progetto',
        tracks: updatedProject.tracks,
      );
    }

    int nextStartMs() {
      var end = 0;
      for (final track in updatedProject.tracks) {
        for (final clip in track.clips) {
          if (clip.endMs > end) end = clip.endMs;
        }
      }
      return end;
    }

    for (var i = 0; i < selectedFiles.length; i++) {
      final file = selectedFiles[i];
      final path = file.path;

      if (path == null) continue;

      final isVideo = _isVideo(file.name);
      final isAudio = _isAudio(file.name);
      final kind = isVideo
          ? MediaKind.video
          : isAudio
              ? MediaKind.audio
              : MediaKind.image;
      var durationMs = 5000;
      VideoPlayerController? candidateController;
      AudioPlayer? candidateAudioPlayer;

      if (isVideo) {
        try {
          candidateController =
              VideoPlayerController.file(File(path));
          await candidateController.initialize();
          durationMs = candidateController.value.duration.inMilliseconds
              .clamp(500, 7200000).toInt();
        } catch (_) {
          await candidateController?.dispose();
          candidateController = null;
          continue;
        }
      }

      if (isAudio) {
        try {
          candidateAudioPlayer = AudioPlayer();
          await candidateAudioPlayer.setFilePath(path);
          final audioDurationMs =
              candidateAudioPlayer.duration?.inMilliseconds;
          if (audioDurationMs != null && audioDurationMs > 0) {
            durationMs = audioDurationMs.clamp(500, 7200000).toInt();
          }
        } catch (_) {
          await candidateAudioPlayer?.dispose();
          candidateAudioPlayer = null;
          continue;
        }
      }

      final clip = EditorClip(
        id: 'clip_${DateTime.now().microsecondsSinceEpoch}_$i',
        source: path,
        kind: kind,
        startMs: nextStartMs(),
        durationMs: durationMs,
        title: file.name,
      );

      final tracks = [...updatedProject.tracks];
      final trackIndex = tracks.indexWhere(
        (track) => track.kind == kind && !track.locked,
      );

      if (trackIndex >= 0) {
        final track = tracks[trackIndex];
        tracks[trackIndex] = track.copyWith(
          clips: [...track.clips, clip]
            ..sort((a, b) => a.startMs.compareTo(b.startMs)),
        );
      } else {
        tracks.add(
          EditorTrack(
            id: 'track_${kind.name}_${DateTime.now().microsecondsSinceEpoch}',
            name: isVideo ? 'Video' : isAudio ? 'Audio' : 'Foto',
            kind: kind,
            clips: [clip],
          ),
        );
      }

      updatedProject = updatedProject.copyWith(tracks: tracks);
      importedCount++;
      lastImported = file;

      if (previewController != null) {
        await previewController.dispose();
        previewController = null;
      }

      if (candidateController != null) {
        previewController = candidateController;
      }
      if (previewAudioPlayer != null) {
        await previewAudioPlayer.dispose();
        previewAudioPlayer = null;
      }
      if (candidateAudioPlayer != null) {
        previewAudioPlayer = candidateAudioPlayer;
      }
    }

    if (!mounted) {
      await previewController?.dispose();
      await previewAudioPlayer?.dispose();
      return;
    }

    if (importedCount == 0 || lastImported == null) {
      await previewController?.dispose();
      await previewAudioPlayer?.dispose();
      _message(t('unsupported'));
      return;
    }

    final oldController = videoController;
    final oldAudioController = audioController;

    setState(() {
      project = updatedProject;
      media = lastImported;
      videoController = previewController;
      audioController = previewAudioPlayer;
      zoom = 1;
    });

    await oldController?.dispose();
    await oldAudioController?.dispose();
    await _persistProject(updatedProject);

    if (mounted) {
      _message('Importati $importedCount file nella timeline.');
    }
  }

  bool _isVideo(String name) {
    final lower = name.toLowerCase();
    return ['.mp4', '.mov', '.avi', '.mkv', '.webm', '.m4v']
        .any(lower.endsWith);
  }

  bool _isAudio(String name) {
    final lower = name.toLowerCase();
    return [
      '.mp3', '.m4a', '.aac', '.wav', '.ogg', '.opus',
      '.flac', '.aiff', '.wma',
    ].any(lower.endsWith);
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  void dispose() {
    widget.smartShield.removeListener(_handleSmartShieldChange);
    videoController?.dispose();
    audioController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = widget.language == AppLanguage.ar;
    return Directionality(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SvgPicture.asset(
                'assets/branding/magiciaedit_mark.svg',
                width: 34,
                height: 34,
                fit: BoxFit.contain,
              ),
              const SizedBox(width: 9),
              const Flexible(
                child: Text(
                  'MagicIAedit',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          actions: [
            if (selectedTab == 0 || selectedTab == 1 || selectedTab == 2)
              IconButton(
                tooltip: 'Importa rapidamente fino a 2 foto',
                icon: const Icon(Icons.photo_library_outlined),
                onPressed: () => importMedia(photosOnly: true, maxFiles: 2),
              ),
            if (selectedTab != 2)
              IconButton(
                tooltip: 'Apri MagicIAedit',
                icon: const Icon(Icons.auto_awesome),
                onPressed: () => setState(() => selectedTab = 2),
              ),
            if (selectedTab != 6)
              IconButton(
                tooltip: t('settings'),
                onPressed: () => setState(() => selectedTab = 6),
                icon: const Icon(Icons.settings_outlined),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: DropdownButton<AppLanguage>(
                value: widget.language,
                underline: const SizedBox.shrink(),
                onChanged: (value) {
                  if (value != null) widget.onLanguageChanged(value);
                },
                items: const [
                  DropdownMenuItem(value: AppLanguage.it, child: Text('🇮🇹 IT')),
                  DropdownMenuItem(value: AppLanguage.en, child: Text('🇬🇧 EN')),
                  DropdownMenuItem(value: AppLanguage.fr, child: Text('🇫🇷 FR')),
                  DropdownMenuItem(value: AppLanguage.es, child: Text('🇪🇸 ES')),
                  DropdownMenuItem(value: AppLanguage.ar, child: Text('🇸🇦 AR')),
                ],
              ),
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            final editor = selectedTab == 11
                ? HomeDashboard(
                    appName: t('app'),
                    subtitle: t('subtitle'),
                    newProjectLabel: t('newProject'),
                    importLabel: t('import'),
                    videoLabel: t('video'),
                    photoLabel: t('photo'),
                    aiLabel: t('ai'),
                    magicLinkLabel: 'MagicLink IA',
                    studioLabel: 'Synthesia Studio IA',
                    teamLabel: 'TeamStudio',
                    savedProjectsLabel: t('savedProjects'),
                    noSavedProjectsLabel: t('noSavedProjects'),
                    projects: savedProjects,
                    onNewProject: _startNewProject,
                    onImport: () {
                      setState(() => selectedTab = 0);
                      importMedia();
                    },
                    onVideo: () => setState(() => selectedTab = 0),
                    onPhoto: () => setState(() => selectedTab = 1),
                    onMagic: () => setState(() => selectedTab = 2),
                    onMagicLink: () => setState(() => selectedTab = 10),
                    onStudio: () => setState(() => selectedTab = 7),
                    onTeam: () => setState(() => selectedTab = 8),
                    onPremium: () => setState(() => selectedTab = 9),
                    onOpenProject: _openSavedProject,
                  )
                : selectedTab == 2
                ? MagicIAeditPanel(
                    project: project,
                    onProjectChanged: _applyMagicIAeditProject,
                    onMessage: _message,
                    onImportMedia: importMedia,
                  )
                : selectedTab == 6
                    ? const AccountSecurityScreen(
                        apiBaseUrl: String.fromEnvironment('MEDIA_API_URL'),
                      )
                    : selectedTab == 7
                        ? const SynthesiaStudioScreen(
                            apiBaseUrl: String.fromEnvironment('MEDIA_API_URL'),
                          )
                        : selectedTab == 8
                            ? const TeamStudioScreen(
                                apiBaseUrl: String.fromEnvironment('MEDIA_API_URL'),
                              )
                            : selectedTab == 10
                                ? MagicLinkScreen(
                                    apiBaseUrl: const String.fromEnvironment('MEDIA_API_URL'),
                                    onImportAuthorizedMedia: () async {
                                      setState(() => selectedTab = 0);
                                      await importMedia();
                                    },
                                  )
                            : selectedTab == 9
                                ? AccountPremiumPage(
                                    apiBaseUrl: const String.fromEnvironment('MEDIA_API_URL'),
                                    onSignIn: () => setState(() => selectedTab = 6),
                                  )
                                : _buildEditor(context);
            final sidebar = _buildSidebar(context);
            return Padding(
              padding: const EdgeInsets.all(16),
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 270, child: sidebar),
                        const SizedBox(width: 16),
                        Expanded(child: editor),
                      ],
                    )
                  : Column(
                      children: [
                        Expanded(child: editor),
                        const SizedBox(height: 8),
                        _buildMobileNavigation(context),
                      ],
                    ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildMobileNavigation(BuildContext context) {
    const destinations = <({int tab, IconData icon, String label})>[
      (tab: 11, icon: Icons.home_rounded, label: 'Home'),
      (tab: 0, icon: Icons.movie_outlined, label: 'Video'),
      (tab: 1, icon: Icons.photo_outlined, label: 'Foto'),
      (tab: 2, icon: Icons.auto_awesome, label: 'MagicIA'),
      (tab: 10, icon: Icons.link, label: 'MagicLink'),
    ];
    final selectedIndex = destinations.indexWhere((item) => item.tab == selectedTab);
    return NavigationBar(
      height: 70,
      selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
      onDestinationSelected: (index) {
        setState(() => selectedTab = destinations[index].tab);
      },
      destinations: destinations
          .map(
            (item) => NavigationDestination(
              icon: Icon(item.icon),
              label: item.label,
            ),
          )
          .toList(),
    );
  }

  Future<void> _openExportDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: SizedBox(
          width: 560,
          height: MediaQuery.sizeOf(dialogContext).height * 0.88,
          child: RemoteExportPanel(
            project: project,
            onClose: () => Navigator.of(dialogContext).pop(),
            onMessage: _message,
          ),
        ),
      ),
    );
  }

  Widget _buildEditor(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 12, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: const Color(0x337B6CE0),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.movie_creation_outlined, color: Color(0xFFC9BEFF)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t('preview'), style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text(
                              media?.name ?? 'Il tuo prossimo progetto inizia qui',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFFAAA8BC)),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0x222EC6B8),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0x5548CFC1)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.circle, size: 7, color: Color(0xFF55D6C5)),
                            SizedBox(width: 6),
                            Text(
                              'LIVE',
                              style: TextStyle(
                                color: Color(0xFF9DEDE2),
                                fontSize: 9,
                                letterSpacing: 1.1,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        tooltip: t('import'),
                        onPressed: importMedia,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF11121B), Color(0xFF202033), Color(0xFF151622)],
                      ),
                      border: Border.all(color: const Color(0x334E4B70)),
                    ),
                    alignment: Alignment.center,
                    child: media == null
                        ? Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 116,
                                  height: 116,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: const Color(0x332C1D63),
                                    boxShadow: const [
                                      BoxShadow(color: Color(0x557B45E8), blurRadius: 34, spreadRadius: 2),
                                    ],
                                    border: Border.all(color: const Color(0x557F6BE0)),
                                  ),
                                  child: SvgPicture.asset(
                                    'assets/branding/magiciaedit_mark.svg',
                                    fit: BoxFit.contain,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                const Text(
                                  'MagicIAedit',
                                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800, letterSpacing: .4, color: Color(0xFFF0E9FF)),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'CREA. TRASFORMA. STUPISCI.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.w700, color: Color(0xFFB9A8FF)),
                                ),
                                const SizedBox(height: 14),
                                Text(t('noMedia'), textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.white70)),
                                const SizedBox(height: 16),
                                FilledButton.icon(
                                  onPressed: importMedia,
                                  icon: const Icon(Icons.upload_file),
                                  label: Text(t('import')),
                                ),
                              ],
                            ),
                          )
                        : InteractiveViewer(
                            minScale: 1,
                            maxScale: 5,
                            child: _mediaPreview(),
                          ),
                  ),
                ),
                if (media != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.zoom_in),
                        Expanded(
                          child: Slider(
                            min: 1,
                            max: 4,
                            value: zoom,
                            label: '${zoom.toStringAsFixed(1)}×',
                            onChanged: (value) => setState(() => zoom = value),
                          ),
                        ),
                        Text('${zoom.toStringAsFixed(1)}×'),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (project.tracks.any((track) => track.clips.isNotEmpty))
          SizedBox(
            height: 300,
            child: SessionTimelineEditor(
              key: ValueKey(project.id),
              project: project,
              onProjectChanged: _handleProjectChanged,
              languageCode: widget.language.name,
            ),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(t('timeline')),
            ),
          ),
        const SizedBox(height: 8),
        Card(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => setState(() => selectedTab = 2),
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('MagicIAedit'),
                ),
                const SizedBox(width: 8),
                _toolButton(Icons.auto_awesome_outlined, t('effects'), () => _message('Libreria effetti: in sviluppo.')),
                const SizedBox(width: 6),
                _toolButton(Icons.title, t('text'), () => _message('Editor testo: in sviluppo.')),
                const SizedBox(width: 6),
                _toolButton(Icons.music_note, t('audio'), () => _message('Traccia audio: in sviluppo.')),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _openExportDialog,
                  icon: const Icon(Icons.file_upload_outlined),
                  label: Text(t('export')),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _mediaPreview() {
    final file = media!;
    if (_isVideo(file.name) && videoController != null) {
      final controller = videoController!;
      return Transform.scale(
        scale: zoom,
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: Stack(
            alignment: Alignment.center,
            children: [
              VideoPlayer(controller),
              IconButton.filledTonal(
                onPressed: () {
                  setState(() {
                    controller.value.isPlaying ? controller.pause() : controller.play();
                  });
                },
                icon: Icon(controller.value.isPlaying ? Icons.pause : Icons.play_arrow),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  height: 30,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Color(0xDD080912), Color(0x00080912)],
                    ),
                  ),
                  child: VideoProgressIndicator(
                    controller,
                    allowScrubbing: true,
                    colors: const VideoProgressColors(
                      playedColor: Color(0xFF9B86FF),
                      bufferedColor: Color(0x887C78A4),
                      backgroundColor: Color(0x557B7890),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_isAudio(file.name)) {
      final player = audioController;
      if (player == null) {
        return const Center(
          child: Icon(Icons.audio_file, size: 88, color: Colors.white),
        );
      }
      return Center(
        child: StreamBuilder<PlayerState>(
          stream: player.playerStateStream,
          builder: (context, snapshot) {
            final playing = snapshot.data?.playing ?? player.playing;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.audio_file, size: 88, color: Colors.white),
                const SizedBox(height: 12),
                Text(file.name,
                    style: const TextStyle(color: Colors.white),
                    textAlign: TextAlign.center),
                IconButton.filledTonal(
                  iconSize: 42,
                  onPressed: () {
                    if (player.playing) {
                      player.pause();
                    } else {
                      player.play();
                    }
                  },
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                ),
              ],
            );
          },
        ),
      );
    }
    if (file.path != null) {
      final previewScale = widget.smartShield.previewDecodeScale;
      final decodeWidth = (MediaQuery.sizeOf(context).width *
              MediaQuery.devicePixelRatioOf(context) *
              previewScale)
          .round()
          .clamp(256, 4096)
          .toInt();
      return Transform.scale(
        scale: zoom,
        child: Image.file(
          File(file.path!),
          fit: BoxFit.contain,
          cacheWidth: decodeWidth,
        ),
      );
    }
    return const Icon(Icons.broken_image, color: Colors.white);
  }

  Widget _buildSidebar(BuildContext context) {
    return Card(
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF24134F), Color(0xFF102B55), Color(0xFF24133F)],
              ),
              border: Border.all(color: const Color(0x557D65D8)),
            ),
            child: Row(
              children: [
                SvgPicture.asset(
                  'assets/branding/magiciaedit_mark.svg',
                  width: 48,
                  height: 48,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('MagicIAedit', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: .2)),
                      SizedBox(height: 3),
                      Text('CREATIVE AI STUDIO', style: TextStyle(fontSize: 9, letterSpacing: 1.4, color: Color(0xFFBDB3F7), fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _sideItem(Icons.home_rounded, 'Home', 11),
          FilledButton.icon(
            onPressed: importMedia,
            icon: const Icon(Icons.add),
            label: Text(t('newProject')),
          ),
          const SizedBox(height: 12),
          _sideItem(Icons.movie, t('video'), 0),
          _sideItem(Icons.image, t('photo'), 1),
          _sideItem(Icons.auto_awesome, t('ai'), 2),
          _sideItem(Icons.dashboard_customize, t('templates'), 3),
          _sideItem(Icons.card_giftcard, t('invite'), 4),
          _sideItem(Icons.workspace_premium, t('premium'), 5),
          const Divider(),
          Text(t('savedProjects'), style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          if (_loadingSavedProjects)
            const LinearProgressIndicator()
          else if (savedProjects.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                t('noSavedProjects'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          else
            ...savedProjects.map(
              (saved) => ListTile(
                dense: true,
                selected: saved.id == project.id,
                leading: const Icon(Icons.folder_open_outlined),
                title: Text(
                  saved.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (action) {
                    if (action == 'rename') _renameSavedProject(saved);
                    if (action == 'delete') _deleteSavedProject(saved);
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'rename',
                      child: Text(t('renameProject')),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(t('deleteProject')),
                    ),
                  ],
                ),
                onTap: () => _openSavedProject(saved),
              ),
            ),
          _sideItem(Icons.video_camera_front_outlined, 'Synthesia Studio IA', 7),
          _sideItem(Icons.link, 'MagicLink IA', 10),
          _sideItem(Icons.groups_outlined, 'TeamStudio', 8),
          _sideItem(Icons.workspace_premium_outlined, t('premium'), 9),
          const Divider(),
          _sideItem(Icons.settings, t('settings'), 6),
          if (selectedTab == 2)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(t('aiComing'), style: Theme.of(context).textTheme.bodySmall),
            ),
        ],
      ),
    );
  }

  Widget _sideItem(IconData icon, String label, int index) {
    return ListTile(
      selected: selectedTab == index,
      leading: Icon(icon),
      title: Text(label),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onTap: () => setState(() => selectedTab = index),
    );
  }

  Widget _toolButton(IconData icon, String label, VoidCallback onPressed) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFFD9D2FF),
        side: const BorderSide(color: Color(0x443D3B50)),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

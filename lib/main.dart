import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import 'models/editor_project.dart';
import 'services/project_store.dart';
import 'services/smart_shield_manager.dart';
import 'editor/session_timeline_editor.dart';
import 'editor/magiciaedit_panel.dart';

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
      title: 'Editore Foto e Video IA',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7657F6)),
        scaffoldBackgroundColor: const Color(0xFFF7F7FB),
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
      'app': 'Editore Foto e Video IA',
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
      'app': 'AI Photo & Video Editor',
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
      'app': 'Éditeur photo et vidéo IA',
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
      'app': 'Editor de foto y vídeo IA',
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
      'app': 'محرر الصور والفيديو بالذكاء الاصطناعي',
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
  int selectedTab = 0;
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
    final projects = [...savedProjects];
    final index = projects.indexWhere((item) => item.id == updated.id);
    if (index >= 0) {
      projects[index] = updated;
    } else {
      projects.add(updated);
    }
    projects.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
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

  Future<void> importMedia() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v',
        'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp',
        'mp3', 'm4a', 'aac', 'wav', 'ogg', 'opus', 'flac', 'aiff', 'wma',
      ],
      allowMultiple: true,
      withData: false,
    );

    if (result == null || result.files.isEmpty) return;

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

    for (var i = 0; i < result.files.length; i++) {
      final file = result.files[i];
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
          title: Text(t('app')),
          actions: [
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
            final editor = selectedTab == 2
                ? MagicIAeditPanel(
                    project: project,
                    onProjectChanged: _applyMagicIAeditProject,
                    onMessage: _message,
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
                        const SizedBox(height: 12),
                        SizedBox(height: 180, child: sidebar),
                      ],
                    ),
            );
          },
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
                ListTile(
                  title: Text(t('preview'), style: const TextStyle(fontWeight: FontWeight.bold)),
                  trailing: IconButton(
                    tooltip: t('import'),
                    onPressed: importMedia,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                  ),
                ),
                Expanded(
                  child: Container(
                    color: const Color(0xFF171820),
                    alignment: Alignment.center,
                    child: media == null
                        ? Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.movie_creation_outlined, color: Colors.white70, size: 52),
                                const SizedBox(height: 12),
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
        Wrap(
          spacing: 6,
          children: [
            _toolButton(Icons.auto_awesome, t('effects'), () => _message('Libreria effetti: in sviluppo.')),
            _toolButton(Icons.title, t('text'), () => _message('Editor testo: in sviluppo.')),
            _toolButton(Icons.music_note, t('audio'), () => _message('Traccia audio: in sviluppo.')),
            FilledButton.icon(
              onPressed: () => _message(t('exportNote')),
              icon: const Icon(Icons.file_upload_outlined),
              label: Text(t('export')),
            ),
          ],
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
          Text(t('subtitle'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
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
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Tooltip(
        message: label,
        child: IconButton(onPressed: onPressed, icon: Icon(icon)),
      ),
    );
  }
}

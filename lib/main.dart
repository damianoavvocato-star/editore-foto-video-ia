import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';

import 'models/editor_project.dart';
import 'services/project_store.dart';
import 'editor/session_timeline_editor.dart';

void main() => runApp(const EditoreApp());

enum AppLanguage { it, en, fr, es, ar }

class EditoreApp extends StatefulWidget {
  const EditoreApp({super.key});

  @override
  State<EditoreApp> createState() => _EditoreAppState();
}

class _EditoreAppState extends State<EditoreApp> {
  AppLanguage language = AppLanguage.it;

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
    },
  };

  static String get(AppLanguage language, String key) =>
      strings[language]?[key] ?? strings[AppLanguage.en]![key] ?? key;
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.language,
    required this.onLanguageChanged,
  });

  final AppLanguage language;
  final ValueChanged<AppLanguage> onLanguageChanged;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  PlatformFile? media;
  VideoPlayerController? videoController;
  double zoom = 1;
  int selectedTab = 0;
  EditorProject project = const EditorProject(id: 'draft', name: 'Nuovo progetto');
  final ProjectStore _projectStore = const ProjectStore();

  Future<void> _persistProject(EditorProject updated) async {
    try {
      final directory = await getApplicationSupportDirectory();
      await _projectStore.save(updated, Directory('${directory.path}/editore_progetti'));
    } catch (error) {
      if (mounted) _message('Salvataggio progetto non riuscito: $error');
    }
  }

  void _makeProjectForMedia(PlatformFile file, bool isVideo) {
    final clip = EditorClip(
      id: 'clip_${DateTime.now().microsecondsSinceEpoch}',
      source: file.path!,
      kind: isVideo ? MediaKind.video : MediaKind.image,
      startMs: 0,
      durationMs: isVideo && videoController != null
          ? (videoController!.value.duration.inMilliseconds.clamp(500, 60000))
          : 5000,
      title: file.name,
    );
    final track = EditorTrack(
      id: 'track_main',
      name: 'Media',
      kind: clip.kind,
      clips: [clip],
    );
    project = EditorProject(
      id: 'project_${DateTime.now().millisecondsSinceEpoch}',
      name: file.name,
      tracks: [track],
    );
    _persistProject(project);
  }

  String t(String key) => Copy.get(widget.language, key);

  Future<void> importMedia() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.media,
      allowMultiple: false,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final path = file.path;
    if (path == null) {
      if (mounted) _message(t('unsupported'));
      return;
    }

    final isVideo = _isVideo(file.name);
    await videoController?.dispose();
    videoController = null;

    if (isVideo) {
      final controller = VideoPlayerController.file(File(path));
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        media = file;
        videoController = controller;
        zoom = 1;
        _makeProjectForMedia(file, true);
      });
    } else {
      setState(() {
        media = file;
        zoom = 1;
        _makeProjectForMedia(file, false);
      });
    }
  }

  bool _isVideo(String name) {
    final lower = name.toLowerCase();
    return ['.mp4', '.mov', '.avi', '.mkv', '.webm', '.m4v']
        .any(lower.endsWith);
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  void dispose() {
    videoController?.dispose();
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
            final editor = _buildEditor(context);
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
        if (media != null)
          SizedBox(
            height: 300,
            child: SessionTimelineEditor(
              key: ValueKey(project.id),
              project: project,
              onProjectChanged: _persistProject,
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
    if (file.path != null) {
      return Transform.scale(
        scale: zoom,
        child: Image.file(File(file.path!), fit: BoxFit.contain),
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

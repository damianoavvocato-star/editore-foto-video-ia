import 'package:flutter/widgets.dart';

/// Starter localization lookup. Add languages by extending this map; production
/// should migrate to Flutter gen_l10n/ARB so pluralization and tooling are covered.
class EditorStrings {
  const EditorStrings(this.locale);

  final Locale locale;

  static const supportedLocales = <Locale>[
    Locale('it'),
    Locale('en'),
    Locale('fr'),
    Locale('es'),
    Locale('ar'),
  ];

  static const _values = <String, Map<String, String>>{
    'it': {
      'appTitle': 'Editor Foto e Video IA',
      'projects': 'Progetti',
      'export': 'Esporta',
      'share': 'Condividi',
      'premium': 'Premium',
      'settings': 'Impostazioni',
      'noProject': 'Nessun progetto aperto',
      'shareNoLink': 'Condividi il file senza link obbligatorio',
    },
    'en': {
      'appTitle': 'AI Photo & Video Editor',
      'projects': 'Projects',
      'export': 'Export',
      'share': 'Share',
      'premium': 'Premium',
      'settings': 'Settings',
      'noProject': 'No project open',
      'shareNoLink': 'Share the file without a required link',
    },
    'fr': {
      'appTitle': 'Éditeur photo et vidéo IA',
      'projects': 'Projets',
      'export': 'Exporter',
      'share': 'Partager',
      'premium': 'Premium',
      'settings': 'Paramètres',
      'noProject': 'Aucun projet ouvert',
      'shareNoLink': 'Partager le fichier sans lien obligatoire',
    },
    'es': {
      'appTitle': 'Editor de foto y vídeo con IA',
      'projects': 'Proyectos',
      'export': 'Exportar',
      'share': 'Compartir',
      'premium': 'Premium',
      'settings': 'Ajustes',
      'noProject': 'Ningún proyecto abierto',
      'shareNoLink': 'Compartir el archivo sin enlace obligatorio',
    },
    'ar': {
      'appTitle': 'محرر الصور والفيديو بالذكاء الاصطناعي',
      'projects': 'المشاريع',
      'export': 'تصدير',
      'share': 'مشاركة',
      'premium': 'بريميوم',
      'settings': 'الإعدادات',
      'noProject': 'لا يوجد مشروع مفتوح',
      'shareNoLink': 'مشاركة الملف دون رابط إلزامي',
    },
  };

  String text(String key) =>
      _values[locale.languageCode]?[key] ??
      _values['en']![key] ??
      key;

  TextDirection get textDirection =>
      locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr;
}

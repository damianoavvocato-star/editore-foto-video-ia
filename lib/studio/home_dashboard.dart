import 'package:flutter/material.dart';
import '../models/editor_project.dart';

class HomeDashboard extends StatelessWidget {
  const HomeDashboard({
    super.key,
    required this.appName,
    required this.subtitle,
    required this.newProjectLabel,
    required this.importLabel,
    required this.videoLabel,
    required this.photoLabel,
    required this.aiLabel,
    required this.magicLinkLabel,
    required this.savedProjectsLabel,
    required this.noSavedProjectsLabel,
    required this.projects,
    required this.onNewProject,
    required this.onImport,
    required this.onVideo,
    required this.onPhoto,
    required this.onMagic,
    required this.onMagicLink,
    required this.onPremium,
    required this.onOpenProject,
  });

  final String appName, subtitle, newProjectLabel, importLabel;
  final String videoLabel, photoLabel, aiLabel, magicLinkLabel;
  final String savedProjectsLabel, noSavedProjectsLabel;
  final List<EditorProject> projects;
  final VoidCallback onNewProject, onImport, onVideo, onPhoto, onMagic, onMagicLink, onPremium;
  final ValueChanged<EditorProject> onOpenProject;

  static const _muted = Color(0xFFAAA8BC);
  static const _cyan = Color(0xFF55D5C9);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxWidth < 640;
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(compact ? 2 : 8, 4, compact ? 2 : 8, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _topLine(compact),
                const SizedBox(height: 22),
                _hero(context, compact),
                const SizedBox(height: 24),
                Row(children: [
                  const Expanded(child: Text('Il tuo studio, senza limiti',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -.4))),
                  if (!compact) const Text('CREA · MODIFICA · CONDIVIDI',
                    style: TextStyle(color: _muted, fontSize: 10, letterSpacing: 1.4, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 13),
                _toolGrid(compact),
                const SizedBox(height: 24),
                _recentProjects(compact),
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _topLine(bool compact) => Row(children: [
    Container(
      width: 46, height: 46,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        gradient: const LinearGradient(colors: [Color(0xFF806BEE), Color(0xFF36BFC8)]),
        boxShadow: const [BoxShadow(color: Color(0x447B65E8), blurRadius: 18, offset: Offset(0, 7))],
      ),
      child: const Icon(Icons.auto_awesome, color: Colors.white, size: 25),
    ),
    const SizedBox(width: 12),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(appName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
      Text(subtitle, style: const TextStyle(color: _muted, fontSize: 12)),
    ])),
    if (!compact) OutlinedButton.icon(onPressed: onPremium,
      icon: const Icon(Icons.workspace_premium_outlined, size: 18), label: const Text('Premium')),
    if (compact) IconButton(tooltip: 'Premium', onPressed: onPremium,
      icon: const Icon(Icons.workspace_premium_outlined)),
  ]);

  Widget _hero(BuildContext context, bool compact) => Container(
    padding: EdgeInsets.all(compact ? 20 : 30),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(28),
      gradient: const LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [Color(0xFF292052), Color(0xFF182B4B), Color(0xFF172B37)],
        stops: [0, .58, 1],
      ),
      border: Border.all(color: const Color(0x557E70D8)),
      boxShadow: const [BoxShadow(color: Color(0x332F4B9B), blurRadius: 30, offset: Offset(0, 14))],
    ),
    child: Stack(children: [
      Positioned(right: -12, top: -30, child: Icon(Icons.auto_awesome,
        size: compact ? 118 : 178, color: const Color(0x1FFFFFFF))),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0x2BFFFFFF), borderRadius: BorderRadius.circular(30),
            border: Border.all(color: const Color(0x557E9DFF)),
          ),
          child: const Text('CREATIVE AI STUDIO',
            style: TextStyle(fontSize: 9, letterSpacing: 1.8, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(height: 16),
        Text('Dai vita alle tue idee.',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w900, letterSpacing: -1, height: 1.05)),
        const SizedBox(height: 9),
        const ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 540),
          child: Text('Foto, video e intelligenza artificiale: tutto quello che ti serve per creare contenuti straordinari, in un solo spazio.',
            style: TextStyle(color: Color(0xFFD6D4E8), height: 1.45, fontSize: 13)),
        ),
        const SizedBox(height: 22),
        Wrap(spacing: 10, runSpacing: 10, children: [
          FilledButton.icon(onPressed: onNewProject, icon: const Icon(Icons.add_rounded),
            label: Text(newProjectLabel),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF8C79F4),
              foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 15))),
          OutlinedButton.icon(onPressed: onImport, icon: const Icon(Icons.cloud_upload_outlined),
            label: Text(importLabel),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white,
              side: const BorderSide(color: Color(0x887F83C4)),
              padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 15))),
        ]),
      ]),
    ]),
  );

  Widget _toolGrid(bool compact) {
    final items = <({IconData icon, String title, String caption, Color color, VoidCallback action})>[
      (icon: Icons.movie_creation_outlined, title: videoLabel, caption: 'Taglia, monta e rifinisci', color: Color(0xFF9C8BFF), action: onVideo),
      (icon: Icons.photo_library_outlined, title: photoLabel, caption: 'Ritocca e valorizza', color: Color(0xFF55D5C9), action: onPhoto),
      (icon: Icons.auto_awesome, title: aiLabel, caption: 'Lascia spazio alla creatività IA', color: Color(0xFFFFB86B), action: onMagic),
      (icon: Icons.link_rounded, title: magicLinkLabel, caption: 'Importa e organizza i contenuti', color: Color(0xFF79B8FF), action: onMagicLink),
    ];
    return GridView.builder(
      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: compact ? 2 : 4, crossAxisSpacing: 11, mainAxisSpacing: 11,
        mainAxisExtent: compact ? 142 : 154),
      itemBuilder: (context, index) {
        final item = items[index];
        return Material(
          color: const Color(0xFF1A1B27), borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20), onTap: item.action,
            child: Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(20),
                border: Border.all(color: item.color.withValues(alpha: .22))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(width: 42, height: 42,
                  decoration: BoxDecoration(color: item.color.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(13)),
                  child: Icon(item.icon, color: item.color, size: 23)),
                const Spacer(),
                Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                const SizedBox(height: 3),
                Text(item.caption, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 10, height: 1.25)),
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _recentProjects(bool compact) {
    final visible = projects.reversed.take(4).toList();
    return Container(
      padding: EdgeInsets.all(compact ? 15 : 19),
      decoration: BoxDecoration(color: const Color(0xFF191A26),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x223F3D56))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(savedProjectsLabel,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
          Text('${projects.length}', style: const TextStyle(color: _muted, fontSize: 12)),
        ]),
        const SizedBox(height: 10),
        if (visible.isEmpty)
          Row(children: [
            const Icon(Icons.folder_open_outlined, color: _muted),
            const SizedBox(width: 10),
            Expanded(child: Text(noSavedProjectsLabel,
              style: const TextStyle(color: _muted, fontSize: 12))),
          ])
        else
          ...visible.map((project) => ListTile(
            contentPadding: EdgeInsets.zero, dense: true,
            leading: const CircleAvatar(backgroundColor: Color(0x332E9EAD),
              child: Icon(Icons.movie_outlined, color: _cyan, size: 19)),
            title: Text(project.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${project.tracks.fold<int>(0, (count, track) => count + track.clips.length)} elementi'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => onOpenProject(project),
          )),
      ]),
    );
  }
}

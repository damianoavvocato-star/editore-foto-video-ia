import 'package:flutter/material.dart';
import '../models/editor_project.dart';

/// Project library UI; the app supplies loaded projects and open/delete actions.
class ProjectLibraryScreen extends StatelessWidget {
  const ProjectLibraryScreen({
    super.key,
    required this.projects,
    required this.onOpen,
    required this.onDelete,
    required this.onCreate,
  });

  final List<EditorProject> projects;
  final ValueChanged<EditorProject> onOpen;
  final ValueChanged<EditorProject> onDelete;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('I miei progetti'),
        actions: [
          IconButton(
            tooltip: 'Nuovo progetto',
            onPressed: onCreate,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: projects.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.video_library_outlined, size: 52),
                  const SizedBox(height: 12),
                  const Text('Non hai ancora progetti salvati'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: onCreate,
                    icon: const Icon(Icons.add),
                    label: const Text('Crea progetto'),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: projects.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final project = projects[index];
                final clipCount =
                    project.tracks.fold<int>(0, (sum, track) => sum + track.clips.length);
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.movie_creation_outlined)),
                    title: Text(project.name),
                    subtitle: Text('$clipCount clip • ${project.width}×${project.height} • ${project.fps} FPS'),
                    onTap: () => onOpen(project),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'delete') onDelete(project);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'delete', child: Text('Elimina')),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

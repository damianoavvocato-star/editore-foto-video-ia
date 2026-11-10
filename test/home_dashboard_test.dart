import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:editore_foto_video_ia/models/editor_project.dart';
import 'package:editore_foto_video_ia/studio/home_dashboard.dart';

void main() {
  testWidgets('home dashboard shows main actions and opens recent projects', (tester) async {
    var openedMagic = false;
    var openedProject = false;
    const project = EditorProject(id: 'p1', name: 'Spot pubblicitario');

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: HomeDashboard(
      appName: 'MagicIAedit',
      subtitle: 'Il tuo studio creativo',
      newProjectLabel: 'Nuovo progetto',
      importLabel: 'Importa foto o video',
      videoLabel: 'Editor video',
      photoLabel: 'Editor foto',
      aiLabel: 'Studio IA',
      magicLinkLabel: 'MagicLink IA',
      studioLabel: 'Synthesia Studio IA',
      teamLabel: 'TeamStudio',
      savedProjectsLabel: 'Progetti recenti',
      noSavedProjectsLabel: 'Nessun progetto salvato',
      projects: const [project],
      onNewProject: () {},
      onImport: () {},
      onVideo: () {},
      onPhoto: () {},
      onMagic: () => openedMagic = true,
      onMagicLink: () {},
      onStudio: () {},
      onTeam: () {},
      onPremium: () {},
      onOpenProject: (_) => openedProject = true,
    ))));

    expect(find.text('MagicIAedit'), findsOneWidget);
    expect(find.text('Nuovo progetto'), findsOneWidget);
    expect(find.text('MagicLink IA'), findsOneWidget);
    expect(find.text('Spot pubblicitario'), findsOneWidget);
    await tester.tap(find.text('Studio IA'));
    await tester.pump();
    expect(openedMagic, isTrue);
    await tester.ensureVisible(find.text('Spot pubblicitario'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spot pubblicitario'));
    await tester.pump();
    expect(openedProject, isTrue);
  });
}

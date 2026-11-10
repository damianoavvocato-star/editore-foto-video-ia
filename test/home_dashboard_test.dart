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
      studioHeading: 'Il tuo studio, senza limiti',
      actionLine: 'CREA · MODIFICA · CONDIVIDI',
      heroEyebrow: 'CREATIVE AI STUDIO',
      heroHeadline: 'Dai vita alle tue idee.',
      heroDescription: 'Foto, video e IA.',
      videoCaption: 'Taglia, monta e rifinisci',
      photoCaption: 'Ritocca e valorizza',
      aiCaption: 'Creatività IA',
      magicLinkCaption: 'Importa contenuti',
      studioCaption: 'Strumenti avanzati',
      teamCaption: 'Collabora',
      premiumTooltip: 'Premium',
      itemsLabel: 'elementi',
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
  testWidgets('home dashboard keeps the four most recent projects in supplied order', (tester) async {
    const projects = [
      EditorProject(id: 'p5', name: 'Progetto più recente'),
      EditorProject(id: 'p4', name: 'Progetto recente 4'),
      EditorProject(id: 'p3', name: 'Progetto recente 3'),
      EditorProject(id: 'p2', name: 'Progetto recente 2'),
      EditorProject(id: 'p1', name: 'Progetto più vecchio'),
    ];

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: HomeDashboard(
      appName: 'MagicIAedit',
      subtitle: 'Il tuo studio creativo',
      newProjectLabel: 'Nuovo progetto',
      importLabel: 'Importa',
      videoLabel: 'Video',
      photoLabel: 'Foto',
      aiLabel: 'Studio IA',
      magicLinkLabel: 'MagicLink IA',
      studioLabel: 'Studio',
      teamLabel: 'Team',
      savedProjectsLabel: 'Progetti recenti',
      noSavedProjectsLabel: 'Nessun progetto',
      studioHeading: 'Il tuo studio, senza limiti',
      actionLine: 'CREA · MODIFICA · CONDIVIDI',
      heroEyebrow: 'CREATIVE AI STUDIO',
      heroHeadline: 'Dai vita alle tue idee.',
      heroDescription: 'Foto, video e IA.',
      videoCaption: 'Taglia, monta e rifinisci',
      photoCaption: 'Ritocca e valorizza',
      aiCaption: 'Creatività IA',
      magicLinkCaption: 'Importa contenuti',
      studioCaption: 'Strumenti avanzati',
      teamCaption: 'Collabora',
      premiumTooltip: 'Premium',
      itemsLabel: 'elementi',
      projects: projects,
      onNewProject: () {},
      onImport: () {},
      onVideo: () {},
      onPhoto: () {},
      onMagic: () {},
      onMagicLink: () {},
      onStudio: () {},
      onTeam: () {},
      onPremium: () {},
      onOpenProject: (_) {},
    ))));

    expect(find.text('Progetto più recente'), findsOneWidget);
    expect(find.text('Progetto recente 2'), findsOneWidget);
    expect(find.text('Progetto più vecchio'), findsNothing);
    expect(tester.getTopLeft(find.text('Progetto più recente')).dy,
      lessThan(tester.getTopLeft(find.text('Progetto recente 2')).dy));
  });

}

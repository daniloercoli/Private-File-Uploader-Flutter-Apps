import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'pages/home_page.dart';
import 'pages/settings_page.dart';
import 'pages/uploads_page.dart';
import 'pages/info_page.dart';
import '../services/wp_api.dart';
import '../services/app_storage.dart';
import 'dart:async';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WP Uploader',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ).copyWith(background: Colors.white, surface: Colors.white),
        scaffoldBackgroundColor: Colors.white,
      ),
      home: const AppScaffold(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class AppScaffold extends StatefulWidget {
  const AppScaffold({super.key});

  @override
  State<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends State<AppScaffold> {
  int _index = 0;

  bool _booting = true; // overlay di avvio
  final List<Widget> _pages = const [HomePage(), UploadsPage(), SettingsPage(), InfoPage()];

  @override
  void initState() {
    super.initState();
    _boot(); // avvia la “modale” di startup
  }

  Future<void> _boot() async {
    // durata minima overlay
    final minDelay = Future.delayed(const Duration(seconds: 2));

    // avvia (eventuale) prefetch ma NON attendere il risultato
    Future<void> prefetch() async {
      final url = await AppStorage.getUrl();
      final user = await AppStorage.getUsername();
      final pass = await AppStorage.getPassword();
      final hasCreds = (url?.isNotEmpty ?? false) && (user?.isNotEmpty ?? false) && (pass?.isNotEmpty ?? false);
      if (!hasCreds) return;

      // timeout breve per non impegnare troppo (e ignoriamo errori)
      try {
        await WpApi.fetchFiles().timeout(const Duration(seconds: 2));
      } catch (_) {
        /* no-op */
      }
    }

    // lancia prefetch senza await
    unawaited(prefetch());

    // spegni overlay appena trascorrono 2s, indipendentemente dallo stato rete
    await minDelay;
    if (!mounted) return;
    setState(() => _booting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: (int i) => setState(() => _index = i),
                  labelType: NavigationRailLabelType.selected,
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home),
                      label: Text('Home'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.list_alt_outlined),
                      selectedIcon: Icon(Icons.list_alt),
                      label: Text('Uploads'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings),
                      label: Text('Settings'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.info_outline),
                      selectedIcon: Icon(Icons.info),
                      label: Text('Info'),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: _pages[_index]),
              ],
            ),

            // 👇 Overlay/modale di avvio
            if (_booting)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.08),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 280),
                      child: Material(
                        color: Colors.white,
                        elevation: 8,
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.folder_open, size: 56),
                              const SizedBox(height: 12),
                              const Text(
                                'Private File Uploader',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 4),
                              FutureBuilder<PackageInfo>(
                                future: PackageInfo.fromPlatform(),
                                builder: (context, snap) {
                                  if (!snap.hasData) {
                                    return const SizedBox.shrink();
                                  }
                                  final info = snap.data!;
                                  final ver = '${info.version}+${info.buildNumber}';
                                  return Text(
                                    'v $ver',
                                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                                    textAlign: TextAlign.center,
                                  );
                                },
                              ),
                              const SizedBox(height: 16),
                              const CircularProgressIndicator(),
                              const SizedBox(height: 12),
                              const Text(
                                'Preparing…',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Just a moment',
                                style: TextStyle(fontSize: 12, color: Colors.black54),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

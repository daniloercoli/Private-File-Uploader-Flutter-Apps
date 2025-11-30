import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../services/app_storage.dart';

class InfoPage extends StatelessWidget {
  const InfoPage({super.key});

  Future<String> _buildDiagnosticsString() async {
    // App
    final pkg = await PackageInfo.fromPlatform();

    // Device/OS
    final di = DeviceInfoPlugin();
    String device = 'n/d';
    String os = 'n/d';

    if (Platform.isAndroid) {
      final a = await di.androidInfo;
      device = '${a.manufacturer} ${a.model} (SDK ${a.version.sdkInt})';
      os = 'Android ${a.version.release} (SDK ${a.version.sdkInt})';
    } else if (Platform.isIOS) {
      final i = await di.iosInfo;
      device = i.utsname.machine ?? 'iPhone/iPad';
      os = 'iOS ${i.systemVersion}';
    } else if (Platform.isMacOS) {
      final m = await di.macOsInfo;
      device = '${m.model} (${m.arch})';
      os = 'macOS ${m.osRelease}';
    } else if (Platform.isLinux) {
      final l = await di.linuxInfo;
      device = l.prettyName ?? 'Linux';
      os = 'Linux ${l.version ?? ''}'.trim();
    } else if (Platform.isWindows) {
      final w = await di.windowsInfo;
      device = 'Windows ${w.computerName}';
      os = 'Windows ${w.displayVersion} (build ${w.buildNumber})';
    } else {
      os = Platform.operatingSystem;
    }

    // Runtime
    final dartVersion = Platform.version.split(' ').first;

    // Settings (senza password)
    final url = (await AppStorage.getUrl()) ?? '';
    final user = (await AppStorage.getUsername()) ?? '';
    final pass = await AppStorage.getPassword();
    final passSet = (pass != null && pass.isNotEmpty) ? 'sì' : 'no';

    final buffer = StringBuffer()
      ..writeln('App: ${pkg.appName} ${pkg.version}+${pkg.buildNumber}')
      ..writeln('OS: $os')
      ..writeln('Device: $device')
      ..writeln('Dart: $dartVersion')
      ..writeln('Impostazioni • URL: ${url.isEmpty ? "—" : url}')
      ..writeln('Impostazioni • Username: ${user.isEmpty ? "—" : user}')
      ..writeln('Impostazioni • Password salvata: $passSet');

    return buffer.toString();
  }

  Future<void> _copyDiagnostics(BuildContext context) async {
    final text = await _buildDiagnosticsString();
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Diagnostica copiata negli appunti')));
    }
  }

  void _openLicenses(BuildContext context, PackageInfo info) {
    showLicensePage(
      context: context,
      applicationName: info.appName.isEmpty ? 'WP Uploader' : info.appName,
      applicationVersion: '${info.version}+${info.buildNumber}',
      applicationIcon: const Icon(Icons.cloud_upload),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 72,
                height: 72,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset('assets/app_icon.png', fit: BoxFit.cover),
                ),
              ),
              const SizedBox(height: 12),
              FutureBuilder<PackageInfo>(
                future: PackageInfo.fromPlatform(),
                builder: (context, snap) {
                  final appName = snap.data?.appName ?? 'WP Uploader';
                  final ver = snap.hasData ? '${snap.data!.version}+${snap.data!.buildNumber}' : '';
                  return Column(
                    children: [
                      Text(appName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
                      if (ver.isNotEmpty) ...[const SizedBox(height: 8), Text('Versione $ver')],
                      const SizedBox(height: 24),
                      const Text(
                        'File Uploader ti permette di caricare in modo semplice e sicuro i tuoi file '
                        'direttamente su WordPress, usando il plugin “Private File Uploader”.\n\n'
                        'I file vengono salvati in una cartella dedicata al tuo utente: puoi copiarne '
                        'subito il link, rinominare o eliminare gli elementi, vedere anteprime di immagini '
                        'e aprire video con le app di sistema, senza passare da servizi cloud esterni.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),

                      // 👉 Licenze sopra "Copia diagnostica"
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: snap.hasData ? () => _openLicenses(context, snap.data!) : null,
                          icon: const Icon(Icons.article_outlined),
                          label: const Text('Licenze / About'),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // 👉 Copia diagnostica
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _copyDiagnostics(context),
                          icon: const Icon(Icons.copy_all),
                          label: const Text('Copia diagnostica'),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

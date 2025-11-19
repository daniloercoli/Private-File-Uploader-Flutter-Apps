import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/wp_api.dart';
import '../services/app_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _uploading = false;
  String? _lastResult; // messaggi di errore/diagnostica
  String? _lastFilePath; // ultimo file locale (Android/iOS) per retry

  // Per Web (retry senza riselezionare)
  Uint8List? _lastBytes;
  String? _lastName;
  String? _lastMime;

  Future<void> _pickAndUpload() async {
    setState(() => _lastResult = null);

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: kIsWeb, // su Web chiedi i byte
    );
    if (result == null || result.files.isEmpty) return;

    final picked = result.files.single;

    if (kIsWeb) {
      // WEB: invia i byte
      final bytes = picked.bytes;
      final name = picked.name;

      if (bytes == null) {
        // fallback: niente byte disponibili (capita se withData:false o alcuni browser)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Selezione non valida (nessun contenuto). Riprova.')));
        return;
      }
      final header = bytes.length >= 12 ? bytes.sublist(0, 12) : bytes;
      final mime = lookupMimeType(name, headerBytes: header) ?? 'application/octet-stream';
      // memorizza per retry
      _lastBytes = bytes;
      _lastName = name;
      _lastMime = mime;
      await _uploadFromBytes(bytes, name, mime: mime);
    } else {
      // ANDROID / iOS: usa il path su filesystem
      final path = picked.path;
      if (path == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selezione file non valida')));
        return;
      }
      _lastFilePath = path; // per retry
      await _uploadFromPath(path);
    }
  }

  Future<void> _uploadFromBytes(Uint8List bytes, String filename, {String? mime}) async {
    setState(() {
      _uploading = true;
      _lastResult = null;
    });

    try {
      final res = await WpApi.uploadBytes(bytes, filename, mime: mime);

      if (res['ok'] == true && res['remoteUrl'] is String && (res['remoteUrl'] as String).isNotEmpty) {
        final remoteUrl = res['remoteUrl'] as String;

        await AppStorage.addUploadedUrl(remoteUrl);
        await Clipboard.setData(ClipboardData(text: remoteUrl));

        if (!mounted) return;
        final wantEmail = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Upload riuscito'),
            content: const Text('Indirizzo del file copiato negli appunti.\nVuoi inviarlo per email?'),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('No')),
              ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Sì')),
            ],
          ),
        );

        if (wantEmail == true) {
          final uri = Uri(scheme: 'mailto', queryParameters: {'body': remoteUrl});
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Upload riuscito')));
        setState(() => _lastResult = null);
      } else {
        final status = res['status'];
        final body = (res['body'] ?? '').toString();
        setState(() => _lastResult = 'HTTP $status — $body');

        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Upload fallito'),
            content: Text('Errore: HTTP $status\n\nVuoi riprovare ad inviare lo stesso file?'),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Chiudi')),
              ElevatedButton(
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  if (_lastBytes != null && _lastName != null) {
                    await _uploadFromBytes(_lastBytes!, _lastName!, mime: _lastMime);
                  }
                },
                child: const Text('Riprova'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _uploadFromPath(String path) async {
    // opzionale: verifica che il file esista ancora
    if (!await File(path).exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Il file non è più disponibile sul dispositivo')));
      return;
    }

    setState(() {
      _uploading = true;
      _lastResult = null;
    });

    try {
      final res = await WpApi.uploadFile(path);

      if (res['ok'] == true && res['remoteUrl'] is String && (res['remoteUrl'] as String).isNotEmpty) {
        final remoteUrl = res['remoteUrl'] as String;

        await AppStorage.addUploadedUrl(remoteUrl);
        await Clipboard.setData(ClipboardData(text: remoteUrl));

        if (!mounted) return;
        final wantEmail = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Upload riuscito'),
            content: const Text('Indirizzo del file copiato negli appunti.\nVuoi inviarlo per email?'),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('No')),
              ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Sì')),
            ],
          ),
        );

        if (wantEmail == true) {
          final uri = Uri(scheme: 'mailto', queryParameters: {'body': remoteUrl});
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Upload riuscito')));
        setState(() => _lastResult = null);
      } else {
        // Fallimento: offri "Riprova" senza riselezione
        final status = res['status'];
        final body = (res['body'] ?? '').toString();
        setState(() => _lastResult = 'HTTP $status — $body');

        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Upload fallito'),
            content: Text('Errore: HTTP $status\n\nVuoi riprovare ad inviare lo stesso file?'),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Chiudi')),
              ElevatedButton(
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  if (_lastFilePath != null) {
                    await _uploadFromPath(_lastFilePath!); // retry immediato
                  }
                },
                child: const Text('Riprova'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_upload, size: 80),
            const SizedBox(height: 16),
            const Text(
              'Carica nuovi file sul tuo Cloud',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _uploading ? null : _pickAndUpload,
              icon: const Icon(Icons.upload_file),
              label: Text(_uploading ? 'Caricamento…' : 'Carica file'),
            ),
            const SizedBox(height: 8),
            // Pulsante Riprova rapido (funziona sia path che web bytes)
            if (!_uploading &&
                _lastResult != null &&
                (_lastFilePath != null || (_lastBytes != null && _lastName != null)))
              OutlinedButton.icon(
                onPressed: () {
                  if (_lastFilePath != null) {
                    _uploadFromPath(_lastFilePath!);
                  } else if (_lastBytes != null && _lastName != null) {
                    _uploadFromBytes(_lastBytes!, _lastName!, mime: _lastMime);
                  }
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Riprova ultimo file'),
              ),
            if (_lastResult != null) ...[
              const SizedBox(height: 16),
              SelectableText(_lastResult!, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}

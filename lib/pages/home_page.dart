import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/wp_api.dart';
import '../services/app_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import '../utils/ui_utils.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _uploading = false;
  String? _lastResult; // messaggi di errore/diagnostica
  http.Client? _currentClient;
  String? _currentFileName;

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
      _currentFileName = name;
      await _uploadFromBytes(bytes, name, mime: mime);
    } else {
      // ANDROID / iOS: usa il path su filesystem
      final path = picked.path;
      if (path == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selezione file non valida')));
        return;
      }
      _currentFileName = path.split('/').last;
      await _uploadFromPath(path);
    }
  }

  void _cancelUpload() {
    // Chiudendo il client, interrompiamo la richiesta HTTP in corso
    _currentClient?.close();
    // Non metto setState qui: lo stato viene sistemato nei finally dei metodi di upload.
  }

  Future<void> _uploadFromBytes(Uint8List bytes, String filename, {String? mime}) async {
    setState(() {
      _uploading = true;
      _lastResult = null;
    });

    _currentClient = http.Client();

    try {
      final res = await WpApi.uploadBytes(bytes, filename, mime: mime, client: _currentClient);
      if (res['cancelled'] == true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Upload annullato')));
        setState(() {
          _lastResult = null;
        });
        return;
      }
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
            content: Text('Errore: HTTP $status\n\n$body'),
            actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Chiudi'))],
          ),
        );
      }
    } finally {
      _currentClient = null;
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
    _currentClient = http.Client();

    try {
      final res = await WpApi.uploadFile(path, client: _currentClient);
      if (res['cancelled'] == true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Upload annullato')));
        setState(() {
          _lastResult = null;
        });
        return;
      }
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
        final bodyShort = shortError(res['body']);
        setState(() => _lastResult = 'HTTP $status — $bodyShort');
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Upload fallito'),
            content: Text('Errore: HTTP $status\n\n$bodyShort'),
            actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Chiudi'))],
          ),
        );
      }
    } finally {
      _currentClient = null;
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
            // Barra di stato upload + pulsante annulla
            if (_uploading && _currentFileName != null) ...[
              const SizedBox(height: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Caricamento in corso: $_currentFileName', textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _cancelUpload,
                    icon: const Icon(Icons.stop),
                    label: const Text('Annulla upload'),
                  ),
                ],
              ),
            ],
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

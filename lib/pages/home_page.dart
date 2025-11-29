import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'dart:isolate';

import '../services/wp_api.dart';
import '../services/app_storage.dart';
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
  double? _uploadProgress; // 0.0–1.0, null = “indeterminata”

  Future<void> _pickAndUpload() async {
    setState(() => _lastResult = null);

    final result = await FilePicker.platform.pickFiles(
      // Web: solo singolo file
      // Mobile: multi selezione
      allowMultiple: !kIsWeb,
      withData: kIsWeb, // su web ci servono i bytes
    );
    if (result == null || result.files.isEmpty) return;

    final files = result.files;

    // WEB: solo singolo file, niente ZIP
    if (kIsWeb) {
      final picked = files.single;
      final bytes = picked.bytes;
      final name = picked.name;

      if (bytes == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Selezione non valida (nessun contenuto). Riprova.')));
        return;
      }
      final header = bytes.length >= 12 ? bytes.sublist(0, 12) : bytes;
      final mime = lookupMimeType(name, headerBytes: header) ?? 'application/octet-stream';
      _currentFileName = name;

      await _uploadFromBytes(bytes, name, mime: mime);
      return;
    }

    // MOBILE:

    // Caso 1: singolo file → comportamento normale
    if (files.length == 1) {
      final picked = files.single;
      final path = picked.path;
      if (path == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selezione file non valida')));
        return;
      }
      _currentFileName = path.split('/').last;
      await _uploadFromPath(path);
      return;
    }

    // Caso 2: più file → ZIP su disco + upload
    await _confirmAndUploadZipMobile(files);
  }

  Future<void> _confirmAndUploadZipMobile(List<PlatformFile> files) async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invia come ZIP'),
        content: Text(
          'Hai selezionato ${files.length} file.\n\n'
          'Verranno inviati come un unico archivio ZIP al server.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annulla')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('OK')),
        ],
      ),
    );

    if (proceed != true) return;

    String? zipPath;

    try {
      // 1) Creiamo un path temporaneo per lo ZIP
      final tempDir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      zipPath = '${tempDir.path}/upload_$ts.zip';

      _currentFileName = zipPath.split('/').last;
      // 1) Attiva subito lo stato di upload (qui si apre
      //   la modale di "upload in corso" / overlay con il pulsante Stop).
      setState(() => _uploading = true);

      // 2) Diamo tempo a Flutter di ridisegnare la UI e mostrare la modale
      //    prima di iniziare il lavoro pesante di creazione ZIP.
      await Future.delayed(const Duration(milliseconds: 50));

      // 3) Lista di path validi dei file selezionati
      final filePaths = <String>[];
      for (final f in files) {
        final path = f.path;
        if (path == null) continue;
        filePaths.add(path);
      }

      if (filePaths.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nessun file valido selezionato')));
        return;
      }

      // 4) Creazione ZIP in un isolate separato
      final createdZipPath = await createZipInIsolate(zipPath: zipPath, filePaths: filePaths);

      if (createdZipPath == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Errore nella creazione dello ZIP')));
        return;
      }

      // 5) Upload usando lo stesso flusso del singolo file
      await _uploadFromPath(zipPath);
    } catch (e) {
      if (!mounted) return;
      final msg = shortError(e);
      setState(() => _lastResult = 'Errore creazione ZIP: $msg');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Errore creazione ZIP: $msg')));
    } finally {
      // Pulizia: cancella lo ZIP temporaneo
      if (zipPath != null) {
        try {
          final f = File(zipPath);
          if (await f.exists()) {
            await f.delete();
          }
        } catch (_) {
          // se fallisce la delete non è un dramma
        }
      }
      if (mounted) {
        setState(() {
          _uploading = false;
          _currentFileName = null;
        });
      }
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
      _uploadProgress = 0.0;
      _lastResult = null;
    });

    _currentClient = http.Client();

    try {
      final res = await WpApi.uploadBytes(
        bytes,
        filename,
        mime: mime,
        client: _currentClient,
        onProgress: (p) {
          if (!mounted) return;
          setState(() => _uploadProgress = p);
        },
      );
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
      if (mounted) {
        setState(() {
          _uploading = false;
          _uploadProgress = null;
          _currentFileName = null;
        });
      }
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
      _uploadProgress = 0.0;
      _lastResult = null;
    });
    _currentClient = http.Client();

    try {
      final res = await WpApi.uploadFile(
        path,
        client: _currentClient,
        onProgress: (p) {
          if (!mounted) return;
          setState(() => _uploadProgress = p);
        },
      );
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
      if (mounted) {
        setState(() {
          _uploading = false;
          _uploadProgress = null;
          _currentFileName = null;
        });
      }
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
                  LinearProgressIndicator(
                    value: _uploadProgress, // null = indeterminata, 0..1 = determinata
                  ),
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

Future<String?> createZipInIsolate({required String zipPath, required List<String> filePaths}) async {
  // Isolate.run esegue il body in un isolate separato
  return Isolate.run<String?>(() {
    try {
      final encoder = ZipFileEncoder();
      encoder.create(zipPath);

      for (final path in filePaths) {
        final file = File(path);
        if (!file.existsSync()) continue;
        encoder.addFile(file); // I/O sincrono ma in background isolate
      }

      encoder.close();

      final zipFile = File(zipPath);
      if (!zipFile.existsSync() || zipFile.lengthSync() == 0) {
        return null;
      }

      return zipPath;
    } catch (_) {
      return null;
    }
  });
}

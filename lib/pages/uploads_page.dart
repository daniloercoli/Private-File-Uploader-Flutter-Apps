import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/wp_api.dart';
import '../utils/ui_utils.dart';
import '../services/app_storage.dart';

class UploadsPage extends StatefulWidget {
  const UploadsPage({super.key});

  @override
  State<UploadsPage> createState() => _UploadsPageState();
}

class _UploadsPageState extends State<UploadsPage> {
  Future<WpFilesResponse>? _future;
  bool _deleting = false;
  bool _missingConfig = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload({bool forceRefresh = false}) async {
    final url = await AppStorage.getUrl();
    final user = await AppStorage.getUsername();
    final pass = await AppStorage.getPassword();

    if (!mounted) return;

    if (url == null || url.isEmpty || user == null || user.isEmpty || pass == null || pass.isEmpty) {
      // Nessuna configurazione: non facciamo chiamate di rete,
      // mostriamo solo un messaggio che invita ad andare in Settings.
      setState(() {
        _missingConfig = true;
        _future = null;
      });
      return;
    }

    setState(() {
      _missingConfig = false;
      _future = WpApi.fetchFiles(forceRefresh: forceRefresh);
    });

    await _future;
  }

  Future<void> _copyUrl(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('URL copiata negli appunti')));
  }

  bool _isVideo(WpFileItem item) {
    final mime = (item.mime ?? '').toLowerCase();
    if (mime.startsWith('video/')) return true;

    final name = item.name.toLowerCase();
    return name.endsWith('.mp4') ||
        name.endsWith('.mov') ||
        name.endsWith('.m4v') ||
        name.endsWith('.webm') ||
        name.endsWith('.avi') ||
        name.endsWith('.mkv');
  }

  Future<void> _onThumbTap(WpFileItem item) async {
    if (item.isImage) {
      await _openFullScreenImage(item);
    } else if (_isVideo(item)) {
      await _openVideo(item);
    }
    // altri tipi: non facciamo nulla
  }

  Future<void> _openVideo(WpFileItem item) async {
    try {
      final uri = Uri.parse(item.url);
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Impossibile aprire il video')));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Impossibile aprire il video')));
    }
  }

  Future<void> _openFullScreenImage(WpFileItem item) async {
    final imageUrl = item.url; // per il fullscreen uso l’URL “pieno”
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => _ImageFullScreenPage(imageUrl: imageUrl, title: item.name),
      ),
    );
  }

  Widget _leadingThumb(WpFileItem item) {
    final isImage = item.isImage;
    final isVideo = _isVideo(item);

    // Costruisco la thumb “nuda”
    Widget thumb;
    if (isImage) {
      final imageUrl = (item.thumbUrl != null && item.thumbUrl!.isNotEmpty) ? item.thumbUrl! : item.url;

      thumb = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: _FadeInThumb(imageUrl: imageUrl, placeholder: _placeholderIcon(item)),
      );
    } else {
      thumb = _placeholderIcon(item);
    }

    // Per immagini e video la thumb diventa tappabile
    if (isImage || isVideo) {
      return GestureDetector(onTap: () => _onThumbTap(item), child: thumb);
    }

    // Tutti gli altri file → nessuna azione sul tap della preview
    return thumb;
  }

  Widget _placeholderIcon(WpFileItem item) {
    final mime = (item.mime ?? '').toLowerCase();
    final isPdf = mime == 'application/pdf' || item.name.toLowerCase().endsWith('.pdf');
    return Container(
      width: 56,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: Colors.black12),
      child: Icon(isPdf ? Icons.picture_as_pdf : Icons.insert_drive_file),
    );
  }

  Future<void> _showDetails(WpFileItem item) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('File details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText('Name: ${item.name}'),
            const SizedBox(height: 6),
            SelectableText('MIME: ${item.mime ?? '—'}'),
            const SizedBox(height: 6),
            SelectableText('Size: ${humanSize(item.size)}'),
            const SizedBox(height: 6),
            SelectableText('Modified: ${humanDate(item.modified)}'),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 6),
            const Text('Remote URL:'),
            const SizedBox(height: 4),
            SelectableText(item.url, style: const TextStyle(fontFamily: 'monospace')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
            },
            child: const Text('Close'),
          ),
          TextButton.icon(
            onPressed: () async {
              await _copyUrl(item.url);
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copy URL'),
          ),
          TextButton.icon(
            onPressed: () {
              Navigator.of(ctx).pop(); // chiudi dialog di dettaglio
              _promptRename(item); // e apri dialog di rename
            },
            icon: const Icon(Icons.drive_file_rename_outline),
            label: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  Future<void> _promptRename(WpFileItem item) async {
    final controller = TextEditingController(text: item.name);
    String? error;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return AlertDialog(
              title: const Text('Rename file'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    decoration: InputDecoration(labelText: 'New name', errorText: error),
                    autofocus: true,
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () {
                    final value = controller.text.trim();
                    if (value.isEmpty) {
                      setStateDialog(() {
                        error = 'Insert a valid filename';
                      });
                      return;
                    }
                    if (value == item.name) {
                      setStateDialog(() {
                        error = 'Name is unchanged';
                      });
                      return;
                    }
                    Navigator.of(ctx).pop(true);
                  },
                  child: const Text('Rename'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) return;

    final newName = controller.text.trim();
    await _renameFile(item, newName);
  }

  Future<void> _renameFile(WpFileItem item, String newName) async {
    setState(() => _deleting = true); // Riuso la overlay sottile come quella usata in delete / "busy"
    try {
      final res = await WpApi.renameFile(item.name, newName);
      if (!mounted) return;

      if (res['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Renamed to $newName')));
        await _reload(forceRefresh: true); // Ricarichiamo la lista dal server per sicurezza
      } else {
        final status = res['status'] ?? '-';
        final bodyShort = shortError(res['body']);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Rename failed (HTTP $status): $bodyShort')));
      }
    } catch (e) {
      if (!mounted) return;
      final bodyShort = shortError(e);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Rename error: $bodyShort')));
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<bool> _confirmAndDelete(WpFileItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete file'),
        content: Text('Do you want to delete “${item.name}” from the server?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.delete),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            label: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return false;

    setState(() => _deleting = true);
    try {
      final res = await WpApi.deleteFile(item.name);
      if (!mounted) return false;

      if (res['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Deleted: ${item.name}')));
        await _reload(forceRefresh: true); // ricarica la lista dal server
        return true;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed (HTTP ${res['status']})')));
        return false;
      }
    } catch (e) {
      if (!mounted) return false;
      final bodyShort = shortError(e);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete error: $bodyShort')));
      return false;
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: () => _reload(forceRefresh: true),
          child: _missingConfig
              // Nessuna configurazione: messaggio amichevole
              ? ListView(
                  children: const [
                    SizedBox(height: 120),
                    Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Nessuna connessione configurata.\n\n'
                          'Imposta URL del sito e credenziali '
                          'nella schermata Impostazioni per vedere i file caricati.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                )
              // Config presente: usiamo il FutureBuilder se _future è pronto
              : (_future == null
                    ? const Center(child: CircularProgressIndicator())
                    : FutureBuilder<WpFilesResponse>(
                        future: _future!,
                        builder: (context, snap) {
                          if (snap.connectionState != ConnectionState.done) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          if (snap.hasError) {
                            final msg = shortError(snap.error);
                            return ListView(
                              children: [
                                const SizedBox(height: 120),
                                Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Text(
                                      'Errore nel caricamento dei file.\n\n$msg',
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }

                          final data = snap.data!;
                          final items = data.items;

                          if (items.isEmpty) {
                            return ListView(
                              children: const [
                                SizedBox(height: 120),
                                Center(
                                  child: Padding(padding: EdgeInsets.all(24), child: Text('No files found.')),
                                ),
                              ],
                            );
                          }

                          return ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: items.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final item = items[index];
                              final size = humanSize(item.size);
                              final subtitle = [
                                if (item.mime != null && item.mime!.isNotEmpty) item.mime,
                                if (size.isNotEmpty) size,
                              ].whereType<String>().join(' • ');

                              return Dismissible(
                                key: ValueKey(item.name),
                                direction: DismissDirection.startToEnd,
                                background: Container(
                                  color: Colors.red,
                                  alignment: Alignment.centerLeft,
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  child: const Icon(Icons.delete, color: Colors.white),
                                ),
                                confirmDismiss: (direction) async {
                                  if (direction == DismissDirection.startToEnd) {
                                    // final deleted =  Non ci serve qui
                                    await _confirmAndDelete(item);
                                    // Non lasciamo a Dismissible il compito di togliere l’item,
                                    // ci pensa _reload() a riallineare la lista col server.
                                    return false;
                                  }
                                  return false;
                                },
                                child: ListTile(
                                  leading: SizedBox(width: 56, height: 56, child: _leadingThumb(item)),
                                  title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  subtitle: subtitle.isEmpty ? null : Text(subtitle),
                                  onTap: () => _showDetails(item),
                                  onLongPress: () => _showDetails(item),
                                  trailing: IconButton(
                                    tooltip: 'Copy URL',
                                    icon: const Icon(Icons.copy),
                                    onPressed: () => _copyUrl(item.url),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      )),
        ),

        // Piccolo overlay quando stiamo cancellando/rinominando
        if (_deleting)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: true,
              child: Container(
                color: Colors.black.withOpacity(0.05),
                alignment: Alignment.topCenter,
                padding: const EdgeInsets.only(top: 8),
                child: const LinearProgressIndicator(minHeight: 2),
              ),
            ),
          ),
      ],
    );
  }
}

class _FadeInThumb extends StatefulWidget {
  final String imageUrl;
  final Widget placeholder;

  const _FadeInThumb({required this.imageUrl, required this.placeholder});

  @override
  State<_FadeInThumb> createState() => _FadeInThumbState();
}

class _FadeInThumbState extends State<_FadeInThumb> {
  bool _loaded = false;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Placeholder sempre visibile sotto
        widget.placeholder,
        // Immagine che fa fade-in quando finisce il caricamento
        AnimatedOpacity(
          opacity: _loaded ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: Image.network(
            widget.imageUrl,
            fit: BoxFit.cover,
            width: 56,
            height: 56,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null && !_loaded) {
                // caricata
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() => _loaded = true);
                  }
                });
              }
              return child;
            },
            errorBuilder: (context, error, stackTrace) {
              // se l’immagine fallisce, lasciamo solo il placeholder
              return const SizedBox.shrink();
            },
          ),
        ),
      ],
    );
  }
}

class _ImageFullScreenPage extends StatelessWidget {
  final String imageUrl;
  final String title;

  const _ImageFullScreenPage({required this.imageUrl, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Center(
        child: InteractiveViewer(maxScale: 5.0, child: Image.network(imageUrl, fit: BoxFit.contain)),
      ),
    );
  }
}

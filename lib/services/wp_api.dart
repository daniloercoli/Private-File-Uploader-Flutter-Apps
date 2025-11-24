import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'app_storage.dart';
import 'dart:typed_data';

// ---- Modello semplice per un file ----
class WpFileItem {
  final String name;
  final String url;
  final int? size;
  final String? mime;
  final int? modified;
  final String? thumbUrl;
  final int? thumbWidth;
  final int? thumbHeight;

  WpFileItem({
    required this.name,
    required this.url,
    this.size,
    this.mime,
    this.modified,
    this.thumbUrl,
    this.thumbWidth,
    this.thumbHeight,
  });

  bool get isImage => (mime ?? '').startsWith('image/');

  factory WpFileItem.fromJson(Map<String, dynamic> json) {
    return WpFileItem(
      name: (json['name'] ?? json['file'] ?? '') as String,
      url: (json['url'] ?? '') as String,
      size: json['size'] is int ? json['size'] as int : (json['size'] is num ? (json['size'] as num).toInt() : null),
      mime: json['mime'] as String?,
      modified: json['modified'] is int
          ? json['modified'] as int
          : (json['modified'] is num ? (json['modified'] as num).toInt() : null),
      thumbUrl: json['thumb_url'] as String?,
      thumbWidth: json['thumb_width'] is int
          ? json['thumb_width'] as int
          : (json['thumb_width'] is num ? (json['thumb_width'] as num).toInt() : null),
      thumbHeight: json['thumb_height'] is int
          ? json['thumb_height'] as int
          : (json['thumb_height'] is num ? (json['thumb_height'] as num).toInt() : null),
    );
  }
}

class WpFilesResponse {
  final bool ok;
  final List<WpFileItem> items;
  final int? total;

  WpFilesResponse({required this.ok, required this.items, this.total});

  factory WpFilesResponse.fromJson(Map<String, dynamic> json) {
    final ok = json['ok'] == true;
    final rawItems = (json['items'] is List) ? (json['items'] as List) : <dynamic>[];
    final items = rawItems.whereType<Map<String, dynamic>>().map((e) => WpFileItem.fromJson(e)).toList();
    return WpFilesResponse(ok: ok, items: items, total: (json['total'] is int) ? json['total'] as int : items.length);
  }
}

class WpApi {
  static Future<WpFilesResponse> fetchFiles() async {
    final baseUrl = await AppStorage.getUrl();
    final username = await AppStorage.getUsername();
    final password = await AppStorage.getPassword();

    if (baseUrl == null || baseUrl.isEmpty) {
      throw Exception('URL non configurato');
    }
    if (username == null || username.isEmpty || password == null || password.isEmpty) {
      throw Exception('Credenziali mancanti');
    }

    final uri = Uri.parse('$baseUrl/wp-json/fileuploader/v1/files');
    final auth = base64Encode(utf8.encode('$username:$password'));
    final res = await http.get(uri, headers: {'Authorization': 'Basic $auth'});

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }

    final Map<String, dynamic> json = jsonDecode(res.body) as Map<String, dynamic>;
    return WpFilesResponse.fromJson(json);
  }

  /// Esegue l'upload del file come multipart su:
  /// {baseUrl}/wp-json/fileuploader/v1/upload
  ///
  /// Salva la URL del server in storage
  static Future<Map<String, dynamic>> uploadFile(String filePath, {http.Client? client}) async {
    final baseUrl = await AppStorage.getUrl();
    final username = await AppStorage.getUsername();
    final password = await AppStorage.getPassword();

    if (baseUrl == null || baseUrl.isEmpty) {
      return {'ok': false, 'status': 0, 'body': 'URL non configurato'};
    }
    if (username == null || username.isEmpty || password == null || password.isEmpty) {
      return {'ok': false, 'status': 0, 'body': 'Credenziali mancanti'};
    }

    final uri = Uri.parse('$baseUrl/wp-json/fileuploader/v1/upload');
    final req = http.MultipartRequest('POST', uri);

    final c = client ?? http.Client();

    // Basic Auth
    final auth = base64Encode(utf8.encode('$username:$password'));
    req.headers['Authorization'] = 'Basic $auth';

    // Possiamo omettere contentType per adesso.
    req.files.add(await http.MultipartFile.fromPath('file', filePath));

    try {
      final streamed = await c.send(req);
      final res = await http.Response.fromStream(streamed);

      final ok = res.statusCode >= 200 && res.statusCode < 300;
      String? remoteUrl;

      // Proviamo a estrarre l'URL dalla risposta
      final body = res.body.trim();
      // 1) JSON noto
      try {
        final obj = jsonDecode(body);
        if (obj is Map) {
          // copriamo vari casi comuni
          remoteUrl = (obj['url'] ?? obj['link'] ?? obj['source_url']) as String?;
          if (remoteUrl == null && obj['guid'] is Map && obj['guid']['rendered'] is String) {
            remoteUrl = obj['guid']['rendered'] as String;
          }
          if (remoteUrl == null && obj['guid'] is String) {
            remoteUrl = obj['guid'] as String;
          }
        } else if (obj is String) {
          // se il server ritorna direttamente la stringa URL
          remoteUrl = obj;
        }
      } catch (_) {
        // 2) non JSON: prova a riconoscere un URL “nudo” nel testo
        final match = RegExp(r'https?://\S+').firstMatch(body);
        if (match != null) remoteUrl = match.group(0);
      }

      return {'ok': ok, 'status': res.statusCode, 'body': body, 'remoteUrl': remoteUrl};
    } on http.ClientException catch (e) {
      // Se abbiamo ricevuto un client esterno è quasi sicuramente una cancellazione
      if (client != null) {
        return {'ok': false, 'cancelled': true, 'status': 0, 'body': 'Upload cancellato: $e'};
      }
      return {'ok': false, 'status': 0, 'body': 'Errore client HTTP: $e'};
    } on SocketException catch (e) {
      return {'ok': false, 'status': 0, 'body': 'Errore di rete: $e'};
    } catch (e) {
      return {'ok': false, 'status': 0, 'body': 'Errore: $e'};
    } finally {
      if (client == null) {
        c.close();
      }
    }
  }

  static Future<Map<String, dynamic>> uploadBytes(
    Uint8List bytes,
    String filename, {
    String? mime,
    http.Client? client,
  }) async {
    final baseUrl = await AppStorage.getUrl();
    final username = await AppStorage.getUsername();
    final password = await AppStorage.getPassword();
    if (baseUrl == null || baseUrl.isEmpty) {
      return {'ok': false, 'status': 0, 'body': 'URL non configurato'};
    }
    if (username == null || username.isEmpty || password == null || password.isEmpty) {
      return {'ok': false, 'status': 0, 'body': 'Credenziali mancanti'};
    }

    final uri = Uri.parse('$baseUrl/wp-json/fileuploader/v1/upload');
    final c = client ?? http.Client();
    final req = http.MultipartRequest('POST', uri);

    // Basic Auth
    final auth = base64Encode(utf8.encode('$username:$password'));
    req.headers['Authorization'] = 'Basic $auth';

    final mediaType = (mime != null && mime.contains('/')) ? MediaType(mime.split('/')[0], mime.split('/')[1]) : null;

    req.files.add(
      http.MultipartFile.fromBytes(
        'file', // campo come da cURL
        bytes,
        filename: filename,
        contentType: mediaType,
      ),
    );

    try {
      final streamed = await c.send(req);
      final res = await http.Response.fromStream(streamed);
      final ok = res.statusCode >= 200 && res.statusCode < 300;

      String? remoteUrl;
      final body = res.body.trim();
      try {
        final obj = jsonDecode(body);
        if (obj is Map) {
          remoteUrl = (obj['url'] ?? obj['link'] ?? obj['source_url']) as String?;
          if (remoteUrl == null && obj['guid'] is Map && obj['guid']['rendered'] is String) {
            remoteUrl = obj['guid']['rendered'] as String;
          }
          if (remoteUrl == null && obj['guid'] is String) {
            remoteUrl = obj['guid'] as String;
          }
        } else if (obj is String) {
          remoteUrl = obj;
        }
      } catch (_) {
        final m = RegExp(r'https?://\S+').firstMatch(body);
        if (m != null) remoteUrl = m.group(0);
      }

      return {'ok': ok, 'status': res.statusCode, 'body': body, 'remoteUrl': remoteUrl};
    } on http.ClientException catch (e) {
      if (client != null) {
        return {'ok': false, 'cancelled': true, 'status': 0, 'body': 'Upload cancellato: $e'};
      }
      return {'ok': false, 'status': 0, 'body': 'Errore client HTTP: $e'};
    } catch (e) {
      return {'ok': false, 'status': 0, 'body': 'Errore: $e'};
    } finally {
      if (client == null) {
        c.close();
      }
    }
  }

  static Future<Map<String, dynamic>> deleteFile(String fileName) async {
    final baseUrl = await AppStorage.getUrl();
    final username = await AppStorage.getUsername();
    final password = await AppStorage.getPassword();

    if (baseUrl == null || baseUrl.isEmpty) {
      return {'ok': false, 'status': 0, 'body': 'URL non configurato'};
    }
    if (username == null || username.isEmpty || password == null || password.isEmpty) {
      return {'ok': false, 'status': 0, 'body': 'Credenziali mancanti'};
    }

    final encoded = Uri.encodeComponent(fileName);
    final uri = Uri.parse('$baseUrl/wp-json/fileuploader/v1/files/$encoded');
    final auth = base64Encode(utf8.encode('$username:$password'));

    final res = await http.delete(uri, headers: {'Authorization': 'Basic $auth'});

    final ok = res.statusCode >= 200 && res.statusCode < 300;
    return {'ok': ok, 'status': res.statusCode, 'body': res.body};
  }

  static Future<Map<String, dynamic>> ping({String? baseUrl, String? username, String? password}) async {
    // se non vengono passati, usa quelli salvati
    final url = baseUrl ?? await AppStorage.getUrl();
    final user = username ?? await AppStorage.getUsername();
    final pass = password ?? await AppStorage.getPassword();

    if (url == null || url.isEmpty) {
      return {'ok': false, 'status': 0, 'body': 'Site URL non configurato'};
    }
    if (user == null || user.isEmpty || pass == null || pass.isEmpty) {
      return {'ok': false, 'status': 0, 'body': 'Credenziali non complete'};
    }

    Uri uri;
    try {
      // normalizza un minimo: niente slash finale multiplo
      final normalized = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
      uri = Uri.parse('$normalized/wp-json/fileuploader/v1/ping');
    } catch (e) {
      return {'ok': false, 'status': 0, 'body': 'URL non valido: $e'};
    }

    final auth = base64Encode(utf8.encode('$user:$pass'));

    try {
      final res = await http.get(uri, headers: {'Authorization': 'Basic $auth'}).timeout(const Duration(seconds: 10));

      final ok = res.statusCode >= 200 && res.statusCode < 300;

      return {'ok': ok, 'status': res.statusCode, 'body': res.body};
    } catch (e) {
      return {'ok': false, 'status': 0, 'body': 'Errore di connessione: $e'};
    }
  }

  static Future<Map<String, dynamic>> renameFile(String oldName, String newName) async {
    final baseUrl = await AppStorage.getUrl();
    final username = await AppStorage.getUsername();
    final password = await AppStorage.getPassword();

    if (baseUrl == null || baseUrl.isEmpty) {
      return {'ok': false, 'status': 0, 'body': 'URL non configurato'};
    }
    if (username == null || username.isEmpty || password == null || password.isEmpty) {
      return {'ok': false, 'status': 0, 'body': 'Credenziali mancanti'};
    }

    // Es: /wp-json/fileuploader/v1/files/{filename}/rename
    final normalized = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final encodedOld = Uri.encodeComponent(oldName);
    final uri = Uri.parse('$normalized/wp-json/fileuploader/v1/files/$encodedOld/rename');

    final auth = base64Encode(utf8.encode('$username:$password'));

    try {
      final res = await http
          .post(
            uri,
            headers: {'Authorization': 'Basic $auth', 'Content-Type': 'application/json'},
            body: jsonEncode({'new_name': newName}),
          )
          .timeout(const Duration(seconds: 15));

      final ok = res.statusCode >= 200 && res.statusCode < 300;

      dynamic body;
      try {
        body = jsonDecode(res.body);
      } catch (_) {
        body = res.body;
      }

      return {'ok': ok, 'status': res.statusCode, 'body': body};
    } catch (e) {
      return {'ok': false, 'status': 0, 'body': 'Errore di connessione: $e'};
    }
  }
}

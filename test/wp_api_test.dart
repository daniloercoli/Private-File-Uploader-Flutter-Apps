import 'package:file_uploader/services/wp_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WpApi.buildRestUri', () {
    test('uses the canonical plugin namespace', () {
      final uri = WpApi.buildRestUri('https://example.com/wordpress', 'files');

      expect(
        uri,
        Uri.parse(
          'https://example.com/wordpress/wp-json/private-file-uploader/v1/files',
        ),
      );
    });

    test('normalizes slashes at URL boundaries', () {
      final uri = WpApi.buildRestUri(
        'https://example.com/wordpress///',
        '///ping',
      );

      expect(
        uri,
        Uri.parse(
          'https://example.com/wordpress/wp-json/private-file-uploader/v1/ping',
        ),
      );
    });

    test('preserves encoded filename segments', () {
      final filename = Uri.encodeComponent('report 2026.pdf');
      final uri = WpApi.buildRestUri('https://example.com', 'files/$filename');

      expect(
        uri.toString(),
        'https://example.com/wp-json/private-file-uploader/v1/files/report%202026.pdf',
      );
    });
  });
}

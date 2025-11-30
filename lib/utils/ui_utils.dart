// lib/utils/ui_utils.dart

/// Restituisce una versione "corta" del testo di errore, limitata a [maxChars] caratteri.
/// Aggiunge "…" in fondo se il testo è stato troncato.
String shortError(Object? body, {int maxChars = 250}) {
  final text = body?.toString().trim() ?? '';
  if (text.length <= maxChars) return text;
  return '${text.substring(0, maxChars)}…';
}

String humanSize(int? bytes) {
  if (bytes == null) return '';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  double v = bytes.toDouble();
  int i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(i == 0 ? 0 : 1)} ${units[i]}';
}

String humanDate(int? epochSeconds) {
  if (epochSeconds == null) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000, isUtc: false);
  return '${dt.year}-${_two(dt.month)}-${_two(dt.day)} ${_two(dt.hour)}:${_two(dt.minute)}';
}

String _two(int n) => n.toString().padLeft(2, '0');

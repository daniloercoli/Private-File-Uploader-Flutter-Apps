// lib/utils/ui_utils.dart

/// Restituisce una versione "corta" del testo di errore, limitata a [maxChars] caratteri.
/// Aggiunge "…" in fondo se il testo è stato troncato.
String shortError(Object? body, {int maxChars = 250}) {
  final text = body?.toString().trim() ?? '';
  if (text.length <= maxChars) return text;
  return '${text.substring(0, maxChars)}…';
}

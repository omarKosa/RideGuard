/// Trims [text] and cuts it to [max] characters for a backend length cap;
/// blank becomes null.
String? clipText(String? text, int max) {
  final t = text?.trim();
  if (t == null || t.isEmpty) return null;
  return t.length <= max ? t : t.substring(0, max).trimRight();
}

class Jinja {
  static String render(String template, Map<String, dynamic> data) {
    return template.replaceAllMapped(RegExp(r'\{\{\s*(\w+)\s*\}\}'), (match) {
      final key = match.group(1)!;
      return data[key]?.toString() ?? '';
    });
  }
}
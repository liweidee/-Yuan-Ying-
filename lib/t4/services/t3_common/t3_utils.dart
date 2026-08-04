String removeChars(String text, String charsToRemove) {
  return text.split('').where((c) => !charsToRemove.contains(c)).join('');
}

String removeTagsExceptList(String html, List<String> tagList) {
  if (html.isEmpty) return html;
  final regex = RegExp(r'<[^>]+>|<!--.*?-->');
  return html.replaceAllMapped(regex, (match) {
    final tag = match.group(0)!;
    if (tag.startsWith('<!--')) return '';
    for (final t in tagList) {
      if (tag.contains('<${t}') || tag.contains('</${t}>')) return tag;
    }
    return '';
  });
}

String replaceTagsWithMapping(String html, Map<String, List<String>> mapping) {
  var result = html;
  for (final entry in mapping.entries) {
    final newTag = entry.key;
    final oldTags = entry.value.join('|');
    result = result.replaceAll(RegExp(r'<(' + oldTags + r')(\s+[^>]*)?>'), '<$newTag\$2>');
    result = result.replaceAll(RegExp(r'</(' + oldTags + r')>'), '</$newTag>');
  }
  return result;
}

List<Map<String, dynamic>> removeDuplicatesByValue(
    List<Map<String, dynamic>> arr, String key) {
  final seen = <String>{};
  final result = <Map<String, dynamic>>[];
  for (final obj in arr) {
    final val = obj[key]?.toString() ?? '';
    if (val.isNotEmpty && !seen.contains(val)) {
      seen.add(val);
      result.add(obj);
    }
  }
  return result;
}

double compareTwoStrings(String first, String second) {
  final a = first.replaceAll(RegExp(r'\s+'), '');
  final b = second.replaceAll(RegExp(r'\s+'), '');
  if (a == b) return 1.0;
  if (a.length < 2 || b.length < 2) return 0.0;
  final bigrams = <String, int>{};
  for (int i = 0; i < a.length - 1; i++) {
    final bg = a.substring(i, i + 2);
    bigrams[bg] = (bigrams[bg] ?? 0) + 1;
  }
  int intersection = 0;
  for (int i = 0; i < b.length - 1; i++) {
    final bg = b.substring(i, i + 2);
    if (bigrams.containsKey(bg) && bigrams[bg]! > 0) {
      intersection++;
      bigrams[bg] = bigrams[bg]! - 1;
    }
  }
  return (2.0 * intersection) / (a.length + b.length - 2);
}

String collapseSpacesAndTrim(String str) {
  str = str.replaceAll(RegExp(r'\r\n|\r|\n'), '');
  str = str.replaceAll(RegExp(r'\s+'), ' ');
  str = str.trim();
  str = str.replaceAll('&nbsp;', ' ');
  str = str.replaceAllMapped(RegExp(r'\\u([0-9a-fA-F]{4})'), (m) {
    return String.fromCharCode(int.parse(m.group(1)!, radix: 16));
  });
  str = str.replaceAll(RegExp(r'\s+'), ' ');
  return str;
}

String convertMultipleUnicodeEscapedWords(String str) {
  return str.replaceAllMapped(RegExp(r'\\u([0-9a-fA-F]{4})'), (m) {
    return String.fromCharCode(int.parse(m.group(1)!, radix: 16));
  });
}
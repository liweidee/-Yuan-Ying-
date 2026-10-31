// lib/modules/agent_llm/utils/message_utils.dart

/// 从 message.content 里提取纯文本（多模态兼容）
String extractContentText(dynamic content) {
  if (content is String) return content;
  if (content is List) {
    final sb = StringBuffer();
    for (final part in content) {
      if (part is Map && part['type'] == 'text') {
        sb.write(part['text']?.toString() ?? '');
      }
    }
    return sb.toString();
  }
  return '';
}

/// 取最后一条 user 消息的纯文本
String extractLastUserText(List<Map<String, dynamic>> messages) {
  final lastUser = messages.lastWhere(
    (m) => m['role'] == 'user',
    orElse: () => <String, dynamic>{},
  );
  if (lastUser.isEmpty) return '';
  return extractContentText(lastUser['content']).trim();
}
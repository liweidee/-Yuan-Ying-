/// 手动导入包声明的市场插件身份。
///
/// 只有包内同时提供稳定 ID 和版本时才返回。文件名、显示名称和 target
/// 不参与身份推断，避免把普通资源包误认为市场插件。
class ManualImportIdentity {
  final String id;
  final String version;

  const ManualImportIdentity({
    required this.id,
    required this.version,
  });

  static ManualImportIdentity? fromJson(Map<dynamic, dynamic> json) {
    final rawId = json['id'] ?? json['pluginId'];
    final rawVersion = json['version'];
    final id = rawId?.toString().trim() ?? '';
    final version = rawVersion?.toString().trim() ?? '';
    if (id.isEmpty || version.isEmpty) return null;
    return ManualImportIdentity(id: id, version: version);
  }
}

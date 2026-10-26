// lib/modules/plugin_center/models/market_entry.dart
import 'dart:ffi' show Abi;
import 'dart:io' show Platform;

/// 市场索引条目
/// 对应 dsplayer-plugin 仓库 market.json 的 plugins[] 每一项
class MarketEntry {
  /// 条目唯一身份（binary/runtime 类 = 包内 plugin.json 的 name）
  final String id;
  final String name;
  final String version;

  /// 包地址：绝对直链 或 相对本索引的路径
  final String url;
  final int sizeBytes;

  /// import / apk / live / server / source
  final String type;

  /// env / app，未声明归 env
  final String category;

  final String? icon;
  final String? author;
  final String? desc;
  final List<String> tags;
  final String? changelog;
  final String? md5;
  final String? minApp;

  /// type=apk 专属：应用包名
  final String? pkg;

  /// 平台词表：android / win32
  final List<String> platforms;

  /// CPU 架构；缺省 = ["arm64-v8a"]
  final List<String> abis;

  MarketEntry({
    required this.id,
    required this.name,
    required this.version,
    required this.url,
    required this.sizeBytes,
    required this.type,
    this.category = 'env',
    this.icon,
    this.author,
    this.desc,
    this.tags = const [],
    this.changelog,
    this.md5,
    this.minApp,
    this.pkg,
    this.platforms = const ['android'],
    this.abis = const ['arm64-v8a'],
  });

  /// 从 market.json 的 plugins[] 单项构造
  factory MarketEntry.fromJson(Map<String, dynamic> json) {
    final rawPlatforms = json['platforms'];
    final rawAbis = json['abis'];
    final rawTags = json['tags'];
    return MarketEntry(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      version: json['version']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      sizeBytes: (json['size'] is num) ? (json['size'] as num).toInt() : 0,
      type: json['type']?.toString() ?? 'import',
      category: json['category']?.toString() ?? 'env',
      icon: json['icon']?.toString(),
      author: json['author']?.toString(),
      desc: json['desc']?.toString(),
      tags: rawTags is List
          ? rawTags.map((e) => e.toString()).toList()
          : const [],
      changelog: json['changelog']?.toString(),
      md5: json['md5']?.toString(),
      minApp: json['minApp']?.toString(),
      pkg: json['pkg']?.toString(),
      platforms: rawPlatforms is List
          ? rawPlatforms.map((e) => e.toString()).toList()
          : const ['android'],
      abis: rawAbis is List
          ? rawAbis.map((e) => e.toString()).toList()
          : const ['arm64-v8a'],
    );
  }

  /// 是否支持 Windows 端
  bool get supportsWindows => platforms.contains('win32');

  /// 是否支持当前平台（Windows / Android）
  bool get supportsCurrentPlatform {
    if (Platform.isWindows) return platforms.contains('win32');
    if (Platform.isAndroid) return platforms.contains('android');
    return false;
  }

  /// 当前宿主进程 ABI 是否匹配
  ///
  /// E2：补 x86_64 / x86 映射。原实现只识别 arm64/arm，x86_64 模拟器上
  /// `abiName` 为空直接返回 true（误判支持），安装后二进制无法执行。
  /// arm64/arm 真机行为完全不变。
  bool get supportsCurrentAbi {
    if (!Platform.isAndroid) return true;
    final currentAbi = Abi.current();
    final abiName = currentAbi == Abi.androidArm64
        ? 'arm64-v8a'
        : currentAbi == Abi.androidArm
            ? 'armeabi-v7a'
            : currentAbi == Abi.androidX64
                ? 'x86_64'
                : currentAbi == Abi.androidIA32
                    ? 'x86'
                    : '';
    if (abiName.isEmpty) return true;
    final declaredAbis = abis.isEmpty ? ['arm64-v8a'] : abis;
    return declaredAbis.contains(abiName);
  }

  /// 展示用大小
  String get sizeText {
    if (sizeBytes <= 0) return '未知';
    const units = ['B', 'KB', 'MB', 'GB'];
    double v = sizeBytes.toDouble();
    int i = 0;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(i == 0 ? 0 : 1)}${units[i]}';
  }
}
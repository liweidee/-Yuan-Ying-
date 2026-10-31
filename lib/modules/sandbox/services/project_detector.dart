// lib/modules/sandbox/services/project_detector.dart
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// 项目类型
enum ProjectType { node, python, php, unknown }

extension ProjectTypeLabel on ProjectType {
  String get label {
    switch (this) {
      case ProjectType.node:
        return 'Node.js';
      case ProjectType.python:
        return 'Python';
      case ProjectType.php:
        return 'PHP';
      case ProjectType.unknown:
        return '未知';
    }
  }
}

/// 项目识别结果
class ProjectInfo {
  final ProjectType type;
  final String hostDir;          // 宿主绝对路径（如 /storage/emulated/0/myapp）
  final String sandboxDir;       // 沙盒内路径（/mnt/sdcard/myapp）
  final String? entryFile;       // 入口文件（如 app.js / main.py）
  final int? port;               // 从项目里识别出的端口
  final String? installCommand;  // 依赖安装命令（如 npm install）
  final String startCommand;     // 启动命令（已含 cd）
  final List<String> warnings;   // 识别过程的提示

  ProjectInfo({
    required this.type,
    required this.hostDir,
    required this.sandboxDir,
    this.entryFile,
    this.port,
    this.installCommand,
    required this.startCommand,
    this.warnings = const [],
  });
}

/// 项目识别器
abstract final class ProjectDetector {
  /// 从宿主目录识别项目
  ///
  /// [hostDir] 宿主绝对路径，必须落在 /storage/emulated/0 下
  static Future<ProjectInfo> detect(String hostDir) async {
    final warnings = <String>[];

    // 1. 计算沙盒路径
    if (!hostDir.startsWith('/storage/emulated/0')) {
      throw Exception('目录必须位于 /storage/emulated/0 下');
    }
    final sandboxDir =
        hostDir.replaceFirst('/storage/emulated/0', '/mnt/sdcard');

    // 2. 尝试各类型识别
    final node = await _detectNode(hostDir, sandboxDir, warnings);
    if (node != null) return node;

    final py = await _detectPython(hostDir, sandboxDir, warnings);
    if (py != null) return py;

    final php = await _detectPhp(hostDir, sandboxDir, warnings);
    if (php != null) return php;

    // 3. 无法识别
    throw Exception(
      '无法识别项目类型。支持：\n'
      '· Node.js（含 package.json）\n'
      '· Python（含 requirements.txt / app.py / main.py）\n'
      '· PHP（含 index.php / composer.json）',
    );
  }

  // ============================================================
  // Node.js
  // ============================================================
  static Future<ProjectInfo?> _detectNode(
    String hostDir,
    String sandboxDir,
    List<String> warnings,
  ) async {
    final pkgJson = File(p.join(hostDir, 'package.json'));
    if (!pkgJson.existsSync()) return null;

    String? entry;
    int? port;
    String installCommand = 'npm install';

    try {
      final json = jsonDecode(await pkgJson.readAsString()) as Map;

      // 入口优先级：scripts.start > main > 常见默认
      final scripts = json['scripts'];
      if (scripts is Map && scripts['start'] is String) {
        final start = (scripts['start'] as String).trim();
        // scripts.start 可能是 "node app.js" 或 "nodemon server.js"
        // 提取出文件（去重运行时前缀）
        final match =
            RegExp(r'(?:node|nodemon|ts-node)\s+([\w\-./]+\.(?:js|ts))')
                .firstMatch(start);
        entry = match?.group(1);
      }
      entry ??= json['main']?.toString();

      // 从 package.json 里嗅端口（约定俗成：config.port 或 scripts 里的 --port）
      final config = json['config'];
      if (config is Map && config['port'] != null) {
        port = int.tryParse(config['port'].toString());
      }
      if (port == null && scripts is Map && scripts['start'] is String) {
        final m = RegExp(r'--port[= ](\d+)')
            .firstMatch(scripts['start'] as String);
        if (m != null) port = int.tryParse(m.group(1)!);
      }
    } catch (e) {
      warnings.add('package.json 解析失败：$e');
    }

    // 常见入口兜底
    entry ??= _findFirstExisting(hostDir, const [
      'app.js',
      'index.js',
      'server.js',
      'main.js',
      'app.ts',
      'src/app.js',
      'src/index.js',
      'src/server.js',
    ]);

    // 有 yarn.lock / pnpm-lock.yaml 时换用对应包管理器
    if (File(p.join(hostDir, 'yarn.lock')).existsSync()) {
      installCommand = 'yarn install';
    } else if (File(p.join(hostDir, 'pnpm-lock.yaml')).existsSync()) {
      installCommand = 'pnpm install';
    } else if (File(p.join(hostDir, 'package-lock.json')).existsSync()) {
      installCommand = 'npm ci || npm install';
    }

    final startCmd = entry != null
        ? 'node $entry'
        : 'node .'; // 交给 node 自己解析 package.json main

    return ProjectInfo(
      type: ProjectType.node,
      hostDir: hostDir,
      sandboxDir: sandboxDir,
      entryFile: entry,
      port: port,
      installCommand: installCommand,
      startCommand: 'cd $sandboxDir && $startCmd',
      warnings: warnings,
    );
  }

  // ============================================================
  // Python
  // ============================================================
  static Future<ProjectInfo?> _detectPython(
    String hostDir,
    String sandboxDir,
    List<String> warnings,
  ) async {
    final hasReq = File(p.join(hostDir, 'requirements.txt')).existsSync();
    final hasPyproject =
        File(p.join(hostDir, 'pyproject.toml')).existsSync();
    final hasSetup = File(p.join(hostDir, 'setup.py')).existsSync();

    // 入口文件兜底
    final entry = _findFirstExisting(hostDir, const [
      'app.py',
      'main.py',
      'manage.py',
      'wsgi.py',
      'server.py',
      'run.py',
      'src/app.py',
      'src/main.py',
    ]);

    // 既没依赖文件，也没入口文件 → 不认为是 Python 项目
    if (!hasReq && !hasPyproject && !hasSetup && entry == null) {
      return null;
    }

    // 依赖安装命令
    String? installCommand;
    if (hasReq) {
      installCommand = 'pip install -r requirements.txt '
          '-i https://pypi.tuna.tsinghua.edu.cn/simple';
    } else if (hasPyproject) {
      installCommand =
          'pip install . -i https://pypi.tuna.tsinghua.edu.cn/simple';
    } else if (hasSetup) {
      installCommand =
          'pip install -e . -i https://pypi.tuna.tsinghua.edu.cn/simple';
    }

    // Django 特殊处理
    if (entry == 'manage.py') {
      return ProjectInfo(
        type: ProjectType.python,
        hostDir: hostDir,
        sandboxDir: sandboxDir,
        entryFile: entry,
        port: 8000,
        installCommand: installCommand,
        startCommand:
            'cd $sandboxDir && python3 manage.py runserver 0.0.0.0:8000',
        warnings: [...warnings, '检测到 Django 项目，默认端口 8000'],
      );
    }

    // FastAPI / Flask / 通用
    final startCmd = entry != null
        ? 'python3 $entry'
        : 'python3 -m http.server 8000';

    return ProjectInfo(
      type: ProjectType.python,
      hostDir: hostDir,
      sandboxDir: sandboxDir,
      entryFile: entry,
      port: entry != null ? null : 8000,
      installCommand: installCommand,
      startCommand: 'cd $sandboxDir && $startCmd',
      warnings: warnings,
    );
  }

  // ============================================================
  // PHP
  // ============================================================
  static Future<ProjectInfo?> _detectPhp(
    String hostDir,
    String sandboxDir,
    List<String> warnings,
  ) async {
    final hasComposer =
        File(p.join(hostDir, 'composer.json')).existsSync();
    final hasIndex = File(p.join(hostDir, 'index.php')).existsSync();
    final hasPublicIndex =
        File(p.join(hostDir, 'public/index.php')).existsSync();

    if (!hasComposer && !hasIndex && !hasPublicIndex) return null;

    // 文档根：优先 public/（Laravel/Symfony 等）
    final docRoot = hasPublicIndex ? '$sandboxDir/public' : sandboxDir;

    // 端口从 composer.json 的 extra 里嗅（若有）
    int? port;
    if (hasComposer) {
      try {
        final json = jsonDecode(
          await File(p.join(hostDir, 'composer.json')).readAsString(),
        ) as Map;
        final extra = json['extra'];
        if (extra is Map && extra['port'] != null) {
          port = int.tryParse(extra['port'].toString());
        }
      } catch (_) {}
    }

    // 纯静态站点（无 PHP 入口，只有 html）→ 交给 httpd
    if (!hasIndex && !hasPublicIndex) {
      return ProjectInfo(
        type: ProjectType.php,
        hostDir: hostDir,
        sandboxDir: sandboxDir,
        port: 8080,
        installCommand: null,
        startCommand:
            'busybox httpd -f -p 8080 -h $sandboxDir',
        warnings: [...warnings, '未发现 PHP 入口，按静态站点处理'],
      );
    }

    final installCommand =
        hasComposer ? 'composer install --no-dev --no-interaction' : null;

    return ProjectInfo(
      type: ProjectType.php,
      hostDir: hostDir,
      sandboxDir: sandboxDir,
      port: port ?? 8000,
      installCommand: installCommand,
      startCommand:
          'php -S 0.0.0.0:${port ?? 8000} -t $docRoot',
      warnings: warnings,
    );
  }

  // ============================================================
  // 工具
  // ============================================================
  static String? _findFirstExisting(String dir, List<String> names) {
    for (final name in names) {
      final f = File(p.join(dir, name));
      if (f.existsSync()) return name;
    }
    return null;
  }
}
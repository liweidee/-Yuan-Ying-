import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:synchronized/synchronized.dart';

import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/modules/plugin_center/services/plugin_paths.dart';
import 'package:yuanying/utils/storage_manager.dart';

/// 直播配置事务。
///
/// 只快照 [SettingBoxKey.liveConfigs]，用于市场/手动直播包在取消或登记失败时
/// 恢复安装前的配置。不会修改直播 key、当前选中线路或其他设置。
class LiveConfigTransaction {
  final List<dynamic> _before;
  bool _closed = false;

  LiveConfigTransaction._(this._before);

  factory LiveConfigTransaction.capture() {
    final raw =
        StorageManager.getSetting<List<dynamic>>(SettingBoxKey.liveConfigs) ??
        <dynamic>[];
    return LiveConfigTransaction._(_deepCopyList(raw));
  }

  Future<void> rollback() async {
    if (_closed) return;
    _closed = true;
    await StorageManager.setSetting(
      SettingBoxKey.liveConfigs,
      _deepCopyList(_before),
    );
  }

  void commit() {
    _closed = true;
  }

  static List<dynamic> _deepCopyList(List<dynamic> source) {
    return source.map(_deepCopyValue).toList();
  }

  static dynamic _deepCopyValue(dynamic value) {
    if (value is Map) {
      return value.map(
        (key, item) => MapEntry(key, _deepCopyValue(item)),
      );
    }
    if (value is List) {
      return value.map(_deepCopyValue).toList();
    }
    return value;
  }
}

/// 源码包文件级事务。
///
/// 源码包会合并到共享数据根目录，因此不能替换整个目录。本事务只记录并备份
/// 包内实际覆盖的文件，取消或异常时原位恢复；正常完成时保留当前合并语义。
class SourcePackageTransaction {
  static final Lock _lock = Lock();

  static Future<T> run<T>({
    required String tag,
    required Directory staging,
    required Directory dataRoot,
    required bool Function() isCancelled,
    required Future<T> Function() afterFilesCommitted,
  }) {
    return _lock.synchronized(() async {
      final transaction = _SourceFileTransaction(
        tag: tag,
        staging: staging,
        dataRoot: dataRoot,
        isCancelled: isCancelled,
      );
      try {
        await transaction.apply();
        final result = await afterFilesCommitted();
        await transaction.commit();
        return result;
      } catch (error, stackTrace) {
        try {
          await transaction.rollback();
        } catch (rollbackError) {
          throw Exception(
            '源码包安装失败，且自动回滚失败：$error；回滚异常：$rollbackError',
          );
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
    });
  }
}

class _SourceFileTransaction {
  static const String _transactionRelativePrefix =
      'plugins/cache/install-transactions/';

  final String tag;
  final Directory staging;
  final Directory dataRoot;
  final bool Function() isCancelled;
  final String _transactionId = '${DateTime.now().microsecondsSinceEpoch}-$pid';

  final List<String> _directories = [];
  final Map<String, String> _files = {};
  final List<String> _createdDirectories = [];
  final List<_SourceFileMutation> _mutations = [];
  final List<File> _temporaryFiles = [];

  Directory? _backupRoot;
  bool _closed = false;

  _SourceFileTransaction({
    required this.tag,
    required this.staging,
    required this.dataRoot,
    required this.isCancelled,
  });

  Future<void> apply() async {
    await _preflight();
    _throwIfCancelled();

    final cacheRoot = Directory(
      p.join(dataRoot.path, 'plugins', 'cache', 'install-transactions'),
    );
    await cacheRoot.create(recursive: true);
    final safeTag = tag.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    _backupRoot = Directory(
      p.join(cacheRoot.path, 'source-$safeTag-$_transactionId'),
    );
    await _backupRoot!.create(recursive: true);

    final sortedDirectories = List<String>.from(_directories)
      ..sort((a, b) => _depth(a).compareTo(_depth(b)));
    for (final relativePath in sortedDirectories) {
      _throwIfCancelled();
      final target = Directory(_targetPath(relativePath));
      if (target.existsSync()) continue;
      await target.create(recursive: true);
      _createdDirectories.add(relativePath);
    }

    for (final entry in _files.entries) {
      _throwIfCancelled();
      final source = File(p.join(staging.path, entry.value));
      final target = File(_targetPath(entry.key));
      await target.parent.create(recursive: true);

      final temporary = File(
        '${target.path}.plugin-center-new-$_transactionId',
      );
      _temporaryFiles.add(temporary);
      await source.copy(temporary.path);
      _throwIfCancelled();

      File? backup;
      if (target.existsSync()) {
        backup = File(
          p.join(_backupRoot!.path, 'files', entry.key),
        );
        await backup.parent.create(recursive: true);
        await target.rename(backup.path);
      }

      final mutation = _SourceFileMutation(target: target, backup: backup);
      _mutations.add(mutation);
      await temporary.rename(target.path);
    }

    _throwIfCancelled();
  }

  Future<void> commit() async {
    if (_closed) return;
    _closed = true;
    await _deleteTemporaryFiles();
    final backupRoot = _backupRoot;
    if (backupRoot != null && backupRoot.existsSync()) {
      try {
        await backupRoot.delete(recursive: true);
      } catch (error) {
        debugPrint(
          '[SourcePackageTransaction] 清理事务备份失败：$error',
        );
      }
    }
  }

  Future<void> rollback() async {
    if (_closed) return;
    _closed = true;

    Object? restoreError;
    StackTrace? restoreStackTrace;
    for (final mutation in _mutations.reversed) {
      try {
        if (mutation.target.existsSync()) {
          await mutation.target.delete();
        }
        final backup = mutation.backup;
        if (backup != null && backup.existsSync()) {
          await backup.parent.create(recursive: true);
          await backup.rename(mutation.target.path);
        }
      } catch (error, stackTrace) {
        restoreError ??= error;
        restoreStackTrace ??= stackTrace;
      }
    }

    await _deleteTemporaryFiles();
    for (final relativePath in _createdDirectories.reversed) {
      try {
        final directory = Directory(_targetPath(relativePath));
        if (directory.existsSync() &&
            await directory.list(followLinks: false).isEmpty) {
          await directory.delete();
        }
      } catch (error) {
        debugPrint(
          '[SourcePackageTransaction] 清理新增目录失败：$relativePath：$error',
        );
      }
    }

    final backupRoot = _backupRoot;
    if (backupRoot != null && backupRoot.existsSync()) {
      try {
        await backupRoot.delete(recursive: true);
      } catch (error) {
        debugPrint(
          '[SourcePackageTransaction] 清理回滚备份失败：$error',
        );
      }
    }

    if (restoreError != null) {
      Error.throwWithStackTrace(
        restoreError,
        restoreStackTrace ?? StackTrace.current,
      );
    }
  }

  Future<void> _preflight() async {
    if (p.equals(staging.path, dataRoot.path)) {
      throw Exception('源码包暂存目录不能与数据根目录相同');
    }

    final seen = <String>{};
    final directories = <String>{};
    final files = <String, String>{};

    await for (final entity in staging.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is Link) {
        throw Exception('源码包包含不支持的符号链接：${entity.path}');
      }
      final sourceRelativePath = _safeRelativePath(entity.path);
      if (sourceRelativePath == 'source.json') continue;
      final relativePath = _stripPayloadPrefix(sourceRelativePath);
      if (relativePath.isEmpty) {
        if (entity is Directory) continue;
        throw Exception('源码包顶层 payload 必须是目录');
      }

      final normalizedForReservedCheck = relativePath.replaceAll('\\', '/');
      if (normalizedForReservedCheck ==
              _transactionRelativePrefix.substring(
                0,
                _transactionRelativePrefix.length - 1,
              ) ||
          normalizedForReservedCheck.startsWith(_transactionRelativePrefix)) {
        throw Exception('源码包包含插件中心事务保留路径：$relativePath');
      }

      if (entity is Directory) {
        _addDirectoryAndParents(relativePath, directories);
        continue;
      }
      if (entity is! File) continue;

      final key = Platform.isWindows
          ? relativePath.toLowerCase()
          : relativePath;
      if (!seen.add(key)) {
        throw Exception('源码包包含重复目标文件：$relativePath');
      }
      files[relativePath] = sourceRelativePath;
      _addDirectoryAndParents(p.dirname(relativePath), directories);
    }

    directories.remove('.');
    final sortedDirectories = directories.toList()
      ..sort((a, b) => _depth(a).compareTo(_depth(b)));
    for (final relativePath in sortedDirectories) {
      final target = _targetPath(relativePath);
      final type = FileSystemEntity.typeSync(target, followLinks: false);
      if (type == FileSystemEntityType.link) {
        throw Exception('目标目录是符号链接，拒绝覆盖：$relativePath');
      }
      if (type == FileSystemEntityType.file) {
        throw Exception('目标目录位置存在同名文件：$relativePath');
      }
    }

    final sortedFiles = files.keys.toList()..sort();
    final directoryKeys = directories
        .map((path) => Platform.isWindows ? path.toLowerCase() : path)
        .toSet();
    for (final relativePath in sortedFiles) {
      final key = Platform.isWindows
          ? relativePath.toLowerCase()
          : relativePath;
      if (directoryKeys.contains(key)) {
        throw Exception('源码包中文件与目录路径冲突：$relativePath');
      }
      final target = _targetPath(relativePath);
      final type = FileSystemEntity.typeSync(target, followLinks: false);
      if (type == FileSystemEntityType.link) {
        throw Exception('目标文件是符号链接，拒绝覆盖：$relativePath');
      }
      if (type == FileSystemEntityType.directory) {
        throw Exception('目标文件位置存在同名目录：$relativePath');
      }
    }

    _directories
      ..clear()
      ..addAll(sortedDirectories);
    _files
      ..clear()
      ..addAll(files);
  }

  String _stripPayloadPrefix(String relativePath) {
    final parts = p.split(relativePath);
    if (parts.isNotEmpty && parts.first == 'payload') {
      parts.removeAt(0);
    }
    return p.joinAll(parts);
  }

  void _addDirectoryAndParents(String relativePath, Set<String> result) {
    var current = p.normalize(relativePath);
    while (current != '.' && current != p.separator && current.isNotEmpty) {
      result.add(current);
      final parent = p.dirname(current);
      if (parent == current) break;
      current = parent;
    }
  }

  String _safeRelativePath(String absolutePath) {
    final relativePath = p.normalize(
      p.relative(p.absolute(absolutePath), from: p.absolute(staging.path)),
    );
    if (relativePath == '.' ||
        p.isAbsolute(relativePath) ||
        relativePath == '..' ||
        relativePath.startsWith('..${p.separator}')) {
      throw Exception('源码包路径越界：$absolutePath');
    }
    final target = _targetPath(relativePath);
    if (!PluginPaths.isWithin(dataRoot, target) ||
        p.equals(target, dataRoot.path)) {
      throw Exception('源码包目标路径越界：$relativePath');
    }
    return relativePath;
  }

  String _targetPath(String relativePath) {
    return p.normalize(p.join(dataRoot.path, relativePath));
  }

  void _throwIfCancelled() {
    if (isCancelled()) throw Exception('已取消源码包安装');
  }

  Future<void> _deleteTemporaryFiles() async {
    for (final temporary in _temporaryFiles) {
      try {
        if (temporary.existsSync()) {
          await temporary.delete();
        }
      } catch (error) {
        debugPrint(
          '[SourcePackageTransaction] 清理临时文件失败：${temporary.path}：$error',
        );
      }
    }
  }

  static int _depth(String path) {
    return p.split(path).length;
  }
}

class _SourceFileMutation {
  final File target;
  final File? backup;

  const _SourceFileMutation({
    required this.target,
    required this.backup,
  });
}

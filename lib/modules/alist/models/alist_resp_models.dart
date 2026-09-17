/// ============ 响应模型 ============

/// fs/list 响应
class AlistFileListResp {
  final List<AlistFileListContent>? content;
  final int total;
  final String readme;
  final bool write;
  final String provider;

  AlistFileListResp({
    this.content,
    required this.total,
    required this.readme,
    required this.write,
    required this.provider,
  });

  factory AlistFileListResp.fromJson(Map<String, dynamic> json) {
    return AlistFileListResp(
      content: (json['content'] as List?)
          ?.map((e) => AlistFileListContent.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int? ?? 0,
      readme: json['readme'] as String? ?? '',
      write: json['write'] as bool? ?? false,
      provider: json['provider'] as String? ?? '',
    );
  }
}

class AlistFileListContent {
  final String name;
  final int? size;
  final bool isDir;
  final String modified;
  final String sign;
  final String thumb;
  final int type;
  final String? readme;

  AlistFileListContent({
    required this.name,
    this.size,
    required this.isDir,
    required this.modified,
    required this.sign,
    required this.thumb,
    required this.type,
    this.readme,
  });

  factory AlistFileListContent.fromJson(Map<String, dynamic> json) {
    return AlistFileListContent(
      name: json['name'] as String? ?? '',
      size: json['size'] as int?,
      isDir: json['is_dir'] as bool? ?? false,
      modified: json['modified'] as String? ?? '',
      sign: json['sign'] as String? ?? '',
      thumb: json['thumb'] as String? ?? '',
      type: json['type'] as int? ?? 0,
      readme: json['readme'] as String?,
    );
  }
}

/// fs/get 响应（单文件信息）
class AlistFileInfoResp {
  final String name;
  final int size;
  final bool isDir;
  final String modified;
  final String sign;
  final String thumb;
  final int type;
  final String? rawUrl;
  final String? readme;
  final String? provider;
  final dynamic related;

  AlistFileInfoResp({
    required this.name,
    required this.size,
    required this.isDir,
    required this.modified,
    required this.sign,
    required this.thumb,
    required this.type,
    this.rawUrl,
    this.readme,
    this.provider,
    this.related,
  });

  factory AlistFileInfoResp.fromJson(Map<String, dynamic> json) {
    return AlistFileInfoResp(
      name: json['name'] as String? ?? '',
      size: json['size'] as int? ?? 0,
      isDir: json['is_dir'] as bool? ?? false,
      modified: json['modified'] as String? ?? '',
      sign: json['sign'] as String? ?? '',
      thumb: json['thumb'] as String? ?? '',
      type: json['type'] as int? ?? 0,
      rawUrl: json['raw_url'] as String?,
      readme: json['readme'] as String?,
      provider: json['provider'] as String?,
      related: json['related'],
    );
  }
}

/// fs/search 响应
class AlistFileSearchResp {
  final List<AlistFileSearchContent>? content;
  final int? total;

  AlistFileSearchResp({this.content, this.total});

  factory AlistFileSearchResp.fromJson(Map<String, dynamic> json) {
    return AlistFileSearchResp(
      content: (json['content'] as List?)
          ?.map((e) =>
              AlistFileSearchContent.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int?,
    );
  }
}

class AlistFileSearchContent {
  String? parent;
  String? name;
  bool? isDir;
  int? size;
  int? type;

  AlistFileSearchContent({
    this.parent,
    this.name,
    this.isDir,
    this.size,
    this.type,
  });

  factory AlistFileSearchContent.fromJson(Map<String, dynamic> json) {
    return AlistFileSearchContent(
      parent: json['parent'] as String?,
      name: json['name'] as String?,
      isDir: json['is_dir'] as bool?,
      size: json['size'] as int?,
      type: json['type'] as int?,
    );
  }
}

/// auth/login 响应
class AlistLoginResp {
  final String token;
  AlistLoginResp({required this.token});

  factory AlistLoginResp.fromJson(Map<String, dynamic> json) {
    return AlistLoginResp(token: json['token'] as String? ?? '');
  }
}

/// me 响应
class AlistMyInfoResp {
  final int id;
  final String username;
  final String password;
  final String basePath;
  final int role;
  final bool disabled;
  final int permission;
  final String ssoId;
  final bool otp;

  AlistMyInfoResp({
    required this.id,
    required this.username,
    required this.password,
    required this.basePath,
    required this.role,
    required this.disabled,
    required this.permission,
    required this.ssoId,
    required this.otp,
  });

  factory AlistMyInfoResp.fromJson(Map<String, dynamic> json) {
    return AlistMyInfoResp(
      id: json['id'] as int? ?? 0,
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
      basePath: json['base_path'] as String? ?? '',
      role: json['role'] as int? ?? 0,
      disabled: json['disabled'] as bool? ?? false,
      permission: json['permission'] as int? ?? -1,
      ssoId: json['sso_id'] as String? ?? '',
      otp: json['otp'] as bool? ?? false,
    );
  }
}

/// public/settings 响应（仅需字段：searchIndex）
class AlistPublicSettingsResp {
  final String? searchIndex;
  final String? version;

  AlistPublicSettingsResp({this.searchIndex, this.version});

  factory AlistPublicSettingsResp.fromJson(Map<String, dynamic> json) {
    return AlistPublicSettingsResp(
      searchIndex: json['search_index'] as String?,
      version: json['version'] as String?,
    );
  }
}

/// ============ 请求模型 ============

class AlistMkdirReq {
  late String path;
  AlistMkdirReq({required this.path});
  Map<String, dynamic> toJson() => {'path': path};
}

class AlistFileRenameReq {
  late String path;
  late String name;
  AlistFileRenameReq({required this.path, required this.name});
  Map<String, dynamic> toJson() => {'path': path, 'name': name};
}

class AlistFileRemoveReq {
  late String dir;
  late List<String> names;
  AlistFileRemoveReq({required this.dir, required this.names});
  Map<String, dynamic> toJson() => {'dir': dir, 'names': names};
}

class AlistCopyMoveReq {
  late String srcDir;
  late String dstDir;
  late List<String> names;
  AlistCopyMoveReq({
    required this.srcDir,
    required this.dstDir,
    required this.names,
  });
  Map<String, dynamic> toJson() => {
        'src_dir': srcDir,
        'dst_dir': dstDir,
        'names': names,
      };
}

/// 下载信息（.downloads 文件内容）
class AlistDownloadsInfo {
  late bool isSupportRange;
  late bool decompress;
  String? lastModified;
  String? etag;
  int? contentLength;

  AlistDownloadsInfo({
    this.isSupportRange = false,
    this.decompress = false,
    this.lastModified,
    this.etag,
    this.contentLength,
  });

  factory AlistDownloadsInfo.fromJson(Map<String, dynamic> json) {
    return AlistDownloadsInfo(
      isSupportRange: json['isSupportRange'] as bool? ?? false,
      decompress: json['decompress'] as bool? ?? false,
      lastModified: json['lastModified'] as String?,
      etag: json['etag'] as String?,
      contentLength: json['contentLength'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'isSupportRange': isSupportRange,
        'decompress': decompress,
        'lastModified': lastModified,
        'etag': etag,
        'contentLength': contentLength,
      };
}
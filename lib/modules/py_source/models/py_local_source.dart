// lib/modules/py_source/models/py_local_source.dart

/// @header 解析结果
class PySourceHeader {
  final String? title;
  final int searchable;
  final int filterable;
  final int quickSearch;
  final String? lang;
  final String? type;   // 源自身的 type（字符串形式）
  final String? icon;

  const PySourceHeader({
    this.title,
    this.searchable = 0,
    this.filterable = 0,
    this.quickSearch = 0,
    this.lang,
    this.type,
    this.icon,
  });

  factory PySourceHeader.empty() => const PySourceHeader();
}

/// 本地 py 源
class PyLocalSource {
  final String name;        // 文件名（不含 .py）
  final String path;        // 绝对路径
  final int size;
  final DateTime modified;

  /// 从 @header 解析的原始元数据（只读，作为重置来源）
  final PySourceHeader header;

  /// Hive 中保存的用户覆盖（优先级高于 header）
  final PySourceMeta? meta;

  PyLocalSource({
    required this.name,
    required this.path,
    required this.size,
    required this.modified,
    this.header = const PySourceHeader(),
    this.meta,
  });

  /// 最终生效的可搜索标记
  int get effectiveSearchable => meta?.searchable ?? header.searchable;
  int get effectiveFilterable => meta?.filterable ?? header.filterable;
  int get effectiveQuickSearch => meta?.quickSearch ?? header.quickSearch;

  /// 最终生效的显示名
  String get effectiveName =>
      (meta?.name != null && meta!.name!.isNotEmpty) ? meta!.name! : name;

  /// 最终生效的 title
  String get effectiveTitle =>
      (meta?.title != null && meta!.title!.isNotEmpty)
          ? meta!.title!
          : (header.title ?? name);

  /// ext（用户在元数据中覆盖的，或空）
  String get effectiveExt => meta?.ext ?? '';

  /// 用于 SourceManager 的唯一 key
  String get siteKey => 'local_py_$name';

  /// 标签文本：可搜/快搜/筛选 + key
  String get tagLine {
    final s = effectiveSearchable == 1 ? '可搜' : '不可搜';
    final q = effectiveQuickSearch == 1 ? '快搜' : '不快搜';
    final f = effectiveFilterable == 1 ? '筛选' : '不筛选';
    return '$s $q $f · $siteKey';
  }

  String get sizeText {
    if (size < 1024) return '${size}B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)}KB';
    return '${(size / 1024 / 1024).toStringAsFixed(1)}MB';
  }

  PyLocalSource copyWith({PySourceMeta? meta}) => PyLocalSource(
        name: name,
        path: path,
        size: size,
        modified: modified,
        header: header,
        meta: meta,
      );
}

/// Hive 中保存的用户覆盖元数据
class PySourceMeta {
  final String? name;
  final String? title;
  final int searchable;
  final int filterable;
  final int quickSearch;
  final String? ext;

  const PySourceMeta({
    this.name,
    this.title,
    this.searchable = 0,
    this.filterable = 0,
    this.quickSearch = 0,
    this.ext,
  });

  factory PySourceMeta.fromJson(Map<String, dynamic> j) => PySourceMeta(
        name: j['name']?.toString(),
        title: j['title']?.toString(),
        searchable: (j['searchable'] as num?)?.toInt() ?? 0,
        filterable: (j['filterable'] as num?)?.toInt() ?? 0,
        quickSearch: (j['quickSearch'] as num?)?.toInt() ?? 0,
        ext: j['ext']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        if (name != null) 'name': name,
        if (title != null) 'title': title,
        'searchable': searchable,
        'filterable': filterable,
        'quickSearch': quickSearch,
        if (ext != null) 'ext': ext,
      };

  PySourceMeta copyWith({
    String? name,
    String? title,
    int? searchable,
    int? filterable,
    int? quickSearch,
    String? ext,
    bool clearExt = false,
  }) =>
      PySourceMeta(
        name: name ?? this.name,
        title: title ?? this.title,
        searchable: searchable ?? this.searchable,
        filterable: filterable ?? this.filterable,
        quickSearch: quickSearch ?? this.quickSearch,
        ext: clearExt ? null : (ext ?? this.ext),
      );
}
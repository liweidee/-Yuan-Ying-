// lib/modules/manual_source/models/manual_source_item.dart

enum ManualSourceType {
  py,
  dr2,
  dr3,
  js,
  html,
  xbpq,
  xyq,
  t4;

  String get dirName {
    switch (this) {
      case ManualSourceType.py: return 'hipy';
      case ManualSourceType.dr2: return 'dr2';
      case ManualSourceType.dr3: return 'dr3';
      case ManualSourceType.js: return 'js';
      case ManualSourceType.html: return 'html';
      case ManualSourceType.xbpq: return 'xbpq';
      case ManualSourceType.xyq: return 'xyq';
      case ManualSourceType.t4: return '';
    }
  }

  String get ext {
    switch (this) {
      case ManualSourceType.py: return 'py';
      case ManualSourceType.html: return 'html';
      case ManualSourceType.t4: return '';
      case ManualSourceType.xbpq:
      case ManualSourceType.xyq:
        return 'json';
      default: return 'js';
    }
  }

  String get label {
    switch (this) {
      case ManualSourceType.py: return 'PY';
      case ManualSourceType.dr2: return 'DR2';
      case ManualSourceType.dr3: return 'DR3';
      case ManualSourceType.js: return 'JS';
      case ManualSourceType.html: return 'HTML';
      case ManualSourceType.xbpq: return 'XBPQ';
      case ManualSourceType.xyq: return 'XYQ';
      case ManualSourceType.t4: return 'T4';
    }
  }

  bool get isFileBased => this != ManualSourceType.t4;

  static ManualSourceType? fromDir(String dir) {
    for (final t in ManualSourceType.values) {
      if (t.dirName == dir) return t;
    }
    return null;
  }
}

class ManualSourceItem {
  final ManualSourceType type;
  final String name;
  final String path;
  final int size;
  final DateTime modified;
  final bool disabled;
  final int searchable;
  final int filterable;
  final int quickSearch;
  final String ext;

  ManualSourceItem({
    required this.type,
    required this.name,
    required this.path,
    required this.size,
    required this.modified,
    this.disabled = false,
    this.searchable = 1,
    this.filterable = 1,
    this.quickSearch = 1,
    this.ext = '',
  });

  String get id => 'manual_${type.name}_$name';

  String get displayName => '$name(${type.label})';

  String get sizeText {
    if (!type.isFileBased) return '';
    if (size < 1024) return '${size}B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)}KB';
    return '${(size / 1024 / 1024).toStringAsFixed(1)}MB';
  }

  String get tagLine {
    final s = searchable == 1 ? '可搜' : '不可搜';
    final q = quickSearch == 1 ? '快搜' : '不快搜';
    final f = filterable == 1 ? '筛选' : '不筛选';
    return '$s $q $f';
  }
}

class ManualSourceMeta {
  final int searchable;
  final int filterable;
  final int quickSearch;
  final bool disabled;
  final String? name;
  final String? api;
  final String? ext;

  const ManualSourceMeta({
    this.searchable = 1,
    this.filterable = 1,
    this.quickSearch = 1,
    this.disabled = false,
    this.name,
    this.api,
    this.ext,
  });

  factory ManualSourceMeta.fromJson(Map<String, dynamic> j) => ManualSourceMeta(
        searchable: (j['searchable'] as num?)?.toInt() ?? 1,
        filterable: (j['filterable'] as num?)?.toInt() ?? 1,
        quickSearch: (j['quickSearch'] as num?)?.toInt() ?? 1,
        disabled: j['disabled'] == true,
        name: j['name']?.toString(),
        api: j['api']?.toString(),
        ext: j['ext']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'searchable': searchable,
        'filterable': filterable,
        'quickSearch': quickSearch,
        'disabled': disabled,
        if (name != null) 'name': name,
        if (api != null) 'api': api,
        if (ext != null) 'ext': ext,
      };

  ManualSourceMeta copyWith({
    int? searchable,
    int? filterable,
    int? quickSearch,
    bool? disabled,
    String? name,
    String? api,
    String? ext,
  }) =>
      ManualSourceMeta(
        searchable: searchable ?? this.searchable,
        filterable: filterable ?? this.filterable,
        quickSearch: quickSearch ?? this.quickSearch,
        disabled: disabled ?? this.disabled,
        name: name ?? this.name,
        api: api ?? this.api,
        ext: ext ?? this.ext,
      );
}
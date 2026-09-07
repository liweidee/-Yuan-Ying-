// lib/modules/tmdb/views/tmdb_detail_page.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:dio/dio.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/modules/setting/controllers/tmdb_config_controller.dart';
import 'package:yuanying/t4/models/video_item.dart';
import 'package:yuanying/core/routes/app_pages.dart';
import 'package:yuanying/services/search_filter_service.dart';
import 'package:yuanying/t4/services/source_manager.dart';
import 'package:yuanying/modules/tmdb/views/tmdb_person_page.dart';

class TmdbDetailPage extends StatefulWidget {
  final VideoItem videoItem;
  final Map<String, dynamic> site;
  final bool fromHome;
  final int? tmdbId;       // 新增：TMDB ID，用于直接获取详情
  final String? mediaType; // 新增：'movie' 或 'tv'

  const TmdbDetailPage({
    super.key,
    required this.videoItem,
    required this.site,
    this.fromHome = false,
    this.tmdbId,
    this.mediaType,
  });

  @override
  State<TmdbDetailPage> createState() => _TmdbDetailPageState();
}

class _TmdbDetailPageState extends State<TmdbDetailPage> {
  late final TmdbConfigController tmdbCtrl = Get.isRegistered<TmdbConfigController>()
      ? Get.find<TmdbConfigController>()
      : Get.put(TmdbConfigController());

  final Dio _dio = Dio();

  bool _isLoading = true;
  String? _errorMsg;
  Map<String, dynamic>? _tmdbData;
  String? _mediaType;

  // 详情字段
  String? _title;
  String? _originalTitle;
  String? _overview;
  String? _tagline;
  String? _posterPath;
  String? _backdropPath;
  String? _releaseDate;
  double? _voteAverage;
  int? _voteCount;
  List<dynamic>? _genres;
  int? _runtime;
  String? _status;
  List<dynamic>? _productionCompanies;
  List<dynamic>? _productionCountries;
  List<dynamic>? _spokenLanguages;
  List<dynamic>? _seasons;
  int? _numberOfSeasons;
  int? _numberOfEpisodes;
  List<dynamic>? _videos;
  List<dynamic>? _credits;
  List<dynamic>? _similar;
  Map<String, dynamic>? _externalIds;

  final ScrollController _scrollController = ScrollController();
  final SearchFilterService _filterService = Get.find<SearchFilterService>();
  final SourceManager _sourceManager = Get.find<SourceManager>();

  bool get _isMatchFailed =>
      _errorMsg == '未找到相关条目' || _errorMsg == '未找到电影或电视剧条目';

  @override
  void initState() {
    super.initState();
    _fetchTmdbData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchTmdbData() async {
    final token = tmdbCtrl.accessToken.value;
    if (token.isEmpty) {
      setState(() {
        _errorMsg = '请先配置 TMDB Access Token';
        _isLoading = false;
      });
      return;
    }

    final apiProxy = tmdbCtrl.apiProxy.value;

    try {
      int tmdbId;
      String? mediaType;

      // ===== 优先使用传入的 tmdbId =====
      if (widget.tmdbId != null && widget.tmdbId! > 0) {
        tmdbId = widget.tmdbId!;
        mediaType = widget.mediaType;
        
        // 如果未指定 mediaType，通过搜索确定类型
        if (mediaType == null) {
          final searchUrl = '$apiProxy/3/search/multi'
              '?query=${Uri.encodeComponent(widget.videoItem.vodName)}'
              '&include_adult=false'
              '&language=zh-CN';
          final searchResp = await _dio.get(
            searchUrl,
            options: Options(
              headers: {
                'Authorization': 'Bearer $token',
                'Accept': 'application/json',
              },
            ),
          );
          if (searchResp.statusCode == 200) {
            final results = searchResp.data['results'] as List?;
            if (results != null && results.isNotEmpty) {
              for (final item in results) {
                final mt = item['media_type'] as String?;
                if (mt == 'movie' || mt == 'tv') {
                  mediaType = mt;
                  break;
                }
              }
            }
          }
          if (mediaType == null) {
            setState(() {
              _errorMsg = '无法确定媒体类型';
              _isLoading = false;
            });
            return;
          }
        }
      } else {
        // ===== 没有 tmdbId，使用搜索 =====
        final searchUrl = '$apiProxy/3/search/multi'
            '?query=${Uri.encodeComponent(widget.videoItem.vodName)}'
            '&include_adult=false'
            '&language=zh-CN';

        final searchResp = await _dio.get(
          searchUrl,
          options: Options(
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          ),
        );

        if (searchResp.statusCode != 200) {
          setState(() {
            _errorMsg = 'TMDB 搜索失败 (${searchResp.statusCode})';
            _isLoading = false;
          });
          return;
        }

        final results = searchResp.data['results'] as List?;
        if (results == null || results.isEmpty) {
          setState(() {
            _errorMsg = '未找到相关条目';
            _isLoading = false;
          });
          return;
        }

        Map<String, dynamic>? selected;
        for (final item in results) {
          final mt = item['media_type'] as String?;
          if (mt == 'movie' || mt == 'tv') {
            selected = item;
            mediaType = mt;
            break;
          }
        }

        if (selected == null) {
          setState(() {
            _errorMsg = '未找到电影或电视剧条目';
            _isLoading = false;
          });
          return;
        }

        tmdbId = selected['id'] as int;
      }

      _mediaType = mediaType;

      final detailUrl = _mediaType == 'movie'
          ? '$apiProxy/3/movie/$tmdbId'
            '?language=zh-CN'
            '&append_to_response=videos,credits,similar,external_ids'
          : '$apiProxy/3/tv/$tmdbId'
            '?language=zh-CN'
            '&append_to_response=videos,credits,similar,external_ids';

      final detailResp = await _dio.get(
        detailUrl,
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          },
        ),
      );

      if (detailResp.statusCode != 200) {
        setState(() {
          _errorMsg = '获取 TMDB 详情失败 (${detailResp.statusCode})';
          _isLoading = false;
        });
        return;
      }

      final data = detailResp.data as Map<String, dynamic>;
      _tmdbData = data;

      _title = data['title'] as String? ?? data['name'] as String?;
      _originalTitle = data['original_title'] as String? ?? data['original_name'] as String?;
      _overview = data['overview'] as String?;
      _tagline = data['tagline'] as String?;
      _posterPath = data['poster_path'] as String?;
      _backdropPath = data['backdrop_path'] as String?;
      _releaseDate = data['release_date'] as String? ?? data['first_air_date'] as String?;
      _voteAverage = (data['vote_average'] as num?)?.toDouble();
      _voteCount = data['vote_count'] as int?;
      _genres = data['genres'] as List?;
      _status = data['status'] as String?;
      _productionCompanies = data['production_companies'] as List?;
      _productionCountries = data['production_countries'] as List?;
      _spokenLanguages = data['spoken_languages'] as List?;

      if (_mediaType == 'movie') {
        _runtime = data['runtime'] as int?;
      }

      if (_mediaType == 'tv') {
        _seasons = data['seasons'] as List?;
        _numberOfSeasons = data['number_of_seasons'] as int?;
        _numberOfEpisodes = data['number_of_episodes'] as int?;
      }

      final videos = data['videos'] as Map?;
      if (videos != null) {
        _videos = videos['results'] as List?;
        if (_videos != null) {
          _videos = _videos!.where((v) {
            final site = v['site'] as String?;
            final type = v['type'] as String?;
            return site == 'YouTube' && (type == 'Trailer' || type == 'Teaser' || type == 'Featurette');
          }).toList();
        }
      }

      final credits = data['credits'] as Map?;
      if (credits != null) {
        _credits = credits['cast'] as List?;
        if (_credits != null && _credits!.length > 12) {
          _credits = _credits!.sublist(0, 12);
        }
      }

      final similar = data['similar'] as Map?;
      if (similar != null) {
        _similar = similar['results'] as List?;
        if (_similar != null && _similar!.length > 10) {
          _similar = _similar!.sublist(0, 10);
        }
      }

      _externalIds = data['external_ids'] != null
          ? Map<String, dynamic>.from(data['external_ids'] as Map)
          : null;

      setState(() {
        _isLoading = false;
      });
    } on DioException catch (e) {
      setState(() {
        _errorMsg = '网络请求失败: ${e.message}';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMsg = '加载失败: $e';
        _isLoading = false;
      });
    }
  }

  // ===== 播放 =====
  void _play() {
    if (widget.fromHome) {
      final pwd = widget.site['ext'] is Map
          ? (widget.site['ext'] as Map)['pwd']?.toString() ?? 'tinydust'
          : 'tinydust';

      Get.toNamed(
        AppPages.detail,
        arguments: {
          'vodId': widget.videoItem.vodId,
          'pwd': pwd,
          'site': widget.site,
        },
      );
    } else {
      _doSearch(_title ?? widget.videoItem.vodName);
    }
  }

  // ===== 跳过（匹配失败时直接播放） =====
  void _handleSkip() {
    final pwd = widget.site['ext'] is Map
        ? (widget.site['ext'] as Map)['pwd']?.toString() ?? 'tinydust'
        : 'tinydust';

    Get.toNamed(
      AppPages.detail,
      arguments: {
        'vodId': widget.videoItem.vodId,
        'pwd': pwd,
        'site': widget.site,
      },
    );
  }

  void _doSearch(String keyword) {
    final query = keyword.trim();
    if (query.isEmpty) {
      SmartDialog.showToast('请输入搜索关键词');
      return;
    }

    List<String> sourceKeys;
    final onlyDefault = _filterService.onlyDefaultSource.value;
    if (onlyDefault) {
      final currentKey = _sourceManager.currentSite.value?['key']?.toString() ?? '';
      sourceKeys = currentKey.isNotEmpty ? [currentKey] : [];
    } else {
      sourceKeys = _filterService.enabledSourceKeyList;
    }

    if (sourceKeys.isEmpty) {
      final currentKey = _sourceManager.currentSite.value?['key']?.toString() ?? '';
      if (currentKey.isNotEmpty) sourceKeys = [currentKey];
    }

    if (sourceKeys.isEmpty) {
      SmartDialog.showToast('没有可用的搜索源');
      return;
    }

    Get.toNamed(
      AppPages.searchResult,
      arguments: {
        'keyword': query,
        'sources': sourceKeys,
        'onlyDefault': onlyDefault,
      },
    );
  }

  void _navigateToPerson(int personId, String personName) {
    Get.to(
      () => TmdbPersonPage(
        personId: personId,
        personName: personName,
      ),
      routeName: AppPages.tmdbPerson,
    );
  }

  // ===== TMDB 搜索（供手动搜索使用） =====
  Future<List<dynamic>?> _performTmdbSearch(String query) async {
    final token = tmdbCtrl.accessToken.value;
    if (token.isEmpty) return null;

    final apiProxy = tmdbCtrl.apiProxy.value;
    try {
      final searchUrl = '$apiProxy/3/search/multi'
          '?query=${Uri.encodeComponent(query)}'
          '&include_adult=false'
          '&language=zh-CN';
      final response = await _dio.get(
        searchUrl,
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          },
        ),
      );
      if (response.statusCode == 200) {
        final results = response.data['results'] as List?;
        if (results != null && results.isNotEmpty) {
          return results.where((item) {
            final mediaType = item['media_type'] as String?;
            return mediaType == 'movie' || mediaType == 'tv';
          }).toList();
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  void _updateFromSearchResult(Map<String, dynamic> result) {
    setState(() {
      _title = result['title'] as String? ?? result['name'] as String?;
      _overview = result['overview'] as String?;
      _posterPath = result['poster_path'] as String?;
      _backdropPath = result['backdrop_path'] as String?;
      _releaseDate = result['release_date'] as String? ?? result['first_air_date'] as String?;
      _voteAverage = (result['vote_average'] as num?)?.toDouble();
      _voteCount = result['vote_count'] as int?;
      _mediaType = result['media_type'] as String?;
      _tmdbData = {'id': result['id']};
      _errorMsg = null;
      _isLoading = false;
    });
  }

  // ===== 手动搜索弹窗 =====
  void _showManualSearchBottomSheet() {
    final colorScheme = Theme.of(Get.context!).colorScheme;
    final isLoading = false.obs;
    final searchResults = <dynamic>[].obs;
    final errorMsg = ''.obs;
    final searchController = TextEditingController(text: widget.videoItem.vodName);

    Future<void> doSearch() async {
      final keyword = searchController.text.trim();
      if (keyword.isEmpty) return;
      isLoading.value = true;
      errorMsg.value = '';
      final results = await _performTmdbSearch(keyword);
      isLoading.value = false;
      if (results != null && results.isNotEmpty) {
        searchResults.value = results;
      } else {
        errorMsg.value = '未找到相关结果';
      }
    }

    showModalBottomSheet(
      context: Get.context!,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.75,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          margin: EdgeInsets.zero,
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
            ),
          ),
          child: Column(
            children: [
              // 顶部拖拽指示条
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.outline.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Text(
                    '手动搜索',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Icon(Icons.close, color: colorScheme.outline),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: searchController,
                      onSubmitted: (_) => doSearch(),
                      decoration: InputDecoration(
                        hintText: '输入关键词搜索...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        prefixIcon: Icon(Icons.search, color: colorScheme.outline),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: doSearch,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    child: const Text('搜索'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Obx(() {
                  if (isLoading.value) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (errorMsg.value.isNotEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline, size: 40, color: colorScheme.outline),
                          const SizedBox(height: 8),
                          Text(errorMsg.value, style: TextStyle(color: colorScheme.outline)),
                        ],
                      ),
                    );
                  }
                  if (searchResults.isEmpty) {
                    return Center(
                      child: Text(
                        '输入关键词搜索',
                        style: TextStyle(color: colorScheme.outline),
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: searchResults.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = searchResults[index] as Map<String, dynamic>;
                      return _buildSearchResultCard(item, colorScheme, searchResults, searchController);
                    },
                  );
                }),
              ),
            ],
          ),
        );
      },
    ).then((_) {
      searchController.dispose();
    });

    doSearch();
  }

  // ===== 搜索结果卡片 =====
  Widget _buildSearchResultCard(
    Map<String, dynamic> result,
    ColorScheme colorScheme,
    RxList<dynamic> searchResults,
    TextEditingController searchController,
  ) {
    final title = result['title'] as String? ?? result['name'] as String? ?? '未知';
    final poster = result['poster_path'] as String?;
    final releaseDate = result['release_date'] as String? ?? result['first_air_date'] as String? ?? '';
    final voteAverage = (result['vote_average'] as num?)?.toDouble();
    final mediaType = result['media_type'] as String? ?? 'movie';

    return GestureDetector(
      onTap: () {
        Navigator.pop(Get.context!);
        _updateFromSearchResult(result);
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withOpacity(0.4),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Container(
                width: 70,
                height: 100,
                color: colorScheme.surfaceContainerHighest,
                child: poster != null
                    ? Image.network(
                        _getImageUrl(poster, size: 'w185'),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                          mediaType == 'movie' ? Icons.movie : Icons.tv,
                          size: 30,
                          color: colorScheme.outline,
                        ),
                      )
                    : Icon(
                        mediaType == 'movie' ? Icons.movie : Icons.tv,
                        size: 30,
                        color: colorScheme.outline,
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (releaseDate.isNotEmpty)
                        Text(
                          releaseDate.split('-').first,
                          style: TextStyle(fontSize: 11, color: colorScheme.outline),
                        ),
                      if (releaseDate.isNotEmpty && voteAverage != null)
                        const SizedBox(width: 8),
                      if (voteAverage != null)
                        Row(
                          children: [
                            Icon(Icons.star, size: 14, color: Colors.amber),
                            const SizedBox(width: 2),
                            Text(
                              voteAverage.toStringAsFixed(1),
                              style: TextStyle(fontSize: 11, color: colorScheme.outline),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                mediaType == 'movie' ? '电影' : '剧集',
                style: TextStyle(fontSize: 10, color: colorScheme.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===== 工具方法 =====
  String _getImageUrl(String? path, {String size = 'w500'}) {
    if (path == null || path.isEmpty) return '';

    String base = tmdbCtrl.imageProxy.value.trim();
    if (!base.endsWith('/')) {
      base = '$base/';
    }

    String cleanSize = size.startsWith('/') ? size.substring(1) : size;
    if (!cleanSize.endsWith('/')) {
      cleanSize = '$cleanSize/';
    }

    String cleanPath = path.startsWith('/') ? path.substring(1) : path;

    return '$base$cleanSize$cleanPath';
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      final parts = dateStr.split('-');
      if (parts.length >= 3) return '${parts[0]}年${parts[1]}月${parts[2]}日';
      return dateStr;
    } catch (_) {
      return dateStr;
    }
  }

  String _formatDuration(int? minutes) {
    if (minutes == null || minutes == 0) return '';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours > 0 && mins > 0) return '${hours}h ${mins}min';
    if (hours > 0) return '${hours}h';
    return '${mins}min';
  }

  Color _getVoteColor(double? vote) {
    if (vote == null) return Colors.grey;
    if (vote >= 7.0) return Colors.green;
    if (vote >= 5.0) return Colors.orange;
    return Colors.red;
  }

  void _openImdb() async {
    if (_externalIds == null) return;
    final imdbId = _externalIds!['imdb_id'] as String?;
    if (imdbId == null || imdbId.isEmpty) {
      SmartDialog.showToast('未找到 IMDB 链接');
      return;
    }
    final url = 'https://www.imdb.com/title/$imdbId/';
    try {
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } else {
        SmartDialog.showToast('无法打开 IMDB 链接');
      }
    } catch (e) {
      SmartDialog.showToast('打开失败: $e');
    }
  }

  /// 从相似推荐卡片跳转到新的 TMDB 详情页
  void _navigateToTmdbDetail(Map<String, dynamic> item) {
    final title = item['title'] as String? ?? item['name'] as String? ?? '';
    final tmdbId = item['id'] as int?;
    final posterPath = item['poster_path'] as String?;
    final mediaType = item['media_type'] as String? ?? 'movie';
    
    if (tmdbId == null) {
      SmartDialog.showToast('无法获取影片信息');
      return;
    }

    final site = _sourceManager.currentSite.value ?? {};

    final videoItem = VideoItem(
      vodId: 'tmdb_$tmdbId',
      vodName: title,
      vodPic: posterPath != null ? _getImageUrl(posterPath, size: 'w342') : '',
      vodRemarks: '',
      vodActor: '',
      typeName: '',
      vodTag: '',
    );

    // 与演员页面跳转方式保持一致：只传 Widget，不传 routeName
    Get.to(
      () => TmdbDetailPage(
        videoItem: videoItem,
        site: site,
        fromHome: false,
        tmdbId: tmdbId,
        mediaType: mediaType,
      ),
    );
  }

  // ===== 构建错误视图（区分匹配失败和普通错误） =====
  Widget _buildErrorView(ColorScheme colorScheme) {
    if (_isMatchFailed) {
      return _buildMatchFailView(colorScheme);
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: colorScheme.error),
              const SizedBox(height: 16),
              Text(
                _errorMsg!,
                style: TextStyle(color: colorScheme.outline, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _fetchTmdbData,
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: colorScheme.primary, width: 1.2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text('重试', style: TextStyle(color: colorScheme.primary)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Get.back(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.surfaceContainerHighest,
                        foregroundColor: colorScheme.onSurface,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('返回'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===== 匹配失败视图 =====
  Widget _buildMatchFailView(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search_off, size: 48, color: colorScheme.error),
              const SizedBox(height: 16),
              Text(
                '未找到匹配',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '未找到与“${widget.videoItem.vodName}”匹配的TMDB条目',
                style: TextStyle(color: colorScheme.outline, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _handleSkip,
                      icon: Icon(Icons.skip_next, color: colorScheme.primary, size: 20),
                      label: Text('跳过', style: TextStyle(color: colorScheme.primary)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: colorScheme.primary, width: 1.2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _showManualSearchBottomSheet,
                      icon: const Icon(Icons.search, size: 20),
                      label: const Text('手动搜索'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Get.back(),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: colorScheme.outline.withOpacity(0.3)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text('返回', style: TextStyle(color: colorScheme.onSurface)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===== build =====
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      extendBodyBehindAppBar: true,
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: colorScheme.primary))
          : _errorMsg != null
              ? _buildErrorView(colorScheme)
              : _buildContent(context),
    );
  }

  // ===== 内容构建 =====
  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final backdropUrl = _getImageUrl(_backdropPath, size: 'original');

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverAppBar(
          expandedHeight: 300,
          pinned: true,
          stretch: true,
          backgroundColor: Colors.transparent,
          flexibleSpace: FlexibleSpaceBar(
            stretchModes: const [StretchMode.zoomBackground],
            background: Stack(
              fit: StackFit.expand,
              children: [
                backdropUrl.isNotEmpty
                    ? Image.network(
                        backdropUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: colorScheme.surfaceContainerHighest,
                          child: Icon(Icons.image_not_supported, size: 60, color: colorScheme.outline),
                        ),
                      )
                    : Container(
                        color: colorScheme.surfaceContainerHighest,
                        child: Icon(Icons.image_not_supported, size: 60, color: colorScheme.outline),
                      ),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.transparent,
                        colorScheme.surface.withOpacity(0.8),
                        colorScheme.surface,
                      ],
                      stops: const [0.0, 0.4, 0.7, 1.0],
                    ),
                  ),
                ),
              ],
            ),
          ),
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new, color: Colors.white, shadows: const [
              Shadow(blurRadius: 4, color: Colors.black26),
            ]),
            onPressed: () => Get.back(),
          ),
          actions: [
            PopupMenuButton<String>(
              icon: Icon(
                Icons.more_vert,
                color: Colors.white,
                size: 28,
                shadows: const [
                  Shadow(blurRadius: 4, color: Colors.black26),
                ],
              ),
              color: Theme.of(context).colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              onSelected: (value) {
                if (value == 'imdb') {
                  _openImdb();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem<String>(
                  value: 'imdb',
                  child: Row(
                    children: [
                      Icon(
                        Icons.open_in_new,
                        size: 18,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '在 IMDB 查看',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),

        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 110,
                        height: 165,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: colorScheme.outline.withOpacity(0.1),
                            width: 1,
                          ),
                        ),
                        child: _posterPath != null
                            ? Image.network(
                                _getImageUrl(_posterPath, size: 'w342'),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Icon(
                                  Icons.image_not_supported,
                                  size: 40,
                                  color: colorScheme.outline,
                                ),
                              )
                            : Icon(Icons.image_not_supported, size: 40, color: colorScheme.outline),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _title ?? '无标题',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (_originalTitle != null && _originalTitle != _title)
                            Text(
                              _originalTitle!,
                              style: TextStyle(
                                fontSize: 13,
                                color: colorScheme.outline,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              if (_releaseDate != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primaryContainer.withOpacity(0.3),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    _releaseDate!.split('-').first,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              if (_mediaType == 'movie' && _runtime != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primaryContainer.withOpacity(0.3),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    _formatDuration(_runtime),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              if (_mediaType == 'tv' && _numberOfSeasons != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primaryContainer.withOpacity(0.3),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '$_numberOfSeasons 季',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              if (_genres != null && _genres!.isNotEmpty)
                                ..._genres!.take(2).map((g) => Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primaryContainer.withOpacity(0.3),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    g['name'] as String? ?? '',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                )),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (_voteAverage != null) ...[
                            Row(
                              children: [
                                SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      SizedBox(
                                        width: 44,
                                        height: 44,
                                        child: CircularProgressIndicator(
                                          value: (_voteAverage! / 10).clamp(0.0, 1.0),
                                          backgroundColor: colorScheme.outline.withOpacity(0.15),
                                          color: _getVoteColor(_voteAverage),
                                          strokeWidth: 3.5,
                                        ),
                                      ),
                                      Text(
                                        '${(_voteAverage! * 10).round()}%',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: _getVoteColor(_voteAverage),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${_voteAverage!.toStringAsFixed(1)} / 10',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                    if (_voteCount != null)
                                      Text(
                                        '${_voteCount!} 人评价',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: colorScheme.outline,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                          ],
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _play,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: colorScheme.primary,
                                foregroundColor: colorScheme.onPrimary,
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              icon: Icon(Icons.play_arrow, size: 18, color: colorScheme.onPrimary),
                              label: Text(
                                widget.fromHome ? '播放' : '搜索',
                                style: TextStyle(fontSize: 14, color: colorScheme.onPrimary),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                if (_tagline != null && _tagline!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      '“${_tagline!}”',
                      style: TextStyle(
                        fontSize: 14,
                        fontStyle: FontStyle.italic,
                        color: colorScheme.outline,
                      ),
                    ),
                  ),

                if (_overview != null && _overview!.isNotEmpty) ...[
                  Text(
                    '简介',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _overview!,
                    style: TextStyle(
                      fontSize: 14,
                      color: colorScheme.onSurfaceVariant,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                _buildDetailInfoCard(context),
                const SizedBox(height: 16),

                if (_credits != null && _credits!.isNotEmpty) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '主演',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        '${_credits!.length} 人',
                        style: TextStyle(fontSize: 12, color: colorScheme.outline),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 130,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _credits!.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        final actor = _credits![index];
                        final name = actor['name'] as String? ?? '';
                        final character = actor['character'] as String? ?? '';
                        final profilePath = actor['profile_path'] as String?;
                        final personId = actor['id'] as int?;

                        return GestureDetector(
                          onTap: () {
                            if (personId != null) {
                              _navigateToPerson(personId, name);
                            } else {
                              SmartDialog.showToast('无法获取演员信息');
                            }
                          },
                          child: SizedBox(
                            width: 85,
                            child: Column(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(45),
                                  child: Container(
                                    width: 70,
                                    height: 70,
                                    color: colorScheme.surfaceContainerHighest,
                                    child: profilePath != null
                                        ? Image.network(
                                            _getImageUrl(profilePath, size: 'w185'),
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => Icon(
                                              Icons.person,
                                              size: 30,
                                              color: colorScheme.outline,
                                            ),
                                          )
                                        : Icon(Icons.person, size: 30, color: colorScheme.outline),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  name,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: colorScheme.onSurface,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  character,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: colorScheme.outline,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                if (_mediaType == 'tv' && _seasons != null && _seasons!.isNotEmpty) ...[
                  Text(
                    '剧集',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ..._seasons!.map((season) {
                    final seasonNumber = season['season_number'] as int?;
                    final name = season['name'] as String? ?? '第 ${seasonNumber ?? 0} 季';
                    final episodeCount = season['episode_count'] as int?;
                    final posterPath = season['poster_path'] as String?;
                    final airDate = season['air_date'] as String?;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              width: 40,
                              height: 56,
                              color: colorScheme.surfaceContainerHighest,
                              child: posterPath != null && posterPath.isNotEmpty
                                  ? Image.network(
                                      _getImageUrl(posterPath, size: 'w92'),
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Icon(
                                        Icons.tv,
                                        size: 20,
                                        color: colorScheme.outline,
                                      ),
                                    )
                                  : Icon(Icons.tv, size: 20, color: colorScheme.outline),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                                Row(
                                  children: [
                                    if (episodeCount != null)
                                      Text(
                                        '$episodeCount 集',
                                        style: TextStyle(fontSize: 11, color: colorScheme.outline),
                                      ),
                                    if (episodeCount != null && airDate != null)
                                      Text(
                                        ' · ',
                                        style: TextStyle(fontSize: 11, color: colorScheme.outline),
                                      ),
                                    if (airDate != null)
                                      Text(
                                        _formatDate(airDate),
                                        style: TextStyle(fontSize: 11, color: colorScheme.outline),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (seasonNumber == 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '特别篇',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.green,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                  const SizedBox(height: 16),
                ],

                // 相似推荐
                if (_similar != null && _similar!.isNotEmpty) ...[
                  Text(
                    '相似推荐',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 200,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _similar!.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        final item = _similar![index];
                        final title = item['title'] as String? ?? item['name'] as String? ?? '';
                        final poster = item['poster_path'] as String?;
                        final releaseDate = item['release_date'] as String? ?? item['first_air_date'] as String?;

                        return GestureDetector(
                          onTap: () {
                            if (item.isNotEmpty) {
                              _navigateToTmdbDetail(item);
                            } else {
                              SmartDialog.showToast('无法获取影片信息');
                            }
                          },
                          child: SizedBox(
                            width: 120,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                    width: 120,
                                    height: 160,
                                    color: colorScheme.surfaceContainerHighest,
                                    child: poster != null && poster.isNotEmpty
                                        ? Image.network(
                                            _getImageUrl(poster, size: 'w185'),
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => Icon(
                                              Icons.movie,
                                              size: 30,
                                              color: colorScheme.outline,
                                            ),
                                          )
                                        : Icon(Icons.movie, size: 30, color: colorScheme.outline),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  title,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: colorScheme.onSurface,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (releaseDate != null && releaseDate.isNotEmpty)
                                  Text(
                                    releaseDate.split('-').first,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: colorScheme.outline,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ===== 详情信息卡片 =====
  Widget _buildDetailInfoCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final items = <MapEntry<String, String>>[];

    if (_status != null && _status!.isNotEmpty) {
      String statusLabel = _status!;
      if (statusLabel == 'Released') statusLabel = '已上映';
      else if (statusLabel == 'Post Production') statusLabel = '后期制作';
      else if (statusLabel == 'Production') statusLabel = '制作中';
      else if (statusLabel == 'Canceled') statusLabel = '已取消';
      items.add(MapEntry('状态', statusLabel));
    }

    if (_genres != null && _genres!.isNotEmpty) {
      final genreNames = _genres!.map((g) => g['name'] as String).join(' · ');
      items.add(MapEntry('类型', genreNames));
    }

    if (_mediaType == 'movie' && _runtime != null) {
      items.add(MapEntry('时长', _formatDuration(_runtime)));
    }

    if (_productionCompanies != null && _productionCompanies!.isNotEmpty) {
      final names = _productionCompanies!.take(3).map((c) => c['name'] as String).join(' · ');
      items.add(MapEntry('制作公司', names));
    }

    if (_productionCountries != null && _productionCountries!.isNotEmpty) {
      final names = _productionCountries!.map((c) => c['name'] as String).join(' · ');
      items.add(MapEntry('国家', names));
    }

    if (_spokenLanguages != null && _spokenLanguages!.isNotEmpty) {
      final names = _spokenLanguages!.take(3).map((l) => l['english_name'] as String).join(' · ');
      items.add(MapEntry('语言', names));
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          children: items.map((entry) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 70,
                    child: Text(
                      entry.key,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.outline,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      entry.value,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
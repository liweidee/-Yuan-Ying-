// lib/modules/tmdb/views/tmdb_person_page.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:dio/dio.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/modules/setting/controllers/tmdb_config_controller.dart';
import 'package:yuanying/core/routes/app_pages.dart';
import 'package:yuanying/services/search_filter_service.dart';
import 'package:yuanying/t4/services/source_manager.dart';
import 'package:yuanying/t4/models/video_item.dart';
import 'package:yuanying/modules/tmdb/views/tmdb_detail_page.dart';
import 'package:yuanying/common/widgets/image_viewer/gallery_viewer.dart';
import 'package:yuanying/common/widgets/image_viewer/hero.dart';

/// TMDB 演员详情页（优化版）
class TmdbPersonPage extends StatefulWidget {
  final int personId;
  final String personName;

  const TmdbPersonPage({
    super.key,
    required this.personId,
    required this.personName,
  });

  @override
  State<TmdbPersonPage> createState() => _TmdbPersonPageState();
}

class _TmdbPersonPageState extends State<TmdbPersonPage> {
  late final TmdbConfigController tmdbCtrl = Get.isRegistered<TmdbConfigController>()
      ? Get.find<TmdbConfigController>()
      : Get.put(TmdbConfigController());

  final Dio _dio = Dio();
  final SearchFilterService _filterService = Get.find<SearchFilterService>();
  final SourceManager _sourceManager = Get.find<SourceManager>();

  bool _isLoading = true;
  String? _errorMsg;

  // ===== 演员信息 =====
  String? _name;
  String? _biography;
  String? _profilePath;
  String? _birthday;
  String? _deathday;
  String? _placeOfBirth;
  double? _popularity;
  int? _gender;
  List<dynamic>? _alsoKnownAs;
  List<dynamic>? _combinedCredits;
  List<String>? _profileImages;

  // ===== UI状态 =====
  final ScrollController _scrollController = ScrollController();
  bool _biographyExpanded = false;
  String _workFilter = '全部';

  List<dynamic> get _filteredCredits {
    if (_combinedCredits == null) return [];
    if (_workFilter == '全部') return _combinedCredits!;
    final type = _workFilter == '电影' ? 'movie' : 'tv';
    return _combinedCredits!.where((item) => item['media_type'] == type).toList();
  }

  @override
  void initState() {
    super.initState();
    _fetchPersonData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchPersonData() async {
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
      // 1. 获取演员详情
      final personUrl = '$apiProxy/3/person/${widget.personId}?language=zh-CN';
      final personResp = await _dio.get(
        personUrl,
        options: Options(headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        }),
      );
      if (personResp.statusCode != 200) {
        setState(() {
          _errorMsg = '获取演员信息失败 (${personResp.statusCode})';
          _isLoading = false;
        });
        return;
      }
      final personData = personResp.data as Map<String, dynamic>;

      // 2. 获取作品列表
      final creditsUrl = '$apiProxy/3/person/${widget.personId}/combined_credits?language=zh-CN';
      final creditsResp = await _dio.get(
        creditsUrl,
        options: Options(headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        }),
      );
      if (creditsResp.statusCode != 200) {
        setState(() {
          _errorMsg = '获取演员作品失败 (${creditsResp.statusCode})';
          _isLoading = false;
        });
        return;
      }
      final creditsData = creditsResp.data as Map<String, dynamic>;

      // 3. 获取演员照片
      final imagesUrl = '$apiProxy/3/person/${widget.personId}/images';
      final imagesResp = await _dio.get(
        imagesUrl,
        options: Options(headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        }),
      );
      List<String>? profileImages;
      if (imagesResp.statusCode == 200 && imagesResp.data['profiles'] != null) {
        final profiles = imagesResp.data['profiles'] as List;
        profileImages = profiles
            .map((p) => p['file_path'] as String)
            .where((path) => path.isNotEmpty)
            .toList();
        if (profileImages.length > 10) profileImages = profileImages.sublist(0, 10);
      }

      // 解析基本信息
      _name = personData['name'] as String? ?? widget.personName;
      _biography = personData['biography'] as String?;
      _profilePath = personData['profile_path'] as String?;
      _birthday = personData['birthday'] as String?;
      _deathday = personData['deathday'] as String?;
      _placeOfBirth = personData['place_of_birth'] as String?;
      _popularity = (personData['popularity'] as num?)?.toDouble();
      _gender = personData['gender'] as int?;
      _alsoKnownAs = personData['also_known_as'] as List?;
      _profileImages = profileImages;

      // 解析作品
      final cast = creditsData['cast'] as List? ?? [];
      _combinedCredits = cast.where((item) {
        final title = item['title'] as String? ?? item['name'] as String?;
        final releaseDate = item['release_date'] as String? ?? item['first_air_date'] as String?;
        return title != null && title.isNotEmpty && releaseDate != null && releaseDate.isNotEmpty;
      }).toList();
      _combinedCredits!.sort((a, b) {
        final dateA = a['release_date'] as String? ?? a['first_air_date'] as String? ?? '';
        final dateB = b['release_date'] as String? ?? b['first_air_date'] as String? ?? '';
        return dateB.compareTo(dateA);
      });

      setState(() => _isLoading = false);
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

  // ===== 工具方法 =====
  String _getImageUrl(String? path, {String size = 'w500'}) {
    if (path == null || path.isEmpty) return '';
    String base = tmdbCtrl.imageProxy.value.trim();
    if (!base.endsWith('/')) base = '$base/';
    String cleanSize = size.startsWith('/') ? size.substring(1) : size;
    if (!cleanSize.endsWith('/')) cleanSize = '$cleanSize/';
    String cleanPath = path.startsWith('/') ? path.substring(1) : path;
    return '$base$cleanSize$cleanPath';
  }

  // ===== 修复1: 正确的 try-catch 语法 =====
  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      final parts = dateStr.split('-');
      if (parts.length >= 3) return '${parts[0]}年${parts[1]}月${parts[2]}日';
      return dateStr;
    } catch (_) {
      // catch 块必须有 {} 体
      return dateStr;
    }
  }

  String _getGenderText(int? gender) {
    if (gender == null) return '未知';
    switch (gender) {
      case 1: return '女';
      case 2: return '男';
      default: return '未知';
    }
  }

  // ===== 相册大图查看（复用详情页组件） =====
  void _showFullImage(String imageUrl) {
    showImageViewer(
      context,
      imageUrl,
      tag: imageUrl,
    );
  }

  // ===== 搜索和跳转 =====
  void _searchWork(String title) {
    final query = title.trim();
    if (query.isEmpty) return;
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

  void _navigateToTmdbDetail(Map<String, dynamic> item) {
    final title = item['title'] as String? ?? item['name'] as String? ?? '';
    final tmdbId = item['id'] as int?;
    final posterPath = item['poster_path'] as String?;
    final mediaType = item['media_type'] as String? ?? 'movie';

    if (tmdbId == null) {
      SmartDialog.showToast('无法获取影片信息');
      return;
    }

    final videoItem = VideoItem(
      vodId: 'tmdb_$tmdbId',
      vodName: title,
      vodPic: posterPath != null ? _getImageUrl(posterPath, size: 'w342') : '',
      vodRemarks: '',
      vodActor: '',
      typeName: '',
      vodTag: '',
    );
    final site = _sourceManager.currentSite.value ?? {};
    Get.to(
      () => TmdbDetailPage(
        videoItem: videoItem,
        site: site,
        fromHome: false,
        tmdbId: tmdbId,
        mediaType: mediaType,
      ),
      routeName: AppPages.tmdbDetail,
    );
  }

  // ===== 构建UI =====
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(
          _name ?? '演员详情',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: colorScheme.onSurface),
          onPressed: () => Get.back(),
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: colorScheme.primary))
          : _errorMsg != null
              ? _buildErrorView(colorScheme)
              : _buildContent(context),
    );
  }

  Widget _buildErrorView(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: colorScheme.error),
            const SizedBox(height: 16),
            Text(_errorMsg!, style: TextStyle(color: colorScheme.outline, fontSize: 14)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchPersonData,
              style: ElevatedButton.styleFrom(backgroundColor: colorScheme.primary),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        // ============================================================
        // 1. 演员信息头部
        // ============================================================
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 110,
                    height: 160,
                    color: colorScheme.surfaceContainerHighest,
                    child: _profilePath != null
                        ? Image.network(
                            _getImageUrl(_profilePath, size: 'w342'),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(Icons.person, size: 50, color: colorScheme.outline),
                          )
                        : Icon(Icons.person, size: 50, color: colorScheme.outline),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _name ?? widget.personName,
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                      ),
                      const SizedBox(height: 4),
                      if (_gender != null)
                        Text('性别: ${_getGenderText(_gender)}', style: TextStyle(color: colorScheme.outline, fontSize: 13)),
                      if (_birthday != null)
                        Text(
                          '出生: ${_formatDate(_birthday)}${_deathday != null ? ' - ${_formatDate(_deathday)}' : ''}',
                          style: TextStyle(color: colorScheme.outline, fontSize: 13),
                        ),
                      if (_placeOfBirth != null && _placeOfBirth!.isNotEmpty)
                        Text('出生地: $_placeOfBirth', style: TextStyle(color: colorScheme.outline, fontSize: 13)),
                      if (_alsoKnownAs != null && _alsoKnownAs!.isNotEmpty)
                        Text(
                          '别名: ${(_alsoKnownAs! as List).take(3).join(' · ')}${_alsoKnownAs!.length > 3 ? ' ...' : ''}',
                          style: TextStyle(color: colorScheme.outline, fontSize: 12),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (_popularity != null)
                        Text('热度: ${_popularity!.toStringAsFixed(1)}', style: TextStyle(color: colorScheme.outline, fontSize: 13)),
                      if (_combinedCredits != null)
                        Text('参演作品: ${_combinedCredits!.length} 部', style: TextStyle(color: colorScheme.outline, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // ============================================================
        // 2. 个人简介（展开/收起）
        // ============================================================
        if (_biography != null && _biography!.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '个人简介',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
                  ),
                  const SizedBox(height: 6),
                  StatefulBuilder(
                    builder: (context, setState) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _biography!,
                            maxLines: _biographyExpanded ? null : 3,
                            overflow: _biographyExpanded ? null : TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant, height: 1.6),
                          ),
                          if (_biography!.length > 120)
                            GestureDetector(
                              onTap: () => setState(() => _biographyExpanded = !_biographyExpanded),
                              child: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  _biographyExpanded ? '收起' : '展开全部',
                                  style: TextStyle(fontSize: 13, color: colorScheme.primary, fontWeight: FontWeight.w500),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),

        // ============================================================
        // 3. 相册（使用详情页图片查看器）
        // ============================================================
        if (_profileImages != null && _profileImages!.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '相册',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 120,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _profileImages!.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final imageUrl = _getImageUrl(_profileImages![index], size: 'w185');
                        return GestureDetector(
                          onTap: () => _showFullImage(imageUrl),
                          child: Hero(
                            tag: imageUrl,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                width: 80,
                                height: 120,
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Image.network(
                                  imageUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 30),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),

        // ============================================================
        // 4. 出演作品（筛选 + 左图右文卡片）
        // ============================================================
        if (_combinedCredits != null && _combinedCredits!.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '出演作品',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
                      ),
                      const Spacer(),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: '全部', label: Text('全部')),
                          ButtonSegment(value: '电影', label: Text('电影')),
                          ButtonSegment(value: '剧集', label: Text('剧集')),
                        ],
                        selected: {_workFilter},
                        onSelectionChanged: (Set<String> newSelection) {
                          setState(() => _workFilter = newSelection.first);
                        },
                        style: ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          minimumSize: WidgetStateProperty.all(const Size(50, 28)),
                          padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 6)),
                          textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _filteredCredits.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = _filteredCredits[index];
                      final title = item['title'] as String? ?? item['name'] as String? ?? '未知';
                      final poster = item['poster_path'] as String?;
                      final releaseDate = item['release_date'] as String? ?? item['first_air_date'] as String? ?? '';
                      final voteAverage = (item['vote_average'] as num?)?.toDouble();
                      final character = item['character'] as String?;
                      final mediaType = item['media_type'] as String? ?? 'movie';

                      return GestureDetector(
                        onTap: () => _navigateToTmdbDetail(item),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 海报
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  width: 70,
                                  height: 100,
                                  color: colorScheme.surfaceContainerHighest,
                                  child: poster != null && poster.isNotEmpty
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
                              // 内容区
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
                                    if (character != null && character.isNotEmpty)
                                      Text(
                                        '饰演: $character',
                                        style: TextStyle(fontSize: 12, color: colorScheme.outline),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    const SizedBox(height: 4),
                                    // 年份（带边框小圆角）
                                    if (releaseDate.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          border: Border.all(color: colorScheme.outline.withOpacity(0.4), width: 0.8),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          releaseDate.split('-').first,
                                          style: TextStyle(fontSize: 11, color: colorScheme.outline),
                                        ),
                                      ),
                                    const SizedBox(height: 4),
                                    // 评分（换行显示）
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
                              ),
                              // 类型标签
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
                    },
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
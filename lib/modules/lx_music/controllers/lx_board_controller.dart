import 'package:get/get.dart';

import 'package:yuanying/modules/lx_music/models/lx_board_model.dart';
import 'package:yuanying/modules/lx_music/models/lx_music_model.dart';
import 'package:yuanying/modules/lx_music/services/lx_board_service.dart';
import 'package:yuanying/modules/lx_music/utils/lx_logger.dart';

/// 洛雪音乐榜单控制器
///
/// 无缓存版本：
/// - 每次切榜单/切源都重新请求
/// - 便于排查接口问题
class LxBoardController extends GetxController {
  final LxBoardService _service = LxBoardService.instance;

  // ==================== 状态 ====================

  /// 当前源
  final RxString source = 'kw'.obs;

  /// 当前源下的榜单分类列表
  final RxList<LxBoardInfo> boards = <LxBoardInfo>[].obs;

  /// 当前选中的榜单
  final Rxn<LxBoardInfo> currentBoard = Rxn<LxBoardInfo>();

  /// 当前榜单的歌曲列表
  final RxList<LxMusic> songs = <LxMusic>[].obs;

  /// 加载状态（首次加载/切榜单）
  final RxBool isLoading = false.obs;

  /// 加载更多状态
  final RxBool isLoadingMore = false.obs;

  /// 错误信息（空字符串 = 无错误）
  final RxString error = ''.obs;

  /// 当前页码
  final RxInt page = 1.obs;

  /// 每页条数（从源响应拿）
  final RxInt limit = 30.obs;

  /// 总条数
  final RxInt total = 0.obs;

  /// 是否有更多
  bool get hasMore => page.value * limit.value < total.value;

  // ==================== 生命周期 ====================

  @override
  void onInit() {
    super.onInit();
    // 首次初始化：默认源（kw）的榜单列表 + 第一个榜单
    Future.microtask(() => _initDefault());
  }

  Future<void> _initDefault() async {
    _loadBoardsForSource('kw');
    final firstBoard = boards.isNotEmpty ? boards.first : null;
    if (firstBoard != null) {
      await selectBoard(firstBoard);
    }
  }

  // ==================== 源切换 ====================

  /// 切换源（自动选中该源的第一个榜单）
  Future<void> setSource(String newSource) async {
    if (source.value == newSource) return;
    if (!LxBoardService.supportedSources.contains(newSource)) return;

    source.value = newSource;
    _loadBoardsForSource(newSource);

    final firstBoard = boards.isNotEmpty ? boards.first : null;
    if (firstBoard != null) {
      await selectBoard(firstBoard);
    }
  }

  void _loadBoardsForSource(String src) {
    boards.value = _service.getBoards(src);
  }

  // ==================== 榜单切换 ====================

  /// 选中某个榜单（加载第一页）
  Future<void> selectBoard(LxBoardInfo board) async {
    currentBoard.value = board;

    // 重置状态
    songs.clear();
    page.value = 1;
    total.value = 0;
    error.value = '';
    isLoading.value = true;

    // 拉第一页（无缓存，每次都请求）
    try {
      LxLogger.info('请求榜单: ${board.source}/${board.bangid}/${board.name}');
      final detail = await _service.getBoardSongs(
        source: board.source,
        bangid: board.bangid,
        page: 1,
      );

      if (detail.list.isEmpty) {
        error.value = '榜单为空或加载失败';
        LxLogger.warn('榜单为空: ${board.name}');
      } else {
        _applyDetail(detail);
        LxLogger.info('榜单加载成功: ${board.name} (${detail.list.length} 首)');
      }
    } catch (e) {
      error.value = '加载失败: $e';
      LxLogger.error('榜单加载异常: $e');
    } finally {
      isLoading.value = false;
    }
  }

  void _applyDetail(LxBoardDetail detail) {
    songs.value = detail.list;
    page.value = detail.page;
    limit.value = detail.limit;
    total.value = detail.total;
  }

  // ==================== 加载更多 ====================

  Future<void> loadMore() async {
    if (isLoadingMore.value || isLoading.value || !hasMore) return;

    final board = currentBoard.value;
    if (board == null) return;

    isLoadingMore.value = true;
    final nextPage = page.value + 1;

    try {
      LxLogger.info('加载更多: ${board.name} 第 $nextPage 页');
      final detail = await _service.getBoardSongs(
        source: board.source,
        bangid: board.bangid,
        page: nextPage,
      );

      if (detail.list.isEmpty) {
        total.value = songs.length;
        return;
      }

      songs.addAll(detail.list);
      page.value = detail.page;
      limit.value = detail.limit;
      total.value = detail.total;
      LxLogger.info('加载更多成功: ${detail.list.length} 首');
    } catch (e) {
      LxLogger.error('加载更多失败: $e');
    } finally {
      isLoadingMore.value = false;
    }
  }

  // ==================== 刷新 ====================

  Future<void> refresh() async {
    final board = currentBoard.value;
    if (board == null) return;
    await selectBoard(board);
  }

  // ==================== 便捷 getter ====================

  String get sourceDisplayName =>
      LxBoardService.sourceNames[source.value] ?? source.value;

  String get currentBoardName => currentBoard.value?.name ?? '未选择';

  List<String> get supportedSources => LxBoardService.supportedSources;

  Map<String, String> get sourceNames => LxBoardService.sourceNames;
}
// lib/modules/manga/controllers/manga_detail_controller.dart
import 'package:get/get.dart';
import 'package:yuanying/t4/models/video_detail.dart';
import 'package:yuanying/t4/services/source_manager.dart';
import 'package:yuanying/t4/services/i_spider_service.dart';

class MangaDetailController extends GetxController {
  final RxBool isLoading = true.obs;
  final RxString error = ''.obs;
  final Rxn<VideoDetail> detail = Rxn<VideoDetail>();
  final RxList<Episode> episodes = <Episode>[].obs;
  final RxString sourceName = ''.obs;

  late String vodId;
  late String pwd;
  Map<String, dynamic>? site;

  void init(String vodId, String pwd, Map<String, dynamic>? site) {
    this.vodId = vodId;
    this.pwd = pwd;
    this.site = site;
    loadDetail();
  }

  Future<void> loadDetail() async {
    isLoading.value = true;
    error.value = '';
    try {
      final api = site != null
          ? Get.find<SourceManager>().createIndependentService(site!)
          : Get.find<SourceManager>().currentApiService;
      final result = await api.getDetail(vodId: vodId, pwd: pwd);
      if (result != null && result.playSources.isNotEmpty) {
        detail.value = result;
        episodes.value = result.playSources.first.episodes;
        sourceName.value = result.playSources.first.name;
      } else {
        error.value = '未获取到章节信息';
      }
    } catch (e) {
      error.value = '加载失败：$e';
    } finally {
      isLoading.value = false;
    }
  }

  void openReader(int index) {
    if (detail.value == null || episodes.isEmpty) return;
    Get.toNamed(
      '/mangaReader',
      arguments: {
        'vodId': vodId,
        'vodName': detail.value!.vodName,
        'vodPic': detail.value!.vodPic,
        'episodes': episodes.map((e) => {'name': e.name, 'url': e.url}).toList(),
        'initialChapter': index,
        'pwd': pwd,
        'site': site,
        'sourceName': sourceName.value,
      },
    );
  }
}
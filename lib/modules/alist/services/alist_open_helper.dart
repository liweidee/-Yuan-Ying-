import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:yuanying/common/widgets/image_viewer/gallery_viewer.dart';
import 'package:yuanying/core/routes/app_pages.dart';
import 'package:yuanying/t4/models/video_detail.dart';
import '../controllers/alist_server_controller.dart';
import '../models/alist_file_item.dart';
import '../services/alist_download_manager.dart';
import '../services/alist_file_utils.dart';
import '../widgets/alist_file_info_dialog.dart';

class AlistOpenHelper {
  AlistOpenHelper._();

  /// 根据文件类型打开
  static Future<void> openItem({
    required BuildContext context,
    required String name,
    required String path,
    String? sign,
    String? thumb,
    bool isDir = false,
  }) async {
    final type = AlistFileUtils.getFileType(isDir, name);
    switch (type) {
      case AlistFileType.folder:
        Get.toNamed(AppPages.alistFileList, arguments: {'path': path});
        break;
      case AlistFileType.video:
      case AlistFileType.audio:
        await _playSingle(name, path, sign);
        break;
      case AlistFileType.image:
        await _openImage(name, path, sign);
        break;
      default:
        AlistFileInfoDialog.show(
          context,
          name: name,
          path: path,
          sign: sign,
          isDir: isDir,
        );
        break;
    }
  }

  /// 播放单个媒体文件（构造单集播放列表）
  static Future<void> _playSingle(
    String name,
    String path,
    String? sign,
  ) async {
    final localPath = AlistDownloadManager.instance.findLocalPath(path);
    final url = localPath ?? await AlistFileUtils.makeFileLink(path, sign);
    if (url == null || url.isEmpty) {
      SmartDialog.showToast('无法获取播放链接');
      return;
    }

    final serverCtrl = Get.find<AlistServerController>();
    final server = serverCtrl.currentServer;
    final serverName = server?.name ?? 'AList';

    final videoDetail = VideoDetail(
      vodId: path,
      vodName: name,
      vodPic: '',
      vodContent: '',
      vodYear: '',
      vodActor: '',
      vodDirector: '',
      vodRemarks: '',
      typeName: '媒体',
      playSources: [
        PlaySource(
          name: serverName,
          episodes: [Episode(name: name, url: url)],
        ),
      ],
    );

    Get.toNamed(
      AppPages.detail,
      arguments: {
        'isPush': true,
        'directUrl': url,
        'directTitle': name,
        'videoDetail': videoDetail,
        'sourceName': serverName,
        'isDirectPushMode': true,
      },
    );
  }

  static Future<void> _openImage(
    String name,
    String path,
    String? sign,
  ) async {
    final url = await AlistFileUtils.makeFileLink(path, sign);
    if (url == null || url.isEmpty) return;
    Get.to(() => GalleryViewer(
          quality: 80,
          sources: [SourceModel(url: url)],
          initIndex: 0,
        ));
  }
}
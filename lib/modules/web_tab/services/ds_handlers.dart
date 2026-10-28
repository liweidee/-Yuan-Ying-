// lib/modules/web_tab/services/ds_handlers.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';

import 'package:yuanying/core/routes/app_pages.dart';
import 'package:yuanying/http/browser_ua.dart';
import 'package:yuanying/http/init.dart';
import 'package:yuanying/modules/main/controllers/main_controller.dart';
import 'package:yuanying/services/search_filter_service.dart';
import 'package:yuanying/t4/models/video_detail.dart';
import 'package:yuanying/t4/services/source_manager.dart';
import 'package:yuanying/utils/storage.dart';

class DsHandlers {
  final InAppWebViewController controller;
  final RxBool isFullscreen;

  final _boxCache = <String, Future<Box>>{};

  /// 嗅探到的视频回调（由 WebTabPage 注入）
  void Function(String url, String title)? _onSniffedVideoCb;

  /// 网盘链接列表回调（由 WebTabPage 注入）
  void Function(List<Map<String, dynamic>> links)? _onCloudLinksCb;

  DsHandlers(this.controller, {RxBool? isFullscreen})
      : isFullscreen = isFullscreen ?? false.obs;

  /// 由 WebTabPage 接线
  void setSniffedVideoCallback(
          void Function(String url, String title)? cb) =>
      _onSniffedVideoCb = cb;

  void setCloudLinksCallback(
          void Function(List<Map<String, dynamic>> links)? cb) =>
      _onCloudLinksCb = cb;

  Future<Map<String, dynamic>> dispatchRaw(List<dynamic> args) async {
    if (args.isEmpty || args[0] is! Map) {
      return {'ok': false, 'error': 'invalid payload'};
    }
    final payload = Map<String, dynamic>.from(args[0] as Map);
    final method = payload['method']?.toString() ?? '';
    final callArgs = payload['args'];
    try {
      final data = await _dispatch(method, callArgs);
      return {'ok': true, 'data': data};
    } catch (e) {
      debugPrint('[DsHandlers] $method 失败: $e');
      return {'ok': false, 'error': e.toString()};
    }
  }

  Future<dynamic> _dispatch(String method, dynamic args) async {
    final a = (args is List) ? args : <dynamic>[];
    switch (method) {
      case 'req':                return _req(a);
      case 'toast':              return _toast(a);
      case 'openVod':            return _openVod(a);
      case 'openLive':           return _openLive();
      case 'openKeep':           return _openKeep();
      case 'openSetting':        return _openSetting();
      case 'search':             return _search(a);
      case 'vod':                return _vod(a);
      case 'play':               return _play(a);
      case 'fullscreen':         return _fullscreen(a);
      case 'tab':                return _tab(a);
      case 'back':               return _back();
      case 'reload':             return _reload();
      case 'replay':             return _reload();
      case 'store.get':          return _storeGet(a);
      case 'store.set':          return _storeSet(a);
      case 'store.del':          return _storeDel(a);
      case 'device':             return _device();
      case 'site':               return _site();
      case 'config':             return _config();
      case 'history':            return _history();
      case 'viewport':           return _viewport();
      case 'extInfo':            return _extInfo();

      // ★ 嗅探 / 网盘推送
      case 'sniffedVideo':       return _onSniffedVideo(a);
      case 'showSniffedVideo':   return _onSniffedVideo(a);
      case 'reportCloudLinks':   return _onReportCloudLinks(a);
      case 'showCloudPush':      return _onShowCloudPush(a);
      case 'pan.play':           return _onPanPlay(a);

      case '__resolveDone':
        return true;
      default:
        throw Exception('unsupported method: $method');
    }
  }

  // ============================================================
  // 嗅探 / 网盘
  // ============================================================
  Future<bool> _onSniffedVideo(List a) async {
    if (a.isEmpty || a[0] is! Map) return false;
    final data = Map<String, dynamic>.from(a[0] as Map);
    final url = data['url']?.toString() ?? '';
    final title = data['title']?.toString() ?? '';
    if (url.isEmpty) return false;
    _onSniffedVideoCb?.call(url, title);
    return true;
  }

  Future<bool> _onReportCloudLinks(List a) async {
    if (a.isEmpty || a[0] is! List) return false;
    final links = (a[0] as List)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    if (links.isEmpty) return false;
    _onCloudLinksCb?.call(links);
    return true;
  }

  Future<bool> _onShowCloudPush(List a) async {
    if (a.isEmpty || a[0] is! Map) return false;
    _onCloudLinksCb?.call([Map<String, dynamic>.from(a[0] as Map)]);
    return true;
  }

  /// 网盘点击推送播放：构造详情页走原生播放路径
  Future<bool> _onPanPlay(List a) async {
    if (a.isEmpty || a[0] is! Map) return false;
    final data = Map<String, dynamic>.from(a[0] as Map);
    final url = data['url']?.toString() ?? '';
    final title = data['title']?.toString() ?? '网盘播放';
    if (url.isEmpty) return false;

    final detail = VideoDetail(
      vodId: 'pan_${DateTime.now().millisecondsSinceEpoch}',
      vodName: title,
      vodPic: '',
      typeName: '网盘',
      playSources: [
        PlaySource(
          name: '网盘',
          episodes: [Episode(name: title, url: url)],
        ),
      ],
    );

    Get.toNamed(
      AppPages.detail,
      arguments: {
        'isPush': true,
        'directUrl': url,
        'directTitle': title,
        'videoDetail': detail,
        'sourceName': '网盘',
        'isDirectPushMode': true,
      },
    );
    return true;
  }

  // ============================================================
  // 网络 / UI / 存储 / 播放（原逻辑）
  // ============================================================
  Future<Map<String, dynamic>> _req(List a) async {
    final url = a.isNotEmpty ? a[0]?.toString() ?? '' : '';
    if (url.isEmpty) throw Exception('url 不能为空');
    final opts = (a.length > 1 && a[1] is Map)
        ? Map<String, dynamic>.from(a[1] as Map)
        : <String, dynamic>{};

    final headers = <String, String>{};
    final rawHeaders = opts['headers'];
    if (rawHeaders is Map) {
      rawHeaders.forEach((k, v) {
        headers[k.toString()] = v.toString();
      });
    }
    if (!headers.keys.any((k) => k.toLowerCase() == 'user-agent')) {
      headers['User-Agent'] = BrowserUa.platform;
    }

    final method = (opts['method'] ?? 'GET').toString().toUpperCase();
    final timeoutSec = (opts['timeout'] as num?)?.toInt() ?? 20;
    final rt = (opts['responseType'] ?? 'text').toString();

    Response<dynamic> resp;
    try {
      resp = await HttpClientFactory.dio.request(
        url,
        data: opts['data'],
        options: Options(
          method: method,
          headers: headers,
          responseType: rt == 'json'
              ? ResponseType.json
              : rt == 'bytes'
                  ? ResponseType.bytes
                  : ResponseType.plain,
          sendTimeout: Duration(seconds: timeoutSec),
          receiveTimeout: Duration(seconds: timeoutSec),
        ),
      );
    } on DioException catch (e) {
      resp = e.response ??
          Response(
            requestOptions: e.requestOptions,
            statusCode: 0,
            data: e.message,
          );
    }

    return {
      'status': resp.statusCode ?? 0,
      'ok': (resp.statusCode ?? 0) >= 200 && (resp.statusCode ?? 0) < 400,
      'url': resp.requestOptions.uri.toString(),
      'body': resp.data,
      'headers': resp.headers.map.map((k, v) => MapEntry(k, v.join(', '))),
      'cookies': <Map<String, dynamic>>[],
    };
  }

  Future<bool> _toast(List a) async {
    final msg = a.isNotEmpty ? a[0]?.toString() ?? '' : '';
    if (msg.isNotEmpty) SmartDialog.showToast(msg);
    return true;
  }

  Future<bool> _fullscreen(List a) async {
    final on = a.isNotEmpty && (a[0] == true || a[0] == 1);
    isFullscreen.value = on;
    return true;
  }

  Future<bool> _tab(List a) async {
    final name = a.isNotEmpty ? a[0]?.toString() ?? '' : '';
    if (name.isEmpty || !Get.isRegistered<MainController>()) return false;
    final mc = Get.find<MainController>();
    final idx = mc.navigationBars.indexWhere((t) => t.name == name);
    if (idx < 0) return false;
    mc.switchPage(idx);
    return true;
  }

  Future<bool> _back() async {
    if (await controller.canGoBack()) {
      await controller.goBack();
    } else {
      Get.back();
    }
    return true;
  }

  Future<bool> _reload() async {
    await controller.reload();
    return true;
  }

  bool _switchTabByName(String name) {
    if (!Get.isRegistered<MainController>()) return false;
    final mc = Get.find<MainController>();
    final idx = mc.navigationBars.indexWhere((t) => t.name == name);
    if (idx < 0) return false;
    mc.switchPage(idx);
    return true;
  }

  Future<bool> _openHome() async => _switchTabByName('home');

  Future<bool> _openLive() async => _switchTabByName('live');

  Future<bool> _openKeep() async {
    Get.toNamed(AppPages.history);
    return true;
  }

  Future<bool> _openSetting() async {
    Get.toNamed(AppPages.setting);
    return true;
  }

  Future<bool> _search(List a) async {
    final kw = a.isNotEmpty ? a[0]?.toString() ?? '' : '';
    if (kw.isEmpty) return false;

    final opts = (a.length > 1 && a[1] is Map)
        ? Map<String, dynamic>.from(a[1] as Map)
        : <String, dynamic>{};
    final direct = opts['direct'] == true;

    if (!direct) {
      Get.toNamed(AppPages.search, arguments: {'keyword': kw});
      return true;
    }

    List<String> sources = [];
    bool onlyDefault = false;
    if (Get.isRegistered<SearchFilterService>()) {
      final filter = Get.find<SearchFilterService>();
      sources = filter.enabledSourceKeyList;
      onlyDefault = filter.onlyDefaultSource.value;
    }

    if (sources.isEmpty) {
      Get.toNamed(AppPages.search, arguments: {'keyword': kw});
      return true;
    }

    Get.toNamed(
      AppPages.searchResult,
      arguments: {
        'keyword': kw,
        'sources': sources,
        'onlyDefault': onlyDefault,
      },
    );
    return true;
  }

  Future<bool> _vod(List a) async {
    final siteKey = a.isNotEmpty ? a[0]?.toString() ?? '' : '';
    final vodId = a.length > 1 ? a[1]?.toString() ?? '' : '';
    if (siteKey.isEmpty) throw Exception('vod: siteKey 缺失');
    if (vodId.isEmpty) throw Exception('vod: vodId 缺失');

    final site = _findSite(siteKey);
    if (site == null) throw Exception('vod: 未找到源 $siteKey');

    String pwd = 'tinydust';
    final ext = site['ext'];
    if (ext is Map && ext['pwd'] != null) {
      pwd = ext['pwd'].toString();
    }

    Get.toNamed(
      AppPages.detail,
      arguments: {
        'vodId': vodId,
        'pwd': pwd,
        'site': site,
      },
    );
    return true;
  }

  Map<String, dynamic>? _findSite(String siteKey) {
    if (!Get.isRegistered<SourceManager>()) return null;
    final sm = Get.find<SourceManager>();
    for (final s in sm.sites) {
      if (s['key']?.toString() == siteKey) return s;
    }
    return null;
  }

  Future<Box> _boxOf(String ns) {
    final name = 'web_ds_${ns.isEmpty ? 'default' : ns}';
    return _boxCache.putIfAbsent(name, () => Hive.openBox(name));
  }

  Future<dynamic> _storeGet(List a) async {
    final k = a.isNotEmpty ? a[0]?.toString() ?? '' : '';
    final ns = a.length > 1 ? a[1]?.toString() ?? '' : '';
    if (k.isEmpty) return null;
    final box = await _boxOf(ns);
    return box.get(k);
  }

  Future<bool> _storeSet(List a) async {
    final k = a.isNotEmpty ? a[0]?.toString() ?? '' : '';
    final v = a.length > 1 ? a[1] : null;
    final ns = a.length > 2 ? a[2]?.toString() ?? '' : '';
    if (k.isEmpty) return false;
    final box = await _boxOf(ns);
    await box.put(k, v);
    return true;
  }

  Future<bool> _storeDel(List a) async {
    final k = a.isNotEmpty ? a[0]?.toString() ?? '' : '';
    final ns = a.length > 1 ? a[1]?.toString() ?? '' : '';
    if (k.isEmpty) return false;
    final box = await _boxOf(ns);
    await box.delete(k);
    return true;
  }

  Future<bool> _openVod(List a) async {
    if (a.isEmpty || a[0] == null || a[0] is! Map) {
      return _openHome();
    }
    final raw = Map<String, dynamic>.from(a[0] as Map);

    final playSources = <PlaySource>[];

    final topEpisodes = raw['episodes'];
    if (topEpisodes is List && topEpisodes.isNotEmpty) {
      final eps = <Episode>[];
      for (final ep in topEpisodes) {
        if (ep is! Map) continue;
        final name = ep['name']?.toString() ?? '';
        final url = ep['url']?.toString() ?? '';
        if (url.isEmpty) continue;
        eps.add(Episode(name: name, url: url, flag: '内联'));
      }
      if (eps.isNotEmpty) {
        playSources.add(PlaySource(name: '内联', episodes: eps));
      }
    }

    final lines = raw['lines'];
    if (lines is List && lines.isNotEmpty) {
      for (final line in lines) {
        if (line is! Map) continue;
        final lineName = line['name']?.toString() ?? '默认';
        final eps = <Episode>[];
        final episodes = line['episodes'];
        if (episodes is List) {
          for (final ep in episodes) {
            if (ep is! Map) continue;
            final name = ep['name']?.toString() ?? '';
            final url = ep['url']?.toString() ?? '';
            if (url.isEmpty) continue;
            eps.add(Episode(name: name, url: url, flag: lineName));
          }
        }
        if (eps.isNotEmpty) {
          playSources.add(PlaySource(name: lineName, episodes: eps));
        }
      }
    }

    if (playSources.isEmpty) {
      final fromList = (raw['vod_play_from']?.toString() ?? '').split(r'$$$');
      final urlList = (raw['vod_play_url']?.toString() ?? '').split(r'$$$');
      for (int i = 0; i < fromList.length && i < urlList.length; i++) {
        final ln = fromList[i].isEmpty ? '线路${i + 1}' : fromList[i];
        final eps = <Episode>[];
        for (final part in urlList[i].split('#')) {
          if (part.isEmpty) continue;
          final idx = part.indexOf(r'$');
          if (idx > 0) {
            eps.add(Episode(
              name: part.substring(0, idx),
              url: part.substring(idx + 1),
            ));
          } else {
            eps.add(Episode(name: part, url: part));
          }
        }
        if (eps.isNotEmpty) {
          playSources.add(PlaySource(name: ln, episodes: eps));
        }
      }
    }

    if (playSources.isEmpty) throw Exception('openVod: 无剧集');

    final detail = VideoDetail(
      vodId: raw['vod_id']?.toString() ??
          'web_${DateTime.now().millisecondsSinceEpoch}',
      vodName: raw['vod_name']?.toString() ??
          raw['title']?.toString() ??
          'Web 播放',
      vodPic: raw['vod_pic']?.toString() ?? '',
      vodRemarks: raw['vod_remarks']?.toString(),
      vodActor: raw['vod_actor']?.toString(),
      vodContent: raw['vod_content']?.toString(),
      vodDirector: raw['vod_director']?.toString(),
      vodYear: raw['vod_year']?.toString(),
      vodArea: raw['vod_area']?.toString(),
      typeName: raw['type_name']?.toString() ?? 'Web 源',
      playSources: playSources,
    );

    final mark = raw['mark']?.toString() ?? '';
    final first = playSources.first;
    int startIdx = 0;
    if (mark.isNotEmpty) {
      final idx = first.episodes.indexWhere((e) => e.name == mark);
      if (idx >= 0) startIdx = idx;
    }

    Get.toNamed(
      AppPages.detail,
      arguments: {
        'isPush': true,
        'directUrl': first.episodes[startIdx].url,
        'directTitle': first.episodes[startIdx].name,
        'videoDetail': detail,
        'sourceName': detail.typeName,
        'isDirectPushMode': true,
      },
    );
    return true;
  }

  Future<bool> _play(List a) async {
    final url = a.isNotEmpty ? a[0]?.toString() ?? '' : '';
    if (url.isEmpty) return false;
    final title = a.length > 1 ? a[1]?.toString() ?? '直链播放' : '直链播放';
    final detail = VideoDetail(
      vodId: 'web_play_${DateTime.now().millisecondsSinceEpoch}',
      vodName: title,
      vodPic: '',
      typeName: 'Web 源',
      playSources: [
        PlaySource(
          name: '直链',
          episodes: [Episode(name: title, url: url)],
        ),
      ],
    );
    Get.toNamed(
      AppPages.detail,
      arguments: {
        'isPush': true,
        'directUrl': url,
        'directTitle': title,
        'videoDetail': detail,
        'sourceName': 'Web 源',
        'isDirectPushMode': true,
      },
    );
    return true;
  }

  // ===== 信息 =====
  String _stableUuid() {
    try {
      final box = Hive.box('app_settings');
      final cached = box.get('web_ds_uuid') as String?;
      if (cached != null && cached.length == 32) return cached;
      final generated = List.generate(
        32,
        (_) => '0123456789abcdef'[
            DateTime.now().microsecondsSinceEpoch % 16],
      ).join();
      box.put('web_ds_uuid', generated);
      return generated;
    } catch (_) {
      return '00000000000000000000000000000000';
    }
  }

  Future<Map<String, dynamic>> _device() async => {
        'uuid': _stableUuid(),
        'name': '源影客户端',
        'ip': '127.0.0.1',
        'type': (Platform.isAndroid || Platform.isIOS) ? 0 : 1,
        'serial': '',
        'eth': '',
        'wlan': '',
        'time': DateTime.now().millisecondsSinceEpoch,
      };

  Future<Map<String, dynamic>> _site() async {
    Map<String, dynamic>? site;
    try {
      if (Get.isRegistered<SourceManager>()) {
        site = Get.find<SourceManager>().currentSite.value;
      }
    } catch (_) {}
    return {
      'key': site?['key']?.toString() ?? '',
      'name': site?['name']?.toString() ?? '',
      'homePage': site?['api']?.toString() ?? '',
      'type': 3,
      'header': <String, dynamic>{},
    };
  }

  Future<Map<String, dynamic>> _config() async => {
        'id': 'yuanying',
        'url': '',
        'desc': '源影',
        'driveCheck': false,
      };

  Future<List<Map<String, dynamic>>> _history() async {
    try {
      final list = GStorage.getHistory();
      return list.map((e) {
        final m = Map<String, dynamic>.from(e);
        return <String, dynamic>{
          'key': m['vod_id']?.toString() ?? '',
          'vodName': m['vod_name']?.toString() ?? '',
          'vodPic': m['vod_pic']?.toString() ?? '',
          'vodRemarks': m['vod_remarks']?.toString() ?? '',
          'vodFlag': m['type_name']?.toString() ?? '',
          'createTime': (m['watchTime'] as num?)?.toInt() ?? 0,
          'opening': 0,
          'ending': 0,
          'position': 0,
          'duration': 0,
          'episodeUrl': '',
          'revSort': false,
          'revPlay': false,
          'speed': 1.0,
          'scale': 1.0,
          'cid': 0,
          'siteKey': m['site_key']?.toString() ?? '',
          'episodeIndex': 0,
          'lineIndex': 0,
        };
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<Map<String, dynamic>> _viewport() async {
    final ctx = Get.context;
    if (ctx == null) {
      return {
        'width': 0,
        'height': 0,
        'keyboardBottom': 0,
        'chromeMode': 'edge',
        'safeInsets': {'top': 0, 'bottom': 0, 'left': 0, 'right': 0},
        'gestureLeft': 0,
        'gestureRight': 0,
        'statusBarHeight': 0,
        'navigationBarHeight': 0,
      };
    }
    final mq = MediaQuery.of(ctx);
    return {
      'width': mq.size.width,
      'height': mq.size.height,
      'safeInsets': {
        'top': mq.padding.top,
        'bottom': mq.padding.bottom,
        'left': mq.padding.left,
        'right': mq.padding.right,
      },
      'gestureLeft': 0,
      'gestureRight': 0,
      'statusBarHeight': mq.padding.top,
      'navigationBarHeight': mq.padding.bottom,
      'keyboardBottom': mq.viewInsets.bottom,
      'chromeMode': isFullscreen.value ? 'fullscreen' : 'edge',
    };
  }

  Future<Map<String, dynamic>> _extInfo() async {
    final site = await _site();
    return {
      'siteKey': site['key'] ?? '',
      'siteName': site['name'] ?? '',
      'homePage': site['homePage'] ?? '',
      'enabled': true,
      'matched': true,
      'ready': true,
    };
  }
}
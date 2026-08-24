import 'package:get/get.dart';
import 'package:yuanying/modules/home/views/home_page.dart';
import 'package:yuanying/modules/setting/views/setting_page.dart';
import 'package:yuanying/modules/setting/views/style_setting.dart';
import 'package:yuanying/modules/setting/views/color_select_page.dart';
import 'package:yuanying/modules/setting/views/site_config_page.dart';
import 'package:yuanying/modules/video/views/video_page.dart';
import 'package:yuanying/modules/main/views/main_page.dart';
import 'package:yuanying/modules/dlna/views/dlna_page.dart';
import 'package:yuanying/modules/search/views/search_page.dart';
import 'package:yuanying/modules/search_result/views/search_result_page.dart';
import 'package:yuanying/modules/favorite/views/favorite_page.dart';
import 'package:yuanying/modules/history/views/history_page.dart';
import 'package:yuanying/modules/setting/views/play_setting_page.dart';
import 'package:yuanying/modules/setting/views/play_speed_set_page.dart';
import 'package:yuanying/modules/setting/views/font_size_select.dart';
import 'package:yuanying/modules/setting/views/bar_set.dart';
import 'package:yuanying/modules/setting/views/extra_setting_page.dart';
import 'package:yuanying/modules/webdav/views/webdav_setting_page.dart';
import 'package:yuanying/modules/webview/views/webview_page.dart';
import 'package:yuanying/modules/disclaimer/views/disclaimer_page.dart';
import 'package:yuanying/modules/debug_log/views/debug_log_page.dart';
import 'package:yuanying/modules/setting/views/about_page.dart';
import 'package:yuanying/modules/catvod_log/views/catvod_log_page.dart';
import 'package:yuanying/modules/setting/views/danmaku_config_page.dart';
import 'package:yuanying/modules/setting/views/tmdb_config_page.dart';
import 'package:yuanying/modules/setting/views/tmdb_match_page.dart';

class AppPages {
  static const String initial = '/';
  static const String setting = '/setting';
  static const String styleSetting = '/style_setting';
  static const String colorSelect = '/color_select';
  static const String siteConfig = '/site_config';
  static const String detail = '/detail';
  static const String dlna = '/dlna';
  static const String search = '/search';
  static const String searchResult = '/search_result';
  static const String favorite = '/favorite';
  static const String history = '/history';
  static const String playSetting = '/play_setting';
  static const String fontSizeSetting = '/fontSizeSetting';
  static const String barSetting = '/barSetting';
  static const String extraSetting = '/extraSetting';
  static const String webdav = '/webdav';
  static const String webview = '/webview';
  static const String disclaimer = '/disclaimer';
  static const String about = '/about';
  static const String debugLogs = '/debugLogs';
  static const String catvodLog = '/catvodLog';
  static const String danmakuConfig = '/danmakuConfig';
  static const String tmdbConfig = '/tmdbConfig';
  static const String tmdbMatch = '/tmdbMatch';

  static final List<GetPage> routes = [
    GetPage(name: initial, page: () => const MainPage()),
    GetPage(name: '/home', page: () => const HomePage()),
    GetPage(name: setting, page: () => const SettingPage()),
    GetPage(name: styleSetting, page: () => const StyleSetting()),
    GetPage(name: colorSelect, page: () => const ColorSelectPage()),
    GetPage(name: siteConfig, page: () => const SiteConfigPage()),
    GetPage(name: detail, page: () => const DetailPage()),
    GetPage(name: about, page: () => const AboutPage()),
    GetPage(
      name: dlna,
      page: () => const DLNAPage()
    ),
    GetPage(name: search, page: () => const SearchPage()),
    GetPage(name: searchResult, page: () => const SearchResultPage()),
    GetPage(name: favorite, page: () => const FavoritePage()),
    GetPage(name: history, page: () => const HistoryPage()),
    GetPage(name: playSetting, page: () => const PlaySettingPage()),
    GetPage(name: '/playSpeedSet', page: () => const PlaySpeedSetPage()),
    GetPage(name: fontSizeSetting, page: () => const FontSizeSelectPage()),
    GetPage(name: barSetting, page: () => const BarSetPage()),
    GetPage(name: extraSetting, page: () => const ExtraSettingPage()),
    GetPage(name: webdav, page: () => const WebDavSettingPage()),
    GetPage(name: webview, page: () => const WebviewPage()),
    GetPage(
      name: disclaimer,
      page: () => const DisclaimerPage(),
    ),
    GetPage(name: debugLogs, page: () => const DebugLogPage()),
    GetPage(
      name: catvodLog,
      page: () => const CatVodLogPage(),
    ),
    GetPage(name: danmakuConfig, page: () => const DanmakuConfigPage()),
    GetPage(name: tmdbConfig, page: () => const TmdbConfigPage()),
    GetPage(name: tmdbMatch, page: () => const TmdbMatchPage()),
  ];
}
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
import 'package:yuanying/modules/system_log/views/system_log_page.dart';
import 'package:yuanying/modules/setting/views/danmaku_config_page.dart';
import 'package:yuanying/modules/setting/views/tmdb_config_page.dart';
import 'package:yuanying/modules/setting/views/tmdb_match_page.dart';
import 'package:yuanying/modules/setting/views/live_config_page.dart';
import 'package:yuanying/modules/novel/views/novel_detail_page.dart';
import 'package:yuanying/modules/novel/views/novel_reader_page.dart';
import 'package:yuanying/modules/transfer/views/transfer_page.dart';
import 'package:yuanying/modules/manga/views/manga_detail_page.dart';
import 'package:yuanying/modules/manga/views/manga_reader_page.dart';
import 'package:yuanying/modules/music/views/music_detail_page.dart';
import 'package:yuanying/modules/music/widgets/player_card.dart';
import 'package:yuanying/modules/tmdb/views/tmdb_detail_page.dart';
import 'package:yuanying/modules/tmdb/views/tmdb_person_page.dart';
import 'package:yuanying/modules/emby/views/emby_server_config_page.dart';
import 'package:yuanying/modules/emby/views/emby_main_shell.dart';
import 'package:yuanying/modules/emby/views/emby_detail_page.dart';
import 'package:yuanying/modules/emby/views/emby_library_page.dart';

import 'package:yuanying/modules/jellyfin/views/jellyfin_server_config_page.dart';
import 'package:yuanying/modules/jellyfin/views/jellyfin_main_shell.dart';
import 'package:yuanying/modules/jellyfin/views/jellyfin_detail_page.dart';
import 'package:yuanying/modules/jellyfin/views/jellyfin_library_page.dart';

import 'package:yuanying/modules/alist/views/alist_server_config_page.dart';
import 'package:yuanying/modules/alist/views/alist_main_shell.dart';
import 'package:yuanying/modules/alist/views/alist_file_list_page.dart';
import 'package:yuanying/modules/alist/views/alist_download_page.dart';
import 'package:yuanying/modules/alist/views/alist_recents_page.dart';
import 'package:yuanying/modules/alist/views/alist_favorite_page.dart';
import 'package:yuanying/modules/alist/views/alist_cache_page.dart';
import 'package:yuanying/modules/alist/views/alist_account_page.dart';
import 'package:yuanying/modules/alist/views/alist_file_reader_page.dart';
import 'package:yuanying/modules/web_sniffer/views/web_sniffer_page.dart';

import 'package:yuanying/modules/webdav_drive/views/webdav_server_config_page.dart';
import 'package:yuanying/modules/webdav_drive/views/webdav_main_shell.dart';

import 'package:yuanying/modules/ftp_drive/views/ftp_server_config_page.dart';
import 'package:yuanying/modules/ftp_drive/views/ftp_main_shell.dart';

import 'package:yuanying/modules/smb_drive/views/smb_server_config_page.dart';
import 'package:yuanying/modules/smb_drive/views/smb_main_shell.dart';

import 'package:yuanying/modules/fnos/views/fnos_server_config_page.dart';
import 'package:yuanying/modules/fnos/views/fnos_main_shell.dart';
import 'package:yuanying/modules/fnos/views/fnos_library_page.dart';
import 'package:yuanying/modules/fnos/views/fnos_detail_page.dart';
import 'package:yuanying/modules/fnos/views/fnos_favorite_page.dart';
import 'package:yuanying/modules/fnos/views/fnos_search_page.dart';

import 'package:yuanying/modules/lx_music/views/lx_music_page.dart';
import 'package:yuanying/modules/lx_music/views/lx_music_detail_page.dart';
import 'package:yuanying/modules/lx_music/views/lx_favorites_page.dart';
import 'package:yuanying/modules/lx_music/views/lx_recent_page.dart';
import 'package:yuanying/modules/lx_music/views/lx_playlist_page.dart';


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
  static const String systemLog = '/systemLog';
  static const String danmakuConfig = '/danmakuConfig';
  static const String tmdbConfig = '/tmdbConfig';
  static const String tmdbMatch = '/tmdbMatch';
  static const String liveConfig = '/liveConfig';
  static const String novelDetail = '/novelDetail';
  static const String novelReader = '/novelReader';
  static const String transfer = '/transfer';
  static const String mangaDetail = '/mangaDetail';
  static const String mangaReader = '/mangaReader';
  static const String musicDetail = '/musicDetail';
  static const String musicPlayer = '/musicPlayer';
  static const String tmdbDetail = '/tmdbDetail';
  static const String tmdbPerson = '/tmdbPerson';
  static const String embyServerConfig = '/emby/server_config';
  static const String embyMain = '/emby/main';
  static const String embyDetail = '/emby/detail';
  static const String embyLibrary = '/emby/library';

  static const String jellyfinServerConfig = '/jellyfin/server_config';
  static const String jellyfinMain = '/jellyfin/main';
  static const String jellyfinDetail = '/jellyfin/detail';
  static const String jellyfinLibrary = '/jellyfin/library';
  
  static const String alistServerConfig = '/alist/server_config';
  static const String alistMain = '/alist/main';
  static const String alistFileList = '/alist/file_list';
  static const String alistDownload = '/alist/download';
  static const String alistRecents = '/alist/recents';
  static const String alistFavorite = '/alist/favorite';
  static const String alistCache = '/alist/cache';
  static const String alistAccount = '/alist/account';
  static const String alistFileReader = '/alist/file_reader';
  static const String webSniffer = '/lab/web_sniffer';

  // WebDAV
  static const String webdavServerConfig = '/webdav/server_config';
  static const String webdavMain = '/webdav/main';

  // FTP / SFTP
  static const String ftpServerConfig = '/ftp/server_config';
  static const String ftpMain = '/ftp/main';

  // SMB
  static const String smbServerConfig = '/smb/server_config';
  static const String smbMain = '/smb/main';

  // FnOS 飞牛影视
  static const String fnosServerConfig = '/fnos/server_config';
  static const String fnosMain         = '/fnos/main';
  static const String fnosLibrary      = '/fnos/library';
  static const String fnosDetail       = '/fnos/detail';
  static const String fnosFavorite     = '/fnos/favorite';
  static const String fnosSearch     = '/fnos/search';

  // 洛雪音乐
  static const String lxMusic = '/lab/lx_music';
  static const String lxMusicDetail = '/lx_music_detail';
  static const String lxFavorites = '/lx_favorites';
  static const String lxRecent = '/lx_recent';
  static const String lxPlaylist = '/lx_playlist';

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
    GetPage(name: systemLog, page: () => const SystemLogPage()),
    GetPage(name: danmakuConfig, page: () => const DanmakuConfigPage()),
    GetPage(name: tmdbConfig, page: () => const TmdbConfigPage()),
    GetPage(name: tmdbMatch, page: () => const TmdbMatchPage()),
    GetPage(name: liveConfig, page: () => const LiveConfigPage()),
    GetPage(name: novelDetail, page: () => const NovelDetailPage()),
    GetPage(name: novelReader, page: () => const NovelReaderPage()),
    GetPage(name: transfer, page: () => const TransferPage()),
    GetPage(name: mangaDetail, page: () => const MangaDetailPage()),
    GetPage(name: mangaReader, page: () => const MangaReaderPage()),
    GetPage(name: musicDetail, page: () => const MusicDetailPage()),
    GetPage(
      name: musicPlayer,
      page: () => const PlayerCard()
    ),
    GetPage(
      name: AppPages.tmdbDetail,
      page: () => TmdbDetailPage(
        videoItem: Get.arguments['videoItem'],
        site: Get.arguments['site'],
        fromHome: Get.arguments['fromHome'] ?? false,
        tmdbId: Get.arguments['tmdbId'],
        mediaType: Get.arguments['mediaType'],
      ),
    ),
    GetPage(
      name: AppPages.tmdbPerson,
      page: () => TmdbPersonPage(
        personId: Get.arguments['personId'],
        personName: Get.arguments['personName'],
      ),
    ),
    GetPage(name: embyServerConfig, page: () => const EmbyServerConfigPage()),
    GetPage(name: embyMain, page: () => const EmbyMainShell()),
    GetPage(name: embyDetail, page: () => const EmbyDetailPage()),
    GetPage(name: embyLibrary, page: () => const EmbyLibraryPage()),

    GetPage(
      name: jellyfinServerConfig,
      page: () => const JellyfinServerConfigPage(),
    ),
    GetPage(
      name: jellyfinMain,
      page: () => const JellyfinMainShell(),
    ),
    GetPage(
      name: jellyfinDetail,
      page: () => const JellyfinDetailPage(),
    ),
    GetPage(
      name: jellyfinLibrary,
      page: () => const JellyfinLibraryPage(),
    ),

    GetPage(name: alistServerConfig, page: () => const AlistServerConfigPage()),
    GetPage(name: alistMain, page: () => const AlistMainShell()),
    GetPage(name: alistFileList, page: () => const AlistFileListWrapper()),
    GetPage(name: alistDownload, page: () => const AlistDownloadPage()),
    GetPage(name: alistRecents, page: () => const AlistRecentsPage()),
    GetPage(name: alistFavorite, page: () => const AlistFavoritePage()),
    GetPage(name: alistCache, page: () => const AlistCachePage()),
    GetPage(name: alistAccount, page: () => const AlistAccountPage()),
    GetPage(name: alistFileReader, page: () => const AlistFileReaderPage()),
    GetPage(name: webSniffer, page: () => const WebSnifferPage()),

    GetPage(
      name: webdavServerConfig,
      page: () => const WebDavServerConfigPage(),
    ),
    GetPage(
      name: webdavMain,
      page: () => const WebDavMainShell(),
    ),

    GetPage(
      name: ftpServerConfig,
      page: () => const FtpServerConfigPage(),
    ),
    GetPage(
      name: ftpMain,
      page: () => const FtpMainShell(),
    ),

    GetPage(
      name: smbServerConfig,
      page: () => const SmbServerConfigPage(),
    ),
    GetPage(
      name: smbMain,
      page: () => const SmbMainShell(),
    ),

    // FnOS 飞牛影视
    GetPage(
      name: fnosServerConfig,
      page: () => const FnosServerConfigPage(),
    ),
    GetPage(
      name: fnosMain,
      page: () => const FnosMainShell(),
    ),
    GetPage(
      name: fnosLibrary,
      page: () => const FnosLibraryPage(),
    ),
    GetPage(
      name: fnosDetail,
      page: () => const FnosDetailPage(),
    ),
    GetPage(
      name: fnosFavorite,
      page: () => const FnosFavoritePage()
    ),
    GetPage(
      name: fnosSearch,
      page: () => const FnosSearchPage()
    ),

    GetPage(
      name: lxMusic,
      page: () => const LxMusicPage()
    ),
    GetPage(
      name: lxMusicDetail,
      page: () => const LxMusicDetailPage(),
    ),
    GetPage(name: lxFavorites, page: () => const LxFavoritesPage()),
    GetPage(name: lxRecent, page: () => const LxRecentPage()),
    GetPage(name: lxPlaylist, page: () => const LxPlaylistPage()),
  ];
}
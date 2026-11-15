/// 字幕网站类型
///
/// 枚举顺序决定 Tab 顺序（SubtitleSiteManager.available 按此顺序返回）。
/// 迅雷排第一：无需配置，默认首选。
enum SubtitleSiteType {
  xunlei('迅雷看看'),
  subhd('SubHD'),
  assrt('射手网'),
  openSubtitles('OpenSubtitles');

  final String displayName;
  const SubtitleSiteType(this.displayName);
}
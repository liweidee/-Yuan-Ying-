/// 在线歌单信息
class LxSonglistInfo {
  final String id;
  final String name;
  final String author;
  final String imgUrl;
  final int playCount;
  final int songCount;
  final String desc;
  final String source;

  LxSonglistInfo({
    required this.id,
    required this.name,
    required this.author,
    required this.imgUrl,
    required this.playCount,
    required this.songCount,
    required this.desc,
    required this.source,
  });
}
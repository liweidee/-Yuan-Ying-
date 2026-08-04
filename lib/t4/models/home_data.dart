import 'video_item.dart';

class HomeData {
  final List<Category> categories;
  final List<VideoItem> list;

  HomeData({
    required this.categories,
    required this.list,
  });

  factory HomeData.fromJson(Map<String, dynamic> json) {
    final List<Category> categories = [];
    if (json['class'] != null && json['class'] is List) {
      for (final item in json['class']) {
        categories.add(Category.fromJson(item));
      }
    }

    final List<VideoItem> list = [];
    if (json['list'] != null && json['list'] is List) {
      for (final item in json['list']) {
        list.add(VideoItem.fromJson(item));
      }
    }

    return HomeData(categories: categories, list: list);
  }
}

class Category {
  final String typeId;
  final String typeName;

  Category({
    required this.typeId,
    required this.typeName,
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      typeId: json['type_id']?.toString() ?? '',
      typeName: json['type_name']?.toString() ?? '',
    );
  }
}
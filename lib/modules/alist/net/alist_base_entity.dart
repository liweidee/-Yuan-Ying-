/// AList 统一响应格式：{ code, message, data }
class AlistBaseEntity<T> {
  late int code;
  late String message;
  T? data;

  AlistBaseEntity(this.code, this.message, this.data);

  AlistBaseEntity.fromJson(Map<String, dynamic> json, T Function(dynamic)? decoder) {
    code = json['code'] as int? ?? -1;
    message = json['message'] as String? ?? '';
    final raw = json['data'];
    if (raw != null && decoder != null) {
      data = decoder(raw);
    }
  }
}
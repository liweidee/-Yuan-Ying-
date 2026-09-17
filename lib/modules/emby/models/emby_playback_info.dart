class EmbyMediaSource {
  final String id;
  final String? container;
  final bool supportsDirectPlay;
  final bool supportsDirectStream;
  final bool supportsTranscoding;
  final List<EmbyMediaStream> streams;

  EmbyMediaSource({
    required this.id,
    this.container,
    this.supportsDirectPlay = false,
    this.supportsDirectStream = false,
    this.supportsTranscoding = false,
    this.streams = const [],
  });

  factory EmbyMediaSource.fromJson(Map<String, dynamic> json) => EmbyMediaSource(
    id: json['Id'] as String,
    container: json['Container'] as String?,
    supportsDirectPlay: json['SupportsDirectPlay'] as bool? ?? false,
    supportsDirectStream: json['SupportsDirectStream'] as bool? ?? false,
    supportsTranscoding: json['SupportsTranscoding'] as bool? ?? false,
    streams: (json['MediaStreams'] as List?)?.map((e) => EmbyMediaStream.fromJson(e as Map<String,dynamic>)).toList() ?? [],
  );
}

class EmbyMediaStream {
  final int index;
  final String type; // Video, Audio, Subtitle
  final String? codec;
  final String? language;
  final String? displayTitle;
  EmbyMediaStream({required this.index, required this.type, this.codec, this.language, this.displayTitle});
  factory EmbyMediaStream.fromJson(Map<String, dynamic> json) => EmbyMediaStream(
    index: json['Index'] as int,
    type: json['Type'] as String,
    codec: json['Codec'] as String?,
    language: json['Language'] as String?,
    displayTitle: json['DisplayTitle'] as String?,
  );
}
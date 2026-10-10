import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:yuanying/modules/music/services/music_player.dart';
import 'package:yuanying/t4/models/video_detail.dart';

class AudioPlayerHandler extends BaseAudioHandler {
  final MusicPlayer player = MusicPlayer();
  late PlaybackEvent _audioEvent;
  final List<StreamSubscription?> _subscriptions = [];

  /// 系统控制栏切歌回调（由 MusicPlayerController 注入）
  Future<void> Function()? onSkipToNext;
  Future<void> Function()? onSkipToPrevious;

  String? _coverUrl;
  String? _artist;
  String? _album;

  /// 是否正在切歌
  ///
  /// 切歌期间主音频停止/加载，若无此标志，audio_service 会向 iOS 上报
  /// playing=false，导致锁屏控制栏被系统移除。
  bool isSwitchingTrack = false;

  double get _speed => player.audio.speed;
  Episode? get current => player.current;

  set current(Episode? value) {
    player.current = value;
    _updateMediaItem();
  }

  AudioPlayerHandler() {
    _subscriptions.add(player.audio.playbackEventStream.listen((event) {
      _audioEvent = event;
    }));
    _subscriptions.add(player.audio.playerStateStream.listen((state) {
      _broadcastState();
    }));
    _updateMediaItem();
    _subscriptions.add(player.audio.positionStream.listen((position) {
      _updatePosition();
    }));
    _subscriptions.add(player.audio.durationStream.listen((duration) {
      if (mediaItem.value != null && duration != null) {
        mediaItem.add(mediaItem.value!.copyWith(duration: duration));
      }
    }));
  }

  Future<void> disposeHandler() async {
    for (var sub in _subscriptions) {
      sub?.cancel();
    }
    player.dispose();
  }

  /// 外部触发状态广播（由 MusicPlayerController 在切歌前后调用）
  void notifyStateChanged() {
    _broadcastState();
  }

  void updateMetadata({String? cover, String? artist, String? album}) {
    bool changed = false;
    if (cover != null && cover != _coverUrl) {
      _coverUrl = cover;
      changed = true;
    }
    if (artist != null && artist != _artist) {
      _artist = artist;
      changed = true;
    }
    if (album != null && album != _album) {
      _album = album;
      changed = true;
    }
    if (changed) {
      _updateMediaItem();
    }
  }

  @override
  Future<void> play({Episode? music, String? url, Map<String, String>? headers}) async {
    if (music != null) {
      await player.play(music: music, url: url, headers: headers);
    } else {
      if (player.current == null) return;
      await player.audio.play();
    }
    _updatePosition();
  }

  @override
  Future<void> pause() async {
    await player.audio.pause();
    _updatePosition();
  }

  @override
  Future<void> seek(Duration position) => player.audio.seek(position);

  @override
  Future<void> skipToPrevious() async {
    if (onSkipToPrevious != null) {
      await onSkipToPrevious!();
      return;
    }
    await player.prev();
    _updateMediaItem();
  }

  @override
  Future<void> skipToNext() async {
    if (onSkipToNext != null) {
      await onSkipToNext!();
      return;
    }
    await player.next();
    _updateMediaItem();
  }

  void _updateMediaItem() {
    if (player.current != null) {
      final newItem = episode2MediaItem(
        player.current!,
        coverUrl: _coverUrl,
        artist: _artist,
        album: _album,
      );
      mediaItem.add(newItem.copyWith(
        duration: player.audio.duration ?? newItem.duration,
      ));
    }
  }

  void _updatePosition() {
    _audioEvent = _audioEvent.copyWith(
      updatePosition: player.audio.position,
      bufferedPosition: player.audio.bufferedPosition,
      updateTime: DateTime.now(),
    );
  }

  void _broadcastState() {
    // 切歌期间"假装"仍在播放，避免控制栏丢失
    final bool effectivePlaying = isSwitchingTrack || player.audio.playing;

    final controls = [
      const MediaControl(
        action: MediaAction.skipToPrevious,
        androidIcon: "drawable/skip_previous",
        label: "上一曲",
      ),
      MediaControl(
        action: MediaAction.playPause,
        androidIcon: effectivePlaying
            ? "drawable/pause_circle"
            : "drawable/play_circle",
        label: "暂停/播放",
      ),
      const MediaControl(
        action: MediaAction.skipToNext,
        androidIcon: "drawable/skip_next",
        label: "下一曲",
      ),
    ];

    AudioProcessingState processingState;
    if (isSwitchingTrack) {
      processingState = AudioProcessingState.buffering;
    } else {
      processingState = {
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[player.audio.processingState] ?? AudioProcessingState.ready;
    }

    playbackState.add(playbackState.value.copyWith(
      controls: controls,
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      processingState: processingState,
      playing: effectivePlaying,
      updatePosition: player.audio.position,
      bufferedPosition: player.audio.bufferedPosition,
      speed: _speed,
      queueIndex: _audioEvent.currentIndex,
    ));
  }
}

MediaItem episode2MediaItem(
  Episode episode, {
  String? coverUrl,
  String? artist,
  String? album,
}) {
  Uri? artUri;
  if (coverUrl != null && coverUrl.isNotEmpty) {
    artUri = Uri.tryParse(coverUrl);
  }
  return MediaItem(
    id: episode.url,
    title: episode.name,
    artist: (artist != null && artist.isNotEmpty) ? artist : '未知歌手',
    album: (album != null && album.isNotEmpty) ? album : '',
    artUri: artUri,
  );
}
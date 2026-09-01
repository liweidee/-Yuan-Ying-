import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:yuanying/modules/music/services/music_player.dart';
import 'package:yuanying/t4/models/video_detail.dart';

class AudioPlayerHandler extends BaseAudioHandler {
  final MusicPlayer player = MusicPlayer();
  late PlaybackEvent _audioEvent;
  final List<StreamSubscription?> _subscriptions = [];

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
      _updateMediaItem();
      _broadcastState();
    }));
    _updateMediaItem();
    _subscriptions.add(player.audio.positionStream.listen((position) {
      _updatePosition();
    }));
    _subscriptions.add(player.audio.durationStream.listen((duration) {
      if (mediaItem.value != null) {
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

  // ===== play 方法保留 url 和 headers 参数 =====
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
    await player.prev();
    _updateMediaItem();
  }

  @override
  Future<void> skipToNext() async {
    await player.next();
    _updateMediaItem();
  }

  void _updateMediaItem() {
    if (player.current != null) {
      final newItem = episode2MediaItem(player.current!);
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
    final controls = [
      const MediaControl(
        action: MediaAction.skipToPrevious,
        androidIcon: "drawable/skip_previous",
        label: "上一曲",
      ),
      MediaControl(
        action: MediaAction.playPause,
        androidIcon: player.audio.playing ? "drawable/pause_circle" : "drawable/play_circle",
        label: "暂停/播放",
      ),
      const MediaControl(
        action: MediaAction.skipToNext,
        androidIcon: "drawable/skip_next",
        label: "下一曲",
      ),
    ];

    final processingState = {
      ProcessingState.loading: AudioProcessingState.loading,
      ProcessingState.buffering: AudioProcessingState.buffering,
      ProcessingState.ready: AudioProcessingState.ready,
      ProcessingState.completed: AudioProcessingState.completed,
    }[player.audio.processingState] ?? AudioProcessingState.ready;

    playbackState.add(playbackState.value.copyWith(
      controls: controls,
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      processingState: processingState,
      playing: player.audio.playing,
      updatePosition: player.audio.position,
      bufferedPosition: player.audio.bufferedPosition,
      speed: _speed,
      queueIndex: _audioEvent.currentIndex,
    ));
  }
}

MediaItem episode2MediaItem(Episode episode) {
  return MediaItem(
    id: episode.url,
    title: episode.name,
    artist: '',
    album: '',
  );
}
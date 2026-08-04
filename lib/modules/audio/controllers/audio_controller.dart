import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';

import 'package:yuanying/plugin/pl_player/models/play_repeat.dart';
import 'package:yuanying/plugin/pl_player/player_pref.dart';
import 'package:yuanying/utils/extension/num_ext.dart';
import 'package:yuanying/utils/platform_utils.dart';

/// 音频数据模型
class AudioItem {
  final String title;
  final String url;
  final String? artist;
  final String? cover;
  final Duration? duration;

  AudioItem({
    required this.title,
    required this.url,
    this.artist,
    this.cover,
    this.duration,
  });
}

/// 音频排序方式
enum AudioSortOrder { normal, asc, desc, random }

extension AudioSortOrderExt on AudioSortOrder {
  String get label {
    switch (this) {
      case AudioSortOrder.normal:
        return '默认';
      case AudioSortOrder.asc:
        return '正序';
      case AudioSortOrder.desc:
        return '倒序';
      case AudioSortOrder.random:
        return '随机';
    }
  }
}

/// 音频播放控制器
class AudioController extends GetxController
    with GetSingleTickerProviderStateMixin {
  // ===== 播放列表数据 =====
  final RxList<AudioItem> playlist = <AudioItem>[].obs;
  final RxInt currentIndex = (-1).obs;
  final RxString currentTitle = ''.obs;
  final RxString currentArtist = ''.obs;
  final RxString currentCover = ''.obs;

  // ===== 播放状态 =====
  Player? _player;
  bool _hasInit = false;
  final Rx<Duration> position = Duration.zero.obs;
  final Rx<Duration> duration = Duration.zero.obs;
  final RxBool isPlaying = false.obs;
  final RxDouble speed = 1.0.obs;

  // ===== 播放模式 =====
  final Rx<PlayRepeat> playMode = Rx<PlayRepeat>(
    PlayRepeat.values[PlayerPref.playRepeat],
  );

  // ===== 音量 =====
  late final RxDouble desktopVolume = RxDouble(PlayerPref.desktopVolume);
  double? _lastVolume;

  // ===== 动画 =====
  late final AnimationController animController;

  List<StreamSubscription>? _subscriptions;

  // ===== 排序 =====
  final Rx<AudioSortOrder> sortOrder = AudioSortOrder.normal.obs;

  // ===== Getter =====
  Player? get player => _player;

  @override
  void onInit() {
    super.onInit();
    animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    final args = Get.arguments;
    if (args != null) {
      _loadFromArguments(args);
    }
  }

  void _loadFromArguments(Map args) {
    final list = args['playlist'] as List<AudioItem>?;
    if (list != null && list.isNotEmpty) {
      playlist.value = list;
      final index = args['index'] ?? 0;
      if (index < playlist.length) {
        currentIndex.value = index;
        _updateCurrentItem(playlist[index]);
        _initPlayerIfNeeded();
        _playCurrent();
      }
    }
  }

  void _updateCurrentItem(AudioItem item) {
    currentTitle.value = item.title;
    currentArtist.value = item.artist ?? '';
    currentCover.value = item.cover ?? '';
  }

  // ===== 播放器初始化 =====
  Future<void> _initPlayerIfNeeded() async {
    if (_hasInit) return;
    _hasInit = true;

    _player = Player(); // 干净地创建，不传任何 options

    // 用官方 API 设置音量
    await _player!.setVolume(
      PlatformUtils.isDesktop
          ? desktopVolume.value * 100
          : PlayerPref.playerVolume.toDouble(),
    );

    if (isClosed) {
      _player!.dispose();
      _player = null;
      return;
    }

    final stream = _player!.stream;
    _subscriptions = [
      stream.position.listen((pos) {
        if (pos.inSeconds != position.value.inSeconds) {
          position.value = pos;
        }
      }),
      stream.duration.listen(duration.call),
      stream.playing.listen((playing) {
        isPlaying.value = playing;
        if (playing) {
          animController.forward();
        } else {
          animController.reverse();
        }
      }),
      stream.completed.listen((completed) {
        if (completed) {
          _onPlaybackComplete();
        }
      }),
    ];
  }

  void _onPlaybackComplete() {
    switch (playMode.value) {
      case PlayRepeat.pause:
        break;
      case PlayRepeat.listOrder:
        playNext();
        break;
      case PlayRepeat.singleCycle:
        _player?.seek(Duration.zero);
        _player?.play();
        break;
      case PlayRepeat.listCycle:
        if (!playNext()) {
          if (playlist.isNotEmpty) {
            playIndex(0);
          } else {
            _player?.seek(Duration.zero);
            _player?.play();
          }
        }
        break;
    }
  }

  // ===== 播放控制 =====
  void playOrPause() {
    if (_player == null) return;
    if ((duration.value - position.value).inMilliseconds < 50) {
      _player!.seek(Duration.zero).whenComplete(_player!.play);
    } else {
      _player!.playOrPause();
    }
  }

  void playIndex(int index) {
    if (index < 0 || index >= playlist.length) return;
    if (currentIndex.value == index) return;

    currentIndex.value = index;
    _updateCurrentItem(playlist[index]);
    _playCurrent();
  }

  void _playCurrent() {
    if (_player == null) return;
    final item = playlist[currentIndex.value];
    _player!.open(
      Media(item.url),
      play: true,
    );
  }

  bool playPrev() {
    if (currentIndex.value <= 0) return false;
    playIndex(currentIndex.value - 1);
    return true;
  }

  bool playNext() {
    if (currentIndex.value >= playlist.length - 1) return false;
    playIndex(currentIndex.value + 1);
    return true;
  }

  void setSpeed(double value) {
    speed.value = value;
    _player?.setRate(value);
  }

  void togglePlayMode() {
    final values = PlayRepeat.values; // 只有4个值
    final current = playMode.value;
    final index = values.indexOf(current);
    final next = values[(index + 1) % values.length];
    playMode.value = next;
    PlayerPref.playRepeat = next.index;
  }

  // ===== 音量控制 =====
  void toggleVolume() {
    if (_lastVolume == null) {
      _lastVolume = desktopVolume.value;
      setVolume(0, clearLastVolume: false);
    } else {
      setVolume(_lastVolume!);
    }
  }

  void setVolume(double volume, {bool clearLastVolume = true}) {
    if (clearLastVolume) {
      _lastVolume = null;
    }
    desktopVolume.value = volume;
    _player?.setVolume(volume * 100);
    PlayerPref.desktopVolume = volume.toPrecision(3);
  }

  void syncVolume() {
    final volume = desktopVolume.value;
    _player?.setVolume(volume * 100);
    PlayerPref.desktopVolume = volume.toPrecision(3);
  }

  // ===== 排序 =====
  void onChangeSort(AudioSortOrder order) {
    if (sortOrder.value == order) return;
    sortOrder.value = order;
    _applySort();
  }

  void _applySort() {
    switch (sortOrder.value) {
      case AudioSortOrder.normal:
        break;
      case AudioSortOrder.asc:
        playlist.sort((a, b) => a.title.compareTo(b.title));
        break;
      case AudioSortOrder.desc:
        playlist.sort((a, b) => b.title.compareTo(a.title));
        break;
      case AudioSortOrder.random:
        playlist.shuffle();
        break;
    }
    // 更新当前索引（使用 url 作为唯一标识，若无则用 title）
    final current = currentTitle.value;
    int index = playlist.indexWhere((e) => e.title == current);
    if (index != -1) {
      currentIndex.value = index;
    }
  }

  // ===== 生命周期 =====
  @override
  void onClose() {
    _subscriptions?.forEach((e) => e.cancel());
    _subscriptions?.clear();
    _player?.dispose();
    _player = null;
    animController.dispose();
    super.onClose();
  }
}
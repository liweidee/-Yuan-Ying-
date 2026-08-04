import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/models/common/enum_with_label.dart';
import 'package:yuanying/plugin/pl_player/controller.dart';
import 'package:collection/collection.dart';

enum _ShutdownType implements EnumWithLabel {
  pause('暂停视频'),
  exit('退出APP');

  @override
  final String label;
  const _ShutdownType(this.label);
}

final shutdownTimerService = ShutdownTimerService._internal();

class ShutdownTimerService {
  ShutdownTimerService._internal();

  VoidCallback? onPause;
  ValueGetter<bool>? isPlaying;

  Timer? _shutdownTimer;
  bool get isActive => _shutdownTimer?.isActive ?? false;
  int _durationInMinutes = 0;
  _ShutdownType _shutdownType = _ShutdownType.pause;

  bool _isWaiting = false;
  bool get isWaiting => _isWaiting;
  bool _waitUntilCompleted = false;

  void _stopTimer() {
    if (_shutdownTimer != null) {
      _shutdownTimer!.cancel();
      _shutdownTimer = null;
    }
  }

  void reset([int durationInMinutes = 0]) {
    _stopTimer();
    _isWaiting = false;
    _durationInMinutes = durationInMinutes;
  }

  void _startShutdownTimer(int durationInMinutes) {
    reset(durationInMinutes);
    if (durationInMinutes == 0) {
      SmartDialog.showToast('取消定时关闭');
      return;
    }
    SmartDialog.showToast('设置 ${_format(durationInMinutes)} 后定时关闭');
    _shutdownTimer = Timer(
      Duration(minutes: durationInMinutes),
      _handleShutdown,
    );
  }

  void _handleShutdown() {
    switch (_shutdownType) {
      case _ShutdownType.pause:
        final player = PlPlayerController.instanceExists() ? PlPlayerController.getInstance() : null;
final isPlaying = this.isPlaying?.call() ?? player?.playerStatus.value.isPlaying ?? false;
        if (isPlaying) {
          if (_waitUntilCompleted) {
            _isWaiting = true;
          } else {
            _durationInMinutes = 0;
            (onPause ?? player?.pause)?.call();
            SmartDialog.showToast('定时时间已到，已暂停');
          }
        }
      case _ShutdownType.exit:
        if (_waitUntilCompleted) {
          final isPlaying = this.isPlaying?.call() ??
    (PlPlayerController.instanceExists() ? PlPlayerController.getInstance().playerStatus.value.isPlaying : false);
          if (isPlaying) {
            _isWaiting = true;
            return;
          }
        }
        _syncProgressAndExit();
    }
  }

  void handleWaiting() {
    switch (_shutdownType) {
      case _ShutdownType.pause:
        _isWaiting = false;
        _durationInMinutes = 0;
        SmartDialog.showToast('定时时间已到，已暂停');
      case _ShutdownType.exit:
        _syncProgressAndExit();
    }
  }

  void _syncProgressAndExit() {
    exit(0);
  }

  static (int hour, int minute) _parseMinutes(int minutes) =>
      (minutes ~/ 60, minutes % 60);

  static String _format(int minutes) {
    if (minutes == 60) return '60分钟';
    final (int hour, int minute) = _parseMinutes(minutes);
    if (hour > 0 && minute > 0) {
      return '$hour小时$minute分钟';
    } else if (hour > 0) {
      return '$hour小时';
    } else {
      return '$minute分钟';
    }
  }

  void showScheduleExitDialog(BuildContext context) {
    const Set<int> scheduleTimeMinutes = {0, 15, 30, 45, 60};
    const TextStyle titleStyle = TextStyle(fontSize: 14);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;

        return StatefulBuilder(
          builder: (_, setState) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Material(
                color: colorScheme.surface,
                borderRadius: const BorderRadius.all(Radius.circular(12)),
                clipBehavior: Clip.hardEdge,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 8),
                    const Center(
                      child: Text('定时关闭', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                    ),
                    const SizedBox(height: 4),
                    ...{...scheduleTimeMinutes, _durationInMinutes}
                        .sorted((a, b) => a.compareTo(b))
                        .map(
                          (minutes) => ListTile(
                            dense: true,
                            onTap: () {
                              Navigator.pop(context);
                              _startShutdownTimer(minutes);
                            },
                            title: Text(
                              switch (minutes) {
                                0 => '禁用',
                                _ => _format(minutes),
                              },
                              style: titleStyle,
                            ),
                            trailing: _durationInMinutes == minutes
                                ? Icon(
                                    size: 20,
                                    Icons.done,
                                    color: theme.colorScheme.primary,
                                  )
                                : null,
                          ),
                        ),
                    ListTile(
                      dense: true,
                      onTap: () {
                        final (int hour, int minute) = _parseMinutes(_durationInMinutes);
                        showTimePicker(
                          context: context,
                          initialEntryMode: TimePickerEntryMode.inputOnly,
                          initialTime: TimeOfDay(hour: hour, minute: minute),
                          builder: (context, child) => MediaQuery(
                            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
                            child: child!,
                          ),
                        ).then((time) {
                          if (time != null) {
                            _startShutdownTimer(time.hour * 60 + time.minute);
                            setState(() {});
                          }
                        });
                      },
                      title: const Text('自定义', style: titleStyle),
                    ),
                    ListTile(
                      dense: true,
                      onTap: () {
                        setState(() {
                          _waitUntilCompleted = !_waitUntilCompleted;
                        });
                      },
                      title: const Text('额外等待视频播放完毕', style: titleStyle),
                      trailing: Transform.scale(
                        alignment: Alignment.centerRight,
                        scale: 0.8,
                        child: Switch(
                          value: _waitUntilCompleted,
                          onChanged: (value) {
                            setState(() {
                              _waitUntilCompleted = value;
                            });
                          },
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 18, bottom: 12),
                      child: Row(
                        spacing: 12,
                        children: [
                          const Text('倒计时结束:', style: titleStyle),
                          ..._ShutdownType.values.map(
                            (e) => GestureDetector(
                              onTap: () {
                                setState(() {
                                  _shutdownType = e;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _shutdownType == e
                                      ? colorScheme.secondaryContainer
                                      : colorScheme.onInverseSurface,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Text(
                                  e.label,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: _shutdownType == e
                                        ? colorScheme.onSecondaryContainer
                                        : colorScheme.outline,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
import 'dart:async';

import 'package:dlna_dart/dlna.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:yuanying/common/widgets/loading_widget/loading_widget.dart';
import 'package:yuanying/common/widgets/loading_widget/http_error.dart';
import 'package:yuanying/common/widgets/view_sliver_safe_area.dart';

class DLNAPage extends StatefulWidget {
  const DLNAPage({super.key});

  @override
  State<DLNAPage> createState() => _DLNAPageState();
}

class _DLNAPageState extends State<DLNAPage> {
  final _searcher = DLNAManager();
  final Map<String, DLNADevice> _deviceList = {};
  late final _url = Get.parameters['url']!;
  late final _title = Get.parameters['title'];
  late final _flag = Get.parameters['flag'] ?? '';

  Timer? _timer;
  bool _isSearching = false;
  DLNADevice? _lastDevice;
  String? _lastDeviceKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onSearch(isInit: true);
    });
  }

  Future<void> _onSearch({bool isInit = false}) async {
    if (_isSearching) return;
    _isSearching = true;
    if (mounted) setState(() {});
    if (!isInit && mounted) {
      _lastDevice = null;
      _deviceList.clear();
      setState(() {});
    }
    try {
      final deviceManager = await _searcher.start();
      if (!mounted) return;
      _timer = Timer(const Duration(seconds: 20), _searcher.stop);
      await for (final deviceList in deviceManager.devices.stream) {
        if (mounted) {
          _deviceList.addAll(deviceList);
          setState(() {});
        }
      }
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
        SmartDialog.showToast('投屏初始化失败: $e');
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _searcher.stop();
    _lastDevice = null;
    _lastDeviceKey = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text('投屏'),
        actions: [
          IconButton(
            tooltip: '',
            onPressed: _onSearch,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          if (_isSearching) linearLoading,
          ViewSliverSafeArea(sliver: _buildBody(colorScheme)),
        ],
      ),
    );
  }

  Widget _buildBody(ColorScheme colorScheme) {
    if (!_isSearching && _deviceList.isEmpty) {
      return HttpError(
        errMsg: '没有设备',
        onReload: _onSearch,
      );
    }
    if (_deviceList.isNotEmpty) {
      final keys = _deviceList.keys.toList();
      return SliverList.builder(
        itemCount: keys.length,
        itemBuilder: (context, index) {
          final key = keys[index];
          final device = _deviceList[key]!;
          final isCurr = key == _lastDeviceKey;
          return ListTile(
            title: Text(
              device.info.friendlyName,
              style: isCurr ? TextStyle(color: colorScheme.primary) : null,
            ),
            subtitle: Text(key),
            trailing: isCurr
                ? Icon(
                    Icons.check_circle_rounded,
                    color: colorScheme.primary,
                    size: 20,
                  )
                : null,
            onTap: () async {
              if (isCurr) return;
              _lastDevice?.pause();
              _lastDevice = device;
              _lastDeviceKey = key;
              setState(() {});
              final displayTitle = _flag.isNotEmpty ? '$_flag - $_title' : _title ?? '';
              await device.setUrl(_url, title: displayTitle);
              await device.play();
              SmartDialog.showToast('已投屏到 ${device.info.friendlyName}');
            },
          );
        },
      );
    }
    return const SliverToBoxAdapter(child: SizedBox.shrink());
  }
}
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/modules/setting/controllers/tmdb_config_controller.dart';

class TmdbMatchPage extends StatefulWidget {
  const TmdbMatchPage({super.key});

  @override
  State<TmdbMatchPage> createState() => _TmdbMatchPageState();
}

class _TmdbMatchPageState extends State<TmdbMatchPage> {
  final controller = Get.find<TmdbConfigController>();
  String _searchQuery = '';
  late List<Map<String, dynamic>> _filteredSites;

  @override
  void initState() {
    super.initState();
    _filteredSites = controller.getSites();
  }

  void _filterSites(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredSites = controller.getSites();
      } else {
        _filteredSites = controller.getSites().where((site) {
          final name = site['name']?.toString() ?? '';
          return name.toLowerCase().contains(query.toLowerCase());
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final enabledCount = controller.getEnabledCount();
    final totalCount = controller.getSites().length;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('站源 TMDB 匹配', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: colorScheme.onSurface),
          onPressed: () => Get.back(),
        ),
      ),
      body: Column(
        children: [
          // 搜索栏
          Padding(
            padding: const EdgeInsets.all(Style.safeSpace),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: _filterSites,
                    decoration: InputDecoration(
                      hintText: '搜索站源名称...',
                      prefixIcon: Icon(Icons.search, color: colorScheme.outline),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.3),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$enabledCount / $totalCount',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 列表
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: Style.safeSpace),
              itemCount: _filteredSites.length,
              separatorBuilder: (_, __) => const SizedBox(height: Style.cardSpace),
              itemBuilder: (context, index) {
                final site = _filteredSites[index];
                final key = site['key']?.toString() ?? '';
                final name = site['name']?.toString() ?? '未命名';
                final isEnabled = controller.isSiteEnabled(key);

                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
                  color: colorScheme.surface,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: TextStyle(
                              fontSize: 15,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                        Switch(
                          value: isEnabled,
                          onChanged: (v) async {
                            await controller.setSiteEnabled(key, v);
                            setState(() {});
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
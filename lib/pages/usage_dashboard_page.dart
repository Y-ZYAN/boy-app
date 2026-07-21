import 'package:flutter/material.dart';

import '../services/usage_stats_service.dart';
import '../widgets/duration_tab.dart';
import '../widgets/recent_tab.dart';

/// 使用数据仪表盘：时长排序 + 近期使用 双 Tab
class UsageDashboardPage extends StatefulWidget {
  const UsageDashboardPage({super.key});

  @override
  State<UsageDashboardPage> createState() => _UsageDashboardPageState();
}

class _UsageDashboardPageState extends State<UsageDashboardPage> {
  final _service = UsageStatsService();
  QueryResult? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.querySessions();
      if (mounted) {
        setState(() {
          _data = result;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '获取数据失败，请下拉重试';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _buildError(context);
    }
    if (_data == null || _data!.sessions.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.hourglass_bottom, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('今天还没有使用记录', style: TextStyle(color: Colors.grey)),
            SizedBox(height: 8),
            Text('先去用一下手机，再回来看吧 👀',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
          ],
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: const TabBar(
              tabs: [
                Tab(text: '时长排序'),
                Tab(text: '近期使用'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                DurationTab(data: _data!, onRefresh: _loadSessions),
                RecentTab(data: _data!, onRefresh: _loadSessions),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
          const SizedBox(height: 16),
          Text('加载失败', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            _error!,
            style: const TextStyle(color: Colors.grey, fontSize: 14),
          ),
          const SizedBox(height: 24),
          FilledButton.tonalIcon(
            onPressed: _loadSessions,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }
}

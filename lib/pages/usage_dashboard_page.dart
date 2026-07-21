import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/app_usage_session.dart';
import '../utils/format_utils.dart';

/// 使用数据仪表盘：时长排序 + 近期使用 双 Tab
class UsageDashboardPage extends StatefulWidget {
  const UsageDashboardPage({super.key});

  @override
  State<UsageDashboardPage> createState() => _UsageDashboardPageState();
}

class _UsageDashboardPageState extends State<UsageDashboardPage> {
  final _channel = const MethodChannel('usage_stats');
  List<AppUsageSession> _sessions = [];
  IconCache _icons = {};
  int _screenOffSeconds = 0;
  int _totalRecordedSeconds = 0; // 含短会话的原始总时长
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
      final raw =
          await _channel.invokeMethod<Map<dynamic, dynamic>>('queryUsageSessions');
      if (raw == null || !mounted) return;

      final rawSessions = raw['sessions'] as List<dynamic>;
      final rawIcons = raw['icons'] as Map<dynamic, dynamic>? ?? {};
      final screenOffMs = raw['screenOffMillis'] as int? ?? 0;
      final totalRecordedMs = raw['totalRecordedMillis'] as int? ?? 0;

      setState(() {
        _sessions = rawSessions
            .cast<Map<dynamic, dynamic>>()
            .map((m) => AppUsageSession.fromMap(Map<String, dynamic>.from(m)))
            .toList();
        _icons = rawIcons.map((key, value) => MapEntry(key as String, value as Uint8List?));
        _screenOffSeconds = (screenOffMs / 1000).round();
        _totalRecordedSeconds = (totalRecordedMs / 1000).round();
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  // ─── App 图标 ────────────────────────────────────────────────────────

  Widget _appIcon(String appName, String packageName, {bool active = false}) {
    final iconBytes = _icons[packageName];
    if (iconBytes != null && iconBytes.isNotEmpty) {
      return CircleAvatar(
        radius: 18,
        backgroundColor: Colors.transparent,
        child: ClipOval(
          child: Image.memory(
            iconBytes,
            width: 36,
            height: 36,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _fallbackAvatar(appName, active: active),
          ),
        ),
      );
    }
    return _fallbackAvatar(appName, active: active);
  }

  Widget _fallbackAvatar(String appName, {bool active = false}) {
    return CircleAvatar(
      backgroundColor: active
          ? Colors.green.withValues(alpha: 0.15)
          : Theme.of(context).colorScheme.primaryContainer,
      child: Text(
        appName.isNotEmpty ? appName[0].toUpperCase() : '?',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: active
              ? Colors.green
              : Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }

  // ─── 构建 ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text('加载失败', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.grey, fontSize: 12)),
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
    if (_sessions.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.hourglass_bottom, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('今天还没有使用记录', style: TextStyle(color: Colors.grey)),
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
                _buildDurationTab(),
                _buildRecentTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab 1: 按 App 汇总使用时长 ──────────────────────────────────────

  Widget _buildDurationTab() {
    // 按 appName 分组
    final Map<String, List<AppUsageSession>> grouped = {};
    for (final s in _sessions) {
      grouped.putIfAbsent(s.appName, () => []).add(s);
    }

    // 按总时长降序排列
    final sorted = grouped.entries.toList()
      ..sort((a, b) {
        final da = a.value.fold<Duration>(Duration.zero, (sum, s) => sum + s.duration);
        final db = b.value.fold<Duration>(Duration.zero, (sum, s) => sum + s.duration);
        return db.compareTo(da);
      });

    // 使用含短会话的原始总时长，而非仅过滤后的会话
    final totalDuration = Duration(seconds: _totalRecordedSeconds);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 今日总览卡片
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.access_time,
                        color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    Text('今日屏幕使用时间',
                        style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  formatDuration(totalDuration),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
                const SizedBox(height: 8),
                _buildTimeBreakdown(totalDuration.inSeconds),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        // 各 App 详情
        for (final entry in sorted) _buildAppGroupCard(entry.key, entry.value),
      ],
    );
  }

  Widget _buildAppGroupCard(String appName, List<AppUsageSession> sessions) {
    final total = sessions.fold<Duration>(Duration.zero, (sum, s) => sum + s.duration);
    // 按开始时间排序（最早的在前）
    sessions.sort((a, b) => a.startTime.compareTo(b.startTime));

    // 取该组第一个 session 的 packageName 来查图标
    final pkg = sessions.first.packageName;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ExpansionTile(
        leading: _appIcon(appName, pkg),
        title: Text(_sessionTitle(appName, sessions.first.isUninstalled),
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('总计 ${formatDuration(total)}',
            style: TextStyle(color: Colors.grey[600], fontSize: 13)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              children: sessions.map((s) => _buildSessionRow(s)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionRow(AppUsageSession s) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(formatTimeRange(s.startTime, s.endTime),
              style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 8),
          if (s.isActive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('使用中',
                  style: TextStyle(color: Colors.green, fontSize: 11)),
            ),
          const Spacer(),
          Text(formatDuration(s.duration),
              style: TextStyle(color: Colors.grey[700], fontSize: 13)),
        ],
      ),
    );
  }

  // ── Tab 2: 近期使用时间线 ──────────────────────────────────────────

  Widget _buildRecentTab() {
    // 按开始时间降序（最新的在最前）
    final sorted = List<AppUsageSession>.from(_sessions)
      ..sort((a, b) => b.startTime.compareTo(a.startTime));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final s = sorted[index];
        // 用 divider 分隔不同的 App（切换 app 时画一条分隔线）
        final prevPkg = index < sorted.length - 1 ? sorted[index + 1].appName : null;
        final showDivider = prevPkg != null && prevPkg != s.appName;

        return Column(
          children: [
            if (showDivider)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(child: Divider(color: Colors.grey[300])),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(Icons.swap_vert, size: 16, color: Colors.grey[400]),
                    ),
                    Expanded(child: Divider(color: Colors.grey[300])),
                  ],
                ),
              ),
            _buildRecentRow(s),
          ],
        );
      },
    );
  }

  /// 时间分解：已记录 + 息屏 + 其他
  Widget _buildTimeBreakdown(int recordedSeconds) {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);
    final elapsedSeconds = now.difference(midnight).inSeconds;
    final otherSeconds =
        elapsedSeconds - recordedSeconds - _screenOffSeconds;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('息屏 ${formatDuration(Duration(seconds: _screenOffSeconds))}',
            style: TextStyle(fontSize: 13, color: Colors.grey[500])),
        if (otherSeconds > 60)
          Text('其他 ${formatDuration(Duration(seconds: otherSeconds))}',
              style: TextStyle(fontSize: 13, color: Colors.grey[500])),
      ],
    );
  }

  /// App 名称，已卸载的加后缀
  String _sessionTitle(String appName, bool uninstalled) {
    return uninstalled ? '$appName (已卸载)' : appName;
  }

  Widget _buildRecentRow(AppUsageSession s) {
    final color = s.isActive ? Colors.green : Colors.grey;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        leading: _appIcon(s.appName, s.packageName, active: s.isActive),
        title: Text(_sessionTitle(s.appName, s.isUninstalled),
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(formatTimeRange(s.startTime, s.endTime)),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(formatDuration(s.duration),
                style: TextStyle(fontWeight: FontWeight.w500, color: color[700])),
            if (s.isActive)
              Text('使用中', style: TextStyle(color: Colors.green[600], fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─── 数据模型 ──────────────────────────────────────────────────────────

class AppUsageSession {
  final String packageName;
  final String appName;
  final DateTime startTime;
  final DateTime? endTime; // null = 正在使用

  AppUsageSession({
    required this.packageName,
    required this.appName,
    required this.startTime,
    this.endTime,
  });

  factory AppUsageSession.fromMap(Map<String, dynamic> map) {
    final endMs = map['endTimeMillis'] as int;
    return AppUsageSession(
      packageName: map['packageName'] as String,
      appName: map['appName'] as String,
      startTime: DateTime.fromMillisecondsSinceEpoch(map['startTimeMillis'] as int),
      endTime: endMs == -1 ? null : DateTime.fromMillisecondsSinceEpoch(endMs),
    );
  }

  Duration get duration =>
      endTime != null ? endTime!.difference(startTime) : DateTime.now().difference(startTime);

  bool get isActive => endTime == null;
}

// ─── 工具函数 ──────────────────────────────────────────────────────────

/// 格式化持续时间为「X小时Y分钟」或「X分钟」或「不到1分钟」
String formatDuration(Duration d) {
  final totalMinutes = d.inMinutes;
  if (totalMinutes <= 0) return '不到1分钟';
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (hours > 0 && minutes > 0) return '$hours小时$minutes分钟';
  if (hours > 0) return '$hours小时';
  return '$minutes分钟';
}

/// 格式化时间段起点 - 终点，如「09:00 - 09:45」
String formatTimeRange(DateTime start, DateTime? end) {
  final s = '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
  if (end == null) return '$s - 现在';
  final e = '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';
  return '$s - $e';
}

// ─── 主应用 ────────────────────────────────────────────────────────────

void main() {
  runApp(const MomGuardApp());
}

class MomGuardApp extends StatelessWidget {
  const MomGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '手机守护',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const UsageMonitorPage(),
    );
  }
}

// ─── 权限检查页面 ──────────────────────────────────────────────────────

class UsageMonitorPage extends StatefulWidget {
  const UsageMonitorPage({super.key});

  @override
  State<UsageMonitorPage> createState() => _UsageMonitorPageState();
}

class _UsageMonitorPageState extends State<UsageMonitorPage>
    with WidgetsBindingObserver {
  final _channel = const MethodChannel('usage_stats');
  bool _hasPermission = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermission();
    }
  }

  Future<void> _checkPermission() async {
    setState(() => _checking = true);
    try {
      final granted = await _channel.invokeMethod<bool>('hasUsageStatsPermission');
      if (mounted) {
        setState(() {
          _hasPermission = granted ?? false;
          _checking = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasPermission = false;
          _checking = false;
        });
      }
    }
  }

  void _openSettings() {
    _channel.invokeMethod('openUsageStatsSettings');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('手机守护'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_checking) return _buildChecking();
    if (!_hasPermission) return _buildNoPermission();
    // 权限已通过 → 仪表盘（不使用 Center/Padding 包裹）
    return const UsageDashboardPage();
  }

  Widget _buildChecking() {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.hourglass_empty, size: 80, color: Colors.grey),
        SizedBox(height: 24),
        CircularProgressIndicator(),
        SizedBox(height: 16),
        Text('正在检查权限…'),
      ],
    );
  }

  Widget _buildNoPermission() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.visibility_off, size: 80, color: Colors.redAccent),
        const SizedBox(height: 24),
        const Text(
          '❌ 未获得「使用情况访问」权限',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.redAccent),
        ),
        const SizedBox(height: 12),
        Text(
          '请授予权限以监控各 App 的使用时长',
          style: TextStyle(color: Colors.grey[600]),
        ),
        const SizedBox(height: 32),
        ElevatedButton.icon(
          onPressed: _openSettings,
          icon: const Icon(Icons.settings),
          label: const Text('前往开启权限'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          ),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: _checkPermission,
          child: const Text('已开启？点此重新检查'),
        ),
      ],
    );
  }
}

// ─── 使用数据仪表盘 ───────────────────────────────────────────────────

class UsageDashboardPage extends StatefulWidget {
  const UsageDashboardPage({super.key});

  @override
  State<UsageDashboardPage> createState() => _UsageDashboardPageState();
}

class _UsageDashboardPageState extends State<UsageDashboardPage> {
  final _channel = const MethodChannel('usage_stats');
  List<AppUsageSession> _sessions = [];
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
      final raw = await _channel.invokeMethod<List<dynamic>>('queryUsageSessions');
      if (raw == null || !mounted) return;
      setState(() {
        _sessions = raw
            .cast<Map<dynamic, dynamic>>()
            .map((m) => AppUsageSession.fromMap(Map<String, dynamic>.from(m)))
            .toList();
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
            child: TabBar(
              tabs: const [
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

    final totalDuration = _sessions.fold<Duration>(Duration.zero, (sum, s) => sum + s.duration);

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
                    Icon(Icons.access_time, color: Theme.of(context).colorScheme.primary),
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

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Text(
            appName.isNotEmpty ? appName[0].toUpperCase() : '?',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        title: Text(appName, style: const TextStyle(fontWeight: FontWeight.w600)),
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
                color: Colors.green.withOpacity(0.15),
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

  Widget _buildRecentRow(AppUsageSession s) {
    final color = s.isActive ? Colors.green : Colors.grey;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: s.isActive
              ? Colors.green.withOpacity(0.15)
              : Theme.of(context).colorScheme.primaryContainer,
          child: Text(
            s.appName.isNotEmpty ? s.appName[0].toUpperCase() : '?',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: s.isActive ? Colors.green : Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        title: Text(s.appName, style: const TextStyle(fontWeight: FontWeight.w600)),
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

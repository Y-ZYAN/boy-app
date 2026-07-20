import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  /// 从设置页面返回时自动重新检查
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermission();
    }
  }

  Future<void> _checkPermission() async {
    setState(() => _checking = true);
    try {
      final granted = await _channel
          .invokeMethod<bool>('hasUsageStatsPermission');
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
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _checking
                    ? Icons.hourglass_empty
                    : _hasPermission
                        ? Icons.visibility
                        : Icons.visibility_off,
                size: 80,
                color: _checking
                    ? Colors.grey
                    : _hasPermission
                        ? Colors.green
                        : Colors.redAccent,
              ),
              const SizedBox(height: 24),
              if (_checking)
                const Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('正在检查权限…'),
                  ],
                )
              else if (_hasPermission)
                const Column(
                  children: [
                    Text(
                      '✅ 权限已开启',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      '监控功能即将上线，敬请期待 👀',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                )
              else
                Column(
                  children: [
                    const Text(
                      '❌ 未获得「使用情况访问」权限',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.redAccent,
                      ),
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 16),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: _checkPermission,
                      child: const Text('已开启？点此重新检查'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

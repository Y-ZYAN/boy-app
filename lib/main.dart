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
      title: '手机使用监控',
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

class _UsageMonitorPageState extends State<UsageMonitorPage> {
  String _status = '正在检查权限…';

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    // 通过 MethodChannel 调用 Android 原生 API 检查使用统计权限
    // 简单版本：引导用户手动开启
    const channel = MethodChannel('usage_stats');
    bool granted;
    try {
      granted = await channel.invokeMethod('hasUsageStatsPermission');
    } catch (_) {
      // MethodChannel 还没注册 → 通过检查 setting 的方式判断
      granted = false;
    }

    if (!mounted) return;

    if (granted) {
      setState(() => _status = '✅ 权限已开启');
    } else {
      setState(() => _status = '❌ 未获得「使用情况访问」权限');
    }
  }

  void _openSettings() {
    const channel = MethodChannel('usage_stats');
    try {
      channel.invokeMethod('openUsageStatsSettings');
    } catch (_) {
      // Fallback: 直接打开设置
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请手动前往：设置 → 应用 → 特殊权限 → 使用情况访问权限')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('手机使用监控'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.visibility,
                size: 80,
                color: _status.startsWith('✅')
                    ? Colors.green
                    : Colors.grey,
              ),
              const SizedBox(height: 24),
              Text(
                _status,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 32),
              if (_status.startsWith('❌'))
                ElevatedButton.icon(
                  onPressed: _openSettings,
                  icon: const Icon(Icons.settings),
                  label: const Text('前往开启权限'),
                ),
              const SizedBox(height: 16),
              Text(
                '需要「使用情况访问」权限才能读取\n各 App 的使用时长数据',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

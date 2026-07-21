import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/enforcement_service.dart';
import 'usage_dashboard_page.dart';

/// 权限检查页面：检查「使用情况访问权限」，通过后跳转到仪表盘
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
      final granted =
          await _channel.invokeMethod<bool>('hasUsageStatsPermission');
      if (mounted) {
        setState(() {
          _hasPermission = granted ?? false;
          _checking = false;
        });
      }
      // 权限通过后自动启动后台监控（需悬浮窗权限）
      if (_hasPermission) {
        _ensureMonitoring();
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

  /// 确保监控服务已启动；未授权悬浮窗则跳转设置
  Future<void> _ensureMonitoring() async {
    // 已在运行就不重复启动
    if (await EnforcementService.isMonitoringActive()) return;
    // 等 Widget 树渲染完再弹对话框，避免 BuildContext 未就绪
    await Future<void>.delayed(Duration.zero);

    final hasOverlay = await EnforcementService.checkOverlayPermission();
    if (!hasOverlay && mounted) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('需要悬浮窗权限'),
          content: const Text('为了在 App 超限时弹出提醒，需要授予「在其他应用上层显示」权限。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('跳过'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('去授权'),
            ),
          ],
        ),
      );
      if (go == true) {
        await EnforcementService.openOverlaySettings();
      } else {
        // 用户跳过 → 仍尝试启动（无遮挡功能）
        await EnforcementService.startMonitoring();
      }
      return;
    }
    await EnforcementService.startMonitoring();
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

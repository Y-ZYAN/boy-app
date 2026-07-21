import 'package:flutter/material.dart';

import 'pages/usage_monitor_page.dart';

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

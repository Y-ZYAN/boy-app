import 'package:flutter_test/flutter_test.dart';

import 'package:boy_app/main.dart';

void main() {
  testWidgets('App launches without error', (WidgetTester tester) async {
    await tester.pumpWidget(const MomGuardApp());

    // 验证权限检测页正常显示
    expect(find.text('手机守护'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:tide_bot/permission_management_page.dart';
import 'package:tide_bot/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const native = MethodChannel('tidebot.native.channel');
  const permissions = MethodChannel('flutter.baseflow.com/permissions/methods');
  final statuses = <int, int>{};
  final checked = <int>[];
  var sdk = 34;
  setUp(() {
    statuses.clear();
    checked.clear();
    sdk = 34;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            native,
            (call) async => {
                  'sdkInt': sdk,
                  'usageAccess': true,
                  'notificationAccess': false,
                  'installPackages': false,
                });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissions, (call) async {
      if (call.method == 'checkPermissionStatus') {
        checked.add(call.arguments as int);
        return statuses[call.arguments] ?? 0;
      }
      if (call.method == 'requestPermissions') {
        return {for (final id in call.arguments as List) id: statuses[id] = 1};
      }
      return true;
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(native, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissions, null);
  });
  Future<void> show(WidgetTester tester) async {
    final theme = TideTheme();
    addTearDown(theme.dispose);
    await tester.pumpWidget(TideBotThemeProvider(
        theme: theme,
        child: const MaterialApp(home: PermissionManagementPage())));
    await tester.pumpAndSettle();
  }

  testWidgets('电池优化打开专用授权入口并在返回后刷新', (tester) async {
    String? requestedKind;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(native, (call) async {
      if (call.method == 'openPermissionSettings') {
        requestedKind = (call.arguments as Map)['kind'] as String;
        return null;
      }
      return {'sdkInt': 34};
    });
    await show(tester);
    final row =
        find.ancestor(of: find.text('忽略电池优化'), matching: find.byType(ListTile));
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(requestedKind, 'battery');
    statuses[Permission.ignoreBatteryOptimizations.value] = 1;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(
        find.descendant(of: row, matching: find.text('已授权')), findsOneWidget);
  });
  testWidgets('未授权可申请，授权后显示打勾状态', (tester) async {
    await show(tester);
    final row =
        find.ancestor(of: find.text('麦克风权限'), matching: find.byType(ListTile));
    await tester.ensureVisible(row);
    expect(
        find.descendant(of: row, matching: find.text('去授权')), findsOneWidget);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(
        find.descendant(of: row, matching: find.text('已授权')), findsOneWidget);
    expect(
        find.descendant(
            of: row, matching: find.byIcon(Icons.check_circle_rounded)),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('刷新后识别相册部分授权，不误显示完整授权', (tester) async {
    statuses[Permission.photos.value] = 3;
    await show(tester);
    final row =
        find.ancestor(of: find.text('相册权限'), matching: find.byType(ListTile));
    await tester.ensureVisible(row);
    expect(
        find.descendant(of: row, matching: find.text('部分授权')), findsOneWidget);
    statuses[Permission.photos.value] = 1;
    await tester.tap(find.byTooltip('刷新权限状态'));
    await tester.pumpAndSettle();
    expect(
        find.descendant(of: row, matching: find.text('已授权')), findsOneWidget);
  });
  testWidgets('旧版 Android 相册使用存储授权，小屏布局不溢出', (tester) async {
    sdk = 32;
    statuses[Permission.storage.value] = 1;
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await show(tester);
    final row =
        find.ancestor(of: find.text('相册权限'), matching: find.byType(ListTile));
    await tester.ensureVisible(row);
    expect(
        find.descendant(of: row, matching: find.text('已授权')), findsOneWidget);
    expect(checked, contains(Permission.storage.value));
    expect(tester.takeException(), isNull);
  });
}

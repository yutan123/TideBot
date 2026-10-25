import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/link_preview_cards.dart';
import 'package:tide_bot/link_preview_models.dart';
import 'package:tide_bot/theme.dart';

void main() {
  testWidgets('展开原文保留原始短链和分享文字，收起不跳转平台', (tester) async {
    const original = '这是分享原文 https://v.douyin.com/original/';
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
          body: Center(
              child: VideoShareCard(
        data: LinkPreviewData(
            url: 'https://www.douyin.com/video/123',
            title: '分享的视频',
            type: LinkType.douyin),
        isUser: true,
        originalText: original,
      ))),
    ));
    expect(find.text(original), findsNothing);
    await tester.tap(find.text('展开分享原文'));
    await tester.pump();
    expect(find.text(original), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('收起分享原文'));
    await tester.pump();
    expect(find.text(original), findsNothing);
    expect(tester.takeException(), isNull);
  });
  for (final width in [320.0, 430.0, 900.0]) {
    testWidgets('缺封面卡片在 $width 宽度下保持紧凑且文字不溢出', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final theme = TideTheme();
      addTearDown(theme.dispose);
      await tester.pumpWidget(TideBotThemeProvider(
        theme: theme,
        child: MaterialApp(
            home: Scaffold(
                body: Align(
          alignment: Alignment.topRight,
          child: MediaQuery(
            data: MediaQueryData(
                size: Size(width, 900),
                textScaler: const TextScaler.linear(1.4)),
            child: const VideoShareCard(
              data: LinkPreviewData(
                  url: 'https://v.douyin.com/abc/',
                  title: '这是一个较长的视频标题，检查标题在小屏幕中的折行与卡片高度',
                  type: LinkType.douyin),
              isUser: true,
            ),
          ),
        ))),
      ));
      await tester.pump();
      final size = tester.getSize(find.byType(VideoShareCard));
      expect(size.width, lessThanOrEqualTo(260));
      expect(size.height, lessThan(280));
      expect(find.text('封面暂不可用 · 点击打开'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

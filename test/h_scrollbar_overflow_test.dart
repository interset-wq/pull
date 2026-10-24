import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader/src/ui/h_scrollbar.dart';

void main() {
  testWidgets('超宽内容首帧后回调溢出量（自然宽 − 视口宽）', (tester) async {
    double? overflow;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: HScrollbar(
                onOverflow: (v) => overflow = v,
                child: const SizedBox(width: 3000, height: 50),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(); // post-frame 回调执行
    expect(overflow, closeTo(2600, 1));
  });

  testWidgets('无溢出回调 0', (tester) async {
    double? overflow;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: HScrollbar(
                onOverflow: (v) => overflow = v,
                child: const SizedBox(width: 100, height: 50),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(overflow, 0.0);
  });
}

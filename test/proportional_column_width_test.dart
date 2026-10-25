import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader/src/ui/proportional_column_width.dart';

void main() {
  testWidgets('wrap 档列宽按内容比例分摊，窄列不再均分拉宽', (tester) async {
    final wide = '汉' * 120; // 自然宽度远超容器宽，触发比例压缩
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 600,
              child: Table(
                defaultColumnWidth: const ProportionalColumnWidth(),
                border: TableBorder.all(),
                children: [
                  TableRow(children: [
                    const KeyedSubtree(
                      key: ValueKey('narrow'),
                      child: Text('序号'),
                    ),
                    KeyedSubtree(
                      key: const ValueKey('wide'),
                      child: Text(wide),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final narrowCell = tester.renderObject<RenderBox>(find.byKey(const ValueKey('narrow')));
    final wideCell = tester.renderObject<RenderBox>(find.byKey(const ValueKey('wide')));

    // 两列自然宽约 1:120，等宽方案是 300:300；比例分摊下窄列应远小于宽列
    expect(narrowCell.size.width, lessThan(wideCell.size.width / 5),
        reason: '窄列 ${narrowCell.size.width} vs 宽列 ${wideCell.size.width}');
    // 总宽被约束在容器内（换行生效，不横向溢出）
    expect(narrowCell.size.width + wideCell.size.width, lessThanOrEqualTo(600.5));
  });

  testWidgets('全空内容列不参与分摊（回退固有宽度，不崩）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 600,
              child: Table(
                defaultColumnWidth: const ProportionalColumnWidth(),
                children: const [
                  TableRow(children: [
                    KeyedSubtree(
                      key: ValueKey('empty'),
                      child: SizedBox.shrink(),
                    ),
                    KeyedSubtree(
                      key: ValueKey('content'),
                      child: Text('内容'),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final empty = tester.renderObject<RenderBox>(find.byKey(const ValueKey('empty')));
    final content = tester.renderObject<RenderBox>(find.byKey(const ValueKey('content')));
    expect(empty.size.width, greaterThanOrEqualTo(0));
    expect(content.size.width, greaterThan(0));
  });

  testWidgets('列宽下限：两位序号列停在下限，不再被比例分摊压到换行', (tester) async {
    const floor = 48.0; // 约等于 2 个汉字 + 单元格水平内边距
    final wide = '汉' * 120;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 600,
              child: Table(
                defaultColumnWidth: const ProportionalColumnWidth(
                  minCellWidth: floor,
                ),
                border: TableBorder.all(),
                children: [
                  TableRow(children: [
                    const KeyedSubtree(
                      key: ValueKey('narrow'),
                      child: Text('01'),
                    ),
                    KeyedSubtree(
                      key: const ValueKey('wide'),
                      child: Text(wide),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final narrowCell = tester.renderObject<RenderBox>(find.byKey(const ValueKey('narrow')));
    // 收缩后窄列停在下限（允许亚像素误差），"01" 单行放下
    expect(narrowCell.size.width, greaterThanOrEqualTo(floor - 0.5),
        reason: '窄列宽 ${narrowCell.size.width} 应 >= 下限 $floor');
  });
}

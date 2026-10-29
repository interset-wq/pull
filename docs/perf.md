# 渲染性能基线

> 2026-10-29 首次测量（阶段 1.1/1.2）。设备：DIO AN00（Android 12，1080×2289），
> profile 模式，`flutter drive` 跑 `integration_test/render_perf_test.dart`。
> 样本是脚本生成的混合长文（标题 / 中英段落 / 列表 / 围栏代码 / 表格 /
> 折叠块），不含 Mermaid 与图片（它们本来就走按需加载）。

## 怎么复现

```bash
# 全档位（会先跑一次 200 行热身，避免冷启动污染）
flutter drive --profile -d <deviceId> \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/render_perf_test.dart

# 只看某一档（内存数字更干净）
flutter drive --profile -d <deviceId> --dart-define=PERF_SIZES=10000 \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/render_perf_test.dart
```

结果同时打印为 `PERF|...` 日志行，并写入 `temp/perf_response.json`。

指标定义：

- `firstFrameMs`：从挂载阅读页到首屏出现正文标记的墙钟时间（含读文件、
  解析、布局、首次上屏）。
- `p50/p95`：连续快速上滑 30 次期间，build + raster 帧耗时的分位数。
- `jank%`：帧耗时 > 16.7ms 的比例。
- `rssΔ`：挂载前 → 滚动后的进程 RSS 增量；同一进程里连续跑多档时会有
  前序文档的内存残留，单档干净值请用 `PERF_SIZES` 单独跑。

## 基线（懒渲染改造前：整篇一次性布局）

| 行数 | 体积 | 首帧 | 滚动 p50 | 滚动 p95 | 掉帧 | RSS 增量 |
|---|---|---|---|---|---|---|
| 500 | 14KB | 315ms | 9.7ms | 12.7ms | 3.3% | +14MB |
| 1000 | 28KB | 499ms | 10.2ms | 11.9ms | 3.3% | +29MB |
| 2000 | 57KB | 1048ms | 9.6ms | 11.5ms | 0% | +47MB |
| 5000 | 142KB | 2301ms | 6.0ms | 9.1ms | 1.6% | +150MB |
| 10000 | 285KB | 4473ms | 6.1ms | 10.6ms | 3.3% | +261MB |

拆开看 5000 / 10000 行：`MarkdownGenerator.buildWidgets`（解析 + 建 Widget）
只占 285~643ms，也就是 **首帧的 85% 花在布局整篇 Column 上**——懒渲染才有意义。

## 改造后（正文按块进 SliverList，导出长图时切回整篇布局）

| 行数 | 首帧 | 滚动 p50 | 滚动 p95 | 掉帧 | RSS 增量 |
|---|---|---|---|---|---|
| 500 | 139ms | 15.8ms | 24.1ms | 43.1% | ≈0 |
| 1000 | 205ms | 12.9ms | 21.2ms | 38.3% | +3MB |
| 2000 | 392ms | 9.1ms | 20.4ms | 31.1% | +11MB |
| 5000 | 459ms | 14.5ms | 19.9ms | 33.3% | +7MB |
| 10000 | 802ms | 9.0ms | 20.4ms | 32.8% | +7MB |

结论：

1. **首帧 2~5.6 倍改善**：5000 行 2.3s → 0.46s；10000 行 4.5s → 0.8s。
   典型 500~1000 行的笔记从 0.3~0.5s 降到 0.14~0.2s。
2. **内存不再随文档线性增长**：10000 行的常驻增量从 +261MB 降到 +7MB
   （只构建视口附近的块）。
3. **代价是滚动时要现构建新块**：快速连续拖动时掉帧率从 1~3% 升到约 33%，
   但 p95 只有约 20ms（≈50fps），不是卡死；正常阅读速度下观感可接受。
   若要继续压，方向是解析结果缓存、预构建下几屏、给代码块/表格加延迟构建，
   不再回到整篇布局。
4. 首帧的下限现在是解析本身（10000 行约 0.6s 的 `buildWidgets`），
   再往下要走「按块增量解析」，属于另一个项目。

## 已知取舍（改动时的护栏）

- 长图导出必须走 `_eagerForCapture` 的一次性布局：RepaintBoundary 只能截到
  已构建的块，懒列表会截出半张图。
- 目录跳转依赖 `scroll_to_index`：每个条目都挂了 `AutoScrollTag`（连续索引），
  标题只记录自己在列表里的槽位（`_headingSlots`）。只给标题挂稀疏索引时，
  估算会算错位置、跳转落空。
- `maxScrollExtent` 在懒列表下是估算值：跳到文末要补齐几次（`_scrollToBottom`
  的循环），顶部进度条也基于这个估算值。
- 续读定位优先标题锚点；锚点没构建时走 `scrollToIndex`，再对齐标题顶部。

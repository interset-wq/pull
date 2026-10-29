# Roadmap · 接手后的开发计划（第三轮）

> 2026-10-29 接手。上一轮的 A/B/C 批次（CI、存储页、克隆进度、搜索增强、目录名标签）
> 已全部交付，明细见 git 历史与 [Roadmap.md](Roadmap.md)。本文件是之后的主计划：
> 不再按「功能清单」排，而是按**日常使用的三个时刻**排。
>
> 推进方式：一项一个原子提交；`flutter analyze --fatal-infos` + `flutter test` 全绿；
> 交互改动在真机（DIO AN00）实测后再合；push / tag / 发版先经作者同意。

## 一、现状基线（2026-10-29 核实）

| 项 | 值 |
|---|---|
| 代码 | main，工作区干净（本轮文档提交尚未推送）；版本号与 tag 一致 |
| 版本 | 1.10.5+15 |
| 检查 | analyze 零问题，156 个测试全绿 |
| CI | PR / main push 跑 analyze + test |
| 设备 | DIO AN00 在线，可装包实测 |

## 二、判断：功能面已经够，剩下的是「三个时刻」

1. **打开 app 时：有没有新东西可读？** 现在只有仓库卡的「同步于」和仓库页里的角标，
   跨仓库的「这次同步带来了什么」看不见——`RepoMeta.recentChanges` 记了数据，却没有出口。
2. **读的时候：顺不顺、看不看得见？** 正文整篇一次性布局
   （`SingleChildScrollView` + `Column`，`markdown_viewer.dart:1569`），长文性能从未测过；
   `.ipynb` 的图表与表格只有一行占位（`ipynb.dart:89`）；代码文件没有大纲，只能滚。
3. **读完之后：想回头找一段，回不回得去？** 只有整篇的收藏与阅读进度，没有段落级书签；
   检索只支持单串匹配（`text_search.dart:52`），两个词一起查收窄不了结果。

本轮四个主题：**渲染地基 → 同步闭环 → 书签 → 代码与检索**，工程债并行。

## 三、阶段与验收

### 阶段 1 · 渲染地基（P0，约 1 周）

- [x] **1.1 长文基线**：2k / 5k / 10k 行三档样本，profile 模式在真机上量首帧、
  掉帧、滚动 fps、峰值内存；数字写进 `docs/perf.md`。结论：整篇一次性布局时
  首帧约 0.45ms/行（5000 行 2.3s、10000 行 4.5s），其中解析只占 15%，
  其余全是布局；内存随行数线性涨（10000 行 +261MB）。
- [x] **1.2 分块渲染**：正文按块进 `SliverList`，只构建视口附近的块；
  长图导出切回 `_eagerForCapture` 一次性布局；目录跳转改用连续条目索引 +
  `AutoScrollTag`，标题记 `_headingSlots` 槽位。实测 5000 行首帧 2.3s→0.46s、
  10000 行 4.5s→0.8s，内存增量 261MB→7MB；代价是快速拖动掉帧率
  1~3%→约 33%（p95 约 20ms），见 `docs/perf.md` 的取舍一节。
- [x] **1.3 Notebook 富输出**：`image/png|jpeg|gif|svg` 解码后按内容哈希存内存
  （`IpynbImageStore`，64MB 上限），正文只留 `pullread-ipynb://<hash>` 短引用；
  有图时丢弃 matplotlib 的 `<Figure ...>` 占位；`text/html` 简单表格降级成
  Markdown 表格（pandas），复杂表格回退 `text/plain`。`ipynb.dart` 补齐了
  9 个单测 + 1 个渲染页 widget 测试。
- *验收*：10k 行首帧明显改善，或给出「不改架构」的数据理由；notebook 图表可见；
  既有测试仍全绿，并新增切块/转换的单测。（阶段 1 全部完成）

### 阶段 2 · 同步闭环（P0，约 1 周半）

- [x] **2.1 拉取进度**：`pull()` 改为 `Isolate.spawn` + `ReceivePort`（进度/结果/错误
  三种消息），isolate 内 `Remote.fetch(transferProgress:)` 回报对象与字节；仓库页
  「同步」与「全部更新」都显示进度对话框。批量与静默拉取补写 `syncedAt` /
  `recentChanges`（此前只有单仓库 pull 写）。
- [x] **2.2 跨仓库更新聚合**：首页 inbox 图标带未读数，`UpdatesPage` 按仓库/镜像分组
  列出新增/修改文件；点开即读并清除该条，支持「全部已读」。打开文件统一走
  `open_note.dart`，仓库页与收件箱共用同一套路由。
- [x] **2.3 仓库页阅读状态**：文件行尾部显示「读到 N% / 已读完」，工具栏「仅看未读」
  隐藏有阅读记录的文件（读到一半算读过）；数据由 `RepoMeta.readAllProgress` 一次读出。
- *验收*：200MB 仓库更新时能看到进度；更新后首页显示「N 篇新内容」，读过的自动消失；
  200 篇笔记的仓库能一屏看出哪些没读。（3 项均已完成，2 个新测试文件覆盖
  本地 pull 快进与收件箱交互）

### 阶段 3 · 书签（P1，约 1 周）

- [x] **3.1 段内书签**：阅读页菜单「在此处加书签」，记录章节标题 + 全篇滚动比例，
  存 `RepoMeta.bookmarks`（单仓库 100 条、同文件 1% 内去重）；本文书签面板可跳转/删除。
- [x] **3.2 书签入口**：首页「书签」横滑条（最近 5 条）+ `BookmarksPage` 跨仓库分组
  列表；点开用 `initialFraction` 直接落到位置，跳过续读恢复。
- *验收*：加书签 → 退出重进 → 跳回误差不超过一屏；书签随仓库删除一并清理。
  （5 个元数据用例 + 3 个 UI 用例覆盖）

### 阶段 4 · 代码与检索（P1，约 1 周）

- [x] **4.1 代码大纲**：`code_outline.dart` 用正则抽 Dart/Python/JS-TS/Java-Kotlin/Go/Rust/
  C-Cpp/shell/yaml 的类与函数（最多 500 条）；AppBar 大纲面板跳行，当前行随滚动高亮。
- [x] **4.2 代码内查找 + 自动换行开关**：复用 `findTextMatches` 的查找条（计数 + 上/下一处），
  AppBar 换行开关（开启后隐藏行号列，长行不再只能横向拖）。
- [x] **4.3 检索质量**：空格/全角空格拆词的多词 AND；摘要改为多区间高亮
  （`SearchSnippet.highlights`）；排序「路径命中全部词 → 命中次数 → 路径」。
- *验收*：1000 行源码能跳到函数；两个中文词能收窄结果；AND 与排序有单测。
  （9 个提取用例 + 3 个查看器用例 + 检索 AND/排序用例）

### 阶段 5 · 工程与平台（P0，约 1 周）

- [x] **5.1 克隆不猜分支**：`Repository.clone` 不再传 `checkoutBranch`（libgit2 检出远端
  HEAD），删掉「删目录重克隆」的 fallback；克隆后用 `readHeadBranch` 把真实分支写进
  meta。避免默认分支非 `main` 的仓库下载两遍。
- [ ] **5.2 依赖治理**：保留 `shared_preferences 2.3.2` 的锁（2.5.x 的 Pigeon/JNI 在部分
  设备上 `getAll` 不返回，见 `c659292`）；删零引用的 `cupertino_icons`；升 `flutter_svg`；
  `flutter pub upgrade` 解锁传递依赖。
- [ ] **5.3 测试补齐**（按数据完整性排序）：`markdown_editor`、`app_prefs`、`dir_size`、
  `pull_progress`、`global_search_page`（历史/过滤/仅标题）、`storage_page`。
- [ ] **5.4 拆巨石**：`markdown_viewer.dart` 3308 行、`home_page.dart` 2634 行——先搬纯
  函数、再搬独立渲染组件、最后拆 `RepoPage` 与阅读页控制器；目标 <1500 / <1200 行。
- [ ] **5.5 平台与 CI**：删掉无人调用的四个平台 adapter + factory（克隆只依赖 URL）；
  `guessPlatform` 补 GitLab 与通用「其他」；剪贴板识别放宽到任意仓库 URL；CI 增加
  `flutter build apk --debug` job，挡 Android 清单/插件回归。
- [ ] **5.6 iOS**：没有 Mac 硬件，冻结；只记录恢复条件（macOS + 真机 + 备选图标 API 验证）。
- *验收*：每项独立提交；analyze + 全量测试全绿；5.5 后 CI 的构建 job 能跑通；
  阶段结束发 1.11.0。

## 四、候选池（不排期）

- **划线/高亮**：`markdown_widget` 的文本节点无法稳定映射回源码偏移，风险高，先不做。
- **图片长按保存/分享**（`gal` 已在依赖里）。
- **后台定时同步**（Android WorkManager）：依赖电池策略，先观察。
- **中文排版微调**：段间距 / 首行缩进的开关。

## 五、边界（本轮不碰）

- 私有仓库鉴权、双链/图谱、协作、静态站、TTS、阅读统计、PDF 导出
  （PDF 的移除决定记录在 [Roadmap.md](Roadmap.md) 的边界一节）。
- 仓库内文件编辑/提交（本地镜像 md 编辑除外）。

## 六、发版节奏

每完成一个阶段合入 main 并发一个 minor（修复走 patch）；push / tag 前询问作者，
Release 只经 GitHub Actions 由 tag 触发，不手动上传 APK。

阶段 1–5 完成后发 **1.11.0**（2026-10 作者已确认），发版 = 改 `pubspec.yaml`
version → 提交 → 打同名 tag 推送。


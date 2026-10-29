# Roadmap · Agent 视角 · 第二阶段

> 接续 [Roadmap.agent.md](Roadmap.agent.md)（第一轮批次 1–4 全部交付，v1.10.x 已发）。
> 本文件是第二轮计划，按「代码事实」而非「愿望清单」排出，与作者的
> [Roadmap.md](Roadmap.md) 并存。结构沿用上代交接时给出的四线划分：
> **先补齐一致性 → 再做离线/空间 → 啃检索硬骨头 → 平台与遗留项**。
> 推进方式：每项一个原子提交，`flutter analyze` + `flutter test` 全绿才算完，
> 交互改动在真机（DIO AN00）上装包实测后再合。

## 现状基线（2026-10-29 核实）

- main 在 `0ce6787`，与 origin/main 齐平；工作区干净；最新发版 v1.10.5+15
- 115 个测试全绿，`flutter analyze --fatal-infos` 零问题
- PR/main 的 CI 已上线（`.github/workflows/ci.yml`）
- 第一轮「打开 → 读 → 翻页 → 找」与第二轮 A/B/C 批次均已交付并在真机（DIO AN00）实测，
  交付明细见各原子提交与 `Roadmap.md`

## 判据（仍存在的缺口）

| 缺口 | 证据 | 影响 |
|---|---|---|
| 正文整篇一次性布局 | `markdown_viewer.dart` 用 `SingleChildScrollView` + `Column`，无懒加载 | 几千行笔记首帧与滚动偏重，无基线数据 |
| Notebook 富输出缺失 | `ipynb.dart` 对 `image/png`、`text/html` 只输出「暂不支持」占位 | matplotlib 图表、pandas 表格在 `.ipynb` 里看不到 |
| 代码查看无大纲 | `code_viewer.dart` 只有行号与高亮 | 长代码文件只能滚，无结构导航 |
| 导出缺 PDF | 长图 / 分享卡片已交付，PDF 未做 | 分享整篇文档的通用格式缺一档 |
| iOS 未冒烟 | 本地文件夹走桌面分支；图标切换 iOS 未实现 | 双端承诺未闭环 |

## 批次 A · 一致性与护栏（先做，1–2 天）

- [x] **A1 PR CI**：`.github/workflows/ci.yml`（Ubuntu + Flutter 3.47.4）跑
  `flutter analyze --fatal-infos` + `flutter test`，PR 与 main push 均触发。
- [ ] **A2 长文渲染性能基线**：用几千行的真实笔记在 profile 模式测首帧与滚动
  jank（帧耗时数据），据此决定「分块渲染」还是只延后构建重型块
  （mermaid/长代码/大表格）。只测量与记录，方案另立项。
  *验收*：有可复现的基线数字与结论，写回本文件。
- [x] **A3 更新后的阅读感知**：pull 之后标出哪些文章是新/改的，避免整仓重读。
  复用 `checkRemote()` 的 commit 区间（fetch 后 `RevWalk`），isolate 内
  diff 新旧头取变更文件清单，与 `NoteIndexCache` 合并后在仓库页/文章列表
  打标。*验收*：pull 完进仓库页能看出新增与更新，无需重扫。

## 批次 B · 离线与空间（3–5 天）

- [x] **B1 存储占用页**：设置「数据」下显示 repos / 本地镜像 / imgcache /
  元数据各占多少，单项清理带确认；imgcache 清理走 `image_cache.dart` 现有
  目录约定。*验收*：能看出 200MB 花在哪、能删。
- [x] **B2 克隆/拉取进度**：isolate 内 `transferProgress`（对象数/字节）经
  `SendPort` 回报，UI 显示进度；clone 提供取消（复用现有 kill + 清理路径）。
  *验收*：200MB 仓库克隆有进度且能取消，取消后无半成品残留。
  *测试*：进度解析逻辑纯单测。

## 批次 C · 检索补全（5–8 天）

- [x] **C1 搜索增强**：历史记录（本地持久化）、按仓库过滤、
  「正文 / 仅标题」模式。
- [x] **C2 标签可用性**：目录名当隐式标签（设置开关，默认开）解决没写
  front-matter 的仓库；未越界到双链/图谱。

## 批次 D · 平台与遗留（按需，不排期）

- [ ] **D1 iOS 冒烟**：本地文件夹选择器（当前走桌面 `getDirectoryPath` 分支）、
  备选图标 API 真机验证——项目级工作量，另起分支。
- [ ] **D2 代码查看器大纲**：正则提取 def/class/function/section，侧栏跳行。
- [ ] **D3 导出 PDF**：作者 Roadmap 最后一项，工程量大，等 A–C 稳定后再排。

## 非目标（沿用作者边界）

私有仓库鉴权、仓库内编辑并提交（本地 md 编辑除外）、双链/图谱、协作、
静态站生成、TTS、阅读统计。本轮不碰，也不为「功能多」重新评估。

## 发版节奏

沿用现有约定：合并 → 改 pubspec `version` → 提交 → 推 `v*` tag →
GitHub Actions 构建 arm64 APK 并创建 Release；禁止手动传 APK。
push 与打 tag 均需作者明确同意。

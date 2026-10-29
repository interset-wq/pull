# AGENTS.md

本地 git 仓库阅读器：把 GitHub / Gitee / GitCode（即 AtomGit）上的笔记仓库克隆到手机，提供原生阅读器体验——Markdown/Notebook 渲染、代码高亮、文章 TOC、目录树浏览；只读，不做编辑提交。零部署、零构建托管。

## 技术栈与选型（已定，勿擅自更换）

- **框架**：Flutter（iOS + Android 双端），Dart 3 / Flutter 3.47+；另含 windows 桌面平台用于本机预览
- **包名**：`com.intersetwq.pullread`（Android applicationId/namespace、iOS bundleId 同一标识；
  Kotlin `MainActivity` 位于 `android/app/src/main/kotlin/com/intersetwq/pullread/`。
  2026-10 由 `com.intersetwq.reader` 更名而来，旧包不覆盖升级、数据不迁移）
- **应用图标切换**：桌面图标可在设置页五选一（摊开书/页即箭/抽页成箭/汇页箭/页堆箭，
  松绿 × 纸白）。Android 用五个 `activity-alias`（同一时刻仅启用一个，经 `PackageManager`
  `setComponentEnabledSetting` 切换，MethodChannel `app_icon`）；自适应图标前景
  `drawable-xxxhdpi/ic_launcher_fg_*.png`（mark 主尺寸归一 432px 的 50%，**XML inset 必须为
  0%**；过大≈66% 会顶满无留白，过小≈33% 加 16% inset 时只占约 1/9）+ 背景 `@color/brand_paper`；闪屏同纸白底。
  iOS/Windows 未实现（iOS 备选图标 API 需真机验证，Windows 无此概念）；
  通道缺失的平台上 `setAppIcon` 仅持久化偏好、静默忽略。
- **git 层**：libgit2 FFI（git2dart），仅用克隆/pull 只读能力；这是本项目最大技术风险点，改动同步层前先做小验证。
  - **Android 硬约束**：git2dart 静态链接的 OpenSSL 无法访问系统证书库，`main()` 必须在 `runApp` 前依次执行 `WidgetsFlutterBinding.ensureInitialized()` → `Libgit2.version`（初始化 libgit2）→ `AndroidSSLHelper.initialize()` → `Libgit2.setSSLCertLocations(file:)`，否则 HTTPS 克隆报 "the SSL certificate is invalid"（CA 证书包随 git2dart_binaries 打包，无需自备）。
  - **isolate 硬约束**：git 操作在后台 isolate 执行（大仓库不卡 UI）；isolate 内捕获 git2dart 原生异常后必须转普通 `Exception` 再抛（原生错误对象不可跨 isolate 发送，直接抛出会导致 Future 永不完成、UI 死转）。pull 用 `Isolate.run`；**clone 用 `Isolate.spawn` + `ReceivePort`**，超时 5 分钟时 `Isolate.kill` 并清理目标目录——`Isolate.run(...).timeout()` 只会让 Future 超时，isolate 继续写盘留下半成品目录，重试报「本地目录已存在」。clone 支持**进度与取消**：isolate 内 `Callbacks.transferProgress` 把对象数/字节经 port 回传（`[0, received, total, bytes]` 消息），UI 显示百分比与已下载体积；`CloneCancelToken.cancel()` 在下一条进度消息时生效（传输是阻塞原生调用，无法即时打断），取消路径复用 kill + 清理目录的 finally 逻辑。
  - **构建陷阱**：`INTERNET` 权限必须声明在 `android/app/src/main/AndroidManifest.xml`——Flutter 模板默认只加在 debug/profile 变体，release 包无网络权限，所有 HTTPS 请求报 `GIT_ERROR_NET: No address associated with hostname`。
  - **dev 启动与图标 alias**：正式包把启动入口放在 `activity-alias`（桌面图标五选一），而 Flutter 工具只认 `<activity>` 上的 MAIN/LAUNCHER，`flutter run` / `flutter drive` 会报 `package identifier or launch activity not found`。因此 `android/app/src/debug/AndroidManifest.xml` 与 `src/profile/AndroidManifest.xml` 各有一份覆盖清单：给 `MainActivity` 挂启动 intent-filter、移除五个 alias。release 不读这两个目录，**图标切换只能在 release 包上验收**；改图标相关逻辑时不要动这两份清单。
- **Markdown 渲染**：markdown_widget + 代码高亮；GFM alert（`> [!NOTE]` 等）与 .ipynb（Jupyter）转 Markdown 渲染
  - **Notebook 富输出**（`lib/src/notes/ipynb.dart` + `ipynb_images.dart`）：代码输出里的 `image/png|jpeg|gif|svg` 解码后按内容哈希存内存（`IpynbImageStore`，64MB 上限、近似 LRU），正文只留 `pullread-ipynb://<hash>` 短引用——绝不把 base64 写进正文（否则复制全文、文内查找、TOC 行号都会被污染）；有图时丢弃 matplotlib 的 `<Figure ...>` 文本占位。`text/html` 的简单表格（无 colspan/rowspan、≤100 行 ≤30 列）降级成 Markdown 表格，解析不了回退 `text/plain`。正文检索用 `toMarkdown(includeImages: false)`，不解码图片。
  - **长文懒渲染**（`lib/src/ui/markdown_viewer.dart`）：正文按块进 `SliverList`，只构建视口附近的块，首帧与内存只和屏高有关——5000 行首帧 2.3s→0.46s、内存增量 150MB→7MB、10000 行 4.5s→0.8s（数字与复现方式见 `docs/perf.md`）。两条硬约束：① 长图导出必须切回 `_eagerForCapture` 的整篇一次性布局，否则 RepaintBoundary 只能截到已构建的块；② 目录跳转依赖 `scroll_to_index` 的**连续条目索引**（每个块都挂 `AutoScrollTag`，标题用 `_headingSlots` 记槽位），改回只给标题挂稀疏锚点会让远距离跳转算错位置。
  - **远程图片缓存**（`lib/src/ui/image_cache.dart`）：网络图先读磁盘缓存，命中立即出图（离线可读，不再等 30s 超时）；URL 经双 32 位哈希落盘到 `<docs>/imgcache`，总量 >200MB 按写入时间淘汰；超过 7 天的缓存在后台静默刷新一次，下载失败回退缓存副本。刷新与二次进入走条件请求：保存图床返回的
ETag/Last-Modified（`<key>.img` 旁 `.meta` sidecar），带
If-None-Match/If-Modified-Since，304 直接用缓存并刷新 mtime 重置过期
窗口，不重传图片本体；手动重试跳过条件头。
- **存储占用页**（`lib/src/ui/storage_page.dart` + `lib/src/utils/dir_size.dart`）：
  设置「数据 → 存储占用」展示 `repos` / `local` / `imgcache` / `.meta`
  四类目录的磁盘体积（体积统计在后台 isolate 递归累加）；图片缓存可
  一键清理（删文件保留目录），元数据区提供清空阅读历史入口，
  仓库/镜像的删除引导回首页对应卡片管理。
- **本地文件夹阅读**（`lib/src/local/local_folder_service.dart`）：Android 走
  `saf` 包授权文件夹（tree URI 持久化，无真实路径，dart:io 读不到）→
  **增量镜像**到 `<docs>/local/<名>` 后复用 RepoPage/渲染管线（与 git 仓库
  同构，不为 SAF 单独抽象内容源）；桌面走 `file_selector` 直选目录。镜像标记
  `.pullread_local` 区分本地来源（「同步」= 增量重镜像）；只镜像
  md/ipynb/代码/图片（>32MB 跳过），重名文件夹自动加序号。增量依据镜像根下
  `.pullread_manifest.json` 的源侧 `(size, mtime)` 快照；SAF 授权必须申请
  **写**权限（`pickDirectory(writePermission: true)`），否则编辑器无法写回。
  `.txt` 同样进镜像，打开时路由到
  阅读页纯文本模式（`decodeTextBytes`：UTF-8 严格校验优先、GBK 回退，
  纯 Dart，`lib/src/utils/text_encoding.dart`）。
- **本地 Markdown 编辑器**（`lib/src/ui/markdown_editor.dart`）：本地镜像 md
  的阅读页菜单「编辑」进入——源码 + 预览切换、手动保存 + 未保存离开提醒；
  保存双写镜像（dart:io）+ 原文件夹（Android SAF `writeFileBytes(overwrite:)`
  按相对路径逐段 `child()` 解析，桌面直写真实路径），保存返回阅读页自动
  重载；仓库内文件只读，仍不做 git 提交。写回失败时记入镜像根下
  `.pullread_pending.json`（`.pullread_manifest.json` 旁）：之后的增量
  同步会**跳过**这些文件并自动重试写回，绝不拿源侧旧内容覆盖镜像——
  设置页「数据 → 未写回的修改」可查看明细、重试或以镜像为准强制覆盖。
- **代码查看**：非 Markdown 文件用语法高亮只读查看（对标 GitHub mobile，并补其痛点：无 TOC、不支持 notebook）
- **目录扫描与缓存**（`lib/src/notes/note_index.dart`）：仓库文件列表在后台
  isolate 扫描（UI 线程不做递归 `listSync`，大仓库不卡首帧），结果缓存到
  `<reposRoot>/.meta/index/<仓库名>.json`；进入仓库页先用缓存渲染、再后台
  重扫校正（stale-while-revalidate）。删除仓库/本地文件夹时一并清理该缓存。
- **正文检索**（`lib/src/search/`）：仓库页搜索框可切换「文件名 / 正文」；
  首页搜索图标进入 `lib/src/ui/global_search_page.dart` 跨仓库检索（逐仓库
  顺序执行、结果流式分组），支持**搜索历史**（AppPrefs 持久化，最多 12 条，
  历史标签点击即搜、✕ 删除）、**按仓库过滤**（多选仓库标签，未选 = 全部）、
  「正文 / 仅标题」两种模式（仅标题只匹配文件名/路径，不读文件内容，
  打开命中不带查找词）。正文检索在 isolate 内读 md/ipynb/txt（单文件
  ≤2MB）做线性匹配，返回命中次数 + 上下文摘要（带命中偏移供
  `SearchSnippetText` 高亮）。**刻意不建倒排索引**：中文 2-gram 的 postings
  条目数与正文字符数同量级，序列化后往往比正文本身还大，而笔记仓库正文只有
  几 MB，页缓存 + `indexOf` 足够快且无索引过期问题。
- **文内查找**（`lib/src/ui/markdown_viewer.dart` + `findTextMatches`）：阅读页
  AppBar 搜索图标打开查找条（raw 模式不提供）；命中按行返回，行号与
  `extractToc` 的 `TocEntry.line` 同一坐标系（都基于 front-matter/ipynb
  转换后的正文），跳转时定位到命中所属章节标题，无标题文档按字符比例滚动。
  正文命中逐字加底色：`MarkdownGenerator.textGenerator` 接管纯文本节点
  （`_FindHighlightNode`），查找词非空时把节点文本按命中切开上底色，
  与 `findTextMatches` 同为大小写不敏感；链接/代码块等非文本节点不高亮。
- **标签聚合**（`lib/src/notes/tag_index.dart` + `lib/src/ui/tag_page.dart`）：
  首页标签图标进入标签页，聚合所有仓库与本地文件夹镜像的 front-matter
  `tags`（只读每个文件头 8KB，isolate 内扫描），点标签按 AND 跨仓库筛选；
  多个标签同时选中即要求全部命中。**目录名隐式标签**（可开关，默认开，
  标签页右上角切换）：开启后每级目录名并入 tags 合并去重，没写
  front-matter 的仓库也能用标签导航。
- **断链检查**（`lib/src/notes/link_check.dart`）：仓库页「更多 → 检查断链」
  批量校验相对链接/图片是否仍存在（跳过外部 URL/锚点/代码块，还原百分号
  编码与 `../`），结果按来源文件分组、可复制清单；纯只读，不修改仓库。
- **同步可感知**：`GitSyncService.checkRemote()` 在 isolate 内 fetch 后用
  `RevWalk(push 远端头, hide 本地头)` 统计落后提交数（不移动本地分支）；
  仓库页「更多 → 检查更新」先展示数量再由用户决定是否 pull。`RepoMeta`
  的 `syncedAt` 在克隆（`writeClone`）与成功 pull（`touchSynced`）时更新，
  仓库卡展示「同步于 …」。**历史分叉处理**：`checkRemote` 反向 RevWalk
  检出本地有而远端没有的提交即判为分叉（远端改写提交记录的典型特征），
  pull 遇到无法 fast-forward 时（`SyncException.diverged`）弹窗询问
  「重新克隆」——按 RepoMeta 记录的原 URL 删除本地仓库并重新克隆，
  阅读进度/收藏/更新标记存于仓库外 meta，不受影响。**更新感知打标**：pull（含「全部更新」与后台
  静默拉取）fast-forward 后在 isolate 内对本地旧头→远端头做 tree diff，
  变更文件（新增/修改，不含删除）记入 `RepoMeta.recentChanges`
  （上限 200 条，超出整体清空）；仓库页文件行显示「新增/更新」角标，
  打开文件即清除该文件的标记。
- **阅读链路**（`lib/src/ui/markdown_viewer.dart`）：
  - **打开即续读**：首帧布局后自动恢复到上次位置（标题锚点优先，无标题按比例），
    SnackBar 提供「从头读」撤销；**不再弹模态框**（旧实现每次打开都问一次）
  - **同目录上一篇/下一篇**复用 `NoteIndexCache`，打开文章时**不做**递归扫描；
    缓存缺失才后台扫描并回写（大仓库打开文章不卡首帧）
  - **正文图片解码宽度**按「屏宽 × devicePixelRatio」限制（320~2048），避免
    原图解码占几十 MB；图库仍按原图（可放大看细节）
  - 从正文搜索结果进入时传 `initialFindQuery`：自动打开查找条、统计命中并
    定位到第一处（否则用户还要自己滚到命中位置）
- **平台适配**：GitHub / Gitee / GitCode 必须通过统一抽象层（`RepositoryAdapter` 之类的接口）接入，禁止在业务代码里直接写某家平台的 API 调用
- **鉴权**：如需 token 只存本地，禁止硬编码或写入日志；当前仅支持公开仓库（用户明确不需要私有仓库功能）

## 第一版范围（反目标即边界）

- 只做：整仓克隆 → 舒服地读（第一优先级是渲染体验）→ 按原目录结构浏览（目录树禁止扁平化）+ 全局搜索
- 已明确不做：**任何编辑/commit/push 功能**（用户 2026-10 移除）、双链/图谱、协作、私有仓库、部署/CI/静态站生成
- 底线：渲染效果不能差于博客；同步冲突/丢内容不可接受——涉及 git 操作的改动必须重点自查这两条

## 开发约定

- 提交：英文 Conventional Commit（feat/fix/chore…），原子化提交；push 必须先经用户同意
- 临时文件放 `temp/`（已加入 .gitignore），不放系统 temp
- 不使用 TDD/SDD 流程；仅当改动触及已有测试覆盖的行为时才同步调整测试
- Windows 环境：Python 读文件必须显式 `encoding="utf-8"`

## 常用命令

```bash
flutter create .            # 项目尚未初始化时先执行
flutter pub get
flutter run                 # 运行（连接设备/模拟器；dev 清单见上文 alias 说明）
flutter analyze             # 静态检查
flutter test
flutter build apk --split-per-abi --target-platform android-arm64

# 长文渲染基线（真机 profile；指标定义与历史数字见 docs/perf.md）
flutter drive --profile -d <deviceId> \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/render_perf_test.dart
# 只测某一档、内存更干净：追加 --dart-define=PERF_SIZES=10000
```

APK 打包约定：只打 arm64-v8a（主流手机架构），固定用上述命令
（产物 `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`，
约 32MB；通用 fat APK 约 79MB）。注意：gradle `ndk.abiFilters` 对
Flutter 注入的 so 无效且与 `--split-per-abi` 冲突，不要用它限制架构；
x86_64 模拟器无法安装本 APK，模拟器调试走 debug 构建。

发版约定：正式 Release 只经 GitHub（interset-wq/pullread）发布——推送
`v*` tag 触发 `.github/workflows/release.yml`，CI 校验 tag 与
pubspec `version` 一致后自动构建 arm64 APK 并创建 Release，禁止手动
上传 APK（避免与源码构建不一致）。发版流程 = 改 pubspec version →
提交 → 打同名 tag 推送。也可在 Actions → Release → Run workflow 手动跑
一次（`workflow_dispatch`）：只做构建 + 签名校验的冒烟，**不创建 Release**
（版本校验与发布步骤只对 tag 生效），用于验证 action / 构建环境升级后
链路仍可用。

## 维护规则

项目结构、构建/测试命令、架构边界、开发约定或本文件记录的其他事实发生变化时，必须在同一次改动中同步更新本文件。

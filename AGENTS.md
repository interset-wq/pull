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
  - **isolate 硬约束**：git 操作在 `Isolate.run` 后台 isolate 执行（大仓库不卡 UI）；isolate 内捕获 git2dart 原生异常后必须转普通 `Exception` 再抛（原生错误对象不可跨 isolate 发送，直接抛出会导致 Future 永不完成、UI 死转）。
  - **构建陷阱**：`INTERNET` 权限必须声明在 `android/app/src/main/AndroidManifest.xml`——Flutter 模板默认只加在 debug/profile 变体，release 包无网络权限，所有 HTTPS 请求报 `GIT_ERROR_NET: No address associated with hostname`。
- **Markdown 渲染**：markdown_widget + 代码高亮；GFM alert（`> [!NOTE]` 等）与 .ipynb（Jupyter）转 Markdown 渲染
- **代码查看**：非 Markdown 文件用语法高亮只读查看（对标 GitHub mobile，并补其痛点：无 TOC、不支持 notebook）
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
flutter run                 # 运行（连接设备/模拟器）
flutter analyze             # 静态检查
flutter test
flutter build apk --split-per-abi --target-platform android-arm64
```

APK 打包约定：只打 arm64-v8a（主流手机架构），固定用上述命令
（产物 `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`，
约 32MB；通用 fat APK 约 79MB）。注意：gradle `ndk.abiFilters` 对
Flutter 注入的 so 无效且与 `--split-per-abi` 冲突，不要用它限制架构；
x86_64 模拟器无法安装本 APK，模拟器调试走 debug 构建。

## 维护规则

项目结构、构建/测试命令、架构边界、开发约定或本文件记录的其他事实发生变化时，必须在同一次改动中同步更新本文件。

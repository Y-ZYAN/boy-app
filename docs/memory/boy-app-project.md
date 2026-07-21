---
name: boy-app-project
description: 手机使用监控 App「手机守护」项目状态，Flutter + GitHub Actions
metadata: 
  node_type: memory
  type: project
  originSessionId: d1ca277c-6649-46ea-9a1a-0e76d2efa1e8
---

# boy-app 项目状态（2026-07-21）

## 项目定位
监控弟弟偷玩妈妈手机的使用记录工具。记录各 App 使用时长和使用模式，提供可视化的使用报告。（当前范围：纯监控，不含限额封锁，详见 [[boy-app-lessons#Phase 2 复盘]]）

## 技术栈
- **语言**: Flutter (3.44.6) + Dart + Kotlin (原生 Android)
- **构建**: GitHub Actions（SSH 推送，remote: `git@github.com:Y-ZYAN/boy-app.git`）
- **目标平台**: Android（当前 OPPO Android 14，厂商适配后续处理）
- **本地目录**: `C:\Users\lenovo\boy-app\`
- **本地 Flutter 可用但缺 Android SDK/JDK** → 全靠 GitHub Actions 编译
- **Flutter 项目内部名**: `boy_app`（`flutter create --org com.momapp --project-name boy_app`，后手工改名一致）
- **Android 桌面显示名**: `手机守护`（`AndroidManifest.xml` 中 `android:label`）

## 仓库状态
- **GitHub**: `Y-ZYAN/boy-app` → **公开仓库**
- 代码无敏感信息（无 API Key、无密码），公开状态暂时安全
- 如需保护隐私，后续可在 GitHub Settings 改为 Private

## 已完成
1. ✅ GitHub Actions 构建流水线配通，SSH 推送成功，APK 可下载
2. ✅ 权限页面：MethodChannel 两端（`MainActivity.kt` ↔ `lib/main.dart`）对接完成
3. ✅ `PACKAGE_USAGE_STATS` 权限检测 + 跳转设置页 + 从设置返回自动重检
4. ✅ OPPO Android 14 实测权限流程走通
5. ✅ **Phase 1** — UsageStatsManager.queryEvents 读取 + 会话配对 + App 时长列表 + 时长排序/近期使用双Tab
6. ✅ 重构：main.dart 拆分为 models/pages/utils 结构
7. ✅ CI 优化：build.yml 加 Gradle 缓存 + workflow_dispatch 手动触发 + dl.sh 脚本
8. ✅ **Phase 2（已移除）** — 原本做了限额封锁（ForegroundService + 悬浮窗），后根据用户反馈砍掉。妈妈只需要查看使用记录，限额可被卸载绕过。`AppLimit` 模型类保留在代码中未清理（`app_usage_session.dart`），作为后续方向的数据结构参考
9. ✅ 保留的 Phase 1 改进：已卸载 App 标记、息屏时间统计、短会话归入总时长

### 核心文件结构
- `android/app/src/main/kotlin/com/momapp/**boy_app**/MainActivity.kt` — 原生 Kotlin 端
  - `hasUsageStatsPermission` / `openUsageStatsSettings` — 权限检测
  - `queryUsageSessions` — 查 UsageEvents 配对会话（返回 sessions+icons 两张表）
  - `resolveAppName` — PackageManager 包名→中文名
  - `getAppIconBytes` — 取 App 图标 PNG 字节数组
- `lib/main.dart` — 入口（路由到 UsageMonitorPage）
- `lib/pages/usage_monitor_page.dart` — 权限检测页，通过后自动启动监控
- `lib/pages/usage_dashboard_page.dart` — 双 Tab 仪表盘
- `lib/models/app_usage_session.dart` — AppUsageSession + AppLimit 模型
- `lib/utils/format_utils.dart` — 时间格式化工具
- `.github/workflows/build.yml` — CI 流水线（含缓存 + 手动触发）
- `android/app/src/main/AndroidManifest.xml` — 权限声明 + app label

## 后续方向（暂缓）
- **限额封锁（原 Phase 2）** — ❌ **已废弃**。弟弟卸载重装即可绕过，妈妈只需要查看记录，不需要封锁。详见 [[boy-app-lessons#Phase 2 复盘]]
- **拦截安装新应用（原 Phase 3）** — ❓ **暂缓**。同样面临卸载绕过问题，需先解决防卸载方案才有意义。

## 已知技术细节

### Kotlin 会话配对逻辑
- 遍历 queryEvents 结果，配对 MOVE_TO_FOREGROUND / MOVE_TO_BACKGROUND
- 切 App 时自动关前一个会话（用后一个的 FOREGROUND 时间作为前一个的结束）
- 仍在使用的 App 以当前时间为结束时间
- 自动过滤 < 1 分钟的短会话（减少干扰），正在使用中的不过滤
- **边界情况**：
  - 只有 FOREGROUND 没有 BACKGROUND（crash/强制杀进程）→ 下一个 App 的 FOREGROUND 事件到达时自动关掉前一个
  - 同一个 App 连续两个 FOREGROUND 没带 BACKGROUND → 忽略重复 FOREGROUND，不产生空会话
  - 当天最后一个会话还在运行中 → endTime 传 -1，Flutter 侧展示"使用中"
  - 过滤条件：`endTimeMillis - startTimeMillis >= MIN_SESSION_MS || endTimeMillis == -1L`

### App 图标实现要点
- `PackageManager.getApplicationIcon(pkg)` 返回 Drawable，不一定是 BitmapDrawable
- **VectorDrawable 处理**：intrinsicWidth/height 可能为 -1，不能依赖。方案是创建固定 96x96 的 Bitmap，用 Canvas 把 Drawable 画上去
- **BitmapDrawable 处理**：直接 `.bitmap` 取出
- 通过 ByteArrayOutputStream.compress(PNG) 转为 byte[]，MethodChannel 原生支持 byte[] ↔ Uint8List 互转
- 图标按包名去重，只在第一次遇到某包名时取一次，存入 iconCache

### API 版本兼容
- 同时处理新旧事件类型：`MOVE_TO_FOREGROUND`(1) / `ACTIVITY_RESUMED`(23)，`MOVE_TO_BACKGROUND`(2) / `ACTIVITY_PAUSED`(24)
- 权限检测：API 29+ 用 `unsafeCheckOp`，旧版用 `checkOpNoThrow`

### Flutter UI 实现要点
- 时长排序 Tab 按 appName 分组，但取图标需要 packageName → 用 `sessions.first.packageName` 取该组包名
- ExpansionTile 解包时 session 按 startTime 升序排列（最早的在前）
- 近期使用 Tab 按 startTime 降序排列（最新的在前），切换不同 App 时用分隔线 + `swap_vert` 图标标记
- ListView 放在 TabBarView 的 Expanded 内，滚动正常

### MethodChannel 详情
- channel name: `usage_stats`
- 方法: `hasUsageStatsPermission` → `Boolean`
- 方法: `openUsageStatsSettings` → `true`
- 方法: `queryUsageSessions` → `Map{ "sessions": [...], "icons": {"pkg": Uint8List} }`

### App 图标传输方案
- Kotlin 侧 `getAppIconBytes()`: PackageManager.getApplicationIcon → Drawable → Bitmap → PNG ByteArray → 随 MethodChannel 返回
- Flutter 侧: `Image.memory(Uint8List)` 展示，失败回退首字母头像
- 图标按包名去重，同一个 App 只传一次 ByteArray
- ByteArray ↔ Uint8List 是 MethodChannel 原生支持的类型，不需要二次编码

## 教训与经验
- **Kotlin 文件路径确认**：`flutter create --org com.momapp --project-name boy_app` 生成的包路径是 `com/momapp/boy_app/` 而非项目根目录名。修改 Kotlin 文件前务必先用 `find` 确认实际路径。
- **OEM 兼容**：OPPO ColorOS Android 14 的 UsageEvents 行为符合标准文档，MOVE_TO_FOREGROUND/BACKGROUND 事件正常上报。

## 网络与认证
- GitHub 网页通，HTTPS（443端口）push 被墙
- SSH（22端口）正常 → **教训：在中国优先配 SSH key，不要依赖 HTTPS push**
- SSH 密钥已配（`~/.ssh/id_ed25519` `mom-app` 标签），已加 GitHub 账号
- 仓库：`git@github.com:Y-ZYAN/boy-app.git`
- 浏览器和终端网络行为不一致（浏览器能上 GitHub，curl 超时）——推测走不同路由

## 实战经验与教训（中国网络环境）

### 下载问题
- 所有 Android SDK 镜像（腾讯/清华/阿里）全部失效
- GitHub release assets（二进制大文件）被拦
- JDK 下载也被拦
- `flutter create` + `flutter pub get` **成功**（pub.dev 联通性正常）
- **最终方案**: 本地写代码 → git push（SSH）→ GitHub Actions 云端编译 → 下载 APK

### Git 操作
- `git credential approve` 可以存 token，但命令会暴露 token 明文
- Flutter 项目本地默认分支 `master`，GitHub 默认 `main` → 需 `git branch -m master main`
- Windows CRLF/LF 换行符警告不影响功能

### GitHub Actions
- `subosito/flutter-action@v2` 指定 `flutter-version: '3.44.x'` 匹配本地版本
- 项目 pubspec.yaml 的 Dart SDK 约束 `^3.12.2` 需要 Flutter 3.44+
- `actions/upload-artifact@v4` 产物在 Actions 页面可直接下载
- GitHub runner 已升级到 Node 24，但 `actions/checkout@v4` 和 `actions/upload-artifact@v4` 仍基于 Node 20（仅警告，不影响）

### OPPO ColorOS (Android 14) 实测
- `Settings.ACTION_USAGE_ACCESS_SETTINGS` 在 ColorOS 能正确跳转
- 权限菜单路径：设置 → 应用 → 权限管理 → 特殊权限 → 使用情况访问权限
- 权限检测 API：Android 10+ 用 `AppOpsManager.unsafeCheckOp()`；旧版本用 `checkOpNoThrow()`
- 返回 App 后通过 `WidgetsBindingObserver.didChangeAppLifecycleState(.resumed)` 自动检测权限变更
- 目前测试设备: PFTM20 (OPPO Pad Air 2 平板)

## Workspace 信息
- 在 `C:\Users\lenovo`（Windows 11）
- Git Bash shell，无代理
- Flutter 3.44.6 已装（缺本地 Android SDK，不用于本地编译）

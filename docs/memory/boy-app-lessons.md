---
name: boy-app-lessons
description: 手机守护 App 项目经验总结——技术决策、踩坑记录、流程优化
metadata: 
  node_type: memory
  type: reference
  originSessionId: c48cc861-1aa1-45fc-9cac-11e15812ec2e
---

# 手机守护（boy-app）项目经验总结

## 项目背景
- **目标**: 监控弟弟偷玩妈妈手机，记录各 App 使用时长
- **硬件**: OPPO Pad Air 2 (PFTM20), Android 14 ColorOS
- **技术栈**: Flutter 3.44.6 + Kotlin + GitHub Actions
- **模式**: 本地写代码 → git push (SSH) → GitHub Actions 编译 → 下载 APK → adb 安装
- [[boy-app-project]]

## 技术决策与踩坑

### 1. 中国网络环境下的 CI 策略
- **HTTPS (443) push 被墙**，SSH (22) 正常 → 必须优先配 SSH key
- **所有 Android SDK 镜像（腾讯/清华/阿里）全部失效** → 不能本地编译
- GitHub release assets（二进制大文件）也被拦
- `flutter create` + `flutter pub get` 成功（pub.dev 联通正常）
- **最终方案**: `git push`(SSH) → GitHub Actions → 下载 APK

### 2. CI 优化经验
- Gradle 缓存（`actions/cache@v4`）可节省 30-50% 编译时间
- `workflow_dispatch` 允许手动触发，不用为编译 fake push
- Flutter 3.44.6 的 compileSdk = 36 (Android 16)，targetSdk = 36
- 公开仓库 GitHub Actions 不限分钟数

### 3. Kotlin × MethodChannel 要点
- method channel name `usage_stats`，两端保持一致
- 返回大数据（如全部已安装 App 列表）可能触发 Binder TransactionTooLarge → 用 `queryIntentActivities(CATEGORY_LAUNCHER)` 替代 `getInstalledApplications`，只返回 30-60 个桌面可见 App
- ByteArray ↔ Uint8List 是 MethodChannel 原生支持类型，不需要二次编码
- SAM lambda `Runnable { ... }` 中 `this` 指向外部的类，不是 Runnable 自己 → 用 `object : Runnable { ... }` 解决

### 4. UsageStatsManager 实战
- `queryEvents` 比 `queryAndAggregateUsageStats` 更实时（后者只更新到上次 background 事件）
- 会话配对逻辑：FOREGROUND→BACKGROUND 配对；FOREGROUND 重叠时自动关闭前一个；当天最后一个未关闭的以当前时间为结束
- **短会话过滤陷阱**：`MIN_SESSION_MS = 60_000` 过滤 < 1 分钟会话，但它们的时长也需要计入总时间。解决方案：返回 `totalRecordedMillis`（原始总和）和 `sessions`（过滤后列表）两个值
- **息屏检测**：`SCREEN_NON_INTERACTIVE`(25) / `SCREEN_INTERACTIVE`(26) 事件在 `queryEvents` 中可获取，用于计算息屏总时长
- 已卸载 App 检测：`resolveAppName` 返回包名本身说明 `NameNotFoundException` → App 已卸载

### 5. Android 兼容性
- **OPPO ColorOS (Android 14)**: UsageEvents 行为符合标准文档，权限流程正常
- **Android 11+ 包可见性**：`getInstalledApplications` 需要 `QUERY_ALL_PACKAGES` 权限才能返回完整列表。但 `getApplicationInfo` 对已知包名仍可工作
- **FlutterActivity 路径**: `com.momapp.boy_app`（由 `flutter create --org com.momapp --project-name boy_app` 决定）
- **前台服务类型**: API 35+ 要求声明 `foregroundServiceType`，如 `specialUse` 需额外 `<property>` 标签

### 6. Phase 2 复盘（限额封锁为何被砍）
- 实现了 EnforcementService (ForegroundService) + UsageLimitManager + Overlay 遮挡
- **用户反馈**: 弟弟只需要卸载再安装就能绕过 → 封锁意义不大
- **妈妈需求**: 只需要看到完整的使用记录，不需要封锁
- **教训**: 在动手实现复杂功能前，先确认真实需求。纯监控（visibility）和主动控制（control）是两个不同场景

### 7. 开发流程优化
- 没有本地 Android SDK 时，每次 `git push → CI → 下载 → 安装` 约 10-15 分钟
- **改进**: 批量提交（3-5 个改动/次），本地跑 `flutter analyze` 确保 Dart 语法正确
- Kotlin 代码无法本地验证 → 写完后重点审查，尤其是 Kotlin 特有的语法（SAM、`apply`、`object` 表达式）
- 最高风险的组件（ForegroundService、Overlay、权限）先做，给它们最多的迭代次数

## 文件结构备忘
```
lib/
  main.dart                       → 入口
  models/app_usage_session.dart   → AppUsageSession + AppLimit + IconCache
  pages/usage_monitor_page.dart   → 权限检查 + 生命周期监听
  pages/usage_dashboard_page.dart → 双 Tab 仪表盘
  utils/format_utils.dart         → formatDuration + formatTimeRange
android/.../MainActivity.kt       → MethodChannel 入口 + queryUsageSessions
android/.../AndroidManifest.xml   → 权限声明 + 服务声明
.github/workflows/build.yml       → CI 流水线（含缓存）
```

## 可复用的代码片段

### Kotlin 会话配对（核心逻辑）
```kotlin
val openSessions = mutableMapOf<String, Long>()
while (events.hasNextEvent()) {
    // ...
    when (eventType) {
        MOVE_TO_FOREGROUND, ACTIVITY_RESUMED -> openSessions[pkg] = time
        MOVE_TO_BACKGROUND, ACTIVITY_PAUSED -> openSessions.remove(pkg)
    }
}
// 仍在使用的 = 有 FOREGROUND 但没有 BACKGROUND 的
val currentForeground = openSessions.maxByOrNull { it.value }?.key
```

### Flutter Material 3 主题
```dart
theme: ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
  useMaterial3: true,
)
```

## 关键连接
- 教学偏好: [[teaching-style]]
- 合作偏好: [[collaboration-tips]]

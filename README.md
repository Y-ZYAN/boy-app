# 📱 手机守护 — Boy App Monitor

> 监控弟弟偷玩妈妈手机的使用记录工具。记录各 App 使用时长，提供可视化的使用报告。

![Build](https://github.com/Y-ZYAN/boy-app/actions/workflows/build.yml/badge.svg)
![License](https://img.shields.io/badge/license-MIT-green)

---

## 功能

- ✅ 读取 Android 使用统计权限（UsageStatsManager）
- ✅ 自动配对 App 使用会话（前台→后台）
- ✅ 「时长排序」Tab：按 App 分组展示总使用时长
- ✅ 「近期使用」Tab：按时间线展示最近打开的 App
- ✅ 真实 App 图标（自动适配 VectorDrawable/BitmapDrawable）
- ✅ 已卸载 App 标记
- ✅ 息屏时间统计
- ✅ 权限检测 + 跳转设置页 + 返回自动重检

## 截图

（待补充）

## 技术栈

| 层 | 技术 |
|---|---|
| 界面 | Flutter 3.44 + Dart |
| 原生层 | Kotlin (MethodChannel) |
| 目标平台 | Android（最低 API 29，Target SDK 36） |
| 构建 | GitHub Actions（本地缺 Android SDK） |

## 快速开始

```bash
# Clone
git clone git@github.com:Y-ZYAN/boy-app.git
cd boy-app

# 安装依赖
flutter pub get

# 构建 APK（需要本地 Android SDK）
flutter build apk --debug
```

> 💡 **注意**：在没有本地 Android SDK 的环境下，直接 push 到 `main` 分支，GitHub Actions 会自动编译产出 APK，在 Actions 页面下载。

## 编译产物

每次 push 到 `main` 或手动触发 `workflow_dispatch`，GitHub Actions 会产出 `boy-app-debug.apk`，在 [Actions 页面](https://github.com/Y-ZYAN/boy-app/actions) 的对应 workflow run 中下载。

## 项目结构

```
lib/
├── main.dart                     # 入口
├── models/app_usage_session.dart # 数据模型
├── pages/
│   ├── usage_monitor_page.dart   # 权限检测页
│   └── usage_dashboard_page.dart # 双 Tab 仪表盘
├── utils/format_utils.dart       # 时间格式化
android/.../MainActivity.kt       # Kotlin MethodChannel 端
.github/workflows/build.yml       # CI 流水线
```

## License

[MIT](LICENSE) © 2026 Y-ZYAN

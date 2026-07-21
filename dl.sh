#!/usr/bin/env bash
# 下载最新 CI 构建的 APK 并安装到平板
# 前提：已安装 gh CLI 并登录（gh auth status）

set -euo pipefail

APP_NAME="boy-app-debug"
INSTALL_DIR="/c/Users/lenovo/Downloads"

echo "=== 下载最新 APK ==="
gh run download --name "$APP_NAME" --dir "$INSTALL_DIR"

# 找最新 APK
APK=$(ls -t "$INSTALL_DIR"/*.apk 2>/dev/null | head -1)
if [ -z "$APK" ]; then
  echo "❌ 未找到 APK 文件"
  exit 1
fi

echo "=== 安装到平板: $(basename "$APK") ==="
adb install -r "$APK" 2>/dev/null && echo "✅ 安装成功" || {
  echo "⚠️  adb install 失败，尝试先卸载再安装…"
  adb uninstall com.momapp.boy_app && adb install "$APK" && echo "✅ 重装成功"
}

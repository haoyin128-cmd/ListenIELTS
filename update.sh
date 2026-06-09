#!/bin/bash
# 一键更新脚本：编译新版本并替换 /Applications 里的旧版本
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="ListenIELTS"
APP_DIR="$PROJECT_DIR/$APP_NAME.app"
INSTALL_DIR="/Applications/$APP_NAME.app"

cd "$PROJECT_DIR"

# 1. 关闭正在运行的应用
if pgrep -x "$APP_NAME" > /dev/null; then
    echo "🛑 正在关闭运行中的 $APP_NAME..."
    osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || pkill -x "$APP_NAME" || true
    sleep 1
fi

# 2. 编译并打包
echo "🔨 开始构建..."
bash "$PROJECT_DIR/build.sh"

# 3. 安装到 /Applications（覆盖旧版本）
if [ -d "$APP_DIR" ]; then
    echo ""
    echo "📥 正在安装到 /Applications..."
    rm -rf "$INSTALL_DIR"
    cp -R "$APP_DIR" "$INSTALL_DIR"

    # 触发 Launchpad / Finder 刷新图标缓存
    touch "$INSTALL_DIR"

    echo "✅ 已安装到 $INSTALL_DIR"
    echo ""
    echo "🚀 启动应用："
    open "$INSTALL_DIR"
else
    echo "❌ 构建失败，未找到 $APP_DIR"
    exit 1
fi

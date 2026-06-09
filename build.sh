#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="ListenIELTS"
BUILD_DIR="$PROJECT_DIR/.build/release"
APP_DIR="$PROJECT_DIR/$APP_NAME.app"

echo "🔨 正在编译 $APP_NAME (Release 模式)..."
cd "$PROJECT_DIR"
swift build -c release

echo "📦 正在创建 .app 打包..."

# 清理旧的
rm -rf "$APP_DIR"

# 创建 .app 目录结构
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# 复制二进制文件
cp "$BUILD_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/"

# 创建 Info.plist
cat > "$APP_DIR/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>ListenIELTS</string>
    <key>CFBundleIdentifier</key>
    <string>com.listenielts.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>ListenIELTS</string>
    <key>CFBundleDisplayName</key>
    <string>ListenIELTS</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>ListenIELTS 不需要使用麦克风，仅用于播放音频文件。</string>
    <key>LSUIElement</key>
    <false/>
</dict>
</plist>
PLIST

# 创建 PkgInfo
echo "APPL????" > "$APP_DIR/Contents/PkgInfo"

# 生成并安装图标
echo "🎨 正在生成应用图标..."
python3 "$PROJECT_DIR/generate_icon.py"

# Ad-hoc 签名（减少 Gatekeeper 报错）
echo "🔐 正在签名..."
codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || echo "   (跳过签名 — 不影响使用)"

echo ""
echo "✅ 完成！应用位于: $APP_DIR"
echo ""
echo "🚀 运行方式："
echo "   open $APP_DIR"
echo ""
echo "💡 或者拖拽到「应用程序」文件夹后从 Launchpad 启动"
echo ""
echo "🔧 如果 macOS 提示「无法验证开发者」："
echo "   右键点击 $APP_NAME.app → 选择「打开」→ 点击「打开」确认"

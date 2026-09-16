#!/bin/bash
# 把 app.swift 打包成 MeetingNotes.app（菜单栏程序，双击运行，无需终端）
set -euo pipefail
cd "$(dirname "$0")"

APP="MeetingNotes.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

echo "==> 编译通用二进制"
swiftc -O -target arm64-apple-macos12  app.swift -o ka-arm64
swiftc -O -target x86_64-apple-macos12 app.swift -o ka-x86_64
lipo -create ka-arm64 ka-x86_64 -output "$APP/Contents/MacOS/MeetingNotes"
rm -f ka-arm64 ka-x86_64

echo "==> 写入 Info.plist"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>MeetingNotes</string>
    <key>CFBundleDisplayName</key><string>MeetingNotes</string>
    <key>CFBundleIdentifier</key><string>com.meetingnotes.app</string>
    <key>CFBundleExecutable</key><string>MeetingNotes</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>12.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>Personal utility</string>
</dict>
</plist>
PLIST

echo "==> ad-hoc 签名"
codesign --force --deep --sign - --identifier com.meetingnotes.app "$APP"

echo "==> 校验"
codesign --verify --deep --strict "$APP" && echo "签名校验通过"
lipo -archs "$APP/Contents/MacOS/MeetingNotes"
echo "✅ 打包完成：$APP"

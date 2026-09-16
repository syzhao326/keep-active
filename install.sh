#!/bin/bash
# keepactive 一键安装脚本
# 用法一（推荐，直接从网上装）：
#   curl -fsSL https://raw.githubusercontent.com/syzhao326/keep-active/main/install.sh | bash
# 用法二（在 clone 下来的目录里）：
#   bash install.sh

set -euo pipefail

REPO="syzhao326/keep-active"
BRANCH="main"
RAW="https://raw.githubusercontent.com/$REPO/$BRANCH"
INSTALL_DIR="$HOME/Library/Application Support/KeepActive"
BIN="$INSTALL_DIR/keepactive"

echo "==> 安装 keepactive 到：$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

# 脚本所在目录（用 curl|bash 方式运行时可能取不到，属正常）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "")"

# 1. 取得二进制：优先用本地（clone 情况），否则从 GitHub 下载
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/keepactive" ]; then
  echo "==> 使用本地二进制"
  cp "$SCRIPT_DIR/keepactive" "$BIN"
else
  echo "==> 从 GitHub 下载二进制"
  curl -fsSL "$RAW/keepactive" -o "$BIN"
fi
chmod +x "$BIN"

# 2. 去掉隔离属性（否则可能提示"无法验证开发者"）
xattr -dr com.apple.quarantine "$BIN" 2>/dev/null || true

# 3. 本地重新 ad-hoc 签名（best-effort，让授权身份更稳定）
codesign --force --sign - --identifier com.keepactive.cli "$BIN" 2>/dev/null || true

# 4. 验证能跑；若跑不起来且系统有 swiftc，则从源码编译
if ! "$BIN" selftest >/dev/null 2>&1; then
  echo "==> 预编译二进制无法直接运行，尝试从源码编译"
  if command -v swiftc >/dev/null 2>&1; then
    SRC="$INSTALL_DIR/main.swift"
    if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/main.swift" ]; then
      cp "$SCRIPT_DIR/main.swift" "$SRC"
    else
      curl -fsSL "$RAW/main.swift" -o "$SRC"
    fi
    swiftc -O "$SRC" -o "$BIN"
    codesign --force --sign - --identifier com.keepactive.cli "$BIN" 2>/dev/null || true
  else
    echo "!! 二进制无法运行，且系统没有 swiftc。" >&2
    echo "   请先安装 Xcode 命令行工具后重试：xcode-select --install" >&2
    exit 1
  fi
fi

# 5. 设置 zsh 别名，方便以后直接敲 keepactive
SHELL_RC="$HOME/.zshrc"
ALIAS_LINE="alias keepactive=\"$BIN\""
if ! grep -qF "$ALIAS_LINE" "$SHELL_RC" 2>/dev/null; then
  {
    echo ""
    echo "# keepactive"
    echo "$ALIAS_LINE"
  } >> "$SHELL_RC"
fi

echo ""
echo "✅ 安装完成！二进制位置：$BIN"
echo ""
echo "================ 接下来还差两步（需要你手动点一下）================"
echo ""
echo "第 1 步 · 授予「辅助功能」权限（必须，否则动不了鼠标）："
echo "    运行下面这行，会自动弹出系统设置，按提示打开 keepactive 的开关："
echo ""
echo "        \"$BIN\" start"
echo ""
echo "    打开开关后，再运行一次同样的命令，就真正在后台启动了。"
echo ""
echo "第 2 步 · （可选）先试打一次飞书："
echo "    先打开飞书文档、把光标点进正文里，再运行："
echo ""
echo "        \"$BIN\" test-feishu"
echo ""
echo "以后新开终端窗口，可直接用： keepactive start / keepactive stop / keepactive status"
echo "==============================================================="

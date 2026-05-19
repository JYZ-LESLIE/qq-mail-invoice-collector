#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

LOG_DIR="$ROOT/content_ops/_runtime/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/invoice_app_launch.log"
exec > >(tee -a "$LOG_FILE") 2>&1

APP_PATH="$ROOT/发票管家.app"
BINARY="发票管家.app/Contents/MacOS/发票管家"
APP_PROCESS="$APP_PATH/Contents/MacOS/发票管家"
NEEDS_PREPARE=0

if [ ! -x "$BINARY" ]; then
  echo "还没有准备好发票管家，正在执行首次准备..."
  NEEDS_PREPARE=1
else
  UPDATED_SOURCE="$(find content_ops/mac content_ops/scripts -maxdepth 1 -type f \( -name '*.swift' -o -name '*.sh' -o -name '*.py' \) -newer "$BINARY" -print -quit)"
  if [ -n "$UPDATED_SOURCE" ]; then
    echo "检测到发票管家有更新，正在重新准备..."
    echo "更新文件：$UPDATED_SOURCE"
    NEEDS_PREPARE=1
  fi
  for SUPPORT_FILE in content_ops/mac/build_invoice_app.sh content_ops/invoices/requirements.txt; do
    if [ "$NEEDS_PREPARE" = "0" ] && [ -f "$SUPPORT_FILE" ] && [ "$SUPPORT_FILE" -nt "$BINARY" ]; then
      echo "检测到发票管家支持文件有更新，正在重新准备..."
      echo "更新文件：$SUPPORT_FILE"
      NEEDS_PREPARE=1
    fi
  done
  if [ "$NEEDS_PREPARE" = "0" ] && ! "$BINARY" --self-test >/dev/null 2>&1; then
    echo "发票管家自检未通过，正在重新准备..."
    NEEDS_PREPARE=1
  fi
fi

if [ "$NEEDS_PREPARE" = "1" ]; then
  "$ROOT/准备发票管家.command"
fi

echo "当前版本：$("$BINARY" --version)"

if pgrep -f "$APP_PROCESS" >/dev/null 2>&1; then
  echo "检测到发票管家已在运行，正在重新打开最新版本..."
  osascript -e 'tell application "发票管家" to quit' >/dev/null 2>&1 || true
  for _ in {1..20}; do
    if ! pgrep -f "$APP_PROCESS" >/dev/null 2>&1; then
      break
    fi
    sleep 0.5
  done
  if pgrep -f "$APP_PROCESS" >/dev/null 2>&1; then
    pkill -f "$APP_PROCESS" >/dev/null 2>&1 || true
    sleep 1
  fi
fi

echo "打开：$APP_PATH"
open -n "$APP_PATH"

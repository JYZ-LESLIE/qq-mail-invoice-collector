#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

echo "首次准备/修复发票管家..."

if [ ! -x "content_ops/invoices/.venv/bin/python" ]; then
  python3 -m venv content_ops/invoices/.venv
fi

content_ops/invoices/.venv/bin/python -m pip install -q -r content_ops/invoices/requirements.txt

mkdir -p "发票整理/私密配置"
if [ ! -f "发票整理/私密配置/accounts.yaml" ]; then
  cp content_ops/invoices/private/accounts.example.yaml "发票整理/私密配置/accounts.yaml"
  echo "已创建多邮箱配置模板：发票整理/私密配置/accounts.yaml"
fi

if [ ! -f "发票整理/私密配置/invoice_mail.env" ]; then
  cp content_ops/invoices/private/invoice_mail.env.example "发票整理/私密配置/invoice_mail.env"
  echo "已创建私密配置模板：发票整理/私密配置/invoice_mail.env"
fi

content_ops/mac/build_invoice_app.sh >/dev/null

echo "准备完成。以后日常使用请双击：启动发票管家.command"

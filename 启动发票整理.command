#!/bin/zsh
set -e

cd "$(dirname "$0")"

echo "正在准备发票整理工具..."

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

echo "启动本地界面：http://127.0.0.1:8501"
open "http://127.0.0.1:8501" >/dev/null 2>&1 || true
content_ops/invoices/.venv/bin/python -m streamlit run content_ops/scripts/invoice_dashboard.py --server.address 127.0.0.1 --server.port 8501

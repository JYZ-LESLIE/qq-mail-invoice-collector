#!/usr/bin/env python3
"""Local Streamlit dashboard for the invoice collector."""

from __future__ import annotations

import csv
import datetime as dt
import json
from pathlib import Path
import subprocess

import streamlit as st
import yaml  # type: ignore

WORKSPACE_ROOT = Path(__file__).resolve().parents[2]
CONFIG_PATH = WORKSPACE_ROOT / "发票整理/私密配置/accounts.yaml"
REPORT_DIR = WORKSPACE_ROOT / "发票整理/台账"
RUNNER = WORKSPACE_ROOT / "content_ops/scripts/invoice_multi_account_runner.py"
PYTHON = WORKSPACE_ROOT / "content_ops/invoices/.venv/bin/python"


def manifest_files() -> list[Path]:
    return sorted(REPORT_DIR.glob("invoice_manifest_*.csv"), key=lambda p: p.stat().st_mtime, reverse=True)


def load_accounts() -> list[dict[str, object]]:
    if not CONFIG_PATH.exists():
        return []
    data = yaml.safe_load(CONFIG_PATH.read_text(encoding="utf-8")) or {}
    return [account for account in data.get("accounts", []) if isinstance(account, dict)]


def summarize_csv(path: Path) -> dict[str, object]:
    if not path.exists():
        return {}
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        rows = list(csv.DictReader(handle))
    formal = [
        row
        for row in rows
        if row.get("status") in {"Parsed", "AI_Verified"}
        and str(row.get("include_in_summary") or "是").strip() != "否"
    ]
    amount = sum(
        float(str((row.get("effective_amount") or row.get("amount") or "0")).replace(",", ""))
        for row in formal
        if str(row.get("effective_amount") or row.get("amount") or "").strip()
    )
    return {"rows": len(rows), "formal": len(formal), "amount": round(amount, 2)}


def parse_last_json_object(output: str) -> dict[str, object]:
    for index, char in enumerate(output):
        if char != "{":
            continue
        try:
            payload = json.loads(output[index:])
        except Exception:
            continue
        if isinstance(payload, dict):
            return payload
    return {}


st.set_page_config(page_title="发票整理工具", layout="wide")
st.title("发票整理工具")

accounts = load_accounts()
if not accounts:
    st.warning("还没有多邮箱配置。请先复制 accounts.example.yaml 到 发票整理/私密配置/accounts.yaml 并填写账号。")
else:
    st.subheader("邮箱账号")
    st.dataframe(
        [
            {
                "账号ID": account.get("id"),
                "名称": account.get("label", ""),
                "类型": account.get("provider", ""),
                "启用": bool(account.get("enabled", True)),
                "IMAP": account.get("imap_host", ""),
                "检索模式": account.get("search_mode", "filtered"),
                "超时秒数": account.get("imap_timeout_seconds", ""),
                "邮箱变量": account.get("email_env", ""),
                "授权码变量": account.get("auth_code_env", ""),
            }
            for account in accounts
        ],
        use_container_width=True,
        hide_index=True,
    )

today = dt.date.today()
col1, col2, col3 = st.columns(3)
with col1:
    since = st.date_input("开始日期", value=today)
with col2:
    until = st.date_input("结束日期", value=today)
with col3:
    limit = st.number_input("最多处理候选邮件数（0 为不限制）", min_value=0, value=0, step=1)

enabled_ids = [str(account.get("id")) for account in accounts if bool(account.get("enabled", True))]
selected = st.multiselect("运行账号", options=[str(account.get("id")) for account in accounts], default=enabled_ids)

manifests = manifest_files()
base_options = ["不合并旧台账"] + [str(path) for path in manifests[:20]]
base_choice = st.selectbox("合并到已有台账", base_options, index=0)
reprocess = st.checkbox("强制重跑已处理邮件", value=False)

if base_choice != "不合并旧台账":
    summary = summarize_csv(Path(base_choice))
    if summary:
        st.caption(f"基准台账：正式发票 {summary['formal']} 张，金额合计 {summary['amount']}")

if st.button("开始整理", type="primary", disabled=not selected):
    cmd = [
        str(PYTHON),
        str(RUNNER),
        "--accounts",
        str(CONFIG_PATH),
        "--since",
        since.isoformat(),
        "--until",
        until.isoformat(),
    ]
    for account_id in selected:
        cmd.extend(["--account", account_id])
    if int(limit) > 0:
        cmd.extend(["--limit", str(int(limit))])
    if reprocess:
        cmd.append("--reprocess")
    if base_choice != "不合并旧台账":
        cmd.extend(["--base-report", base_choice])

    with st.status("正在整理发票...", expanded=True) as status:
        result = subprocess.run(cmd, cwd=str(WORKSPACE_ROOT), text=True, capture_output=True)
        st.code(result.stdout or "(无输出)")
        if result.stderr:
            st.code(result.stderr)
        if result.returncode != 0:
            status.update(label="运行失败", state="error")
        else:
            status.update(label="运行完成", state="complete")
            payload = parse_last_json_object(result.stdout)
            if payload:
                st.success(f"本次新增正式发票 {payload.get('new_formal_invoices', payload.get('formal_invoices'))} 张，金额合计 {payload.get('new_formal_amount', payload.get('formal_amount'))}")
                if payload.get("base_report"):
                    st.caption(f"合并后正式发票 {payload.get('merged_formal_invoices')} 张，金额合计 {payload.get('merged_formal_amount')}")
                st.markdown(f"Excel：`{payload.get('xlsx_report')}`")
                st.markdown(f"CSV：`{payload.get('csv_report')}`")

st.subheader("最近台账")
recent = []
for path in manifests[:10]:
    summary = summarize_csv(path)
    recent.append(
        {
            "文件": path.name,
            "正式发票": summary.get("formal", 0),
            "金额合计": summary.get("amount", 0),
            "路径": str(path),
        }
    )
st.dataframe(recent, use_container_width=True, hide_index=True)

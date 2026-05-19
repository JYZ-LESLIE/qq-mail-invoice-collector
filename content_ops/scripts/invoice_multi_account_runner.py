#!/usr/bin/env python3
"""Multi-account invoice collection runner."""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
from pathlib import Path
import sys
import time
from typing import Iterable

try:
    import yaml  # type: ignore
except Exception as exc:
    raise SystemExit("Missing PyYAML. Run content_ops/invoices/.venv/bin/python -m pip install -r content_ops/invoices/requirements.txt") from exc

SCRIPT_DIR = Path(__file__).resolve().parent
WORKSPACE_ROOT = SCRIPT_DIR.parents[1]
INVOICE_ROOT = WORKSPACE_ROOT / "发票整理"
CONFIG_DIR = INVOICE_ROOT / "私密配置"
REPORT_DIR = INVOICE_ROOT / "台账"
STATE_DIR = INVOICE_ROOT / "运行状态"

sys.path.insert(0, str(SCRIPT_DIR))
import invoice_2026_collector as collector  # noqa: E402
import ledger_invoice_folder  # noqa: E402
import reimbursement_manager  # noqa: E402


def load_accounts_config(path: Path) -> dict[str, object]:
    if not path.exists():
        raise SystemExit(f"找不到多邮箱配置：{path}\n请先复制 content_ops/invoices/private/accounts.example.yaml 到 发票整理/私密配置/accounts.yaml")
    data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    if not isinstance(data, dict):
        raise SystemExit(f"多邮箱配置格式不正确：{path}")
    return data


def load_base_rows(path: Path | None) -> list[dict[str, str]]:
    if not path or not path.exists():
        return []
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        rows = list(csv.DictReader(handle))
    for row in rows:
        row.setdefault("row_source", "base_report")
    return rows


def row_cache_path(account_id: str, since: str, until: str, limit: int | None) -> Path:
    suffix = f"{since.replace('-', '')}_{until.replace('-', '')}"
    if limit:
        suffix += f"_limit{limit}"
    return STATE_DIR / f"rows_{account_id}_{suffix}.jsonl"


def account_log_path(account_id: str) -> Path:
    return STATE_DIR / f"log_{account_id}.db"


def safe_account_id(value: object) -> str:
    text = str(value or "").strip()
    if not text:
        raise SystemExit("accounts.yaml 里每个账号都必须有 id。")
    return "".join(ch if ch.isalnum() or ch in {"_", "-"} else "_" for ch in text)


def enabled_accounts(config: dict[str, object], selected: list[str] | None) -> list[dict[str, object]]:
    raw_accounts = config.get("accounts") or []
    if not isinstance(raw_accounts, list):
        raise SystemExit("accounts.yaml 的 accounts 必须是列表。")
    selected_set = set(selected or [])
    accounts: list[dict[str, object]] = []
    for raw in raw_accounts:
        if not isinstance(raw, dict):
            continue
        account_id = safe_account_id(raw.get("id"))
        if selected_set and account_id not in selected_set:
            continue
        if not selected_set and not bool(raw.get("enabled", True)):
            continue
        account = dict(raw)
        account["id"] = account_id
        accounts.append(account)
    return accounts


def account_overview(config: dict[str, object]) -> list[dict[str, object]]:
    raw_accounts = config.get("accounts") or []
    if not isinstance(raw_accounts, list):
        return []
    overview: list[dict[str, object]] = []
    for raw in raw_accounts:
        if not isinstance(raw, dict):
            continue
        overview.append(
            {
                "id": raw.get("id", ""),
                "label": raw.get("label", ""),
                "provider": raw.get("provider", ""),
                "enabled": bool(raw.get("enabled", True)),
                "imap_host": raw.get("imap_host", ""),
                "mailbox": raw.get("mailbox", "INBOX"),
                "search_mode": raw.get("search_mode", "filtered"),
                "imap_timeout_seconds": raw.get("imap_timeout_seconds", ""),
                "email_env": raw.get("email_env", ""),
                "auth_code_env": raw.get("auth_code_env", ""),
            }
        )
    return overview


def account_env(base_env: dict[str, str], account: dict[str, object]) -> dict[str, str]:
    env = dict(base_env)
    email = str(account.get("email") or env.get(str(account.get("email_env") or "")) or "").strip()
    auth_code = str(account.get("auth_code") or account.get("password") or env.get(str(account.get("auth_code_env") or "")) or "").strip()
    if not email or not auth_code:
        raise SystemExit(
            f"账号 {account.get('id')} 缺少邮箱或授权码。请在 invoice_mail.env 中填写 "
            f"{account.get('email_env') or 'email'} / {account.get('auth_code_env') or 'auth_code'}。"
        )
    env["QQ_EMAIL"] = email
    env["QQ_IMAP_AUTH_CODE"] = auth_code
    env["QQ_IMAP_HOST"] = str(account.get("imap_host") or env.get("QQ_IMAP_HOST") or "imap.qq.com")
    env["QQ_IMAP_PORT"] = str(account.get("imap_port") or env.get("QQ_IMAP_PORT") or "993")
    env["QQ_MAILBOX"] = str(account.get("mailbox") or env.get("QQ_MAILBOX") or "INBOX")
    if account.get("imap_timeout_seconds"):
        env["IMAP_TIMEOUT_SECONDS"] = str(account.get("imap_timeout_seconds") or "")
    if account.get("search_mode"):
        env["INVOICE_SEARCH_MODE"] = str(account.get("search_mode") or "")
    return env


def mask_email(value: str) -> str:
    if "@" not in value:
        return "***"
    name, domain = value.split("@", 1)
    if len(name) <= 2:
        masked = name[:1] + "*"
    else:
        masked = name[:2] + "***" + name[-1:]
    return f"{masked}@{domain}"


def annotate_rows(rows: list[dict[str, str]], account: dict[str, object], env: dict[str, str]) -> list[dict[str, str]]:
    annotated: list[dict[str, str]] = []
    for row in rows:
        item = dict(row)
        item["row_source"] = "current_run"
        item["account_id"] = str(account.get("id") or "")
        item["account_provider"] = str(account.get("provider") or "")
        item["account_email"] = env.get("QQ_EMAIL", "")
        annotated.append(item)
    return annotated


def parse_row_date(value: str) -> dt.date | None:
    text = str(value or "").strip()
    if not text:
        return None
    try:
        return dt.date.fromisoformat(text[:10])
    except ValueError:
        return None


def filter_formal_rows_by_invoice_date(rows: list[dict[str, str]], since: str, until: str) -> list[dict[str, str]]:
    since_date = dt.date.fromisoformat(since)
    until_date = dt.date.fromisoformat(until)
    filtered: list[dict[str, str]] = []
    for row in rows:
        if row.get("status") not in {"Parsed", "AI_Verified"}:
            filtered.append(row)
            continue
        invoice_date = parse_row_date(str(row.get("invoice_date") or ""))
        if invoice_date and since_date <= invoice_date <= until_date:
            filtered.append(row)
    return filtered


def run_accounts(
    *,
    accounts_path: Path,
    since: str,
    until: str,
    limit: int | None,
    selected_accounts: list[str] | None,
    reprocess: bool,
    base_report: Path | None,
) -> dict[str, object]:
    started = time.time()
    for directory in (CONFIG_DIR, REPORT_DIR, STATE_DIR):
        directory.mkdir(parents=True, exist_ok=True)

    config = load_accounts_config(accounts_path)
    global_env_path = Path(str(config.get("global_env") or CONFIG_DIR / "invoice_mail.env"))
    if not global_env_path.is_absolute():
        global_env_path = WORKSPACE_ROOT / global_env_path
    base_env = collector.load_env(global_env_path)
    accounts = enabled_accounts(config, selected_accounts)
    if not accounts:
        raise SystemExit("没有启用的邮箱账号。请检查 accounts.yaml 的 enabled 或 --account 参数。")

    base_rows = load_base_rows(base_report)
    all_new_rows: list[dict[str, str]] = []
    account_summaries: list[dict[str, object]] = []

    for account in accounts:
        account_id = str(account["id"])
        env = account_env(base_env, account)
        log_db = account_log_path(account_id)
        cache_path = row_cache_path(account_id, since, until, limit)
        print(f"开始扫描账号：{account_id} <{mask_email(env.get('QQ_EMAIL', ''))}>")
        rows = collector.scan_mailbox(
            env,
            since,
            until,
            limit,
            log_db=log_db,
            reprocess=reprocess,
            row_cache=cache_path,
        )
        annotated = annotate_rows(rows, account, env)
        all_new_rows.extend(annotated)
        account_summaries.append(
            {
                "account_id": account_id,
                "email": mask_email(env.get("QQ_EMAIL", "")),
                "provider": account.get("provider", ""),
                "rows": len(annotated),
                "row_cache": str(cache_path),
                "log_db": str(log_db),
            }
        )

    all_new_rows = filter_formal_rows_by_invoice_date(all_new_rows, since, until)
    merged_rows = collector.clean_manifest_rows(filter_formal_rows_by_invoice_date(base_rows + all_new_rows, since, until))
    report_path = collector.write_report(merged_rows)
    xlsx_path = collector.write_xlsx_report(merged_rows, report_path)
    invoice_folder_summary = ledger_invoice_folder.prepare_ledger_invoice_folder(report_path, rows=merged_rows)
    reimbursement_rows = reimbursement_manager.sync_pool()
    reimbursement_summary = reimbursement_manager.status_summary(reimbursement_rows)
    formal_rows = [row for row in merged_rows if collector.row_is_countable_invoice(row)]
    new_formal_rows = [row for row in collector.clean_manifest_rows(all_new_rows) if collector.row_is_countable_invoice(row)]
    total_amount = sum(collector.effective_amount(row) for row in formal_rows)
    new_total_amount = sum(collector.effective_amount(row) for row in new_formal_rows)
    summary = {
        "status": "completed",
        "accounts": account_summaries,
        "new_rows": len(all_new_rows),
        "new_formal_invoices": len(new_formal_rows),
        "new_formal_amount": round(new_total_amount, 2),
        "merged_rows": len(merged_rows),
        "formal_invoices": len(new_formal_rows),
        "formal_amount": round(new_total_amount, 2),
        "merged_formal_invoices": len(formal_rows),
        "merged_formal_amount": round(total_amount, 2),
        "csv_report": str(report_path),
        "xlsx_report": str(xlsx_path),
        "invoice_folder": str(invoice_folder_summary.get("invoice_folder") or ""),
        "invoice_folder_manifest": str(invoice_folder_summary.get("manifest_path") or ""),
        "invoice_files": int(invoice_folder_summary.get("invoice_files") or 0),
        "missing_invoice_files": int(invoice_folder_summary.get("missing_files") or 0),
        "cumulative_ledger": str(reimbursement_summary.get("pool_xlsx") or ""),
        "pending_reimbursement_invoices": int(reimbursement_summary.get("pending_invoices") or 0),
        "reimbursed_invoices": int(reimbursement_summary.get("reimbursed_invoices") or 0),
        "base_report": str(base_report or ""),
        "elapsed_seconds": round(time.time() - started, 1),
    }
    summary_path = STATE_DIR / f"multi_account_summary_{dt.datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
    summary_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    summary["summary_path"] = str(summary_path)
    return summary


def main(argv: Iterable[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Run invoice collection across multiple IMAP accounts.")
    parser.add_argument("--accounts", type=Path, default=CONFIG_DIR / "accounts.yaml")
    parser.add_argument("--since", default=dt.date.today().isoformat())
    parser.add_argument("--until", default=dt.date.today().isoformat())
    parser.add_argument("--limit", type=int, default=None)
    parser.add_argument("--account", action="append", default=None, help="Run only this account id. Can be repeated.")
    parser.add_argument("--reprocess", action="store_true")
    parser.add_argument("--base-report", type=Path, default=None, help="Existing CSV manifest to merge with.")
    parser.add_argument("--list-accounts", action="store_true", help="Print configured accounts without reading mailbox credentials.")
    args = parser.parse_args(list(argv) if argv is not None else None)
    if args.list_accounts:
        config = load_accounts_config(args.accounts)
        print(json.dumps({"accounts": account_overview(config)}, ensure_ascii=False, indent=2))
        return 0
    summary = run_accounts(
        accounts_path=args.accounts,
        since=args.since,
        until=args.until,
        limit=args.limit,
        selected_accounts=args.account,
        reprocess=args.reprocess,
        base_report=args.base_report,
    )
    summary_json = json.dumps(summary, ensure_ascii=False)
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    print(f"INVOICE_SUMMARY_JSON={summary_json}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

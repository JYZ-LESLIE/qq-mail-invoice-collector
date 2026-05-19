#!/usr/bin/env python3
"""Read-only iCloud invoice scan wrapper for 发票管家.

This first-stage wrapper only reads existing iCloud scan artifacts and writes a
local status summary. It does not submit invoice applications, send mail,
delete mail, move mail, or transmit company invoice details.
"""

from __future__ import annotations

import csv
import datetime as dt
import json
from pathlib import Path


WORKSPACE_ROOT = Path(__file__).resolve().parents[2]
STATE_DIR = WORKSPACE_ROOT / "发票整理/运行状态"
EXPORT_PACK = Path("/Users/jiyuanzheng/codex_exports/icloud_invoice_prepare_pack")
ARCHIVE_CSV = EXPORT_PACK / "icloud_all_archived_company_invoices_2024_to_now.csv"
SUPPLEMENT_REPORT = EXPORT_PACK / "icloud_2025_2026_supplement_scan_report.txt"
SUPPLEMENT_CANDIDATES = EXPORT_PACK / "icloud_2025_2026_supplement_candidates.csv"
SUPPLEMENT_SEEN_SKIPPED = EXPORT_PACK / "icloud_2025_2026_supplement_seen_skipped.csv"
INDEX_HTML = EXPORT_PACK / "index.html"


def read_csv_rows(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def read_report_value(text: str, label: str) -> int | None:
    for line in text.splitlines():
        if line.startswith(label):
            digits = "".join(ch for ch in line if ch.isdigit())
            return int(digits) if digits else None
    return None


def main() -> int:
    STATE_DIR.mkdir(parents=True, exist_ok=True)

    archived_rows = read_csv_rows(ARCHIVE_CSV)
    candidate_rows = read_csv_rows(SUPPLEMENT_CANDIDATES)
    skipped_rows = read_csv_rows(SUPPLEMENT_SEEN_SKIPPED)
    report_text = SUPPLEMENT_REPORT.read_text(encoding="utf-8") if SUPPLEMENT_REPORT.exists() else ""
    total_amount = round(sum(float(row.get("amount") or 0) for row in archived_rows), 2)
    new_candidates = len(candidate_rows)

    summary = {
        "status": "completed",
        "mode": "readonly_local_artifact_scan",
        "submitted_applications": 0,
        "transmitted_company_info": False,
        "archived_company_invoice_count": len(archived_rows),
        "archived_company_invoice_amount": total_amount,
        "high_relevance_mail_hits": read_report_value(report_text, "跨文件夹命中邮件") or 0,
        "new_icloud_credentials": new_candidates,
        "seen_credentials_skipped": len(skipped_rows),
        "official_query_invoiceable": read_report_value(report_text, "官方查询可开票") or 0,
        "waiting_return_mail": "无" if "等待回邮：无" in report_text else "需查看补漏报告",
        "result_page": str(INDEX_HTML),
        "supplement_report": str(SUPPLEMENT_REPORT),
        "archive_csv": str(ARCHIVE_CSV),
        "generated_at": dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
    }
    out_path = STATE_DIR / f"icloud_readonly_scan_{dt.datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
    summary["summary_path"] = str(out_path)
    out_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")

    print("iCloud 只读扫描完成。")
    print(f"已归档公司抬头 PDF：{summary['archived_company_invoice_count']} 张，金额 {summary['archived_company_invoice_amount']:.2f} 元")
    print(f"补漏高相关邮件：{summary['high_relevance_mail_hits']} 封")
    print(f"新发现 iCloud 正式凭证：{summary['new_icloud_credentials']} 条")
    print("本次没有提交开票申请，没有发送公司资料。")
    print(f"ICLOUD_SCAN_SUMMARY_JSON={json.dumps(summary, ensure_ascii=False)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

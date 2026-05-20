#!/usr/bin/env python3
"""Local reimbursement round manager for 发票管家.

This module keeps a cumulative invoice pool and creates reimbursement rounds
from invoices that have not entered a previous round. It only reads local
ledgers and copies local invoice files; it does not read mailboxes or submit
anything externally.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
import re
import shutil
from pathlib import Path
from typing import Iterable


SCRIPT_DIR = Path(__file__).resolve().parent
WORKSPACE_ROOT = SCRIPT_DIR.parents[1]
INVOICE_ROOT = WORKSPACE_ROOT / "发票整理"
LEDGER_DIR = INVOICE_ROOT / "台账"
REIMBURSEMENT_ROOT = INVOICE_ROOT / "报销管理"
ROUNDS_DIR = REIMBURSEMENT_ROOT / "报销批次"
POOL_FILES_DIR = REIMBURSEMENT_ROOT / "累计池发票文件"
POOL_CSV = REIMBURSEMENT_ROOT / "累计发票池.csv"
POOL_XLSX = REIMBURSEMENT_ROOT / "累计发票池.xlsx"
POOL_REJECTED_CSV = REIMBURSEMENT_ROOT / "累计池不入池清单.csv"
VALID_STATUSES = {"Parsed", "AI_Verified", "已解析", "AI复核"}
UNREIMBURSED = "未报销"
IN_ROUND = "已入批次待提交"
CURRENT_YEAR = dt.date.today().year

POOL_COLUMNS = [
    "发票唯一键",
    "发票号码",
    "开票日期",
    "收款方",
    "付款方",
    "金额",
    "计入金额",
    "发票类型",
    "发票文件",
    "来源台账",
    "首次入池时间",
    "最近更新时间",
    "报销状态",
    "报销批次",
    "报销时间",
    "报销文件夹",
    "备注",
]

REJECTION_COLUMNS = [
    "原因",
    "状态",
    "发票号码",
    "开票日期",
    "收款方",
    "付款方",
    "金额",
    "发票文件",
    "来源台账",
    "邮件主题",
    "备注",
]

FOREIGN_RECEIPT_MARKERS = (
    "auckland",
    "new zealand",
    "united states",
    "usd",
    "eur",
    "gbp",
    "nzd",
    " aud",
    "cad",
    "seats.aero",
    "intercontinental auckland",
    "your receipt",
    "receipt from",
    "amount due",
)

BAD_PARTY_VALUES = {
    "销",
    "购",
    "名称",
    "名称_",
    "销售方",
    "购买方",
    "纳税人识别号",
    "开票人",
}


def now_text() -> str:
    return dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def safe_component(value: object, fallback: str = "未命名") -> str:
    text = str(value or "").strip() or fallback
    text = re.sub(r'[\\/:*?"<>|\r\n\t]+', "_", text)
    text = re.sub(r"\s+", " ", text).strip(" .")
    return text[:80] or fallback


def row_value(row: dict[str, str], *keys: str) -> str:
    for key in keys:
        value = str(row.get(key) or "").strip()
        if value:
            return value
    return ""


def amount_text(value: object) -> str:
    text = str(value or "").replace(",", "").strip()
    if not text:
        return ""
    try:
        return f"{float(text):.2f}"
    except ValueError:
        return text


def has_chinese(value: object) -> bool:
    return bool(re.search(r"[\u4e00-\u9fff]", str(value or "")))


def normalized_invoice_number(value: object) -> str:
    return str(value or "").strip().replace(" ", "")


def is_china_tax_invoice_number(value: object) -> bool:
    number = normalized_invoice_number(value)
    return bool(re.fullmatch(r"\d{8,24}", number))


def is_apple_personal_receipt_number(value: object) -> bool:
    return bool(re.fullmatch(r"MC\d{6,}", normalized_invoice_number(value), flags=re.IGNORECASE))


def party_quality_issue(value: object, *, allow_personal: bool = False) -> str:
    text = str(value or "").strip()
    normalized = re.sub(r"\s+", "", text)
    if not text:
        return "关键字段空白"
    if allow_personal and normalized in {"个人", "季元征", "季元徵"}:
        return ""
    if normalized in BAD_PARTY_VALUES or normalized.startswith("名称_"):
        return "识别到票面标签，不是公司/个人名称"
    if not has_chinese(text):
        return "不是中文税票主体"
    if len(normalized) < 2:
        return "主体名称过短"
    return ""


def row_text(row: dict[str, str], *extra_values: object) -> str:
    values = list(extra_values)
    values.extend(row.get(key, "") for key in row.keys())
    return " ".join(str(value or "") for value in values)


def invoice_year(value: object) -> int | None:
    match = re.search(r"(20\d{2})", str(value or ""))
    if not match:
        return None
    return int(match.group(1))


def foreign_receipt_reason(row: dict[str, str]) -> str:
    combined = row_text(row).lower()
    if any(marker in combined for marker in FOREIGN_RECEIPT_MARKERS):
        return "海外收据/外币账单，不是中国税务发票"
    if "$" in combined and not any(marker in combined for marker in ("增值税", "数电", "电子发票")):
        return "外币符号账单，不是中国税务发票"
    return ""


def invoice_key(row: dict[str, str]) -> str:
    number = row_value(row, "invoice_number", "发票号码")
    if number:
        return f"发票号码:{number}"
    date = row_value(row, "invoice_date", "开票日期")
    seller = row_value(row, "seller", "收款方")
    purchaser = row_value(row, "purchaser", "付款方")
    amount = amount_text(row_value(row, "effective_amount", "计入金额", "amount", "金额"))
    return f"无号码:{date}|{seller}|{purchaser}|{amount}"


def append_note_once(row: dict[str, str], text: str) -> None:
    current = str(row.get("备注") or "").strip()
    if text and text not in current:
        row["备注"] = "；".join(part for part in (current, text) if part)


def cleanup_auto_notes(text: object) -> str:
    stale_notes = {
        "自动修正购买方/销售方颠倒。",
        "按原始发票文件修正购买方/销售方。",
    }
    parts = [part.strip() for part in str(text or "").split("；") if part.strip()]
    return "；".join(part for part in parts if part not in stale_notes)


def looks_like_party_name(value: object) -> bool:
    text = str(value or "").strip()
    if not text or not re.search(r"[\u4e00-\u9fff]", text):
        return False
    if re.fullmatch(r"20\d{2}年\d{1,2}月\d{1,2}日", text) or re.fullmatch(r"20\d{2}[-/.]\d{1,2}[-/.]\d{1,2}", text):
        return False
    if any(token in text for token in ("发票号码", "开票日期", "开票人", "项目名称", "价税合计", "税率", "税额")):
        return False
    return True


def normalized_party_text(value: object) -> str:
    return re.sub(r"[^\w\u4e00-\u9fff]+", "", str(value or ""))


def invoice_pdf_parties(source_text: str) -> tuple[str, str]:
    source = Path(source_text).expanduser()
    if source_text and not source.is_absolute():
        source = (WORKSPACE_ROOT / source).resolve()
    if not source.exists() or source.suffix.lower() != ".pdf":
        return "", ""
    try:
        from invoice_pdf_parser import extract_china_invoice_parties, extract_pdf_text_from_stream

        text = extract_pdf_text_from_stream(source.read_bytes(), max_pages=1)
        lines = [line.strip() for line in text.splitlines() if line.strip()]
        parties = extract_china_invoice_parties(lines)
    except Exception:
        return "", ""
    seller = str(parties.get("seller") or "").strip()
    purchaser = str(parties.get("purchaser") or "").strip()
    if looks_like_party_name(seller) and looks_like_party_name(purchaser):
        return seller, purchaser
    return "", ""


def seller_hint_from_subject(subject: object) -> str:
    text = str(subject or "")
    patterns = (
        r"来自(.+?)的(?:一张)?电子发票",
        r"【(.+?)】开具的(?:数电)?发票",
        r"收到一张【(.+?)】开具的(?:数电)?发票",
        r"【电子发票】(.+?)[（(]",
        r"电子发票下载\s+(.+?)-\d",
    )
    for pattern in patterns:
        match = re.search(pattern, text)
        if match:
            candidate = match.group(1).strip(" 【】[]")
            if looks_like_party_name(candidate):
                return candidate
    return ""


def normalize_pool_parties(row: dict[str, str], source_row: dict[str, str] | None = None) -> dict[str, str]:
    source_row = source_row or {}
    seller = seller_hint_from_subject(source_row.get("mail_subject") or source_row.get("邮件主题"))
    current_seller = str(row.get("收款方") or "").strip()
    current_purchaser = str(row.get("付款方") or "").strip()
    if (
        seller
        and normalized_party_text(seller) == normalized_party_text(current_purchaser)
        and current_seller
        and normalized_party_text(seller) != normalized_party_text(current_seller)
    ):
        row["收款方"] = seller
        row["付款方"] = current_seller
        append_note_once(row, "按邮件开票方线索修正购买方/销售方。")
        return row

    pdf_seller, pdf_purchaser = invoice_pdf_parties(str(row.get("发票文件") or ""))
    if (
        pdf_seller
        and pdf_purchaser
        and normalized_party_text(pdf_seller) == normalized_party_text(current_purchaser)
        and normalized_party_text(pdf_purchaser) == normalized_party_text(current_seller)
    ):
        row["收款方"] = pdf_seller
        row["付款方"] = pdf_purchaser
        append_note_once(row, "按票面购买方/销售方位置修正。")
    return row


def pool_rejection_reason(row: dict[str, str]) -> str:
    status = row_value(row, "status", "状态")
    include = row_value(row, "include_in_summary", "计入汇总") or "是"
    output_file = row_value(row, "output_file", "整理后文件", "发票文件")
    if status and status not in VALID_STATUSES:
        return "未解析成功，保留在人工复核/线索区"
    if include == "否":
        return "已标记不计入汇总"
    if not output_file:
        return "缺少发票文件"

    foreign_reason = foreign_receipt_reason(row)
    if foreign_reason:
        return foreign_reason

    invoice_number = row_value(row, "invoice_number", "发票号码")
    if is_apple_personal_receipt_number(invoice_number):
        return "Apple 个人电子收据号，不是换开后的税务发票号码"
    if not is_china_tax_invoice_number(invoice_number):
        return "缺少有效中国税务发票号码"

    seller = row_value(row, "seller", "收款方")
    purchaser = row_value(row, "purchaser", "付款方")
    seller_issue = party_quality_issue(seller)
    if seller_issue:
        return f"收款方{seller_issue}"
    purchaser_issue = party_quality_issue(purchaser, allow_personal=True)
    if purchaser_issue:
        return f"付款方{purchaser_issue}"

    invoice_date = row_value(row, "invoice_date", "开票日期")
    if not invoice_date:
        return "缺少开票日期"
    year = invoice_year(invoice_date)
    if year and year != CURRENT_YEAR:
        return "非本年度发票，不能进入本轮报销"
    if not amount_text(row_value(row, "effective_amount", "计入金额", "amount", "金额")):
        return "缺少金额"
    return ""


def should_pool_row(row: dict[str, str]) -> bool:
    return not pool_rejection_reason(row)


def rejected_pool_row(row: dict[str, str], ledger_path: Path, reason: str) -> dict[str, str]:
    return {
        "原因": reason,
        "状态": row_value(row, "status", "状态"),
        "发票号码": row_value(row, "invoice_number", "发票号码"),
        "开票日期": row_value(row, "invoice_date", "开票日期"),
        "收款方": row_value(row, "seller", "收款方"),
        "付款方": row_value(row, "purchaser", "付款方"),
        "金额": amount_text(row_value(row, "effective_amount", "计入金额", "amount", "金额")),
        "发票文件": row_value(row, "output_file", "整理后文件", "发票文件"),
        "来源台账": str(ledger_path),
        "邮件主题": row_value(row, "mail_subject", "邮件主题"),
        "备注": row_value(row, "note", "备注"),
    }


def read_csv(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def write_csv(path: Path, rows: list[dict[str, str]], columns: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def write_xlsx(path: Path, rows: list[dict[str, str]], columns: list[str], sheet_name: str) -> None:
    try:
        import pandas as pd
    except Exception:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    df = pd.DataFrame(rows, columns=columns)
    with pd.ExcelWriter(path, engine="openpyxl") as writer:
        df.to_excel(writer, index=False, sheet_name=sheet_name)


def ledger_csv_files(ledger_dir: Path) -> list[Path]:
    if not ledger_dir.exists():
        return []
    return sorted(
        [path for path in ledger_dir.glob("*.csv") if not path.name.startswith("~$")],
        key=lambda path: path.stat().st_mtime,
    )


def pool_row_from_ledger(row: dict[str, str], ledger_path: Path, existing: dict[str, str] | None) -> dict[str, str]:
    timestamp = now_text()
    previous = existing or {}
    output_file = row_value(row, "output_file", "整理后文件", "发票文件")
    source = Path(output_file).expanduser()
    if output_file and not source.is_absolute():
        output_file = str((WORKSPACE_ROOT / source).resolve())
    pooled = {
        "发票唯一键": "",
        "发票号码": row_value(row, "invoice_number", "发票号码"),
        "开票日期": row_value(row, "invoice_date", "开票日期"),
        "收款方": row_value(row, "seller", "收款方"),
        "付款方": row_value(row, "purchaser", "付款方"),
        "金额": amount_text(row_value(row, "amount", "金额")),
        "计入金额": amount_text(row_value(row, "effective_amount", "计入金额", "amount", "金额")),
        "发票类型": row_value(row, "category", "发票类型") or "未分类",
        "发票文件": output_file,
        "来源台账": str(ledger_path),
        "首次入池时间": previous.get("首次入池时间") or timestamp,
        "最近更新时间": timestamp,
        "报销状态": previous.get("报销状态") or UNREIMBURSED,
        "报销批次": previous.get("报销批次") or "",
        "报销时间": previous.get("报销时间") or "",
        "报销文件夹": previous.get("报销文件夹") or "",
        "备注": cleanup_auto_notes(previous.get("备注")),
    }
    normalize_pool_parties(pooled, row)
    pooled["发票唯一键"] = invoice_key(pooled)
    return pooled


def sync_pool(
    *,
    ledger_dir: Path = LEDGER_DIR,
    pool_csv: Path = POOL_CSV,
    pool_xlsx: Path = POOL_XLSX,
) -> list[dict[str, str]]:
    REIMBURSEMENT_ROOT.mkdir(parents=True, exist_ok=True)
    existing_by_key = {row.get("发票唯一键", ""): row for row in read_csv(pool_csv) if row.get("发票唯一键")}
    merged_by_key: dict[str, dict[str, str]] = dict(existing_by_key)
    rejected_rows: list[dict[str, str]] = []

    for ledger_path in ledger_csv_files(ledger_dir):
        for row in read_csv(ledger_path):
            rejection_reason = pool_rejection_reason(row)
            if rejection_reason:
                if row_value(row, "output_file", "整理后文件", "发票文件") or row_value(row, "invoice_number", "发票号码"):
                    rejected_rows.append(rejected_pool_row(row, ledger_path, rejection_reason))
                continue
            raw_key = invoice_key(row)
            candidate = pool_row_from_ledger(row, ledger_path, existing_by_key.get(raw_key) or merged_by_key.get(raw_key))
            key = candidate["发票唯一键"]
            if key != raw_key:
                previous = existing_by_key.get(key) or merged_by_key.get(key) or existing_by_key.get(raw_key) or merged_by_key.get(raw_key)
                candidate = pool_row_from_ledger(row, ledger_path, previous)
                merged_by_key.pop(raw_key, None)
            merged_by_key[key] = candidate

    rows = sorted(
        collapse_safe_duplicate_source_rows(list(merged_by_key.values())),
        key=lambda row: (row.get("开票日期", ""), row.get("收款方", ""), row.get("发票号码", "")),
    )
    write_csv(pool_csv, rows, POOL_COLUMNS)
    write_xlsx(pool_xlsx, rows, POOL_COLUMNS, "累计发票池")
    write_csv(POOL_REJECTED_CSV, rejected_rows, REJECTION_COLUMNS)
    return rows


def normalized_source_path(row: dict[str, str]) -> str:
    source_text = str(row.get("发票文件") or "").strip()
    if not source_text:
        return ""
    source = Path(source_text).expanduser()
    if not source.is_absolute():
        source = (WORKSPACE_ROOT / source).resolve()
    try:
        return str(source.resolve())
    except OSError:
        return str(source)


def duplicate_source_groups(rows: list[dict[str, str]]) -> list[list[dict[str, str]]]:
    by_source: dict[str, list[dict[str, str]]] = {}
    for row in rows:
        source = normalized_source_path(row)
        if source:
            by_source.setdefault(source, []).append(row)
    return [items for items in by_source.values() if len(items) > 1]


def duplicate_issue_rows(groups: list[list[dict[str, str]]]) -> list[dict[str, str]]:
    issue_rows: list[dict[str, str]] = []
    for index, group in enumerate(groups, start=1):
        for row in group:
            issue_rows.append(
                {
                    "重复组": str(index),
                    "发票唯一键": row.get("发票唯一键", ""),
                    "发票号码": row.get("发票号码", ""),
                    "开票日期": row.get("开票日期", ""),
                    "收款方": row.get("收款方", ""),
                    "付款方": row.get("付款方", ""),
                    "金额": row.get("金额", ""),
                    "计入金额": row.get("计入金额", ""),
                    "发票文件": row.get("发票文件", ""),
                    "来源台账": row.get("来源台账", ""),
                    "报销状态": row.get("报销状态", ""),
                }
            )
    return issue_rows


def write_duplicate_manifest(groups: list[list[dict[str, str]]]) -> Path:
    REIMBURSEMENT_ROOT.mkdir(parents=True, exist_ok=True)
    duplicate_path = REIMBURSEMENT_ROOT / f"重复发票文件_{dt.datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"
    write_csv(
        duplicate_path,
        duplicate_issue_rows(groups),
        ["重复组", "发票唯一键", "发票号码", "开票日期", "收款方", "付款方", "金额", "计入金额", "发票文件", "来源台账", "报销状态"],
    )
    return duplicate_path


def can_auto_merge_duplicate_group(group: list[dict[str, str]]) -> bool:
    numbers = {str(row.get("发票号码") or "").strip() for row in group if str(row.get("发票号码") or "").strip()}
    dates = {str(row.get("开票日期") or "").strip() for row in group if str(row.get("开票日期") or "").strip()}
    sellers = {str(row.get("收款方") or "").strip() for row in group if str(row.get("收款方") or "").strip()}
    amounts = {amount_text(row.get("计入金额") or row.get("金额") or "") for row in group if amount_text(row.get("计入金额") or row.get("金额") or "")}
    return len(numbers) <= 1 and len(dates) <= 1 and len(sellers) <= 1 and len(amounts) <= 1


def preferred_duplicate_row(group: list[dict[str, str]]) -> dict[str, str]:
    def score(row: dict[str, str]) -> tuple[int, int, float]:
        source_ledger = Path(str(row.get("来源台账") or ""))
        try:
            ledger_mtime = source_ledger.stat().st_mtime
        except OSError:
            ledger_mtime = 0.0
        non_empty = sum(1 for value in row.values() if str(value or "").strip())
        return (1 if str(row.get("发票号码") or "").strip() else 0, non_empty, ledger_mtime)

    preferred = dict(max(group, key=score))
    status_rows = [row for row in group if is_reimbursed(row)]
    if status_rows:
        status_source = max(status_rows, key=lambda row: str(row.get("报销时间") or row.get("最近更新时间") or ""))
        for key in ["报销状态", "报销批次", "报销时间", "报销文件夹", "备注"]:
            preferred[key] = status_source.get(key, "")
    first_seen = sorted([str(row.get("首次入池时间") or "") for row in group if str(row.get("首次入池时间") or "").strip()])
    if first_seen:
        preferred["首次入池时间"] = first_seen[0]
    notes = [str(row.get("备注") or "").strip() for row in group if str(row.get("备注") or "").strip()]
    merge_note = "自动合并同一发票文件重复记录，保留信息更完整的一条。"
    preferred["备注"] = "；".join(dict.fromkeys([*notes, merge_note]))
    return preferred


def collapse_safe_duplicate_source_rows(rows: list[dict[str, str]]) -> list[dict[str, str]]:
    groups = duplicate_source_groups(rows)
    if not groups:
        return rows
    duplicate_ids = {id(row) for group in groups for row in group if can_auto_merge_duplicate_group(group)}
    collapsed: list[dict[str, str]] = []
    handled_groups: set[int] = set()
    for row in rows:
        if id(row) not in duplicate_ids:
            collapsed.append(row)
            continue
        for index, group in enumerate(groups):
            if index in handled_groups or row not in group or not can_auto_merge_duplicate_group(group):
                continue
            collapsed.append(preferred_duplicate_row(group))
            handled_groups.add(index)
            break
    return collapsed


def is_reimbursed(row: dict[str, str]) -> bool:
    return row.get("报销状态") not in {"", UNREIMBURSED}


def total_amount(rows: list[dict[str, str]]) -> float:
    total = 0.0
    for row in rows:
        try:
            total += float(str(row.get("计入金额") or row.get("金额") or 0).replace(",", ""))
        except ValueError:
            continue
    return round(total, 2)


def date_range(rows: list[dict[str, str]]) -> tuple[str, str]:
    values = sorted({str(row.get("开票日期") or "").strip() for row in rows if str(row.get("开票日期") or "").strip()})
    if not values:
        return "", ""
    return values[0], values[-1]


def unique_target(path: Path) -> Path:
    if not path.exists():
        return path
    counter = 2
    while True:
        candidate = path.with_name(f"{path.stem}_{counter}{path.suffix}")
        if not candidate.exists():
            return candidate
        counter += 1


def copy_invoice(source_text: str, target_dir: Path, target_name: str = "") -> str:
    source = Path(source_text).expanduser()
    if not source.is_absolute():
        source = (WORKSPACE_ROOT / source).resolve()
    if not source.exists():
        return ""
    target_dir.mkdir(parents=True, exist_ok=True)
    target = target_dir / (target_name or source.name)
    if target.exists():
        try:
            if target.stat().st_size == source.stat().st_size:
                return str(target)
        except OSError:
            pass
        target = unique_target(target)
    shutil.copy2(source, target)
    return str(target)


def invoice_copy_name(row: dict[str, str], source_text: str) -> str:
    source = Path(source_text)
    suffix = source.suffix.lower() or ".pdf"
    date = safe_component(row.get("开票日期"), "未知日期")
    seller = safe_component(row.get("收款方"), "未知收款方")
    amount = safe_component(row.get("计入金额") or row.get("金额"), "未知金额")
    number = safe_component(row.get("发票号码") or source.stem, "无号码")
    return f"{date}_{seller}_{amount}_{number}{suffix}"


def clear_previous_generated_files(target_root: Path) -> None:
    manifest_path = target_root / "发票文件清单.csv"
    if not manifest_path.exists():
        return
    try:
        target_root_resolved = target_root.resolve()
    except OSError:
        return
    for row in read_csv(manifest_path):
        copied_text = str(row.get("发票文件") or "").strip()
        if not copied_text:
            continue
        copied = Path(copied_text).expanduser()
        try:
            copied_resolved = copied.resolve()
            copied_resolved.relative_to(target_root_resolved)
        except (OSError, ValueError):
            continue
        if copied_resolved.exists() and copied_resolved.is_file():
            try:
                copied_resolved.unlink()
            except OSError:
                pass
    for folder in sorted([path for path in target_root.rglob("*") if path.is_dir()], key=lambda path: len(path.parts), reverse=True):
        try:
            folder.rmdir()
        except OSError:
            pass


def prepare_invoice_files_folder(
    *,
    scope: str = "pending",
    pool_csv: Path = POOL_CSV,
    folder_root: Path = POOL_FILES_DIR,
) -> dict[str, object]:
    rows = read_csv(pool_csv)
    if scope == "all":
        selected = rows
        folder_name = "全部累计发票"
    else:
        scope = "pending"
        selected = [row for row in rows if not is_reimbursed(row)]
        folder_name = "本轮待报销发票"

    duplicate_groups = duplicate_source_groups(rows)
    if duplicate_groups:
        duplicate_path = write_duplicate_manifest(duplicate_groups)
        return status_summary(
            rows,
            extra={
                "status": "duplicate_files",
                "duplicate_invoice_files": sum(len(group) for group in duplicate_groups),
                "duplicate_invoice_file_groups": len(duplicate_groups),
                "duplicate_manifest": str(duplicate_path),
                "invoice_file_scope": scope,
                "invoice_rows": 0,
                "invoice_files": 0,
                "missing_invoice_files": 0,
            },
        )

    target_root = folder_root / folder_name
    target_root.mkdir(parents=True, exist_ok=True)
    clear_previous_generated_files(target_root)

    copied_rows: list[dict[str, str]] = []
    missing_rows: list[dict[str, str]] = []
    copied_by_source: dict[str, str] = {}

    for row in selected:
        source_text = str(row.get("发票文件") or "").strip()
        source = Path(source_text).expanduser()
        if source_text and not source.is_absolute():
            source = (WORKSPACE_ROOT / source).resolve()
        if not source_text or not source.exists():
            missing_rows.append(
                {
                    "发票唯一键": row.get("发票唯一键", ""),
                    "发票号码": row.get("发票号码", ""),
                    "开票日期": row.get("开票日期", ""),
                    "收款方": row.get("收款方", ""),
                    "金额": row.get("金额", ""),
                    "发票文件": source_text,
                }
            )
            continue
        resolved_source = str(source.resolve())
        if resolved_source in copied_by_source:
            copied_path = copied_by_source[resolved_source]
        else:
            category = safe_component(row.get("发票类型"), "未分类")
            copied_path = copy_invoice(str(source), target_root / category, invoice_copy_name(row, str(source)))
            copied_by_source[resolved_source] = copied_path
        category = safe_component(row.get("发票类型"), "未分类")
        copied_rows.append(
            {
                "发票唯一键": row.get("发票唯一键", ""),
                "发票号码": row.get("发票号码", ""),
                "开票日期": row.get("开票日期", ""),
                "收款方": row.get("收款方", ""),
                "付款方": row.get("付款方", ""),
                "金额": row.get("金额", ""),
                "计入金额": row.get("计入金额", ""),
                "发票类型": category,
                "报销状态": row.get("报销状态", ""),
                "发票文件": copied_path,
                "原路径": resolved_source,
            }
        )

    manifest_path = target_root / "发票文件清单.csv"
    write_csv(
        manifest_path,
        copied_rows,
        ["发票唯一键", "发票号码", "开票日期", "收款方", "付款方", "金额", "计入金额", "发票类型", "报销状态", "发票文件", "原路径"],
    )

    missing_manifest = ""
    missing_path = target_root / "缺失文件清单.csv"
    if missing_rows:
        write_csv(missing_path, missing_rows, ["发票唯一键", "发票号码", "开票日期", "收款方", "金额", "发票文件"])
        missing_manifest = str(missing_path)
    elif missing_path.exists():
        try:
            missing_path.unlink()
        except OSError:
            pass

    return status_summary(
        rows,
        extra={
            "status": "invoice_files_prepared",
            "invoice_file_scope": scope,
            "invoice_folder": str(target_root),
            "invoice_folder_manifest": str(manifest_path),
            "invoice_rows": len(copied_rows),
            "invoice_files": len(copied_by_source),
            "missing_invoice_files": len(missing_rows),
            "missing_manifest": missing_manifest,
        },
    )


def missing_invoice_files(rows: list[dict[str, str]]) -> list[dict[str, str]]:
    missing: list[dict[str, str]] = []
    for row in rows:
        source_text = str(row.get("发票文件") or "").strip()
        source = Path(source_text).expanduser()
        if source_text and not source.is_absolute():
            source = (WORKSPACE_ROOT / source).resolve()
        if not source_text or not source.exists():
            missing.append(
                {
                    "发票唯一键": row.get("发票唯一键", ""),
                    "发票号码": row.get("发票号码", ""),
                    "开票日期": row.get("开票日期", ""),
                    "收款方": row.get("收款方", ""),
                    "金额": row.get("金额", ""),
                    "发票文件": source_text,
                }
            )
    return missing


def write_missing_manifest(rows: list[dict[str, str]], *, prefix: str = "缺失发票文件") -> Path:
    REIMBURSEMENT_ROOT.mkdir(parents=True, exist_ok=True)
    missing_path = REIMBURSEMENT_ROOT / f"{prefix}_{dt.datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"
    write_csv(missing_path, rows, ["发票唯一键", "发票号码", "开票日期", "收款方", "金额", "发票文件"])
    return missing_path


def start_round(
    *,
    round_name: str | None = None,
    ledger_dir: Path = LEDGER_DIR,
    pool_csv: Path = POOL_CSV,
    pool_xlsx: Path = POOL_XLSX,
    rounds_dir: Path = ROUNDS_DIR,
) -> dict[str, object]:
    rows = read_csv(pool_csv)
    pending = [row for row in rows if not is_reimbursed(row)]
    if not pending:
        return status_summary(rows, extra={"status": "no_pending", "round_invoice_count": 0, "round_amount": 0.0})

    duplicate_groups = duplicate_source_groups(rows)
    if duplicate_groups:
        duplicate_path = write_duplicate_manifest(duplicate_groups)
        return status_summary(
            rows,
            extra={
                "status": "duplicate_files",
                "duplicate_invoice_files": sum(len(group) for group in duplicate_groups),
                "duplicate_invoice_file_groups": len(duplicate_groups),
                "duplicate_manifest": str(duplicate_path),
                "round_invoice_count": 0,
                "round_amount": 0.0,
            },
        )

    missing_rows = missing_invoice_files(pending)
    if missing_rows:
        missing_path = write_missing_manifest(missing_rows)
        return status_summary(
            rows,
            extra={
                "status": "missing_files",
                "missing_invoice_files": len(missing_rows),
                "missing_manifest": str(missing_path),
                "round_invoice_count": 0,
                "round_amount": 0.0,
            },
        )

    round_id = safe_component(round_name or f"报销批次_{dt.datetime.now().strftime('%Y%m%d_%H%M%S')}", "报销批次")
    round_dir = rounds_dir / round_id
    invoice_dir = round_dir / "发票文件"
    round_dir.mkdir(parents=True, exist_ok=True)
    created_at = now_text()

    round_rows: list[dict[str, str]] = []
    copy_failures: list[dict[str, str]] = []
    for row in pending:
        source_text = row.get("发票文件", "")
        copied_path = copy_invoice(
            source_text,
            invoice_dir / safe_component(row.get("发票类型"), "未分类"),
            invoice_copy_name(row, source_text),
        )
        if not copied_path:
            copy_failures.append(
                {
                    "发票唯一键": row.get("发票唯一键", ""),
                    "发票号码": row.get("发票号码", ""),
                    "开票日期": row.get("开票日期", ""),
                    "收款方": row.get("收款方", ""),
                    "金额": row.get("金额", ""),
                    "发票文件": row.get("发票文件", ""),
                }
            )
            continue
        updated = dict(row)
        updated["报销状态"] = IN_ROUND
        updated["报销批次"] = round_id
        updated["报销时间"] = created_at
        updated["报销文件夹"] = str(round_dir)
        updated["备注"] = "已放入报销批次，后续新批次默认排除。"
        round_item = dict(updated)
        round_item["本批次文件"] = copied_path
        round_rows.append(round_item)

    if copy_failures:
        missing_path = write_missing_manifest(copy_failures, prefix="复制失败发票文件")
        return status_summary(
            rows,
            extra={
                "status": "missing_files",
                "missing_invoice_files": len(copy_failures),
                "missing_manifest": str(missing_path),
                "round_invoice_count": 0,
                "round_amount": 0.0,
            },
        )

    updated_by_key = {row["发票唯一键"]: row for row in rows}
    for row in round_rows:
        pool_item = {key: row.get(key, "") for key in POOL_COLUMNS}
        updated_by_key[row["发票唯一键"]] = pool_item
    updated_rows = sorted(updated_by_key.values(), key=lambda row: (row.get("开票日期", ""), row.get("收款方", ""), row.get("发票号码", "")))
    write_csv(pool_csv, updated_rows, POOL_COLUMNS)
    write_xlsx(pool_xlsx, updated_rows, POOL_COLUMNS, "累计发票池")

    round_columns = POOL_COLUMNS + ["本批次文件"]
    round_csv = round_dir / "本轮报销清单.csv"
    round_xlsx = round_dir / "本轮报销清单.xlsx"
    write_csv(round_csv, round_rows, round_columns)
    write_xlsx(round_xlsx, round_rows, round_columns, "本轮报销清单")

    metadata = {
        "round_id": round_id,
        "created_at": created_at,
        "round_folder": str(round_dir),
        "round_csv": str(round_csv),
        "round_xlsx": str(round_xlsx),
        "invoice_folder": str(invoice_dir),
        "round_invoice_count": len(round_rows),
        "round_amount": total_amount(round_rows),
    }
    (round_dir / "报销批次摘要.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8")
    return status_summary(updated_rows, extra={"status": "round_created", **metadata})


def latest_round(rounds_dir: Path = ROUNDS_DIR) -> dict[str, object]:
    rounds = list_rounds(rounds_dir=rounds_dir, limit=1)
    return rounds[0] if rounds else {}


def list_rounds(*, rounds_dir: Path = ROUNDS_DIR, limit: int = 8) -> list[dict[str, object]]:
    if not rounds_dir.exists():
        return []
    metadata_files = sorted(rounds_dir.glob("*/报销批次摘要.json"), key=lambda path: path.stat().st_mtime, reverse=True)
    records: list[dict[str, object]] = []
    for metadata_path in metadata_files[:limit]:
        round_dir = metadata_path.parent
        modified_at = dt.datetime.fromtimestamp(metadata_path.stat().st_mtime).strftime("%Y-%m-%d %H:%M:%S")
        try:
            metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
        except Exception:
            metadata = {}
        metadata.setdefault("round_id", round_dir.name)
        metadata.setdefault("round_folder", str(round_dir))
        metadata.setdefault("round_csv", str(round_dir / "本轮报销清单.csv"))
        metadata.setdefault("round_xlsx", str(round_dir / "本轮报销清单.xlsx"))
        metadata.setdefault("invoice_folder", str(round_dir / "发票文件"))
        metadata.setdefault("created_at", modified_at)
        metadata["modified_at"] = modified_at
        records.append(metadata)
    return records


def issue_manifests(*, reimbursement_root: Path = REIMBURSEMENT_ROOT, limit: int = 6) -> list[dict[str, object]]:
    if not reimbursement_root.exists():
        return []
    files = sorted(
        list(reimbursement_root.glob("缺失发票文件_*.csv"))
        + list(reimbursement_root.glob("复制失败发票文件_*.csv"))
        + list(reimbursement_root.glob("重复发票文件_*.csv")),
        key=lambda path: path.stat().st_mtime,
        reverse=True,
    )
    records: list[dict[str, object]] = []
    for path in files[:limit]:
        modified_at = dt.datetime.fromtimestamp(path.stat().st_mtime).strftime("%Y-%m-%d %H:%M:%S")
        records.append(
            {
                "name": path.name,
                "path": str(path),
                "modified_at": modified_at,
                "rows": len(read_csv(path)),
            }
        )
    return records


def pool_rejection_summary(path: Path = POOL_REJECTED_CSV) -> dict[str, object]:
    rows = read_csv(path)
    by_reason: dict[str, int] = {}
    for row in rows:
        reason = str(row.get("原因") or "未说明").strip()
        by_reason[reason] = by_reason.get(reason, 0) + 1
    return {
        "pool_rejected_csv": str(path),
        "pool_rejected_rows": len(rows),
        "pool_rejected_by_reason": by_reason,
    }


def manifest_file_issues(manifest_path: Path, *, expected_rows: int | None = None) -> list[dict[str, str]]:
    issues: list[dict[str, str]] = []
    rows = read_csv(manifest_path)
    if expected_rows is not None and len(rows) != expected_rows:
        issues.append({"类型": "清单数量不一致", "说明": f"清单 {len(rows)} 条，应为 {expected_rows} 条", "文件": str(manifest_path)})
    seen_paths: set[str] = set()
    for index, row in enumerate(rows, start=2):
        file_text = str(row.get("发票文件") or "").strip()
        if not file_text:
            issues.append({"类型": "清单缺少发票文件路径", "说明": f"第 {index} 行没有发票文件路径", "文件": str(manifest_path)})
            continue
        file_path = Path(file_text).expanduser()
        if not file_path.is_absolute():
            file_path = (WORKSPACE_ROOT / file_path).resolve()
        resolved = str(file_path)
        if resolved in seen_paths:
            issues.append({"类型": "清单重复文件", "说明": f"第 {index} 行重复指向同一个发票文件", "文件": resolved})
        seen_paths.add(resolved)
        if not file_path.exists():
            issues.append({"类型": "清单文件不存在", "说明": f"第 {index} 行指向的发票文件不存在", "文件": resolved})
    return issues


def audit_pool_rows(rows: list[dict[str, str]]) -> list[dict[str, str]]:
    issues: list[dict[str, str]] = []
    for index, row in enumerate(rows, start=2):
        reason = pool_rejection_reason(row)
        if reason:
            issues.append(
                {
                    "类型": "累计池记录不合格",
                    "说明": reason,
                    "行号": str(index),
                    "发票号码": row.get("发票号码", ""),
                    "发票文件": row.get("发票文件", ""),
                }
            )
    for group_index, group in enumerate(duplicate_source_groups(rows), start=1):
        for row in group:
            issues.append(
                {
                    "类型": "同一发票文件对应多条记录",
                    "说明": f"重复组 {group_index}",
                    "发票号码": row.get("发票号码", ""),
                    "发票文件": row.get("发票文件", ""),
                }
            )
    for row in missing_invoice_files(rows):
        issues.append(
            {
                "类型": "累计池发票文件缺失",
                "说明": row.get("收款方", ""),
                "发票号码": row.get("发票号码", ""),
                "发票文件": row.get("发票文件", ""),
            }
        )
    return issues


def audit_summary(rows: list[dict[str, str]]) -> dict[str, object]:
    pending = [row for row in rows if not is_reimbursed(row)]
    issues = audit_pool_rows(rows)
    pending_manifest = POOL_FILES_DIR / "本轮待报销发票" / "发票文件清单.csv"
    all_manifest = POOL_FILES_DIR / "全部累计发票" / "发票文件清单.csv"
    if pending_manifest.exists():
        issues.extend(manifest_file_issues(pending_manifest, expected_rows=len(pending)))
    if all_manifest.exists():
        issues.extend(manifest_file_issues(all_manifest, expected_rows=len(rows)))
    by_type: dict[str, int] = {}
    for issue in issues:
        issue_type = issue.get("类型", "未分类")
        by_type[issue_type] = by_type.get(issue_type, 0) + 1
    return {
        **status_summary(rows),
        "status": "audit_passed" if not issues else "audit_failed",
        "audit_issues": len(issues),
        "audit_issues_by_type": by_type,
        "audit_issue_examples": issues[:20],
    }


def status_summary(rows: list[dict[str, str]], extra: dict[str, object] | None = None) -> dict[str, object]:
    reimbursed = [row for row in rows if is_reimbursed(row)]
    pending = [row for row in rows if not is_reimbursed(row)]
    duplicate_groups = duplicate_source_groups(rows)
    summary: dict[str, object] = {
        "status": "completed",
        "pool_csv": str(POOL_CSV),
        "pool_xlsx": str(POOL_XLSX),
        "reimbursement_root": str(REIMBURSEMENT_ROOT),
        "rounds_dir": str(ROUNDS_DIR),
        "pool_exists": POOL_CSV.exists(),
        "total_invoices": len(rows),
        "total_amount": total_amount(rows),
        "pending_invoices": len(pending),
        "pending_amount": total_amount(pending),
        "pending_date_from": date_range(pending)[0],
        "pending_date_to": date_range(pending)[1],
        "reimbursed_invoices": len(reimbursed),
        "reimbursed_amount": total_amount(reimbursed),
        "duplicate_invoice_files": sum(len(group) for group in duplicate_groups),
        "duplicate_invoice_file_groups": len(duplicate_groups),
        "latest_round": latest_round(),
        "rounds": list_rounds(),
        "missing_manifests": issue_manifests(),
        **pool_rejection_summary(),
    }
    if extra:
        summary.update(extra)
    return summary


def main(argv: Iterable[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Manage reimbursement rounds from local invoice ledgers.")
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("status")
    subparsers.add_parser("audit")
    subparsers.add_parser("refresh")
    files_parser = subparsers.add_parser("prepare-files")
    files_parser.add_argument("--scope", choices=["pending", "all"], default="pending")
    start_parser = subparsers.add_parser("start-round")
    start_parser.add_argument("--name", default="")
    args = parser.parse_args(list(argv) if argv is not None else None)

    if args.command == "status":
        summary = status_summary(read_csv(POOL_CSV))
    elif args.command == "audit":
        summary = audit_summary(read_csv(POOL_CSV))
    elif args.command == "refresh":
        rows = sync_pool()
        summary = status_summary(rows)
    elif args.command == "prepare-files":
        summary = prepare_invoice_files_folder(scope=args.scope)
    elif args.command == "start-round":
        summary = start_round(round_name=args.name or None)
    else:
        raise SystemExit(f"Unknown command: {args.command}")

    print(json.dumps(summary, ensure_ascii=False, indent=2))
    print(f"REIMBURSEMENT_SUMMARY_JSON={json.dumps(summary, ensure_ascii=False)}")
    return 2 if summary.get("status") == "audit_failed" else 0


if __name__ == "__main__":
    raise SystemExit(main())

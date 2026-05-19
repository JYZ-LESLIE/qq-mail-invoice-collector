#!/usr/bin/env python3
"""Prepare a per-ledger invoice folder for 发票管家.

The folder is built from the ledger CSV and contains copies of the invoice
files referenced by that ledger. It is a local packaging helper only; it does
not read mailboxes or contact any external service.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import shutil
from pathlib import Path
from typing import Iterable


SCRIPT_DIR = Path(__file__).resolve().parent
WORKSPACE_ROOT = SCRIPT_DIR.parents[1]
INVOICE_ROOT = WORKSPACE_ROOT / "发票整理"
LEDGER_INVOICE_ROOT = INVOICE_ROOT / "台账对应发票"
MANIFEST_NAME = "发票文件清单.csv"
VALID_STATUSES = {"Parsed", "AI_Verified", "已解析", "AI复核"}


def safe_component(value: object, fallback: str = "未分类") -> str:
    text = str(value or "").strip() or fallback
    text = re.sub(r'[\\/:*?"<>|\r\n\t]+', "_", text)
    text = re.sub(r"\s+", " ", text).strip(" .")
    return text[:80] or fallback


def sibling_csv_for(path: Path) -> Path:
    if path.suffix.lower() == ".csv":
        return path
    candidate = path.with_suffix(".csv")
    if candidate.exists():
        return candidate
    raise FileNotFoundError(f"找不到与台账对应的 CSV：{candidate}")


def read_ledger_rows(ledger_path: Path) -> tuple[Path, list[dict[str, str]]]:
    csv_path = sibling_csv_for(ledger_path)
    with csv_path.open("r", encoding="utf-8-sig", newline="") as handle:
        return csv_path, list(csv.DictReader(handle))


def row_value(row: dict[str, str], *keys: str) -> str:
    for key in keys:
        value = str(row.get(key) or "").strip()
        if value:
            return value
    return ""


def should_include(row: dict[str, str]) -> bool:
    status = row_value(row, "status", "状态")
    output_file = row_value(row, "output_file", "整理后文件")
    if not output_file:
        return False
    if status:
        return status in VALID_STATUSES
    return True


def unique_target(path: Path) -> Path:
    if not path.exists():
        return path
    counter = 2
    while True:
        candidate = path.with_name(f"{path.stem}_{counter}{path.suffix}")
        if not candidate.exists():
            return candidate
        counter += 1


def copy_invoice_file(source: Path, target_dir: Path) -> Path:
    target_dir.mkdir(parents=True, exist_ok=True)
    target = target_dir / source.name
    if target.exists():
        try:
            if target.stat().st_size == source.stat().st_size:
                return target
        except OSError:
            pass
        target = unique_target(target)
    shutil.copy2(source, target)
    return target


def prepare_ledger_invoice_folder(
    ledger_path: Path,
    rows: list[dict[str, str]] | None = None,
    *,
    folder_root: Path = LEDGER_INVOICE_ROOT,
) -> dict[str, object]:
    ledger_path = ledger_path.expanduser().resolve()
    csv_path = ledger_path
    if rows is None:
        csv_path, rows = read_ledger_rows(ledger_path)

    folder_name = safe_component(ledger_path.with_suffix("").name, "发票台账")
    target_root = folder_root / folder_name
    target_root.mkdir(parents=True, exist_ok=True)

    copied_rows: list[dict[str, str]] = []
    missing_rows: list[dict[str, str]] = []
    seen_sources: set[str] = set()

    for row in rows:
        if not should_include(row):
            continue
        source_text = row_value(row, "output_file", "整理后文件")
        source = Path(source_text).expanduser()
        if not source.is_absolute():
            source = (WORKSPACE_ROOT / source).resolve()
        if not source.exists() or source_text in seen_sources:
            if not source.exists():
                missing_rows.append(
                    {
                        "发票号码": row_value(row, "invoice_number", "发票号码"),
                        "开票日期": row_value(row, "invoice_date", "开票日期"),
                        "收款方": row_value(row, "seller", "收款方"),
                        "原路径": source_text,
                    }
                )
            continue
        seen_sources.add(source_text)
        category = safe_component(row_value(row, "category", "发票类型"), "未分类")
        copied = copy_invoice_file(source, target_root / category)
        copied_rows.append(
            {
                "发票号码": row_value(row, "invoice_number", "发票号码"),
                "开票日期": row_value(row, "invoice_date", "开票日期"),
                "收款方": row_value(row, "seller", "收款方"),
                "付款方": row_value(row, "purchaser", "付款方"),
                "金额": row_value(row, "amount", "金额"),
                "发票类型": category,
                "发票文件": str(copied),
                "原路径": str(source),
            }
        )

    manifest_path = target_root / MANIFEST_NAME
    with manifest_path.open("w", encoding="utf-8-sig", newline="") as handle:
        fieldnames = ["发票号码", "开票日期", "收款方", "付款方", "金额", "发票类型", "发票文件", "原路径"]
        writer = csv.DictWriter(handle, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(copied_rows)

    missing_path = ""
    if missing_rows:
        missing_file = target_root / "缺失文件清单.csv"
        with missing_file.open("w", encoding="utf-8-sig", newline="") as handle:
            fieldnames = ["发票号码", "开票日期", "收款方", "原路径"]
            writer = csv.DictWriter(handle, fieldnames=fieldnames, extrasaction="ignore")
            writer.writeheader()
            writer.writerows(missing_rows)
        missing_path = str(missing_file)

    return {
        "status": "completed",
        "ledger_path": str(ledger_path),
        "csv_path": str(csv_path),
        "invoice_folder": str(target_root),
        "manifest_path": str(manifest_path),
        "invoice_files": len(copied_rows),
        "missing_files": len(missing_rows),
        "missing_manifest": missing_path,
    }


def main(argv: Iterable[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Prepare the invoice folder that matches a ledger.")
    parser.add_argument("ledger", type=Path)
    args = parser.parse_args(list(argv) if argv is not None else None)

    summary = prepare_ledger_invoice_folder(args.ledger)
    print(f"已准备台账对应发票文件夹：{summary['invoice_folder']}")
    print(f"发票文件：{summary['invoice_files']} 个，缺失：{summary['missing_files']} 个")
    print(f"LEDGER_FOLDER_SUMMARY_JSON={json.dumps(summary, ensure_ascii=False)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

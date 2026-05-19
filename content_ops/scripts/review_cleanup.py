#!/usr/bin/env python3
"""Clean review files that are clearly outside the current reimbursement year.

This helper only moves local files inside 发票整理/人工复核. It does not read
mailboxes or submit anything externally. Files without a confident invoice date
are kept in the review queue.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
import re
import shutil
import zipfile
from pathlib import Path
from typing import Iterable


SCRIPT_DIR = Path(__file__).resolve().parent
WORKSPACE_ROOT = SCRIPT_DIR.parents[1]
INVOICE_ROOT = WORKSPACE_ROOT / "发票整理"
REVIEW_ROOT = INVOICE_ROOT / "人工复核"
QR_DIR = REVIEW_ROOT / "二维码线索"
NON_CHINA_DIR = REVIEW_ROOT / "非中国发票"
OUT_OF_YEAR_DIR = REVIEW_ROOT / "非本年度发票"


def current_year() -> int:
    return dt.date.today().year


def safe_component(value: object, fallback: str = "未命名") -> str:
    text = str(value or "").strip() or fallback
    text = re.sub(r'[\\/:*?"<>|\r\n\t]+', "_", text)
    text = re.sub(r"\s+", " ", text).strip(" .")
    return text[:120] or fallback


def unique_target(path: Path) -> Path:
    if not path.exists():
        return path
    counter = 2
    while True:
        candidate = path.with_name(f"{path.stem}_{counter}{path.suffix}")
        if not candidate.exists():
            return candidate
        counter += 1


def is_under(path: Path, folder: Path) -> bool:
    try:
        path.resolve().relative_to(folder.resolve())
        return True
    except (OSError, ValueError):
        return False


def iter_review_candidates(review_root: Path = REVIEW_ROOT) -> list[Path]:
    excluded = [QR_DIR, NON_CHINA_DIR, OUT_OF_YEAR_DIR]
    if not review_root.exists():
        return []
    candidates: list[Path] = []
    for path in review_root.rglob("*"):
        if not path.is_file() or path.name.startswith("."):
            continue
        if any(is_under(path, folder) for folder in excluded):
            continue
        candidates.append(path)
    return sorted(candidates)


def normalize_date(year: str, month: str, day: str) -> str:
    try:
        value = dt.date(int(year), int(month), int(day))
    except ValueError:
        return ""
    return value.isoformat()


def date_from_text(text: str) -> str:
    compact = re.sub(r"\s+", "", text or "")
    date_label = r"(?:开票日期|发票日期|填开日期|出票日期|InvoiceDate|IssueDate|IssueTime)"
    patterns = [
        rf"{date_label}[^0-9]{{0,12}}(20\d{{2}})年(\d{{1,2}})月(\d{{1,2}})日",
        rf"{date_label}[^0-9]{{0,12}}(20\d{{2}})[-/.](\d{{1,2}})[-/.](\d{{1,2}})",
    ]
    for pattern in patterns:
        match = re.search(pattern, compact)
        if match:
            normalized = normalize_date(match.group(1), match.group(2), match.group(3))
            if normalized:
                return normalized
    return ""


def date_from_filename(path: Path) -> str:
    name = path.name
    labeled = date_from_text(name)
    if labeled:
        return labeled
    patterns = [
        r"^(20\d{2})[-_.](\d{1,2})[-_.](\d{1,2})(?:\D|$)",
        r"^(20\d{2})(\d{2})(\d{2})(?:\D|$)",
    ]
    for pattern in patterns:
        match = re.search(pattern, name)
        if match:
            normalized = normalize_date(match.group(1), match.group(2), match.group(3))
            if normalized:
                return normalized
    return ""


def read_text_best_effort(path: Path, max_bytes: int = 512_000) -> str:
    data = path.read_bytes()[:max_bytes]
    for encoding in ("utf-8", "gb18030", "utf-16", "latin1"):
        try:
            return data.decode(encoding, errors="ignore")
        except Exception:
            continue
    return ""


def date_from_pdf(path: Path) -> str:
    try:
        from invoice_pdf_parser import extract_invoice_date, extract_pdf_text_from_stream
    except Exception:
        return ""
    try:
        text = extract_pdf_text_from_stream(path.read_bytes(), max_pages=2)
    except Exception:
        return ""
    if not text:
        return ""
    compact = re.sub(r"\s+", "", text)
    return extract_invoice_date(compact, [line.strip() for line in text.splitlines() if line.strip()]) or date_from_text(text)


def date_from_ofd(path: Path) -> str:
    try:
        with zipfile.ZipFile(path) as archive:
            for info in archive.infolist():
                if info.is_dir() or not info.filename.lower().endswith(".xml") or info.file_size > 1024 * 1024:
                    continue
                text = archive.read(info).decode("utf-8", errors="ignore")
                invoice_date = date_from_text(text)
                if invoice_date:
                    return invoice_date
    except Exception:
        return ""
    return ""


def detect_invoice_date(path: Path) -> tuple[str, str]:
    invoice_date = date_from_filename(path)
    if invoice_date:
        return invoice_date, "filename"
    suffix = path.suffix.lower()
    if suffix == ".pdf":
        invoice_date = date_from_pdf(path)
        if invoice_date:
            return invoice_date, "pdf_text"
    if suffix == ".xml":
        invoice_date = date_from_text(read_text_best_effort(path))
        if invoice_date:
            return invoice_date, "xml_text"
    if suffix == ".ofd":
        invoice_date = date_from_ofd(path)
        if invoice_date:
            return invoice_date, "ofd_text"
    return "", ""


def write_manifest(path: Path, rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    columns = ["原路径", "新路径", "开票日期", "识别方式", "处理时间"]
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def cleanup_out_of_year(*, target_year: int, dry_run: bool = False) -> dict[str, object]:
    candidates = iter_review_candidates()
    moved_rows: list[dict[str, str]] = []
    unknown_count = 0
    current_year_count = 0

    for path in candidates:
        invoice_date, source = detect_invoice_date(path)
        if not invoice_date:
            unknown_count += 1
            continue
        year = int(invoice_date[:4])
        if year == target_year:
            current_year_count += 1
            continue
        target_dir = OUT_OF_YEAR_DIR / str(year)
        target = unique_target(target_dir / safe_component(path.name, path.name))
        moved_rows.append(
            {
                "原路径": str(path),
                "新路径": str(target),
                "开票日期": invoice_date,
                "识别方式": source,
                "处理时间": dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            }
        )
        if not dry_run:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(path), str(target))

    manifest_path = ""
    if moved_rows and not dry_run:
        manifest = OUT_OF_YEAR_DIR / f"非本年度清理清单_{dt.datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"
        write_manifest(manifest, moved_rows)
        manifest_path = str(manifest)

    summary = {
        "status": "completed",
        "target_year": target_year,
        "dry_run": dry_run,
        "scanned_files": len(candidates),
        "moved_files": len(moved_rows),
        "current_year_files": current_year_count,
        "unknown_date_files": unknown_count,
        "archive_folder": str(OUT_OF_YEAR_DIR),
        "manifest_path": manifest_path,
    }
    return summary


def main(argv: Iterable[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Move non-current-year review files out of the review queue.")
    parser.add_argument("--year", type=int, default=current_year())
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(list(argv) if argv is not None else None)

    summary = cleanup_out_of_year(target_year=args.year, dry_run=args.dry_run)
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    print(f"REVIEW_CLEANUP_SUMMARY_JSON={json.dumps(summary, ensure_ascii=False)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

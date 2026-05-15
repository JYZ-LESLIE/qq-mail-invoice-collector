#!/usr/bin/env python3
"""Invoice PDF parsing helpers built around raw PDF bytes."""

from __future__ import annotations

import base64
import json
from pathlib import Path
import random
import re
import shutil
import subprocess
import tempfile
import time
from typing import Callable
from urllib import request as urlrequest
from urllib.error import HTTPError, URLError


URL_RE = re.compile(r"https?://[^\s\"'<>）)]+", re.IGNORECASE)


def parse_invoice_pdf_stream(
    pdf_bytes: bytes,
    filename: str = "",
    vision_extract: Callable[[list[str], str], dict[str, str]] | None = None,
    max_pages: int = 2,
) -> dict[str, object]:
    """Parse an invoice PDF from raw bytes.

    Text extraction is attempted first. If key fields remain incomplete and a
    vision extractor is supplied, pages are rendered to image data URLs and sent
    to the extractor.
    """

    result: dict[str, object] = {
        "source_filename": filename,
        "status": "unknown",
        "engine": "",
        "invoice_date": "",
        "seller": "",
        "purchaser": "",
        "amount": "",
        "invoice_code": "",
        "invoice_number": "",
        "invoice_kind": "",
        "category": "",
        "links": [],
        "raw_text": "",
        "error": "",
    }

    if not pdf_bytes or len(pdf_bytes) < 128:
        result.update(status="invalid_pdf", error="empty_or_too_small_pdf")
        return result

    raw_text = extract_pdf_text_from_stream(pdf_bytes, max_pages=max_pages)
    result["raw_text"] = raw_text[:20000]
    result["links"] = extract_links_from_text(raw_text)
    if should_reject_as_non_china_invoice(raw_text):
        result.update(status="non_china_invoice", engine="pdf_text", error="non_china_invoice")
        return result

    fields = parse_invoice_fields_from_text(raw_text)
    if has_minimum_invoice_fields(fields):
        result.update(fields)
        result.update(status="parsed", engine="pdf_text")
        return result

    if vision_extract:
        image_data_urls = render_pdf_pages_to_data_urls(pdf_bytes, max_pages=max_pages)
        if image_data_urls:
            prompt = invoice_extraction_prompt(raw_text)
            ai_fields = normalize_ai_fields(vision_extract(image_data_urls, prompt) or {})
            merged = {**fields, **{k: v for k, v in ai_fields.items() if v}}
            result.update(merged)
            result.update(
                status="parsed" if has_minimum_invoice_fields(merged) else "need_review",
                engine="vision_fallback",
            )
            return result

    result.update(fields)
    result.update(status="need_review", engine="pdf_text_partial")
    return result


def parse_invoice_pdf_pages(
    pdf_bytes: bytes,
    filename: str = "",
    vision_extract: Callable[[list[str], str], dict[str, str]] | None = None,
) -> list[dict[str, object]]:
    """Parse each PDF page as a separate invoice candidate."""
    if not pdf_bytes or len(pdf_bytes) < 128:
        return [parse_invoice_pdf_stream(pdf_bytes, filename=filename, vision_extract=vision_extract)]

    try:
        import fitz  # type: ignore
    except Exception:
        parsed = parse_invoice_pdf_stream(pdf_bytes, filename=filename, vision_extract=vision_extract)
        parsed.update(page_number=1, page_count=1)
        return [parsed]

    pages: list[dict[str, object]] = []
    try:
        with fitz.open(stream=pdf_bytes, filetype="pdf") as doc:
            page_count = len(doc)
            for page_index in range(page_count):
                page = doc.load_page(page_index)
                raw_text = (page.get_text("text") or "").replace("\xa0", " ").strip()
                fields = parse_invoice_fields_from_text(raw_text)
                links = extract_links_from_text(raw_text)
                result: dict[str, object] = {
                    "source_filename": filename,
                    "status": "unknown",
                    "engine": "",
                    "page_number": page_index + 1,
                    "page_count": page_count,
                    "invoice_date": "",
                    "seller": "",
                    "purchaser": "",
                    "amount": "",
                    "invoice_code": "",
                    "invoice_number": "",
                    "invoice_kind": "",
                    "category": "",
                    "links": links,
                    "raw_text": raw_text[:20000],
                    "error": "",
                }
                if should_reject_as_non_china_invoice(raw_text):
                    result.update(status="non_china_invoice", engine="pdf_text", error="non_china_invoice")
                    pages.append(result)
                    continue
                if has_minimum_invoice_fields(fields):
                    result.update(fields)
                    result.update(status="parsed", engine="pdf_text")
                    pages.append(result)
                    continue

                if vision_extract:
                    data_url = render_pdf_page_to_data_url(pdf_bytes, page_index)
                    if data_url:
                        prompt = invoice_extraction_prompt(raw_text)
                        ai_fields = normalize_ai_fields(vision_extract([data_url], prompt) or {})
                        merged = {**fields, **{k: v for k, v in ai_fields.items() if v}}
                        result.update(merged)
                        result.update(
                            status="parsed" if has_minimum_invoice_fields(merged) else "need_review",
                            engine="vision_fallback",
                        )
                        pages.append(result)
                        continue

                result.update(fields)
                result.update(status="need_review", engine="pdf_text_partial")
                pages.append(result)
    except Exception as exc:
        parsed = parse_invoice_pdf_stream(pdf_bytes, filename=filename, vision_extract=vision_extract)
        parsed.update(page_number=1, page_count=1, error=str(exc) or str(parsed.get("error", "")))
        return [parsed]

    return pages or [parse_invoice_pdf_stream(pdf_bytes, filename=filename, vision_extract=vision_extract)]


def split_pdf_page_to_bytes(pdf_bytes: bytes, page_index: int) -> bytes:
    """Return a one-page PDF for a 0-based page index."""
    try:
        import fitz  # type: ignore
    except Exception:
        return pdf_bytes
    try:
        with fitz.open(stream=pdf_bytes, filetype="pdf") as src:
            with fitz.open() as dst:
                dst.insert_pdf(src, from_page=page_index, to_page=page_index)
                return bytes(dst.tobytes(garbage=4, deflate=True))
    except Exception:
        return pdf_bytes


def extract_pdf_text_from_stream(pdf_bytes: bytes, max_pages: int = 2) -> str:
    extractors = (
        _extract_text_with_pymupdf,
        _extract_text_with_pypdf,
        _extract_text_with_pdftotext,
        _extract_text_from_raw_pdf_bytes,
    )
    for extractor in extractors:
        text = extractor(pdf_bytes, max_pages)
        if looks_like_useful_pdf_text(text):
            return text
    return ""


def _extract_text_with_pymupdf(pdf_bytes: bytes, max_pages: int) -> str:
    try:
        import fitz  # type: ignore
    except Exception:
        return ""
    try:
        with fitz.open(stream=pdf_bytes, filetype="pdf") as doc:
            parts = []
            for page_index in range(min(max_pages, len(doc))):
                parts.append(doc.load_page(page_index).get_text("text") or "")
            return "\n".join(parts).replace("\xa0", " ").strip()
    except Exception:
        return ""


def _extract_text_with_pypdf(pdf_bytes: bytes, max_pages: int) -> str:
    try:
        from pypdf import PdfReader  # type: ignore
    except Exception:
        try:
            from PyPDF2 import PdfReader  # type: ignore
        except Exception:
            return ""
    try:
        import io

        reader = PdfReader(io.BytesIO(pdf_bytes))
        parts = []
        for page in list(reader.pages)[:max_pages]:
            parts.append(page.extract_text() or "")
        return "\n".join(parts).replace("\xa0", " ").strip()
    except Exception:
        return ""


def _extract_text_with_pdftotext(pdf_bytes: bytes, max_pages: int) -> str:
    pdftotext = shutil.which("pdftotext")
    if not pdftotext:
        return ""
    with tempfile.NamedTemporaryFile(suffix=".pdf") as handle:
        handle.write(pdf_bytes)
        handle.flush()
        try:
            result = subprocess.run(
                [pdftotext, "-layout", "-f", "1", "-l", str(max_pages), handle.name, "-"],
                check=False,
                capture_output=True,
                text=True,
                timeout=25,
            )
        except Exception:
            return ""
    if result.returncode != 0:
        return ""
    return result.stdout.replace("\xa0", " ").strip()


def _extract_text_from_raw_pdf_bytes(pdf_bytes: bytes, max_pages: int) -> str:
    del max_pages
    try:
        decoded = pdf_bytes.decode("utf-8", errors="ignore")
    except Exception:
        return ""
    readable = re.sub(r"[^\x20-\x7E\u4e00-\u9fff，。；：￥（）《》、]+", "\n", decoded)
    lines = [line.strip() for line in readable.splitlines() if line.strip()]
    joined = "\n".join(lines)
    if looks_like_useful_pdf_text(joined):
        return "\n".join(lines[:300]).strip()

    chunks = []
    for match in re.finditer(r"\(([^()]{2,200})\)", decoded):
        value = match.group(1)
        if any(token in value for token in ("发票", "开票", "名称", "价税", "invoice", "Invoice")):
            chunks.append(value)
    return "\n".join(chunks[:200]).strip()


def looks_like_useful_pdf_text(text: str) -> bool:
    normalized = (text or "").strip()
    if len(normalized) < 20:
        return False
    markers = ("发票", "电子发票", "开票日期", "价税合计", "购买方", "销售方", "invoice", "Invoice")
    return any(marker in normalized for marker in markers)


def is_china_invoice_text(text: str) -> bool:
    normalized = text or ""
    compact = re.sub(r"\s+", "", normalized)
    china_markers = ("电子发票", "增值税", "价税合计", "开票日期", "购买方信息", "销售方信息", "纳税人识别号")
    return "发票" in compact and any(marker in compact for marker in china_markers)


def should_reject_as_non_china_invoice(text: str) -> bool:
    normalized = text or ""
    if not normalized.strip():
        return False
    if is_china_invoice_text(normalized):
        return False
    lower = normalized.lower()
    foreign_markers = ("invoice", "receipt", "amount due", "subtotal", "usd", "united states", "bill to")
    return any(marker in lower for marker in foreign_markers)


def extract_links_from_text(text: str) -> list[str]:
    seen: set[str] = set()
    urls: list[str] = []
    for url in URL_RE.findall(text or ""):
        clean = url.rstrip(".,;，。；")
        if clean not in seen:
            seen.add(clean)
            urls.append(clean)
    return urls


def render_pdf_pages_to_data_urls(pdf_bytes: bytes, max_pages: int = 2) -> list[str]:
    try:
        import fitz  # type: ignore
    except Exception:
        return []
    try:
        with fitz.open(stream=pdf_bytes, filetype="pdf") as doc:
            images = []
            matrix = fitz.Matrix(2.0, 2.0)
            for page_index in range(min(max_pages, len(doc))):
                pix = doc.load_page(page_index).get_pixmap(matrix=matrix, alpha=False)
                png_bytes = pix.tobytes("png")
                b64 = base64.b64encode(png_bytes).decode("utf-8")
                images.append(f"data:image/png;base64,{b64}")
            return images
    except Exception:
        return []


def render_pdf_page_to_data_url(pdf_bytes: bytes, page_index: int) -> str:
    try:
        import fitz  # type: ignore
    except Exception:
        return ""
    try:
        with fitz.open(stream=pdf_bytes, filetype="pdf") as doc:
            if page_index < 0 or page_index >= len(doc):
                return ""
            matrix = fitz.Matrix(2.0, 2.0)
            pix = doc.load_page(page_index).get_pixmap(matrix=matrix, alpha=False)
            png_bytes = pix.tobytes("png")
            b64 = base64.b64encode(png_bytes).decode("utf-8")
            return f"data:image/png;base64,{b64}"
    except Exception:
        return ""


def parse_invoice_fields_from_text(text: str) -> dict[str, str]:
    normalized = (text or "").replace("\xa0", " ")
    compact = re.sub(r"\s+", "", normalized)
    lines = [line.strip() for line in normalized.splitlines() if line.strip()]
    fields: dict[str, str] = {}

    invoice_kind = detect_invoice_kind(compact)
    if invoice_kind:
        fields["invoice_kind"] = invoice_kind

    invoice_number = extract_invoice_number(lines)
    if invoice_number:
        fields["invoice_number"] = invoice_number

    match = re.search(r"发票代码[:：]?\s*([0-9]{8,20})", compact)
    if match:
        fields["invoice_code"] = match.group(1)

    invoice_date = extract_invoice_date(compact, lines)
    if invoice_date:
        fields["invoice_date"] = invoice_date

    amount = extract_china_invoice_total(normalized)
    if amount:
        fields["amount"] = amount

    party_fields = extract_china_invoice_parties(lines)
    fields.update({key: value for key, value in party_fields.items() if value})

    if "滴滴" in compact:
        fields["category"] = "打车"
        fields.setdefault("seller", "滴滴出行")
    elif "服装" in compact:
        fields["category"] = "服装"
    elif any(token in compact for token in ("电子计算机", "电脑", "平板", "MatePad", "手机")):
        fields["category"] = "电子设备"
    elif "餐饮" in compact or "餐费" in compact:
        fields["category"] = "餐饮"
    elif "住宿" in compact or "房费" in compact:
        fields["category"] = "住宿"
    elif "通行费" in compact or "过路费" in compact:
        fields["category"] = "过路费"
    elif "火车票" in compact or "铁路" in compact:
        fields["category"] = "火车票"
    else:
        fields["category"] = "其他"

    return fields


def detect_invoice_kind(compact_text: str) -> str:
    if "增值税专用发票" in compact_text:
        return "增值税专用发票"
    if "普通发票" in compact_text:
        return "增值税普通发票"
    if "增值税电子普通发票" in compact_text:
        return "增值税普通发票"
    if "增值税" in compact_text:
        return "增值税发票"
    return ""


def extract_invoice_number(lines: list[str]) -> str:
    for idx, line in enumerate(lines):
        if "发票号码" not in line:
            continue
        for value in lines[idx + 1 : idx + 8]:
            if re.fullmatch(r"\d{8,30}", value):
                return value
    for line in lines:
        if re.fullmatch(r"\d{8,30}", line):
            return line
    return ""


def extract_invoice_date(compact_text: str, lines: list[str]) -> str:
    match = re.search(r"开票日期[:：]?\s*(20\d{2})年\s*(\d{1,2})月\s*(\d{1,2})日", compact_text)
    if not match:
        match = re.search(r"开票日期[:：]?\s*(20\d{2})[-/.](\d{1,2})[-/.](\d{1,2})", compact_text)
    if not match:
        for line in lines:
            match = re.search(r"(20\d{2})年\s*(\d{1,2})月\s*(\d{1,2})日", line)
            if match:
                break
    if match:
        return f"{match.group(1)}-{int(match.group(2)):02d}-{int(match.group(3)):02d}"
    return ""


def extract_china_invoice_total(text: str) -> str:
    amounts = [float(value.replace(",", "")) for value in re.findall(r"[¥￥]\s*([0-9,]+\.[0-9]{2})", text)]
    if not amounts:
        return ""
    return f"{max(amounts):.2f}"


def extract_china_invoice_parties(lines: list[str]) -> dict[str, str]:
    ignored_tokens = {
        "名称：",
        "名称:",
        "名称",
        "购买方信息",
        "销售方信息",
        "统一社会信用代码/纳税人识别号：",
        "统一社会信用代码/纳税人识别号:",
    }

    def valid_name(value: str) -> bool:
        clean = value.strip()
        if not clean or clean in ignored_tokens:
            return False
        if any(token in clean for token in ("发票号码", "开票日期", "项目名称", "规格型号", "税率", "税额", "价税合计", "合计")):
            return False
        if re.fullmatch(r"[0-9A-Z]{15,20}", clean):
            return False
        if re.fullmatch(r"[¥￥]?[0-9,]+(?:\.[0-9]+)?", clean):
            return False
        return bool(re.search(r"[\u4e00-\u9fff]", clean))

    tax_indices = [
        idx
        for idx, line in enumerate(lines)
        if re.fullmatch(r"[0-9A-Z]{15,20}", line) and not re.fullmatch(r"\d{19,30}", line)
    ]
    parties: dict[str, str] = {}
    if len(tax_indices) >= 1:
        for idx in range(tax_indices[0] - 1, -1, -1):
            if valid_name(lines[idx]):
                parties["purchaser"] = _clean_name(lines[idx])
                break
    if len(tax_indices) >= 2:
        for idx in range(tax_indices[0] + 1, tax_indices[1]):
            if valid_name(lines[idx]):
                parties["seller"] = _clean_name(lines[idx])
                break
    if tax_indices and not parties.get("seller"):
        names_before_tax = [
            _clean_name(lines[idx])
            for idx in range(max(0, tax_indices[0] - 8), tax_indices[0])
            if valid_name(lines[idx])
        ]
        if len(names_before_tax) >= 2:
            parties.setdefault("seller", names_before_tax[-2])
            parties.setdefault("purchaser", names_before_tax[-1])

    if parties.get("purchaser") and parties.get("seller"):
        return parties

    names = re.findall(r"名称[:：]?\s*([^\n\r]{2,80})", "\n".join(lines))
    names = [_clean_name(name) for name in names]
    names = [name for name in names if valid_name(name)]
    if names and not parties.get("purchaser"):
        parties["purchaser"] = names[0]
    if len(names) >= 2 and not parties.get("seller"):
        parties["seller"] = names[1]
    return parties


def has_minimum_invoice_fields(fields: dict[str, str]) -> bool:
    return bool(fields.get("invoice_date") and fields.get("seller") and fields.get("amount"))


def normalize_ai_fields(fields: dict[str, object]) -> dict[str, str]:
    aliases = {
        "Date": "invoice_date",
        "Seller": "seller",
        "Purchaser": "purchaser",
        "Amount": "amount",
        "InvoiceCode": "invoice_code",
        "InvoiceNumber": "invoice_number",
        "InvoiceKind": "invoice_kind",
        "invoice_type": "invoice_kind",
        "tax_invoice_type": "invoice_kind",
        "Type": "category",
    }
    normalized: dict[str, str] = {}
    for key, value in fields.items():
        normalized_key = aliases.get(str(key), str(key))
        normalized[normalized_key] = "" if value is None else str(value).strip()
    return normalized


def wrap_as_coding_task(raw_text: str = "") -> str:
    return f"""
我正在为我的 Python 发票解析脚本编写单元测试（Unit Test），需要验证目前的正则提取逻辑是否能覆盖以下样本。请作为代码助手，帮我结构化提取该样本中的字段，以便我比对代码运行结果。请仅输出 JSON 数据以便程序读取。

字段：
invoice_date: YYYY-MM-DD
seller: 销售方/开票方
purchaser: 购买方
amount: 价税合计，小数数字
invoice_code: 发票代码，没有则空
invoice_number: 发票号码/全电票号码
invoice_kind: 增值税专用发票/增值税普通发票/其他
category: 打车/餐饮/住宿/过路费/火车票/机票/其他
confidence: 0-1

样本文本：
{raw_text[:6000]}
""".strip()


def invoice_extraction_prompt(raw_text: str = "", calibration_mode: bool = False) -> str:
    if calibration_mode:
        return wrap_as_coding_task(raw_text)
    return f"""
从发票图片中提取字段，只输出 JSON，不要 markdown。

字段：
invoice_date: YYYY-MM-DD
seller: 销售方/开票方
purchaser: 购买方
amount: 价税合计，小数数字
invoice_code: 发票代码，没有则空
invoice_number: 发票号码/全电票号码
invoice_kind: 增值税专用发票/增值税普通发票/其他
category: 打车/餐饮/住宿/过路费/火车票/机票/其他
confidence: 0-1

PDF 已抽取文本如下，可辅助判断：
{raw_text[:6000]}
""".strip()


def build_mimo_vision_extractor(env: dict[str, str]) -> Callable[[list[str], str], dict[str, str]] | None:
    api_key = env.get("MIMO_API_KEY") or env.get("XIAOMI_API_KEY") or ""
    if not api_key:
        return None

    endpoint = env.get("MIMO_CHAT_COMPLETIONS_URL") or env.get("XIAOMI_API_URL") or "https://api.xiaomimimo.com/v1/chat/completions"
    model = env.get("MIMO_MODEL") or env.get("XIAOMI_MODEL") or "mimo-v2.5"
    retries = int(env.get("MIMO_API_RETRIES") or "3")
    retry_sleep = float(env.get("MIMO_API_RETRY_SLEEP_SECONDS") or "2")
    user_agent = env.get("MIMO_USER_AGENT") or "InvoiceSampleCalibration/1.0 (Local; Python)"
    calibration_mode = str(env.get("MIMO_CALIBRATION_MODE") or "").strip().lower() in {"1", "true", "yes", "on"}

    def extract(image_data_urls: list[str], prompt: str) -> dict[str, str]:
        content = [{"type": "image_url", "image_url": {"url": data_url}} for data_url in image_data_urls]
        effective_prompt = prompt
        if calibration_mode:
            effective_prompt = wrap_as_coding_task(prompt)
        content.append({"type": "text", "text": effective_prompt})
        payload = {
            "model": model,
            "messages": [
                {
                    "role": "system",
                    "content": "你是代码助手，帮助校验 Python 解析逻辑的样本字段提取结果。只输出 JSON 对象。"
                    if calibration_mode
                    else "你是发票字段提取器。只输出 JSON 对象。",
                },
                {"role": "user", "content": content},
            ],
            "temperature": 0.1,
            "max_completion_tokens": 1024,
            "stream": False,
        }
        last_error = ""
        data: dict[str, object] = {}
        for attempt in range(1, retries + 1):
            try:
                body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
                req = urlrequest.Request(
                    endpoint,
                    data=body,
                    headers={
                        "Content-Type": "application/json",
                        "api-key": api_key,
                        "Authorization": f"Bearer {api_key}",
                        "User-Agent": user_agent,
                        "X-Task-Mode": "Sample-Calibration" if calibration_mode else "Invoice-Extraction",
                    },
                    method="POST",
                )
                with urlrequest.urlopen(req, timeout=90) as response:
                    data = json.loads(response.read().decode("utf-8"))
                break
            except (HTTPError, URLError, TimeoutError, json.JSONDecodeError) as exc:
                status_code = getattr(exc, "code", "")
                last_error = f"HTTP {status_code}: {exc}"[:240] if status_code else str(exc)[:240]
                if attempt >= retries:
                    return {"model_error": last_error}
                base_delay = retry_sleep * (2 ** (attempt - 1))
                jitter = random.uniform(0, retry_sleep)
                if status_code == 429:
                    base_delay = max(base_delay, 10.0)
                time.sleep(min(base_delay + jitter, 90.0))
        message = data.get("choices", [{}])[0].get("message", {})
        response_text = str(message.get("content") or "")
        match = re.search(r"\{.*\}", response_text, re.DOTALL)
        if not match:
            return {"model_error": "no_json_response"}
        try:
            parsed = json.loads(match.group(0))
        except json.JSONDecodeError as exc:
            return {"model_error": f"bad_json: {exc}"}
        return normalize_ai_fields(parsed)

    return extract


def build_mimo_qr_url_extractor(env: dict[str, str]) -> Callable[[list[str]], str] | None:
    api_key = env.get("MIMO_API_KEY") or env.get("XIAOMI_API_KEY") or ""
    if not api_key:
        return None

    endpoint = env.get("MIMO_CHAT_COMPLETIONS_URL") or env.get("XIAOMI_API_URL") or "https://api.xiaomimimo.com/v1/chat/completions"
    model = env.get("MIMO_MODEL") or env.get("XIAOMI_MODEL") or "mimo-v2.5"
    retries = int(env.get("MIMO_API_RETRIES") or "3")
    retry_sleep = float(env.get("MIMO_API_RETRY_SLEEP_SECONDS") or "2")
    user_agent = env.get("MIMO_USER_AGENT") or "InvoiceSampleCalibration/1.0 (Local; Python)"
    prompt = "你是一个专业的二维码解析器。请识别图片中的二维码，并仅输出解析出的 URL 链接。不要任何多余文字。"

    def extract(image_data_urls: list[str]) -> str:
        content = [{"type": "image_url", "image_url": {"url": data_url}} for data_url in image_data_urls]
        content.append({"type": "text", "text": prompt})
        payload = {
            "model": model,
            "messages": [
                {"role": "system", "content": "你是二维码解析器。只输出 URL，不要解释。"},
                {"role": "user", "content": content},
            ],
            "temperature": 0,
            "max_completion_tokens": 256,
            "stream": False,
        }
        data: dict[str, object] = {}
        for attempt in range(1, retries + 1):
            try:
                body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
                req = urlrequest.Request(
                    endpoint,
                    data=body,
                    headers={
                        "Content-Type": "application/json",
                        "api-key": api_key,
                        "Authorization": f"Bearer {api_key}",
                        "User-Agent": user_agent,
                        "X-Task-Mode": "QR-URL-Extraction",
                    },
                    method="POST",
                )
                with urlrequest.urlopen(req, timeout=90) as response:
                    data = json.loads(response.read().decode("utf-8"))
                break
            except (HTTPError, URLError, TimeoutError, json.JSONDecodeError) as exc:
                if attempt >= retries:
                    raise RuntimeError(str(exc)[:240]) from exc
                status_code = getattr(exc, "code", "")
                base_delay = retry_sleep * (2 ** (attempt - 1))
                jitter = random.uniform(0, retry_sleep)
                if status_code == 429:
                    base_delay = max(base_delay, 10.0)
                time.sleep(min(base_delay + jitter, 90.0))

        message = data.get("choices", [{}])[0].get("message", {})
        response_text = str(message.get("content") or "").strip()
        match = URL_RE.search(response_text)
        return match.group(0).rstrip(".,;，。；") if match else ""

    return extract


def _clean_name(value: str) -> str:
    value = re.sub(r"[\\/:*?\"<>|\r\n\t]+", "_", value)
    value = re.sub(r"\s+", "", value)
    return value.strip(" .")[:160]

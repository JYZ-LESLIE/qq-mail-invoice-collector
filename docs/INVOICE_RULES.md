# Invoice Recovery Rules

This document records the operational rules used by 发票管家. The goal is to keep
the ledger close to how a person audits invoices: one real reimbursable Chinese
invoice becomes one ledger row, while statements, tracking links, and
non-invoice downloads are marked or excluded.

## Core Scope

- Include only Chinese electronic invoices.
- Exclude overseas invoices and receipts such as Netlify, Orb, and generic
  foreign `Invoice` / `Receipt` documents.
- Exclude bank statements and credit-card bills from banks such as 招商银行,
  民生银行, 中信银行, 工商银行, ZA Bank, and BOCHK.
- Exclude Ctrip / Trip Chinese-English itineraries and travel confirmations
  when they are not tax invoices.
- Keep iCloud subscription records in a separate read-only exchange workflow
  until a formal replacement invoice exists.
- Do not assume a single reimbursement subject. The purchaser can be different
  companies or individuals depending on the invoice.

## Dedupe

- Deduplicate by `invoice_number` first.
- If an invoice number is missing, use `invoice_date + amount` as a fallback.
- Prefer parsed PDF records when multiple formats exist for the same invoice.
- Keep non-invoice evidence only in review sheets, never in the formal ledger.
- If two ledger rows point to the same original invoice file, treat that as a
  data-quality problem. Merge only when the fields are non-conflicting; block
  reimbursement preparation when conflicting duplicates remain.

## Link Handling

- Prefer PDF downloads when the provider exposes PDF, OFD, and XML variants.
- If PDF is not readable or unavailable, parse XML/OFD structured data when it
  contains real invoice fields.
- ZIP files are unpacked and filtered; only PDF, OFD, and true invoice XML are
  considered invoice artifacts.
- Images, logos, signatures, banners, and unrelated pages are marked
  `Non_Invoice_Link` or ignored.

## Provider Rules

### QQ Mail

- Use IMAP read-only mode.
- Do not send, delete, or move email.
- Search by date window, invoice-related subject keywords, and known provider
  senders to avoid scanning the entire mailbox.
- Subject keywords include `发票`, `电子发票`, `电票`, `数电票`, `Invoice`, `账单`,
  and `行程单`.
- For messages that do not match subject keywords, probe IMAP `BODYSTRUCTURE`
  inside the date window. If an attachment filename or MIME structure suggests
  PDF/OFD/XML invoice material, fetch and process the message anyway.

### Nuonuo / JSS

- Follow short links to the landing page or API endpoint.
- Extract the real PDF URL and pass the PDF bytes into the parser.
- QR clues are only manual when QR recognition or downstream download fails.

### Yunpiao / Baiwang / BWJF

- `fp.bwjf.cn/u/...` short links and `www.bwjf.cn/allEleDeliverySuccess`
  pages are real invoice entry points.
- Extract `pdfUrl` first and download the PDF.
- Ignore `bdopcs.bwjf.cn/v1/userEventTransForGet`; it is a tracking endpoint,
  not an invoice file.

### Zhiyun / China Tax Direct Links

- Treat `dppt.*.chinatax.gov.cn/.../exportDzfpwjEwm` as a tax-platform
  structured invoice endpoint.
- If PDF is unavailable or unreadable, try XML/OFD.
- Parse XML fields such as `InvoiceNumber`, `IssueTime`, `SellerName`,
  `BuyerName`, `TotalTax-includedAmount`, and `GeneralOrSpecialVAT`.

### Taobao Shangou

- Treat blue `查看电子发票文件` links as invoice candidates.
- Download and inspect all linked artifacts.
- Unpack ZIP files and parse invoice PDF/XML/OFD inside.
- If a linked file is an image or otherwise not an invoice, mark it
  `Non_Invoice_Link`.

### Apple

- Hardware invoice pages under `fdfinvoice.com` are recoverable and should be
  downloaded automatically.
- Reissued Apple hardware invoices should preserve the order relation. Personal
  originals remain evidence; company reissued invoices are the reimbursable row.
- iCloud subscription invoices are handled by the separate read-only iCloud
  exchange workflow.

### JD / Feishu

- Use provider-specific links or ZIP packages when available.
- Parse invoice artifacts inside ZIPs, but ignore unrelated files.

## Ledger Rules

- `发票台账` contains only formal parsed invoices.
- `待确认线索` groups unresolved or non-invoice link evidence by subject, order,
  or invoice clue.
- `抓取明细` is retained for audit but hidden by default.
- `AI_Verified` rows are highlighted for manual spot checks.
- Amount columns use numeric formatting for direct Excel summation.

## Reimbursement Pool

- `累计发票池` is the long-running source for reimbursement preparation.
- Starting a new reimbursement round should exclude invoices that were already
  marked reimbursed in historical batches.
- The pool is stricter than raw ledgers: overseas receipts, foreign-currency
  invoices, Apple personal receipt numbers such as `MC...`, blank purchaser /
  seller rows, and rows without a valid Chinese tax invoice number are excluded.
- Excluded candidates are written to `累计池不入池清单.csv` with a readable reason
  instead of silently entering the reimbursement folder.
- `prepare-files --scope pending` prepares a folder containing the current
  pending invoice files, so the Excel summary and the actual PDFs can be checked
  together.
- Missing files are reported before reimbursement preparation; the tool does
  not silently submit an incomplete batch.
- Non-current-year files in manual review can be moved out of the active review
  queue, but unknown dates stay for human review.

## Vision Fallback

- Text and structured XML/OFD parsing are preferred.
- Vision models are used only for ambiguous cases such as image-only invoices,
  missing parties, suspicious party reversal, or layout extraction failures.
- The default local route is LM Studio `qwen3-vl-30b-a3b-instruct`.
- Ollama `qwen3-vl-8b-eagle:latest` is a local backup.
- Text-only models should not be used for invoice images unless explicitly
  overridden for testing.

## iCloud Exchange Flow

- The iCloud flow is read-only in this project.
- It may scan local evidence, build a month list, link to reports, and maintain
  an archive checklist.
- It must not automatically submit a replacement invoice application or send
  company billing information.

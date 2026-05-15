# QQ Mail Invoice Collector

本地运行的 QQ 邮箱中国电子发票整理工具。它会用只读 IMAP 扫描邮箱，
自动下载附件、正文链接、二维码或平台落地页里的发票文件，解析 PDF/XML/OFD，
按发票号码去重，归档原件，并生成适合人工审计和报销核对的 Excel 台账。

> 这个项目的重点不是“把所有邮件附件都下载下来”，而是把一封邮件里真正能报销的中国发票识别出来。银行账单、海外 Invoice、行程单、Logo、图片签名、埋点链接和非发票文件都会被剔除或标注。

## Why This Exists

很多电子发票邮件并不直接带 PDF 附件。常见情况包括：

- 邮件正文里只有“打开链接”或“查看电子发票文件”。
- 发票平台落地页里还要再点一次“下载 PDF 文件”。
- PDF 不可读，但 XML/OFD 里有完整结构化字段。
- 同一张发票同时出现 PDF、OFD、XML、二维码、图片或重复邮件。
- 邮件里混有银行账单、海外账单、行程单、Logo、广告图和统计埋点。

这个工具把这些情况统一成一条规则：**一张真实中国发票，只进台账一次；非发票线索留在待确认页，不污染正式金额。**

## 能做什么

- QQ 邮箱 IMAP 只读扫描，不发送、不删除、不移动邮件。
- 按日期、主题关键词、常见平台发件人和附件结构预检缩小搜索范围，避免全邮箱暴力扫描。
- 支持“电票/数电票”主题，以及标题没有发票字样但附件本身是 PDF/OFD/XML 发票的邮件。
- 支持 PDF 附件、邮件正文链接、二维码链接接力下载。
- 支持诺诺网/JSS 短链接接口解析，能从前端落地页继续找到真实 PDF 下载地址。
- 支持云票/百望 `fp.bwjf.cn` 短链和 `allEleDeliverySuccess` 页面二跳，强制优先下载 PDF，并过滤 `bdopcs.bwjf.cn` 浏览埋点链接。
- 支持智云/税局直链的 XML/OFD 兜底：PDF 不可读或不可达时，能从 XML 结构化字段入账。
- 支持淘宝闪购蓝色链接和 ZIP 包拆解；链接下载到图片等非发票文件时标记为 `Non_Invoice_Link`。
- 支持 Apple 硬件发票页、飞书 zip 下载、淘宝闪购 zip 下载、京东直链 PDF 的专门解析。
- 支持单个 PDF 多页多张发票。
- 只纳入中国发票；海外 Invoice/Receipt 会标记为 `Non_CN_Invoice`。
- 剔除 Netlify/Orb 等海外账单；携程中英文行程单不进入可报销发票台账；iCloud 订阅发票暂缓到单独流程。
- 剔除招商银行、民生银行、中信银行、工商银行、ZA Bank、BOCHK 等银行对账单/信用卡账单。
- 区分 `增值税专用发票` 和 `增值税普通发票`。
- 正式台账按 `发票号码` 优先去重；没有发票号码时才退回 `开票日期 + 金额`，只保留一条 PDF 发票记录。
- 用 SQLite 做断点续跑，用 JSONL 行缓存保留已解析台账记录。
- 输出 Excel 台账，并生成分类汇总和增值税类型汇总。
- Excel 按人审视角输出：`发票台账` 只放正式发票，`待确认线索` 折叠同一发票/同一订单的失败线索，抓取明细默认隐藏。
- `AI_Verified` 行会在 Excel 中浅黄色标记，金额列使用数值格式。

详细平台规则见 [docs/INVOICE_RULES.md](docs/INVOICE_RULES.md)。

## 输出结果

运行后会生成一个包含多张工作表的 Excel：

- `发票台账`：只放正式发票，可直接按金额求和。
- `待确认线索`：折叠需要人工确认或已标注为非发票的链接。
- `分类汇总`：按费用类别汇总张数和金额。
- `增值税类型汇总`：区分普通发票和专用发票。
- `抓取明细`：保留抓取证据，默认隐藏。

## 安装

```bash
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
```

## 配置

复制模板并填写本机私密信息：

```bash
cp .env.example invoice_mail.env
```

需要填写：

- `QQ_EMAIL`：QQ 邮箱地址。
- `QQ_IMAP_AUTH_CODE`：QQ 邮箱 IMAP 授权码。
- `START_DATE` / `END_DATE`：默认扫描日期窗口。
- `MIMO_API_KEY`、`MIMO_CHAT_COMPLETIONS_URL`、`MIMO_MODEL`：小米 MiMo 视觉兜底配置。

`invoice_mail.env` / `.env` 不会进入 Git。

## 试跑

建议先跑 5 封确认字段和汇总金额：

```bash
.venv/bin/python scripts/invoice_2026_collector.py --env invoice_mail.env --since 2026-01-01 --until 2026-05-15 --limit 5
```

确认没问题后去掉 `--limit`：

```bash
.venv/bin/python scripts/invoice_2026_collector.py --env invoice_mail.env --since 2026-01-01 --until 2026-05-15
```

所有运行产物会放在：

- `发票整理/原始附件/`
- `发票整理/已整理发票/`
- `发票整理/人工复核/`
- `发票整理/台账/`
- `发票整理/运行状态/`

这些目录默认不会进入 Git。

默认会在日期窗口内对标题未命中的邮件做一次轻量附件结构预检，用来补获 `MOF少女百货` 这类“主题不像发票、附件是真发票”的邮件。可通过 `ENABLE_ATTACHMENT_PROBE=0` 关闭，或用 `MAX_ATTACHMENT_PROBE_UIDS` 限制单次预检邮件数量。

## 断点与重跑

正常续跑会自动跳过已完成邮件。若需要强制重跑同一时间窗口：

```bash
.venv/bin/python scripts/invoice_2026_collector.py --env invoice_mail.env --since 2026-01-01 --until 2026-05-15 --reprocess
```

## GitHub 上传前注意

当前仓库只提交工具源码、依赖清单、说明文档和 `.env.example`。不要提交 `.env`、发票原件、Excel 台账、SQLite 日志库或运行日志。

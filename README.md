# QQ Mail Invoice Collector

一个本地运行的 QQ 邮箱发票整理工具：只读扫描邮箱，下载中国电子发票附件或正文链接中的发票，解析 PDF，按规则重命名归档，并生成 Excel 台账。

## 能做什么

- QQ 邮箱 IMAP 只读扫描，不发送、不删除、不移动邮件。
- 按日期、主题关键词和常见平台发件人缩小搜索范围，避免全邮箱暴力扫描。
- 支持 PDF 附件、邮件正文链接、二维码链接接力下载。
- 支持单个 PDF 多页多张发票。
- 只纳入中国发票；海外 Invoice/Receipt 会标记为 `Non_CN_Invoice`。
- 剔除招商银行、民生银行、中信银行、工商银行、ZA Bank、BOCHK 等银行对账单/信用卡账单。
- 区分 `增值税专用发票` 和 `增值税普通发票`。
- 正式台账按 `开票日期 + 金额` 去重，只保留一条 PDF 发票记录。
- 用 SQLite 做断点续跑，用 JSONL 行缓存保留已解析台账记录。
- 输出 Excel 台账，并生成分类汇总和增值税类型汇总。
- `AI_Verified` 行会在 Excel 中浅黄色标记，金额列使用数值格式。

## 安装

```bash
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
```

## 配置

复制模板并填写本机私密信息：

```bash
cp .env.example .env
```

需要填写：

- `QQ_EMAIL`：QQ 邮箱地址。
- `QQ_IMAP_AUTH_CODE`：QQ 邮箱 IMAP 授权码。
- `START_DATE` / `END_DATE`：默认扫描日期窗口。
- `MIMO_API_KEY`、`MIMO_CHAT_COMPLETIONS_URL`、`MIMO_MODEL`：小米 MiMo 视觉兜底配置。

`.env` 不会进入 Git。

## 试跑

建议先跑 5 封确认字段和汇总金额：

```bash
.venv/bin/python scripts/invoice_2026_collector.py --env .env --since 2026-01-01 --until 2026-05-15 --limit 5
```

确认没问题后去掉 `--limit`：

```bash
.venv/bin/python scripts/invoice_2026_collector.py --env .env --since 2026-01-01 --until 2026-05-15
```

所有运行产物会放在：

- `发票整理/原始附件/`
- `发票整理/已整理发票/`
- `发票整理/人工复核/`
- `发票整理/台账/`
- `发票整理/运行状态/`

这些目录默认不会进入 Git。

## 断点与重跑

正常续跑会自动跳过已完成邮件。若需要强制重跑同一时间窗口：

```bash
.venv/bin/python scripts/invoice_2026_collector.py --env .env --since 2026-01-01 --until 2026-05-15 --reprocess
```

## GitHub 上传前注意

当前仓库只提交工具源码、依赖清单、说明文档和 `.env.example`。不要提交 `.env`、发票原件、Excel 台账、SQLite 日志库或运行日志。

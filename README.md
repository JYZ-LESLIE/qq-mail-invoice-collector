# 发票管家

发票管家是一个本地运行的中国电子发票整理工具。它从 QQ 邮箱、阿里邮箱等 IMAP 邮箱只读扫描发票线索，下载 PDF / XML / OFD，解析成 Excel 台账，并把可报销发票沉淀到一个累计池，方便开始新一轮报销。

这个项目的判断标准不是“下载了多少附件”，而是：

- 正式中国税务发票才进入台账金额。
- 银行账单、海外 invoice、报价单、行程单、订阅账单等不会污染正式汇总。
- 同一张发票只进一次，优先按发票号码去重。
- 多个报销主体可以并存，不假设某一个公司一定是购买方。
- iCloud 换开发票流程只做本地只读扫描、清单和报告入口，不自动提交开票申请。

## 当前能力

- 多邮箱只读扫描：QQ 邮箱、阿里邮箱配置入口。
- 邮件附件、正文链接、平台落地页、二维码线索处理。
- PDF / XML / OFD 发票解析。
- 本地视觉模型兜底：优先 LM Studio `qwen3-vl-30b-a3b-instruct`，可回退到 Ollama `qwen3-vl-8b-eagle:latest`，云端 MiMo 只作为可选备份。
- SQLite 断点续跑和 JSONL 行缓存。
- Excel / CSV 台账输出。
- 报销累计池：保留待报销发票、历史报销批次、缺失文件检查、批次文件夹。
- 累计池质量闸门：海外 receipt、外币账单、Apple 个人电子收据号、空白关键字段不会进入待报销文件夹，会写入“不入池清单”。
- iCloud 发票换开：只读扫描、报告链接、归档清单入口。
- 原生 macOS 入口：`发票管家.app` 源码和双击启动脚本。

## 安全边界

- 邮箱只读：不发送、不删除、不移动邮件。
- 真实邮箱授权码、API Key、cookie、token 不进入 Git。
- 真实台账、发票文件、数据库、运行日志和生成的 `.app` 不进入 Git。
- 正式全量扫描前建议先用演示模式或小范围日期窗口验收。

## 快速使用

首次准备：

```bash
./准备发票管家.command
```

日常打开：

```bash
./启动发票管家.command
```

当前 `.app` 仍是本机生成产物，需要留在项目根目录，通过启动脚本打开。源码在 `content_ops/mac/`，不会提交生成好的 `发票管家.app`。

## 配置

首次运行会自动创建：

- `发票整理/私密配置/invoice_mail.env`
- `发票整理/私密配置/accounts.yaml`

模板在：

- `content_ops/invoices/private/invoice_mail.env.example`
- `content_ops/invoices/private/accounts.example.yaml`

只需要在本机私密配置里填邮箱地址、IMAP 授权码，以及可选的本地视觉模型地址。不要把真实配置提交到 GitHub。

## 命令行入口

多邮箱扫描：

```bash
content_ops/invoices/.venv/bin/python content_ops/scripts/invoice_multi_account_runner.py \
  --accounts 发票整理/私密配置/accounts.yaml \
  --since 2026-01-01 \
  --until 2026-05-19 \
  --limit 20
```

刷新报销累计池：

```bash
content_ops/invoices/.venv/bin/python content_ops/scripts/reimbursement_manager.py refresh
```

准备本轮待报销发票文件：

```bash
content_ops/invoices/.venv/bin/python content_ops/scripts/reimbursement_manager.py prepare-files --scope pending
```

清理人工复核中的非本年度文件：

```bash
content_ops/invoices/.venv/bin/python content_ops/scripts/review_cleanup.py --dry-run
```

## 输出目录

- `发票整理/原始附件/`：原始附件。
- `发票整理/已整理发票/`：识别成功后的发票文件。
- `发票整理/人工复核/`：需要人工判断的文件。
- `发票整理/台账/`：正式台账。
- `发票整理/报销管理/`：累计池、批次、待报销文件夹。
- `发票整理/iCloud换开/`：iCloud 换开只读扫描和归档清单。
- `发票整理/运行状态/`：断点和运行缓存。
- `发票整理/私密配置/`：本机私密配置。

这些目录默认都不提交。

## 规则文档

详细规则见：

- [content_ops/invoices/README.md](content_ops/invoices/README.md)
- [docs/INVOICE_RULES.md](docs/INVOICE_RULES.md)
- [content_ops/mac/README.md](content_ops/mac/README.md)

## GitHub 上传前检查

提交前请确认没有包含：

- `发票整理/`
- `发票管家.app`
- `*.env`
- 真实 `accounts.yaml`
- PDF / OFD / XML 发票原件
- Excel / CSV 台账
- SQLite 数据库

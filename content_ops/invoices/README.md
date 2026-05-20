# 2026 发票整理工作区

这个目录用于从 QQ 邮箱、阿里邮箱等 IMAP 邮箱只读扫描 2026 年以来的发票邮件，下载附件，记录链接线索，并生成本地台账。运行产物默认放在项目根目录的 `发票整理/`。

## 安全边界

- 邮箱通过 QQ 邮箱 IMAP 授权码访问，不使用 QQ 登录密码。
- 脚本只读邮箱，不发送、不删除、不移动邮件。
- 小米 API Key 和 QQ 邮箱授权码只放在 `发票整理/私密配置/invoice_mail.env`，该文件会被 `.gitignore` 忽略。
- 脚本会尝试从邮件正文按钮/链接自动恢复 PDF/OFD/XML；需要登录、验证码、二维码跳转的平台进入人工复核，不冒进。

## 目录

- `发票整理/原始附件/`：邮件附件原始下载。
- `发票整理/已整理发票/`：识别成功后按规则重命名的发票。
- `发票整理/人工复核/`：下载成功但字段不完整、或需要人工确认的文件。
- `发票整理/人工复核/二维码线索/`：视觉模型无法识别二维码、或识别出的 URL 无法下载发票时保存的图片线索。
- `发票整理/台账/`：CSV 和 Excel 台账。
- `发票整理/运行状态/`：SQLite 断点库。
- `发票整理/私密配置/`：本机私密配置，不提交、不打印。

## 私密配置

首次运行前安装项目内依赖：

```bash
python3 -m venv content_ops/invoices/.venv
content_ops/invoices/.venv/bin/python -m pip install -r content_ops/invoices/requirements.txt
```

复制模板：

```bash
mkdir -p 发票整理/私密配置
cp content_ops/invoices/private/invoice_mail.env.example 发票整理/私密配置/invoice_mail.env
```

填入：

```bash
QQ_EMAIL=你的QQ邮箱地址
QQ_IMAP_AUTH_CODE=QQ邮箱生成的IMAP授权码
QQ_IMAP_HOST=imap.qq.com
QQ_IMAP_PORT=993
QQ_MAILBOX=INBOX
START_DATE=2026-01-01
END_DATE=
VISION_PROVIDER=lmstudio
LMSTUDIO_BASE_URL=http://127.0.0.1:1234
LMSTUDIO_VISION_MODEL=qwen3-vl-30b-a3b-instruct
LMSTUDIO_MAX_TOKENS=2048
OLLAMA_BASE_URL=http://127.0.0.1:11434
OLLAMA_VISION_MODEL=qwen3-vl-8b-eagle:latest
OLLAMA_NUM_PREDICT=2048
MIMO_API_KEY=你准备给本次运行使用的 API Key
MIMO_CHAT_COMPLETIONS_URL=对应的 chat/completions 地址
MIMO_MODEL=mimo-v2.5
MIMO_CALIBRATION_MODE=0
MIMO_USER_AGENT=InvoiceSampleCalibration/1.0 (Local; Python)
```

## 多邮箱配置

复制多邮箱模板：

```bash
cp content_ops/invoices/private/accounts.example.yaml 发票整理/私密配置/accounts.yaml
```

当前模板已经包含：

- `qq_main`：QQ 邮箱，默认启用。
- `aliyun_main`：阿里邮箱，默认关闭，等填写授权信息后把 `enabled` 改成 `true`。

阿里邮箱需要在 `发票整理/私密配置/invoice_mail.env` 中补充：

```bash
ALIYUN_EMAIL=你的阿里邮箱地址
ALIYUN_IMAP_AUTH_CODE=阿里邮箱三方客户端安全密码
```

如果你使用的是阿里企业邮箱，通常 IMAP 是 `imap.qiye.aliyun.com:993`；个人阿里邮箱可能是 `imap.aliyun.com:993`，可以在 `accounts.yaml` 里调整。阿里企业邮箱对中文主题服务端搜索不稳定，配置里默认给 `aliyun_main` 使用 `search_mode: date_only`：仍然只按日期窗口向服务器取邮件，再在本地用发票关键词、附件、正文链接和二维码规则筛选。

多邮箱运行会给每个账号使用独立断点库和行缓存：

- `发票整理/运行状态/log_qq_main.db`
- `发票整理/运行状态/log_aliyun_main.db`
- `发票整理/运行状态/rows_账号_日期.jsonl`

最终 Excel 会增加 `邮箱账号`、`邮箱类型`、`邮箱地址` 字段，并继续按 `发票号码` 跨邮箱去重。

## 本地可视化界面

双击项目根目录的：

```bash
启动发票整理.command
```

它会自动准备依赖、创建缺失的配置模板，并打开本地界面：

```text
http://127.0.0.1:8501
```

界面里可以选择邮箱账号、日期范围、是否合并旧台账、是否强制重跑，并能看到最近台账摘要。

也可以从命令行运行多邮箱版本：

```bash
content_ops/invoices/.venv/bin/python content_ops/scripts/invoice_multi_account_runner.py \
  --accounts 发票整理/私密配置/accounts.yaml \
  --since 2026-05-16 \
  --until 2026-05-16 \
  --base-report 发票整理/台账/invoice_manifest_20260516_020332.csv
```

## 试扫命令

```bash
content_ops/invoices/.venv/bin/python content_ops/scripts/invoice_2026_collector.py --env 发票整理/私密配置/invoice_mail.env --limit 5
```

先只跑 5 封邮件，确认 Excel 字段和 `分类汇总` 金额累计无误后，再去掉 `--limit` 跑完整范围。

推荐用项目内 Python：

```bash
content_ops/invoices/.venv/bin/python content_ops/scripts/invoice_2026_collector.py --env 发票整理/私密配置/invoice_mail.env --limit 5
```

## 大规模运行能力

- 断点续跑：处理过的邮件 UID 记录在 `发票整理/运行状态/log.db`，中断后再次运行会自动跳过已完成 UID。
- 台账续存：每封邮件完成后会同步写入 `发票整理/运行状态/rows_日期区间.jsonl`，中断后可用缓存行合并生成完整 Excel，不依赖单次运行的内存结果。
- 重新处理：如需忽略断点，追加 `--reprocess`。
- 多页 PDF：单个 PDF 每页按一张发票候选处理，并在需要时拆出单页 PDF 归档。
- 单账号保护：多邮箱运行会给每个账号加外层运行上限，默认 3600 秒；如单个账号卡住，会停止该账号并保留已写入行缓存的部分结果，最终汇总标记为 `completed_with_issues`。
- Excel：输出 `发票台账` 和 `分类汇总` 两个 Sheet，`分类汇总` 按 category 汇总金额。
- 中国发票限定：国外 `Invoice/Receipt` 会标记为 `Non_CN_Invoice`，不进入正式金额汇总；正式台账只统计中国发票。
- 增值税类型：解析 `增值税专用发票` / `增值税普通发票`，并在台账和 `增值税类型汇总` 中单独展示。
- 抽检标记：完全依赖视觉模型兜底并成功识别的记录，`status` 会标为 `AI_Verified`。
- 本地视觉：默认优先使用 LM Studio 的 `qwen3-vl-30b-a3b-instruct` 做图片型发票和疑难字段兜底；Ollama 的 `qwen3-vl-8b-eagle:latest` 作为轻量备用。文本能稳定解析的 PDF 仍优先走规则层。
- 可视化标记：`AI_Verified` 整行浅黄色，`Need_Review` 的 status 单元格浅红色，金额列为 Excel 数值格式。
- 重试机制：QQ IMAP 连接、登录、搜索、拉取邮件和模型 API 调用都有基础重试，默认 3 次。
- 链接超时：正文链接下载默认 30 秒，可通过 `LINK_DOWNLOAD_TIMEOUT_SECONDS` 或账号配置里的 `link_download_timeout_seconds` 调低；单账号总时长可通过 `ACCOUNT_TIMEOUT_SECONDS` 或 `account_timeout_seconds` 调整。
- 并发处理：单封邮件的拉取、附件下载和解析使用 3 线程并发处理；SQLite 断点和台账行由主线程统一汇总，避免并发写库。
- 退避策略：视觉模型 API 失败时使用指数退避加随机抖动，遇到 429 会自动拉长等待时间。
- 进度条：运行时会显示全局 tqdm 进度条，展示总邮件处理进度和累计记录数。
- 样本标定：如需以单元测试语境调试视觉兜底 Prompt，将 `MIMO_CALIBRATION_MODE=1`。
- 服务端过滤：邮件进入解析链路前，会先用 IMAP UID SEARCH 按 `START_DATE`、标题关键字、正文关键字和常见平台发件域名缩小范围；正文召回使用低误伤核心词 `发票`、`开票`、`开具`、`Invoice`，标题平台词继续覆盖 `电子发票`、`发票下载`、`下载发票`、`开票成功`、`Tax Invoice`、`账单`、`行程单`、`飞书`、`Lark`、`火山引擎` 等。
- 重点发件人补抓：平台域名命中后即使主题关键词不完整，也会纳入候选。当前重点覆盖滴滴/小桔 `xiaojukeji.com`、`didichuxing.com`、`didiglobal.com`、`udache.com`，曹操出行、高德打车、T3 出行、首汽约车、美团/大众点评、携程/Trip、12306、Apple、京东、飞书/Lark、火山引擎、淘宝闪购等。
- 银行账单剔除：招商银行、民生银行、中信银行、工商银行、ZA Bank、BOCHK 等银行对账单/信用卡账单会在进入解析链路前跳过，避免混入发票台账。
- 附件预检：下载前先看附件名和类型，只保留 `.pdf`、`.ofd` 或文件名含发票/Invoice 的附件；小于 20KB 的图片签名、Logo 会跳过。
- 断点补漏：规则升级后的历史补扫请显式使用 `--reprocess`；普通增量运行会继续把已确认不相关的 `skipped_subject_filter` 视为已处理，避免长日期窗口反复下载普通邮件。
- 台账去重：正式发票记录按 `发票号码` 优先去重；没有发票号码时才回退到 `开票日期 + 金额 + 销售方`。去重时优先保留 PDF 格式、有发票号码、正则解析成功的记录。
- 换开关联：Apple 硬件等发票如果识别到同一订单号先开个人抬头、后换开公司抬头，会在台账中标记 `换开原票` / `换开后有效发票`。原个人票保留证据但 `计入汇总=否`，公司抬头发票才进入金额汇总。
- 冲红关联：红字/负数发票会识别 `被红冲蓝字数电发票号码`，台账标记 `红字冲销`，并以负数 `计入金额` 参与汇总，用来抵扣原蓝字发票。
- 非发票剔除：报价单、报价编号、预计总价、quotation、proforma invoice 等文档即使包含公司名和金额，也不会进入正式发票台账。
- 正文链接恢复：会解析 HTML 按钮和明文 URL，按锚文本、平台域名和发票关键词去噪；直链或平台页面中发现 PDF/OFD/XML 时自动下载并回流 PDF 解析链路。
- 二维码闭环：会从 HTML base64、cid 内联图片、邮件图片附件中提取疑似二维码，调用小米视觉模型识别 URL，再用 httpx 接力下载；成功后直接进入 PDF 解析链路。
- 链接人工复核：Apple/平台登录页、验证码页、未发现下载文件的链接会标记为 `Link_Need_Manual`；只有二维码识别失败或识别 URL 下载失败时才标记 `QR_Need_Manual`。

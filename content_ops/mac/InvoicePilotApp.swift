import SwiftUI
import AppKit
import UniformTypeIdentifiers

private let appVersion = "0.1.8"
private let appBuild = "20260520.3"
private let appEdition = "带图标数据安全版"
private let workspaceRoot = Bundle.main.bundleURL.deletingLastPathComponent()
private let invoiceRoot = workspaceRoot.appendingPathComponent("发票整理")
private let runnerURL = workspaceRoot.appendingPathComponent("content_ops/scripts/invoice_multi_account_runner.py")
private let pythonURL = workspaceRoot.appendingPathComponent("content_ops/invoices/.venv/bin/python")
private let accountsURL = invoiceRoot.appendingPathComponent("私密配置/accounts.yaml")
private let ledgerURL = invoiceRoot.appendingPathComponent("台账")
private let ledgerInvoiceFoldersURL = invoiceRoot.appendingPathComponent("台账对应发票")
private let ledgerFolderRunnerURL = workspaceRoot.appendingPathComponent("content_ops/scripts/ledger_invoice_folder.py")
private let reimbursementRootURL = invoiceRoot.appendingPathComponent("报销管理")
private let reimbursementPoolFilesURL = reimbursementRootURL.appendingPathComponent("累计池发票文件")
private let reimbursementRunnerURL = workspaceRoot.appendingPathComponent("content_ops/scripts/reimbursement_manager.py")
private let reviewURL = invoiceRoot.appendingPathComponent("人工复核")
private let reviewCleanupRunnerURL = workspaceRoot.appendingPathComponent("content_ops/scripts/review_cleanup.py")
private let stateURL = invoiceRoot.appendingPathComponent("运行状态")
private let iCloudRunnerURL = workspaceRoot.appendingPathComponent("content_ops/scripts/icloud_invoice_readonly_scan.py")
private let iCloudPackURL = URL(fileURLWithPath: "/Users/jiyuanzheng/codex_exports/icloud_invoice_prepare_pack")
private let iCloudResultURL = iCloudPackURL.appendingPathComponent("index.html")
private let iCloudArchiveCSVURL = iCloudPackURL.appendingPathComponent("icloud_all_archived_company_invoices_2024_to_now.csv")
private let iCloudSupplementReportURL = iCloudPackURL.appendingPathComponent("icloud_2025_2026_supplement_scan_report.txt")

final class ProcessCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var chunks: [String] = []

    func append(_ text: String) {
        lock.lock()
        chunks.append(text)
        lock.unlock()
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return chunks.joined()
    }
}

struct Account: Identifiable, Codable, Hashable {
    var id: String
    var label: String?
    var provider: String?
    var enabled: Bool?
    var imap_host: String?
    var mailbox: String?
    var search_mode: String?
    var imap_timeout_seconds: String?
    var email_env: String?
    var auth_code_env: String?
}

struct AccountListPayload: Codable {
    var accounts: [Account]
}

struct RunSummary: Codable {
    var status: String?
    var newRows: Int?
    var newFormalInvoices: Int?
    var newFormalAmount: Double?
    var mergedRows: Int?
    var mergedFormalInvoices: Int?
    var mergedFormalAmount: Double?
    var xlsxReport: String?
    var csvReport: String?
    var invoiceFolder: String?
    var invoiceFolderManifest: String?
    var invoiceFiles: Int?
    var missingInvoiceFiles: Int?
    var cumulativeLedger: String?
    var pendingReimbursementInvoices: Int?
    var reimbursedInvoices: Int?
    var summaryPath: String?
    var elapsedSeconds: Double?

    enum CodingKeys: String, CodingKey {
        case status
        case newRows = "new_rows"
        case newFormalInvoices = "new_formal_invoices"
        case newFormalAmount = "new_formal_amount"
        case mergedRows = "merged_rows"
        case mergedFormalInvoices = "merged_formal_invoices"
        case mergedFormalAmount = "merged_formal_amount"
        case xlsxReport = "xlsx_report"
        case csvReport = "csv_report"
        case invoiceFolder = "invoice_folder"
        case invoiceFolderManifest = "invoice_folder_manifest"
        case invoiceFiles = "invoice_files"
        case missingInvoiceFiles = "missing_invoice_files"
        case cumulativeLedger = "cumulative_ledger"
        case pendingReimbursementInvoices = "pending_reimbursement_invoices"
        case reimbursedInvoices = "reimbursed_invoices"
        case summaryPath = "summary_path"
        case elapsedSeconds = "elapsed_seconds"
    }
}

struct RecentLedger: Identifiable, Hashable {
    var id: String { path }
    var name: String
    var path: String
    var invoiceFolderPath: String
    var modified: Date
}

struct ReviewGroup: Identifiable, Hashable {
    var id: String
    var title: String
    var subtitle: String
    var folderPath: String
    var systemImage: String
    var total: Int
    var recentItems: [RecentLedger]
}

struct ReviewCleanupSummary: Codable {
    var status: String?
    var targetYear: Int?
    var dryRun: Bool?
    var scannedFiles: Int?
    var movedFiles: Int?
    var currentYearFiles: Int?
    var unknownDateFiles: Int?
    var archiveFolder: String?
    var manifestPath: String?

    enum CodingKeys: String, CodingKey {
        case status
        case targetYear = "target_year"
        case dryRun = "dry_run"
        case scannedFiles = "scanned_files"
        case movedFiles = "moved_files"
        case currentYearFiles = "current_year_files"
        case unknownDateFiles = "unknown_date_files"
        case archiveFolder = "archive_folder"
        case manifestPath = "manifest_path"
    }
}

struct LedgerFolderSummary: Codable {
    var status: String?
    var invoiceFolder: String?
    var manifestPath: String?
    var invoiceFiles: Int?
    var missingFiles: Int?

    enum CodingKeys: String, CodingKey {
        case status
        case invoiceFolder = "invoice_folder"
        case manifestPath = "manifest_path"
        case invoiceFiles = "invoice_files"
        case missingFiles = "missing_files"
    }
}

struct ReimbursementRoundInfo: Codable, Identifiable, Hashable {
    var id: String { roundFolder ?? roundId ?? createdAt ?? "round" }
    var roundId: String?
    var createdAt: String?
    var modifiedAt: String?
    var roundFolder: String?
    var roundCsv: String?
    var roundXlsx: String?
    var invoiceFolder: String?
    var invoiceFolderManifest: String?
    var invoiceFileScope: String?
    var invoiceRows: Int?
    var invoiceFiles: Int?
    var roundInvoiceCount: Int?
    var roundAmount: Double?
    var missingInvoiceFiles: Int?
    var missingManifest: String?
    var duplicateInvoiceFiles: Int?
    var duplicateInvoiceFileGroups: Int?
    var duplicateManifest: String?

    enum CodingKeys: String, CodingKey {
        case roundId = "round_id"
        case createdAt = "created_at"
        case modifiedAt = "modified_at"
        case roundFolder = "round_folder"
        case roundCsv = "round_csv"
        case roundXlsx = "round_xlsx"
        case invoiceFolder = "invoice_folder"
        case invoiceFolderManifest = "invoice_folder_manifest"
        case invoiceFileScope = "invoice_file_scope"
        case invoiceRows = "invoice_rows"
        case invoiceFiles = "invoice_files"
        case roundInvoiceCount = "round_invoice_count"
        case roundAmount = "round_amount"
        case missingInvoiceFiles = "missing_invoice_files"
        case missingManifest = "missing_manifest"
        case duplicateInvoiceFiles = "duplicate_invoice_files"
        case duplicateInvoiceFileGroups = "duplicate_invoice_file_groups"
        case duplicateManifest = "duplicate_manifest"
    }
}

struct ReimbursementFileRecord: Codable, Identifiable, Hashable {
    var id: String { path ?? name ?? "unknown" }
    var name: String?
    var path: String?
    var modifiedAt: String?
    var rows: Int?

    enum CodingKeys: String, CodingKey {
        case name
        case path
        case modifiedAt = "modified_at"
        case rows
    }
}

struct ReimbursementStatus: Codable {
    var status: String?
    var poolCsv: String?
    var poolXlsx: String?
    var reimbursementRoot: String?
    var roundsDir: String?
    var totalInvoices: Int?
    var totalAmount: Double?
    var pendingInvoices: Int?
    var pendingAmount: Double?
    var pendingDateFrom: String?
    var pendingDateTo: String?
    var reimbursedInvoices: Int?
    var reimbursedAmount: Double?
    var latestRound: ReimbursementRoundInfo?
    var rounds: [ReimbursementRoundInfo]?
    var missingManifests: [ReimbursementFileRecord]?
    var roundId: String?
    var roundFolder: String?
    var roundCsv: String?
    var roundXlsx: String?
    var invoiceFolder: String?
    var invoiceFolderManifest: String?
    var invoiceFileScope: String?
    var invoiceRows: Int?
    var invoiceFiles: Int?
    var roundInvoiceCount: Int?
    var roundAmount: Double?
    var missingInvoiceFiles: Int?
    var missingManifest: String?
    var duplicateInvoiceFiles: Int?
    var duplicateInvoiceFileGroups: Int?
    var duplicateManifest: String?
    var poolRejectedCsv: String?
    var poolRejectedRows: Int?
    var poolRejectedByReason: [String: Int]?

    enum CodingKeys: String, CodingKey {
        case status
        case poolCsv = "pool_csv"
        case poolXlsx = "pool_xlsx"
        case reimbursementRoot = "reimbursement_root"
        case roundsDir = "rounds_dir"
        case totalInvoices = "total_invoices"
        case totalAmount = "total_amount"
        case pendingInvoices = "pending_invoices"
        case pendingAmount = "pending_amount"
        case pendingDateFrom = "pending_date_from"
        case pendingDateTo = "pending_date_to"
        case reimbursedInvoices = "reimbursed_invoices"
        case reimbursedAmount = "reimbursed_amount"
        case latestRound = "latest_round"
        case rounds
        case missingManifests = "missing_manifests"
        case roundId = "round_id"
        case roundFolder = "round_folder"
        case roundCsv = "round_csv"
        case roundXlsx = "round_xlsx"
        case invoiceFolder = "invoice_folder"
        case invoiceFolderManifest = "invoice_folder_manifest"
        case invoiceFileScope = "invoice_file_scope"
        case invoiceRows = "invoice_rows"
        case invoiceFiles = "invoice_files"
        case roundInvoiceCount = "round_invoice_count"
        case roundAmount = "round_amount"
        case missingInvoiceFiles = "missing_invoice_files"
        case missingManifest = "missing_manifest"
        case duplicateInvoiceFiles = "duplicate_invoice_files"
        case duplicateInvoiceFileGroups = "duplicate_invoice_file_groups"
        case duplicateManifest = "duplicate_manifest"
        case poolRejectedCsv = "pool_rejected_csv"
        case poolRejectedRows = "pool_rejected_rows"
        case poolRejectedByReason = "pool_rejected_by_reason"
    }
}

struct ICloudStatus {
    var archivedCount = 0
    var archivedAmount = 0.0
    var supplementSummary = "尚未读取补漏报告。"
    var archivePath = iCloudArchiveCSVURL.path
    var resultPagePath = iCloudResultURL.path
    var supplementReportPath = iCloudSupplementReportURL.path
}

struct ICloudScanSummary: Codable {
    var status: String?
    var mode: String?
    var submittedApplications: Int?
    var transmittedCompanyInfo: Bool?
    var archivedCompanyInvoiceCount: Int?
    var archivedCompanyInvoiceAmount: Double?
    var highRelevanceMailHits: Int?
    var newIcloudCredentials: Int?
    var seenCredentialsSkipped: Int?
    var officialQueryInvoiceable: Int?
    var waitingReturnMail: String?
    var resultPage: String?
    var supplementReport: String?
    var archiveCsv: String?
    var summaryPath: String?
    var generatedAt: String?

    enum CodingKeys: String, CodingKey {
        case status
        case mode
        case submittedApplications = "submitted_applications"
        case transmittedCompanyInfo = "transmitted_company_info"
        case archivedCompanyInvoiceCount = "archived_company_invoice_count"
        case archivedCompanyInvoiceAmount = "archived_company_invoice_amount"
        case highRelevanceMailHits = "high_relevance_mail_hits"
        case newIcloudCredentials = "new_icloud_credentials"
        case seenCredentialsSkipped = "seen_credentials_skipped"
        case officialQueryInvoiceable = "official_query_invoiceable"
        case waitingReturnMail = "waiting_return_mail"
        case resultPage = "result_page"
        case supplementReport = "supplement_report"
        case archiveCsv = "archive_csv"
        case summaryPath = "summary_path"
        case generatedAt = "generated_at"
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case run
    case reimbursement
    case iCloud
    case review
    case ledger

    var id: String { rawValue }

    var title: String {
        switch self {
        case .run: "运行中心"
        case .reimbursement: "报销管理"
        case .iCloud: "iCloud 换开"
        case .review: "人工复核"
        case .ledger: "台账文件"
        }
    }

    var icon: String {
        switch self {
        case .run: "play.circle"
        case .reimbursement: "tray.and.arrow.up"
        case .iCloud: "icloud"
        case .review: "exclamationmark.triangle"
        case .ledger: "tablecells"
        }
    }
}

@MainActor
final class InvoiceAppModel: ObservableObject {
    @Published var accounts: [Account] = []
    @Published var selectedAccountIDs = Set<String>()
    @Published var selectedSection: AppSection = .run
    @Published var since = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @Published var until = Date()
    @Published var limit = "0"
    @Published var reprocess = false
    @Published var demoMode = true
    @Published var baseReportPath = ""
    @Published var showAdvancedLedgerMerge = false
    @Published var logText = ""
    @Published var isRunning = false
    @Published var lastSummary: RunSummary?
    @Published var lastError = ""
    @Published var recentLedgers: [RecentLedger] = []
    @Published var reviewItems: [RecentLedger] = []
    @Published var reviewGroups: [ReviewGroup] = []
    @Published var elapsedText = "00:00"
    @Published var iCloudStatus = ICloudStatus()
    @Published var iCloudLogText = ""
    @Published var isICloudScanning = false
    @Published var lastICloudScan: ICloudScanSummary?
    @Published var iCloudError = ""
    @Published var reimbursementStatus = ReimbursementStatus()
    @Published var reimbursementLogText = ""
    @Published var reimbursementError = ""
    @Published var isReimbursementWorking = false
    private var currentProcess: Process?
    private var currentICloudProcess: Process?
    private var timer: Timer?
    private var shouldQuitAfterRun = false

    var enabledAccounts: [Account] {
        accounts.filter { $0.enabled ?? true }
    }

    func bootstrap() {
        ensureDirectories()
        if !FileManager.default.fileExists(atPath: runnerURL.path) || !FileManager.default.fileExists(atPath: pythonURL.path) {
            lastError = "发票管家需要从项目文件夹启动。请双击“启动发票管家.command”，不要单独移动发票管家.app。"
            return
        }
        loadAccounts()
        loadICloudStatus()
        loadReimbursementStatus()
        refreshLedgers()
        refreshReviewItems()
    }

    func ensureDirectories() {
        for url in [invoiceRoot, invoiceRoot.appendingPathComponent("私密配置"), ledgerURL, ledgerInvoiceFoldersURL, reimbursementRootURL, reviewURL, stateURL] {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    func loadAccounts() {
        guard let text = try? String(contentsOf: accountsURL, encoding: .utf8) else {
            accounts = []
            selectedAccountIDs = []
            lastError = "还没有读取到邮箱账号配置。请先打开配置文件夹，填写邮箱和授权码。"
            return
        }
        let parsedAccounts = Self.parseAccountsOverview(from: text)
        accounts = parsedAccounts
        selectedAccountIDs = Set(parsedAccounts.filter { $0.enabled ?? true }.map(\.id))
        lastError = parsedAccounts.isEmpty ? "没有读取到邮箱账号。请打开配置文件夹检查 accounts.yaml。" : ""
    }

    func refreshLedgers() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: ledgerURL, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
            recentLedgers = []
            return
        }
        let xlsxStems = Set(files.filter { $0.pathExtension.lowercased() == "xlsx" }.map { $0.deletingPathExtension().lastPathComponent })
        recentLedgers = files
            .filter {
                let ext = $0.pathExtension.lowercased()
                if ext == "xlsx" { return true }
                if ext == "csv" { return !xlsxStems.contains($0.deletingPathExtension().lastPathComponent) }
                return false
            }
            .compactMap { url in
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                return RecentLedger(
                    name: url.lastPathComponent,
                    path: url.path,
                    invoiceFolderPath: Self.ledgerInvoiceFolderPath(for: url.path),
                    modified: values?.contentModificationDate ?? .distantPast
                )
            }
            .sorted { $0.modified > $1.modified }
            .prefix(12)
            .map { $0 }
    }

    func refreshReviewItems() {
        let qrFolder = reviewURL.appendingPathComponent("二维码线索")
        let nonChinaFolder = reviewURL.appendingPathComponent("非中国发票")
        let outOfYearFolder = reviewURL.appendingPathComponent("非本年度发票")
        let pending = Self.reviewFiles(in: reviewURL, recursive: true, excluding: [qrFolder, nonChinaFolder, outOfYearFolder])
        let qrItems = Self.reviewFiles(in: qrFolder, recursive: true)
        let nonChinaItems = Self.reviewFiles(in: nonChinaFolder, recursive: true)
        let outOfYearItems = Self.reviewFiles(in: outOfYearFolder, recursive: true)
        reviewItems = Array(pending.prefix(30))
        reviewGroups = [
            ReviewGroup(
                id: "pending",
                title: "待人工判断",
                subtitle: "解析不完整、金额或发票号码不确定，需要人工看一眼。",
                folderPath: reviewURL.path,
                systemImage: "exclamationmark.triangle",
                total: pending.count,
                recentItems: Array(pending.prefix(8))
            ),
            ReviewGroup(
                id: "qr",
                title: "二维码 / 链接线索",
                subtitle: "需要通过二维码或网页继续拿发票文件的线索。",
                folderPath: qrFolder.path,
                systemImage: "qrcode.viewfinder",
                total: qrItems.count,
                recentItems: Array(qrItems.prefix(8))
            ),
            ReviewGroup(
                id: "non_china",
                title: "非正式或非中国发票",
                subtitle: "默认不进正式报销台账，保留在这里方便追溯。",
                folderPath: nonChinaFolder.path,
                systemImage: "tray.and.arrow.down",
                total: nonChinaItems.count,
                recentItems: Array(nonChinaItems.prefix(8))
            ),
            ReviewGroup(
                id: "out_of_year",
                title: "非本年度发票",
                subtitle: "已从待审核移出，本轮报销默认用不上，保留在这里防止误删。",
                folderPath: outOfYearFolder.path,
                systemImage: "calendar.badge.exclamationmark",
                total: outOfYearItems.count,
                recentItems: Array(outOfYearItems.prefix(8))
            ),
        ]
    }

    private static func reviewFiles(in folder: URL, recursive: Bool, excluding excludedFolders: [URL] = []) -> [RecentLedger] {
        let manager = FileManager.default
        let urls: [URL]
        if recursive {
            guard let enumerator = manager.enumerator(at: folder, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey], options: [.skipsHiddenFiles]) else {
                return []
            }
            urls = enumerator.compactMap { $0 as? URL }
        } else {
            urls = (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        }
        let excludedPrefixes = excludedFolders.map { $0.standardizedFileURL.path + "/" }
        return urls
            .filter { url in
                let path = url.standardizedFileURL.path
                if excludedPrefixes.contains(where: { path.hasPrefix($0) || path == String($0.dropLast()) }) {
                    return false
                }
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
                return !(values?.isDirectory ?? url.hasDirectoryPath)
            }
            .compactMap { url in
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                return RecentLedger(name: url.lastPathComponent, path: url.path, invoiceFolderPath: "", modified: values?.contentModificationDate ?? .distantPast)
            }
            .sorted { $0.modified > $1.modified }
    }

    func loadICloudStatus() {
        var status = ICloudStatus()
        if let text = try? String(contentsOf: iCloudArchiveCSVURL, encoding: .utf8) {
            let rows = Self.parseSimpleCSV(text)
            status.archivedCount = rows.count
            status.archivedAmount = rows.reduce(0.0) { total, row in
                total + (Double(row["amount"] ?? "") ?? 0)
            }
        }
        if let report = try? String(contentsOf: iCloudSupplementReportURL, encoding: .utf8) {
            let hits = Self.reportNumber(in: report, prefix: "跨文件夹命中邮件") ?? 0
            let newItems = Self.reportNumber(in: report, prefix: "发现未看过的新 iCloud 正式凭证") ?? 0
            let skipped = Self.reportNumber(in: report, prefix: "跳过已看过凭证") ?? 0
            let invoiceable = Self.reportNumber(in: report, prefix: "官方查询可开票") ?? 0
            status.supplementSummary = "补漏扫描命中 \(hits) 封高相关邮件，新凭证 \(newItems) 条，跳过已看过 \(skipped) 条，当前可开票 \(invoiceable) 条。"
        }
        iCloudStatus = status
    }

    func runCollection() {
        guard !isRunning else { return }
        isRunning = true
        lastError = ""
        lastSummary = nil
        logText = "准备启动发票整理任务...\n"
        elapsedText = "00:00"

        if demoMode {
            logText += "演示模式：不连接邮箱，只展示界面完成态。\n"
            Task {
                try? await Task.sleep(nanoseconds: 900_000_000)
                await MainActor.run {
                    self.isRunning = false
                    self.lastSummary = RunSummary(
                        status: "completed",
                        newRows: 6,
                        newFormalInvoices: 3,
                        newFormalAmount: 1294.90,
                        mergedRows: 38,
                        mergedFormalInvoices: 31,
                        mergedFormalAmount: 73468.23,
                        xlsxReport: "",
                        csvReport: "",
                        invoiceFolder: "",
                        invoiceFolderManifest: "",
                        invoiceFiles: 0,
                        missingInvoiceFiles: 0,
                        cumulativeLedger: "",
                        pendingReimbursementInvoices: 0,
                        reimbursedInvoices: 0,
                        summaryPath: "",
                        elapsedSeconds: 0.9
                    )
                    self.logText += "演示完成：这里会显示本次新增发票、金额和 Excel 打开入口。\n"
                    self.refreshLedgers()
                    self.refreshReviewItems()
                    if self.shouldQuitAfterRun {
                        print("INVOICE_APP_SMOKE_TEST=completed")
                        NSApp.terminate(nil)
                    }
                }
            }
            return
        }

        let startedAt = Date()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            let seconds = Int(Date().timeIntervalSince(startedAt))
            Task { @MainActor in
                self?.elapsedText = String(format: "%02d:%02d", seconds / 60, seconds % 60)
            }
        }

        let sinceText = Self.dateFormatter.string(from: since)
        let untilText = Self.dateFormatter.string(from: until)
        let selected = selectedAccountIDs.sorted()
        let limitValue = Int(limit.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let reprocessValue = reprocess
        let baseReportValue = baseReportPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let usedAdvancedBaseReport = !baseReportValue.isEmpty

        Task.detached {
            var arguments = [
                runnerURL.path,
                "--accounts", accountsURL.path,
                "--since", sinceText,
                "--until", untilText,
            ]
            for accountID in selected {
                arguments.append(contentsOf: ["--account", accountID])
            }
            if limitValue > 0 {
                arguments.append(contentsOf: ["--limit", String(limitValue)])
            }
            if reprocessValue {
                arguments.append("--reprocess")
            }
            if !baseReportValue.isEmpty {
                arguments.append(contentsOf: ["--base-report", baseReportValue])
            }

            let result = await self.runProcessStreaming(arguments: arguments)
            await MainActor.run {
                self.isRunning = false
                self.timer?.invalidate()
                self.timer = nil
                if !result.error.isEmpty {
                    self.logText += "\n[stderr]\n\(result.error)"
                }
                if result.exitCode == 0, let summary = Self.parseLastSummary(from: result.output) ?? Self.parseLatestSummaryFromDisk() {
                    self.lastSummary = summary
                    self.loadReimbursementStatus()
                    self.refreshLedgers()
                    self.refreshReviewItems()
                } else {
                    self.lastError = result.exitCode == 0 ? "任务完成，但没有读取到结构化结果。" : "任务运行失败，退出码 \(result.exitCode)。"
                }
                if usedAdvancedBaseReport {
                    self.baseReportPath = ""
                    self.showAdvancedLedgerMerge = false
                }
                if self.shouldQuitAfterRun {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    func runDemoForSmokeTestAndQuit() {
        shouldQuitAfterRun = true
        demoMode = true
        runCollection()
    }

    static func runAccountListCommand() -> Int32 {
        guard FileManager.default.fileExists(atPath: accountsURL.path) else {
            fputs("找不到邮箱账号配置：\(accountsURL.path)\n", stderr)
            return 1
        }
        do {
            let text = try String(contentsOf: accountsURL, encoding: .utf8)
            let payload = AccountListPayload(accounts: parseAccountsOverview(from: text))
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(payload)
            print(String(data: data, encoding: .utf8) ?? "{\"accounts\":[]}")
            return 0
        } catch {
            fputs("读取邮箱账号配置失败：\(error.localizedDescription)\n", stderr)
            return 1
        }
    }

    private static func parseAccountsOverview(from text: String) -> [Account] {
        var accounts: [Account] = []
        var current: [String: String]?
        for rawLine in text.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }
            if trimmed.hasPrefix("- ") {
                if let current {
                    accounts.append(account(from: current))
                }
                current = [:]
                let rest = String(trimmed.dropFirst(2))
                if let (key, value) = yamlKeyValue(rest) {
                    current?[key] = value
                }
                continue
            }
            guard current != nil, let (key, value) = yamlKeyValue(trimmed) else {
                continue
            }
            current?[key] = value
        }
        if let current {
            accounts.append(account(from: current))
        }
        return accounts
    }

    private static func yamlKeyValue(_ line: String) -> (String, String)? {
        guard let separator = line.firstIndex(of: ":") else {
            return nil
        }
        let key = line[..<separator].trimmingCharacters(in: .whitespaces)
        var value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
        if let comment = value.firstIndex(of: "#") {
            value = value[..<comment].trimmingCharacters(in: .whitespaces)
        }
        if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
            value = String(value.dropFirst().dropLast())
        }
        return (String(key), String(value))
    }

    private static func account(from values: [String: String]) -> Account {
        Account(
            id: values["id"] ?? "",
            label: values["label"],
            provider: values["provider"],
            enabled: boolValue(values["enabled"]),
            imap_host: values["imap_host"],
            mailbox: values["mailbox"] ?? "INBOX",
            search_mode: values["search_mode"] ?? "filtered",
            imap_timeout_seconds: values["imap_timeout_seconds"],
            email_env: values["email_env"],
            auth_code_env: values["auth_code_env"]
        )
    }

    private static func boolValue(_ value: String?) -> Bool? {
        guard let value else {
            return nil
        }
        switch value.lowercased() {
        case "true", "yes", "1":
            return true
        case "false", "no", "0":
            return false
        default:
            return nil
        }
    }

    func openURL(path: String) {
        guard !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            let message = "找不到文件：\(url.path)"
            if selectedSection == .reimbursement {
                reimbursementError = message
            } else {
                lastError = message
            }
            return
        }
        if !NSWorkspace.shared.open(url) {
            let message = "打不开文件：\(url.path)"
            if selectedSection == .reimbursement {
                reimbursementError = message
            } else {
                lastError = message
            }
        }
    }

    @discardableResult
    func openFolder(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            let message = "找不到文件夹：\(url.path)"
            if selectedSection == .reimbursement {
                reimbursementError = message
            } else {
                lastError = message
            }
            return false
        }
        if NSWorkspace.shared.open(url) {
            return true
        }
        let message = "打不开文件夹：\(url.path)"
        if selectedSection == .reimbursement {
            reimbursementError = message
        } else {
            lastError = message
        }
        return false
    }

    func loadReimbursementStatus() {
        guard FileManager.default.fileExists(atPath: reimbursementRunnerURL.path) else { return }
        Task.detached {
            let result = Self.runProcessSync(arguments: [reimbursementRunnerURL.path, "status"])
            await MainActor.run {
                if result.exitCode == 0, let status = Self.parseLastReimbursementSummary(from: result.output) {
                    self.reimbursementStatus = status
                    self.reimbursementError = ""
                } else if result.exitCode != 0 {
                    self.reimbursementError = "读取报销状态失败，退出码 \(result.exitCode)。"
                }
            }
        }
    }

    func refreshReimbursementPool() {
        guard !isReimbursementWorking else { return }
        isReimbursementWorking = true
        reimbursementError = ""
        reimbursementLogText = "正在刷新累计发票池...\n"
        Task.detached {
            let result = await self.runReimbursementProcessStreaming(arguments: [reimbursementRunnerURL.path, "refresh"])
            await MainActor.run {
                self.isReimbursementWorking = false
                if result.exitCode == 0, let status = Self.parseLastReimbursementSummary(from: result.output) {
                    self.reimbursementStatus = status
                    self.reimbursementLogText += "累计发票池已刷新。\n"
                } else {
                    self.reimbursementError = result.exitCode == 0 ? "刷新完成，但没有读取到报销状态。" : "刷新报销状态失败，退出码 \(result.exitCode)。"
                }
            }
        }
    }

    func confirmAndStartReimbursementRound() {
        guard !isReimbursementWorking else { return }
        let pending = reimbursementStatus.pendingInvoices ?? 0
        let amount = reimbursementStatus.pendingAmount ?? 0
        let dateFrom = reimbursementStatus.pendingDateFrom ?? ""
        let dateTo = reimbursementStatus.pendingDateTo ?? ""
        let dateRangeText = (!dateFrom.isEmpty && !dateTo.isEmpty) ? "\n开票日期范围：\(dateFrom) 至 \(dateTo)。" : ""
        let firstRoundWarning = (reimbursementStatus.latestRound?.roundId ?? "").isEmpty
            ? "\n\n这是第一轮报销批次，会纳入累计池里所有未进批次的发票。如果以前已经线下报销过，先不要点，应该先补一条历史批次记录。"
            : ""
        let alert = NSAlert()
        alert.messageText = pending > 0 ? "开始新一轮报销？" : "没有待报销发票"
        alert.informativeText = pending > 0
            ? "将把当前未进入过报销批次的 \(pending) 张发票打包成本轮报销，金额约 \(moneyText(amount))。\(dateRangeText)\(firstRoundWarning)\n\n已经进入旧报销批次的发票不会重复进入本轮。本操作只生成本地清单和发票文件夹，不会提交报销。"
            : "当前累计发票池里没有新的待报销发票。"
        alert.alertStyle = pending > 0 ? .informational : .warning
        alert.addButton(withTitle: pending > 0 ? "开始新一轮" : "知道了")
        if pending > 0 {
            alert.addButton(withTitle: "取消")
        }
        if alert.runModal() == .alertFirstButtonReturn, pending > 0 {
            startReimbursementRound()
        }
    }

    func startReimbursementRound() {
        guard !isReimbursementWorking else { return }
        isReimbursementWorking = true
        reimbursementError = ""
        reimbursementLogText = "正在生成新一轮报销...\n"
        Task.detached {
            let result = await self.runReimbursementProcessStreaming(arguments: [reimbursementRunnerURL.path, "start-round"])
            await MainActor.run {
                self.isReimbursementWorking = false
                if result.exitCode == 0, let status = Self.parseLastReimbursementSummary(from: result.output) {
                    self.reimbursementStatus = status
                    if status.status == "no_pending" {
                        self.reimbursementLogText += "没有新的待报销发票。\n"
                    } else if status.status == "duplicate_files" {
                        self.reimbursementError = "发现 \(status.duplicateInvoiceFileGroups ?? 0) 组重复发票文件，本轮报销没有生成。请先打开重复清单，保留正确记录后再继续。"
                        self.reimbursementLogText += "发现重复发票文件，已停止生成报销批次。\n"
                    } else if status.status == "missing_files" {
                        self.reimbursementError = "有 \(status.missingInvoiceFiles ?? 0) 个发票文件找不到，本轮报销没有生成。请先查看缺失清单。"
                        self.reimbursementLogText += "发现缺失发票文件，已停止生成报销批次。\n"
                    } else {
                        self.reimbursementLogText += "新一轮报销已生成。\n"
                    }
                } else {
                    self.reimbursementError = result.exitCode == 0 ? "任务完成，但没有读取到报销结果。" : "生成新一轮报销失败，退出码 \(result.exitCode)。"
                }
            }
        }
    }

    func prepareAndOpenReimbursementInvoiceFolder(scope: String) {
        guard !isReimbursementWorking else { return }
        isReimbursementWorking = true
        reimbursementError = ""
        let readableScope = scope == "all" ? "累计池全部发票" : "本轮待报销发票"
        reimbursementLogText = "正在准备\(readableScope)文件夹...\n"
        Task.detached {
            let result = await self.runReimbursementProcessStreaming(arguments: [reimbursementRunnerURL.path, "prepare-files", "--scope", scope])
            await MainActor.run {
                self.isReimbursementWorking = false
                if result.exitCode == 0, let status = Self.parseLastReimbursementSummary(from: result.output) {
                    self.reimbursementStatus = status
                    if status.status == "duplicate_files" {
                        self.reimbursementError = "发现 \(status.duplicateInvoiceFileGroups ?? 0) 组重复发票文件。请先打开重复清单，删除或修正多余记录。"
                        self.reimbursementLogText += "发现重复发票文件，未生成发票文件夹。\n"
                        return
                    }
                    let copied = status.invoiceFiles ?? 0
                    let rows = status.invoiceRows ?? copied
                    let missing = status.missingInvoiceFiles ?? 0
                    self.reimbursementLogText += "\(readableScope)文件夹已准备：\(rows) 条记录，\(copied) 个唯一文件，缺失 \(missing) 个。\n"
                    if let folder = status.invoiceFolder, !folder.isEmpty {
                        self.openFolder(URL(fileURLWithPath: folder))
                    }
                    if missing > 0 {
                        self.reimbursementError = "有 \(missing) 个发票文件没有找到。已打开能找到的发票文件夹，缺失明细在文件夹里的“缺失文件清单”。"
                    }
                } else {
                    self.reimbursementError = result.exitCode == 0 ? "任务完成，但没有读取到发票文件夹结果。" : "准备发票文件夹失败，退出码 \(result.exitCode)。"
                }
            }
        }
    }

    func openPreparedOrPrepareReimbursementInvoiceFolder(scope: String) {
        let readableScope = scope == "all" ? "累计池全部发票" : "本轮待报销发票"
        let folderName = scope == "all" ? "全部累计发票" : "本轮待报销发票"
        let folderURL = reimbursementPoolFilesURL.appendingPathComponent(folderName)
        let manifestURL = folderURL.appendingPathComponent("发票文件清单.csv")
        if preparedReimbursementFolderIsCurrent(scope: scope, folderURL: folderURL, manifestURL: manifestURL) {
            reimbursementError = ""
            if openFolder(folderURL) {
                reimbursementLogText = "已打开\(readableScope)文件夹。\n"
            }
            return
        }
        prepareAndOpenReimbursementInvoiceFolder(scope: scope)
    }

    private func preparedReimbursementFolderIsCurrent(scope: String, folderURL: URL, manifestURL: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              FileManager.default.fileExists(atPath: manifestURL.path) else {
            return false
        }
        let expectedRows = scope == "all" ? (reimbursementStatus.totalInvoices ?? 0) : (reimbursementStatus.pendingInvoices ?? 0)
        guard let manifestPaths = manifestInvoiceFilePaths(at: manifestURL, inside: folderURL) else { return false }
        guard expectedRows > 0,
              manifestPaths.count == expectedRows,
              regularFileCount(in: folderURL, excluding: manifestURL) == expectedRows else {
            return false
        }
        guard let manifestDate = fileModifiedDate(manifestURL) else { return false }
        let poolDate = fileModifiedDate(URL(fileURLWithPath: reimbursementStatus.poolXlsx ?? ""))
            ?? fileModifiedDate(URL(fileURLWithPath: reimbursementStatus.poolCsv ?? ""))
        guard let poolDate, manifestDate >= poolDate else { return false }
        return manifestPaths.allSatisfy { FileManager.default.fileExists(atPath: $0) }
    }

    private func manifestInvoiceFilePaths(at url: URL, inside folderURL: URL) -> Set<String>? {
        guard let rows = csvRows(at: url), let header = rows.first else { return nil }
        guard let fileColumn = header.firstIndex(of: "发票文件") else { return nil }
        let folderPath = folderURL.standardizedFileURL.path
        var paths = Set<String>()
        for row in rows.dropFirst() {
            guard fileColumn < row.count else { return nil }
            let filePath = URL(fileURLWithPath: row[fileColumn]).standardizedFileURL.path
            guard !filePath.isEmpty, filePath.hasPrefix(folderPath + "/") else { return nil }
            paths.insert(filePath)
        }
        return paths
    }

    private func csvRows(at url: URL) -> [[String]]? {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = contents.makeIterator()
        while let char = iterator.next() {
            if char == "\"" {
                if inQuotes, let next = iterator.next() {
                    if next == "\"" {
                        field.append("\"")
                    } else {
                        inQuotes = false
                        if next == "," {
                            row.append(field)
                            field = ""
                        } else if next == "\n" {
                            row.append(field)
                            rows.append(row)
                            row = []
                            field = ""
                        } else if next != "\r" {
                            field.append(next)
                        }
                    }
                } else {
                    inQuotes.toggle()
                }
            } else if char == "," && !inQuotes {
                row.append(field)
                field = ""
            } else if char == "\n" && !inQuotes {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else if char != "\r" || inQuotes {
                field.append(char)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows.filter { !$0.allSatisfy { $0.isEmpty } }
    }

    private func regularFileCount(in folderURL: URL, excluding excludedURL: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(at: folderURL, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return 0
        }
        var count = 0
        for case let fileURL as URL in enumerator where fileURL.path != excludedURL.path {
            if (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                count += 1
            }
        }
        return count
    }

    private func fileModifiedDate(_ url: URL) -> Date? {
        guard !url.path.isEmpty else { return nil }
        return try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }

    func prepareAndOpenLedgerInvoiceFolder(for ledgerPath: String) {
        let cleaned = ledgerPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        if FileManager.default.fileExists(atPath: Self.ledgerInvoiceFolderPath(for: cleaned)) {
            openFolder(URL(fileURLWithPath: Self.ledgerInvoiceFolderPath(for: cleaned)))
            return
        }
        guard FileManager.default.fileExists(atPath: ledgerFolderRunnerURL.path) else {
            openFolder(ledgerInvoiceFoldersURL)
            return
        }
        let result = runProcess(arguments: [ledgerFolderRunnerURL.path, cleaned])
        if result.exitCode == 0, let summary = Self.parseLastLedgerFolderSummary(from: result.output), let folder = summary.invoiceFolder, !folder.isEmpty {
            refreshLedgers()
            openFolder(URL(fileURLWithPath: folder))
        } else {
            lastError = result.exitCode == 0 ? "没有生成台账对应的发票文件夹。" : "生成台账对应发票文件夹失败，退出码 \(result.exitCode)。"
            if !result.error.isEmpty {
                lastError += "\n\(result.error)"
            }
        }
    }

    func chooseBaseReport() {
        let panel = NSOpenPanel()
        panel.title = "高级修复：选择旧扫描 CSV 台账"
        panel.message = "正常扫新发票不需要选这里。只有在旧扫描台账需要重新合并时才使用。"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = ledgerURL
        if panel.runModal() == .OK {
            baseReportPath = panel.url?.path ?? ""
        }
    }

    func stopCollection() {
        currentProcess?.terminate()
        logText += "\n已请求停止当前任务。\n"
    }

    func stopICloudScan() {
        currentICloudProcess?.terminate()
        iCloudLogText += "\n已请求停止 iCloud 只读扫描。\n"
    }

    func confirmAndCleanupOutOfYearReviewFiles() {
        guard FileManager.default.fileExists(atPath: reviewCleanupRunnerURL.path) else {
            lastError = "找不到人工复核清理工具。"
            return
        }
        let year = Calendar.current.component(.year, from: Date())
        let alert = NSAlert()
        alert.messageText = "移出非本年度发票？"
        alert.informativeText = "会检查人工复核里的待判断文件。能明确识别出开票日期且年份不是 \(year) 的文件，会移到“非本年度发票”文件夹。\n\n识别不出日期的文件会继续留在待审核里。不会扫邮箱，不会提交报销。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "移出非本年度")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            cleanupOutOfYearReviewFiles(year: year)
        }
    }

    func cleanupOutOfYearReviewFiles(year: Int) {
        Task.detached {
            let result = Self.runProcessSync(arguments: [reviewCleanupRunnerURL.path, "--year", String(year)])
            await MainActor.run {
                if result.exitCode == 0, let summary = Self.parseLastReviewCleanupSummary(from: result.output) {
                    self.refreshReviewItems()
                    let alert = NSAlert()
                    alert.messageText = "非本年度清理完成"
                    alert.informativeText = "检查 \(summary.scannedFiles ?? 0) 个待审核文件，移出 \(summary.movedFiles ?? 0) 个非 \(year) 年文件。\n\n识别不出日期的 \(summary.unknownDateFiles ?? 0) 个文件仍留在待审核里。"
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "知道了")
                    if let folder = summary.archiveFolder, !folder.isEmpty {
                        alert.addButton(withTitle: "打开非本年度文件夹")
                        if alert.runModal() == .alertSecondButtonReturn {
                            self.openFolder(URL(fileURLWithPath: folder))
                        }
                    } else {
                        alert.runModal()
                    }
                } else {
                    self.lastError = result.exitCode == 0 ? "清理完成，但没有读取到清理结果。" : "清理非本年度发票失败，退出码 \(result.exitCode)。"
                }
            }
        }
    }

    func confirmAndRun() {
        let alert = NSAlert()
        alert.messageText = "开始整理发票？"
        let accountCount = selectedAccountIDs.count
        let sinceText = Self.dateFormatter.string(from: since)
        let untilText = Self.dateFormatter.string(from: until)
        var info = demoMode
            ? "当前是演示模式，不会连接邮箱，只会展示运行完成后的界面。"
            : "将读取 \(accountCount) 个邮箱，邮件时间范围 \(sinceText) 至 \(untilText)，下载疑似发票并生成台账。"
        if reprocess {
            info += "\n\n已开启“重新检查已处理邮件”，运行时间会更长，并可能重新下载历史线索。"
        }
        if !baseReportPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            info += "\n\n本次会额外合并一个旧扫描台账。这只用于修复历史流水，报销导入仍以“截止目前汇总”为准。"
        } else {
            info += "\n\n完成后会自动刷新“截止目前汇总（导入用）”。新发票会进入当前累计池，不需要手动选择旧台账。"
        }
        info += "\n\n不会提交或显示邮箱授权码。"
        alert.informativeText = info
        alert.alertStyle = reprocess ? .warning : .informational
        alert.addButton(withTitle: "开始整理")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            runCollection()
        }
    }

    func confirmAndRunICloudReadonlyScan() {
        guard !isICloudScanning else { return }
        let alert = NSAlert()
        alert.messageText = "只读扫描 iCloud 新凭证？"
        alert.informativeText = "第一阶段只读取本地 iCloud 扫描证据，生成摘要和链接入口。\n\n不会提交开票申请，不会发送公司抬头、税号或收票邮箱。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "开始只读扫描")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            runICloudReadonlyScan()
        }
    }

    func runICloudReadonlyScan() {
        guard !isICloudScanning else { return }
        isICloudScanning = true
        iCloudError = ""
        lastICloudScan = nil
        iCloudLogText = "准备启动 iCloud 只读扫描...\n"

        Task.detached {
            let result = await self.runICloudProcessStreaming(arguments: [iCloudRunnerURL.path])
            await MainActor.run {
                self.isICloudScanning = false
                if !result.error.isEmpty {
                    self.iCloudLogText += "\n[stderr]\n\(result.error)"
                }
                if result.exitCode == 0, let summary = Self.parseLastICloudSummary(from: result.output) {
                    self.lastICloudScan = summary
                    self.loadICloudStatus()
                } else {
                    self.iCloudError = result.exitCode == 0 ? "只读扫描完成，但没有读取到结构化结果。" : "只读扫描失败，退出码 \(result.exitCode)。"
                }
            }
        }
    }

    private func runProcess(arguments: [String]) -> (output: String, error: String, exitCode: Int32) {
        Self.runProcessSync(arguments: arguments)
    }

    nonisolated private static func pythonEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        return environment
    }

    nonisolated private static func runProcessSync(arguments: [String]) -> (output: String, error: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = pythonURL
        process.arguments = arguments
        process.currentDirectoryURL = workspaceRoot
        process.environment = Self.pythonEnvironment()

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let outputCapture = ProcessCapture()
        let errorCapture = ProcessCapture()

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            outputCapture.append(text)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            errorCapture.append(text)
        }

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            return ("", error.localizedDescription, 1)
        }

        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        let output = outputCapture.text + (String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
        let error = errorCapture.text + (String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
        return (output, error, process.terminationStatus)
    }

    nonisolated private func runProcessStreaming(arguments: [String]) async -> (output: String, error: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = pythonURL
        process.arguments = arguments
        process.currentDirectoryURL = workspaceRoot
        process.environment = Self.pythonEnvironment()

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let outputCapture = ProcessCapture()
        let errorCapture = ProcessCapture()

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            outputCapture.append(text)
            Task { @MainActor in self.logText += text }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            errorCapture.append(text)
            Task { @MainActor in self.logText += text }
        }

        do {
            try process.run()
            await MainActor.run { self.currentProcess = process }
            process.waitUntilExit()
        } catch {
            return ("", error.localizedDescription, 1)
        }

        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        let output = outputCapture.text + (String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
        let error = errorCapture.text + (String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
        await MainActor.run { self.currentProcess = nil }
        return (output, error, process.terminationStatus)
    }

    nonisolated private func runICloudProcessStreaming(arguments: [String]) async -> (output: String, error: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = pythonURL
        process.arguments = arguments
        process.currentDirectoryURL = workspaceRoot
        process.environment = Self.pythonEnvironment()

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let outputCapture = ProcessCapture()
        let errorCapture = ProcessCapture()

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            outputCapture.append(text)
            Task { @MainActor in self.iCloudLogText += text }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            errorCapture.append(text)
            Task { @MainActor in self.iCloudLogText += text }
        }

        do {
            try process.run()
            await MainActor.run { self.currentICloudProcess = process }
            process.waitUntilExit()
        } catch {
            return ("", error.localizedDescription, 1)
        }

        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        let output = outputCapture.text + (String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
        let error = errorCapture.text + (String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
        await MainActor.run { self.currentICloudProcess = nil }
        return (output, error, process.terminationStatus)
    }

    nonisolated private func runReimbursementProcessStreaming(arguments: [String]) async -> (output: String, error: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = pythonURL
        process.arguments = arguments
        process.currentDirectoryURL = workspaceRoot
        process.environment = Self.pythonEnvironment()

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let outputCapture = ProcessCapture()
        let errorCapture = ProcessCapture()

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            outputCapture.append(text)
            Task { @MainActor in self.reimbursementLogText += text }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            errorCapture.append(text)
            Task { @MainActor in self.reimbursementLogText += text }
        }

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ("", error.localizedDescription, 1)
        }

        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        let output = outputCapture.text + (String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
        let error = errorCapture.text + (String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
        return (output, error, process.terminationStatus)
    }

    private static func parseLastSummary(from output: String) -> RunSummary? {
        for line in output.components(separatedBy: .newlines).reversed() {
            guard line.hasPrefix("INVOICE_SUMMARY_JSON=") else { continue }
            let json = String(line.dropFirst("INVOICE_SUMMARY_JSON=".count))
            guard let data = json.data(using: .utf8) else { continue }
            return try? JSONDecoder().decode(RunSummary.self, from: data)
        }
        let starts = output.indices.filter { output[$0] == "{" }
        for start in starts.reversed() {
            let json = String(output[start...])
            guard let data = json.data(using: .utf8),
                  let summary = try? JSONDecoder().decode(RunSummary.self, from: data),
                  summary.status != nil
            else {
                continue
            }
            return summary
        }
        return nil
    }

    private static func parseLatestSummaryFromDisk() -> RunSummary? {
        guard let files = try? FileManager.default.contentsOfDirectory(at: stateURL, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
            return nil
        }
        guard let latest = files
            .filter({ $0.lastPathComponent.hasPrefix("multi_account_summary_") && $0.pathExtension == "json" })
            .compactMap({ url -> (url: URL, modified: Date)? in
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                return (url, values?.contentModificationDate ?? .distantPast)
            })
            .sorted(by: { $0.modified > $1.modified })
            .first?.url,
              let data = try? Data(contentsOf: latest),
              var summary = try? JSONDecoder().decode(RunSummary.self, from: data)
        else {
            return nil
        }
        summary.summaryPath = latest.path
        return summary
    }

    private static func parseLastLedgerFolderSummary(from output: String) -> LedgerFolderSummary? {
        for line in output.components(separatedBy: .newlines).reversed() {
            guard line.hasPrefix("LEDGER_FOLDER_SUMMARY_JSON=") else { continue }
            let json = String(line.dropFirst("LEDGER_FOLDER_SUMMARY_JSON=".count))
            guard let data = json.data(using: .utf8) else { continue }
            return try? JSONDecoder().decode(LedgerFolderSummary.self, from: data)
        }
        return nil
    }

    private static func parseLastReimbursementSummary(from output: String) -> ReimbursementStatus? {
        for line in output.components(separatedBy: .newlines).reversed() {
            guard line.hasPrefix("REIMBURSEMENT_SUMMARY_JSON=") else { continue }
            let json = String(line.dropFirst("REIMBURSEMENT_SUMMARY_JSON=".count))
            guard let data = json.data(using: .utf8) else { continue }
            return try? JSONDecoder().decode(ReimbursementStatus.self, from: data)
        }
        return nil
    }

    private static func parseLastReviewCleanupSummary(from output: String) -> ReviewCleanupSummary? {
        for line in output.components(separatedBy: .newlines).reversed() {
            guard line.hasPrefix("REVIEW_CLEANUP_SUMMARY_JSON=") else { continue }
            let json = String(line.dropFirst("REVIEW_CLEANUP_SUMMARY_JSON=".count))
            guard let data = json.data(using: .utf8) else { continue }
            return try? JSONDecoder().decode(ReviewCleanupSummary.self, from: data)
        }
        return nil
    }

    private static func ledgerInvoiceFolderPath(for ledgerPath: String) -> String {
        let url = URL(fileURLWithPath: ledgerPath)
        let stem = url.deletingPathExtension().lastPathComponent
        return ledgerInvoiceFoldersURL.appendingPathComponent(stem).path
    }

    private func moneyText(_ value: Double) -> String {
        "¥" + String(format: "%.2f", value)
    }

    private static func parseLastICloudSummary(from output: String) -> ICloudScanSummary? {
        for line in output.components(separatedBy: .newlines).reversed() {
            guard line.hasPrefix("ICLOUD_SCAN_SUMMARY_JSON=") else { continue }
            let json = String(line.dropFirst("ICLOUD_SCAN_SUMMARY_JSON=".count))
            guard let data = json.data(using: .utf8) else { continue }
            return try? JSONDecoder().decode(ICloudScanSummary.self, from: data)
        }
        return nil
    }

    private static func parseSimpleCSV(_ text: String) -> [[String: String]] {
        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard let headerLine = lines.first else { return [] }
        let headers = splitCSVLine(headerLine)
        return lines.dropFirst().map { line in
            let values = splitCSVLine(line)
            var row: [String: String] = [:]
            for (index, key) in headers.enumerated() {
                row[key] = index < values.count ? values[index] : ""
            }
            return row
        }
    }

    private static func splitCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var iterator = line.makeIterator()
        while let character = iterator.next() {
            if character == "\"" {
                inQuotes.toggle()
            } else if character == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        fields.append(current)
        return fields
    }

    private static func reportNumber(in text: String, prefix: String) -> Int? {
        for line in text.components(separatedBy: .newlines) where line.hasPrefix(prefix) {
            let digits = line.filter { $0.isNumber }
            return digits.isEmpty ? nil : Int(digits)
        }
        return nil
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

struct SidebarView: View {
    @ObservedObject var model: InvoiceAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("发票管家")
                .font(.title2.weight(.semibold))
                .padding(.horizontal, 18)
                .padding(.top, 22)

            VStack(alignment: .leading, spacing: 6) {
                Text("运行")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 18)
                ForEach(AppSection.allCases) { section in
                    sidebarButton(section.title, icon: section.icon, selected: model.selectedSection == section) {
                        model.selectedSection = section
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("邮箱")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 18)
                if model.accounts.isEmpty {
                    Text("未读取到账号")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                }
                ForEach(model.accounts) { account in
                    Button {
                        if model.selectedAccountIDs.contains(account.id) {
                            model.selectedAccountIDs.remove(account.id)
                        } else {
                            model.selectedAccountIDs.insert(account.id)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: model.selectedAccountIDs.contains(account.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(model.selectedAccountIDs.contains(account.id) ? .blue : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.label?.isEmpty == false ? account.label! : account.id)
                                    .lineLimit(1)
                                Text(account.provider ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 4) {
                Text("版本 \(appVersion)")
                    .font(.caption.weight(.semibold))
                Text("\(appEdition) · build \(appBuild)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
        }
        .background(.regularMaterial)
        .toolbar {
            Button {
                model.loadAccounts()
                model.loadICloudStatus()
                model.loadReimbursementStatus()
                model.refreshLedgers()
                model.refreshReviewItems()
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
        }
    }

    private func sidebarButton(_ title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .frame(width: 18)
                Text(title)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(selected ? Color.accentColor.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .foregroundStyle(selected ? .primary : .secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }
}

struct RunCenterView: View {
    @ObservedObject var model: InvoiceAppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                controls
                importSummaryView
                if let summary = model.lastSummary {
                    summaryView(summary)
                } else if !model.lastError.isEmpty {
                    noticeView(title: "需要处理", message: model.lastError, systemImage: "exclamationmark.triangle.fill", color: .orange)
                }
                logView
                recentLedgers
            }
            .padding(24)
            .padding(.top, 12)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItemGroup {
                Button {
                    model.openFolder(invoiceRoot.appendingPathComponent("私密配置"))
                } label: {
                    Label("配置", systemImage: "gearshape")
                }
                Button {
                    model.openFolder(ledgerURL)
                } label: {
                    Label("打开台账", systemImage: "folder")
                }
                Button {
                    model.openFolder(reviewURL)
                } label: {
                    Label("人工复核", systemImage: "tray.full")
                }
                if model.isRunning {
                    Button(role: .destructive) {
                        model.stopCollection()
                    } label: {
                        Label("停止", systemImage: "stop.fill")
                    }
                } else {
                    Button {
                        model.confirmAndRun()
                    } label: {
                        Label("开始", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.selectedAccountIDs.isEmpty)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("运行中心")
                    .font(.largeTitle.weight(.semibold))
                Text("选择邮箱和邮件时间，自动整理中国发票，完成后刷新可报销导入的累计池。")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isRunning {
                VStack(alignment: .trailing, spacing: 6) {
                    ProgressView()
                        .controlSize(.large)
                    Text("已运行 \(model.elapsedText)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                DatePicker("邮件开始日期", selection: $model.since, displayedComponents: .date)
                DatePicker("邮件结束日期", selection: $model.until, displayedComponents: .date)
                TextField("最多检查邮件数，0 为不限制", text: $model.limit)
                    .frame(width: 180)
                    .textFieldStyle(.roundedBorder)
                Text("已选 \(model.selectedAccountIDs.count) 个邮箱")
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                Toggle("演示模式，不连接邮箱", isOn: $model.demoMode)
                Toggle("强制重跑已处理邮件", isOn: $model.reprocess)
                    .disabled(model.demoMode)
                Label("新扫到的发票会自动进入本轮累计池", systemImage: "tray.full")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            DisclosureGroup("高级修复：合并旧扫描台账", isExpanded: $model.showAdvancedLedgerMerge) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("正常报销不用选这里。只有要修复某个历史扫描流水时，才选择“发票整理/台账”里的 CSV。报销导入始终打开下方“截止目前汇总”。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        TextField("旧扫描 CSV，可留空", text: $model.baseReportPath)
                            .textFieldStyle(.roundedBorder)
                            .disabled(model.demoMode)
                        Button {
                            model.chooseBaseReport()
                        } label: {
                            Label("选择旧扫描", systemImage: "doc.badge.plus")
                        }
                        .disabled(model.demoMode)
                        Button {
                            model.baseReportPath = ""
                        } label: {
                            Label("清空", systemImage: "xmark.circle")
                        }
                        .disabled(model.demoMode || model.baseReportPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            if model.demoMode {
                Text("演示模式只用于验收界面，不会读取邮箱。关闭后才会真正整理发票。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var importSummaryView: some View {
        let total = model.reimbursementStatus.totalInvoices ?? 0
        let amount = model.reimbursementStatus.totalAmount ?? 0
        let pending = model.reimbursementStatus.pendingInvoices ?? 0
        let poolPath = model.reimbursementStatus.poolXlsx ?? ""
        let duplicateGroups = model.reimbursementStatus.duplicateInvoiceFileGroups ?? 0
        let importBlocked = duplicateGroups > 0
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("截止目前汇总（导入用）", systemImage: "tray.full.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.blue)
                    Text("这里和“报销管理”的累计池是同一份。需要导入报销时，优先打开这份 Excel。")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(money(amount))
                        .font(.title2.monospacedDigit().weight(.semibold))
                    Text(poolDateText)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 14) {
                metric("汇总发票", "\(total) 张")
                metric("待导入", "\(pending) 张")
                metric("已进批次", "\(model.reimbursementStatus.reimbursedInvoices ?? 0) 张")
            }
            HStack {
                Button {
                    model.openURL(path: poolPath)
                } label: {
                    Label("打开导入 Excel", systemImage: "tablecells")
                }
                .buttonStyle(.borderedProminent)
                .disabled(poolPath.isEmpty || importBlocked)
                Button {
                    model.openURL(path: model.reimbursementStatus.poolCsv ?? "")
                } label: {
                    Label("打开 CSV", systemImage: "doc.plaintext")
                }
                .disabled((model.reimbursementStatus.poolCsv ?? "").isEmpty)
                Button {
                    model.openPreparedOrPrepareReimbursementInvoiceFolder(scope: "all")
                } label: {
                    Label("打开对应发票文件夹", systemImage: "folder")
                }
                .disabled(model.isReimbursementWorking || total == 0)
                Button {
                    model.refreshReimbursementPool()
                } label: {
                    Label("刷新汇总", systemImage: "arrow.clockwise")
                }
                .disabled(model.isReimbursementWorking)
                Spacer()
            }
            if importBlocked {
                Text("发现 \(duplicateGroups) 组发票文件重复指向，先到“报销管理”处理后再导入。")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if total == 0 {
                Text("还没有生成累计池。先运行一次整理，或点击刷新汇总。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("这份汇总会随报销池刷新而更新；历史扫描台账只用于追溯，不建议作为报销导入版本。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func summaryView(_ summary: RunSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("运行完成", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3.weight(.semibold))
                Spacer()
                if let elapsed = summary.elapsedSeconds {
                    Text("\(elapsed, specifier: "%.1f") 秒")
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 14) {
                metric("新增正式发票", "\(summary.newFormalInvoices ?? 0) 张")
                metric("新增金额", money(summary.newFormalAmount ?? 0))
                metric("合并后发票", "\(summary.mergedFormalInvoices ?? 0) 张")
                metric("合并后金额", money(summary.mergedFormalAmount ?? 0))
            }
            if (summary.newFormalInvoices ?? 0) == 0 && (summary.mergedFormalInvoices ?? 0) > 0 {
                Text("本次没有新增发票，通常表示这些邮件已经整理过。需要重新检查时再打开“强制重跑已处理邮件”。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let pending = summary.pendingReimbursementInvoices {
                Text("累计发票池当前待报销 \(pending) 张，已进入报销批次 \(summary.reimbursedInvoices ?? 0) 张。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button {
                    model.openURL(path: summary.xlsxReport ?? "")
                } label: {
                    Label("打开本次台账", systemImage: "tablecells")
                }
                .disabled((summary.xlsxReport ?? "").isEmpty)
                Button {
                    model.openURL(path: summary.cumulativeLedger ?? model.reimbursementStatus.poolXlsx ?? "")
                } label: {
                    Label("打开累计池", systemImage: "tray.full")
                }
                .disabled(((summary.cumulativeLedger ?? "").isEmpty) && ((model.reimbursementStatus.poolXlsx ?? "").isEmpty))
                Button {
                    model.openURL(path: summary.csvReport ?? "")
                } label: {
                    Label("打开 CSV", systemImage: "doc.plaintext")
                }
                .disabled((summary.csvReport ?? "").isEmpty)
                Button {
                    let ledgerPath = (summary.xlsxReport?.isEmpty == false ? summary.xlsxReport : summary.csvReport) ?? ""
                    if let folder = summary.invoiceFolder, !folder.isEmpty {
                        model.openFolder(URL(fileURLWithPath: folder))
                    } else {
                        model.prepareAndOpenLedgerInvoiceFolder(for: ledgerPath)
                    }
                } label: {
                    Label("打开发票文件夹", systemImage: "folder")
                }
                .disabled(((summary.xlsxReport ?? "").isEmpty && (summary.csvReport ?? "").isEmpty) && (summary.invoiceFolder ?? "").isEmpty)
                Button {
                    model.openFolder(reviewURL)
                } label: {
                    Label("查看待复核", systemImage: "exclamationmark.triangle")
                }
            }
            if let files = summary.invoiceFiles, files > 0 {
                Text("已为这份台账准备 \(files) 个发票文件。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.monospacedDigit().weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func money(_ value: Double) -> String {
        "¥" + String(format: "%.2f", value)
    }

    private var poolDateText: String {
        let from = model.reimbursementStatus.pendingDateFrom ?? ""
        let to = model.reimbursementStatus.pendingDateTo ?? ""
        if !from.isEmpty && !to.isEmpty {
            return "\(from) 至 \(to)"
        }
        return "截止目前"
    }

    private func noticeView(title: String, message: String, systemImage: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(message).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var logView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("运行日志")
                .font(.headline)
            ScrollView {
                Text(model.logText.isEmpty ? "尚未运行。" : model.logText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .frame(minHeight: 160, maxHeight: 280)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var recentLedgers: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("最近扫描台账")
                        .font(.headline)
                    Text("这里是每次扫描留下的流水记录；报销导入请用上方“截止目前汇总”。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.refreshLedgers()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }
            ForEach(model.recentLedgers) { ledger in
                HStack {
                    Image(systemName: ledger.path.hasSuffix(".xlsx") ? "tablecells" : "doc.plaintext")
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ledger.name)
                            .lineLimit(1)
                        Text(ledger.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        model.openURL(path: ledger.path)
                    } label: {
                        Label("打开", systemImage: "arrow.up.forward.square")
                    }
                    Button {
                        model.prepareAndOpenLedgerInvoiceFolder(for: ledger.path)
                    } label: {
                        Label("发票文件夹", systemImage: "folder")
                    }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }
}

struct ReimbursementView: View {
    @ObservedObject var model: InvoiceAppModel
    @State private var showLog = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                nextRoundView
                historyView
                issueView
                rejectedPoolView
                fileEntrancesView
                if !model.reimbursementError.isEmpty {
                    noticeView(title: "需要处理", message: model.reimbursementError, systemImage: "exclamationmark.triangle.fill", color: .orange)
                }
                logView
            }
            .padding(24)
            .padding(.top, 12)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItemGroup {
                Button {
                    model.refreshReimbursementPool()
                } label: {
                    Label("刷新累计池", systemImage: "arrow.clockwise")
                }
                Button {
                    model.confirmAndStartReimbursementRound()
                } label: {
                    Label("新一轮报销", systemImage: "plus.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isReimbursementWorking)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("报销工作台")
                    .font(.largeTitle.weight(.semibold))
                Text("这里负责准备本轮报销资料、保留历史批次、检查缺失发票文件。不会提交报销。")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isReimbursementWorking {
                VStack(alignment: .trailing, spacing: 6) {
                    ProgressView()
                        .controlSize(.large)
                    Text("处理中")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var nextRoundView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("本轮待报销", systemImage: "tray.full.fill")
                .foregroundStyle(.blue)
                .font(.title3.weight(.semibold))
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                Text("\(model.reimbursementStatus.pendingInvoices ?? 0)")
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("张待打包")
                    .font(.title3.weight(.semibold))
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(money(model.reimbursementStatus.pendingAmount ?? 0))
                        .font(.title2.monospacedDigit().weight(.semibold))
                    Text(pendingDateText)
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Button {
                    model.confirmAndStartReimbursementRound()
                } label: {
                    Label("开始新一轮报销", systemImage: "plus.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isReimbursementWorking || (model.reimbursementStatus.pendingInvoices ?? 0) == 0)
                Button {
                    model.openURL(path: model.reimbursementStatus.poolXlsx ?? "")
                } label: {
                    Label("查看累计池 Excel", systemImage: "tablecells")
                }
                .disabled((model.reimbursementStatus.poolXlsx ?? "").isEmpty)
                Button {
                    model.openPreparedOrPrepareReimbursementInvoiceFolder(scope: "pending")
                } label: {
                    Label("打开对应发票文件夹", systemImage: "folder")
                }
                .disabled(model.isReimbursementWorking || (model.reimbursementStatus.pendingInvoices ?? 0) == 0)
                Spacer()
            }
            if (model.reimbursementStatus.latestRound?.roundId ?? "").isEmpty {
                Text("当前还没有历史批次。第一次开始新一轮会纳入上方全部待报销发票。")
                    .foregroundStyle(.secondary)
            } else {
                Text("已进入旧批次的发票不会重复进入本轮。")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var historyView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("历史报销批次", systemImage: "clock.arrow.circlepath")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button {
                    model.openFolder(URL(fileURLWithPath: model.reimbursementStatus.roundsDir ?? reimbursementRootURL.appendingPathComponent("报销批次").path))
                } label: {
                    Label("打开批次文件夹", systemImage: "folder")
                }
            }
            let rounds = model.reimbursementStatus.rounds ?? []
            if rounds.isEmpty {
                Text("还没有生成过报销批次。生成后，这里会保留每一轮的清单和发票文件夹。")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(rounds) { round in
                        roundRow(round)
                        if round.id != (rounds.last?.id ?? "") {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var issueView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("待处理问题", systemImage: "exclamationmark.triangle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.orange)
                Spacer()
                Button {
                    model.openFolder(reimbursementRootURL)
                } label: {
                    Label("打开报销管理", systemImage: "folder")
                }
            }
            let manifests = model.reimbursementStatus.missingManifests ?? []
            if manifests.isEmpty {
                Text("目前没有缺失或重复发票文件清单。")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(manifests) { manifest in
                        HStack(spacing: 12) {
                            Image(systemName: "doc.plaintext")
                                .foregroundStyle(.orange)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(manifest.name ?? "缺失清单")
                                    .lineLimit(1)
                                Text("\(manifest.rows ?? 0) 条，\(manifest.modifiedAt ?? "")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                model.openURL(path: manifest.path ?? "")
                            } label: {
                                Label("打开", systemImage: "arrow.up.forward.square")
                            }
                            .disabled((manifest.path ?? "").isEmpty)
                        }
                        .padding(.vertical, 8)
                        if manifest.id != (manifests.last?.id ?? "") {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var rejectedPoolView: some View {
        let rows = model.reimbursementStatus.poolRejectedRows ?? 0
        return Group {
            if rows > 0 {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("未进入报销池", systemImage: "line.3.horizontal.decrease.circle")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.orange)
                        Spacer()
                        Button {
                            model.openURL(path: model.reimbursementStatus.poolRejectedCsv ?? "")
                        } label: {
                            Label("打开清单", systemImage: "doc.plaintext")
                        }
                        .disabled((model.reimbursementStatus.poolRejectedCsv ?? "").isEmpty)
                    }
                    Text("\(rows) 条记录没有进入累计池。下面是系统返回的主要原因，打开清单可以逐条查看。")
                        .foregroundStyle(.secondary)
                    if let reasons = model.reimbursementStatus.poolRejectedByReason, !reasons.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(reasons.sorted(by: { $0.value > $1.value }).prefix(4), id: \.key) { reason, count in
                                HStack {
                                    Text(reason)
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(count)")
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                                .font(.caption)
                            }
                        }
                    }
                }
                .padding(18)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private var fileEntrancesView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("常用入口")
                .font(.headline)
            HStack {
                Button {
                    model.refreshReimbursementPool()
                } label: {
                    Label("刷新累计池", systemImage: "arrow.clockwise")
                }
                .disabled(model.isReimbursementWorking)
                Button {
                    model.openFolder(reimbursementRootURL)
                } label: {
                    Label("报销总文件夹", systemImage: "folder")
                }
                Button {
                    model.openPreparedOrPrepareReimbursementInvoiceFolder(scope: "all")
                } label: {
                    Label("累计池全部发票", systemImage: "folder.fill")
                }
                .disabled(model.isReimbursementWorking || (model.reimbursementStatus.totalInvoices ?? 0) == 0)
                if let folder = latestRoundFolder {
                    Button {
                        model.openFolder(URL(fileURLWithPath: folder))
                    } label: {
                        Label("最近一轮发票文件夹", systemImage: "folder.badge.person.crop")
                    }
                }
            }
            Text("“打开对应发票文件夹”会按累计池复制本地发票文件，方便核对；这里不会提交报销，也不会发送公司信息。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var logView: some View {
        DisclosureGroup("运行记录", isExpanded: $showLog) {
            ScrollView {
                Text(model.reimbursementLogText.isEmpty ? "尚未操作。" : model.reimbursementLogText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .frame(minHeight: 150, maxHeight: 260)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func roundRow(_ round: ReimbursementRoundInfo) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .foregroundStyle(.blue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(round.roundId ?? "报销批次")
                    .lineLimit(1)
                Text("\(round.roundInvoiceCount ?? 0) 张，\(money(round.roundAmount ?? 0))，\(round.createdAt ?? round.modifiedAt ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.openFolder(URL(fileURLWithPath: round.roundFolder ?? ""))
            } label: {
                Label("文件夹", systemImage: "folder")
            }
            .disabled((round.roundFolder ?? "").isEmpty)
            Button {
                model.openURL(path: round.roundXlsx ?? "")
            } label: {
                Label("清单", systemImage: "tablecells")
            }
            .disabled((round.roundXlsx ?? "").isEmpty)
        }
        .padding(.vertical, 8)
    }

    private func money(_ value: Double) -> String {
        "¥" + String(format: "%.2f", value)
    }

    private var pendingDateText: String {
        let from = model.reimbursementStatus.pendingDateFrom ?? ""
        let to = model.reimbursementStatus.pendingDateTo ?? ""
        if from.isEmpty || to.isEmpty {
            return "暂无日期范围"
        }
        return "\(from) 至 \(to)"
    }

    private var latestRoundFolder: String? {
        if let folder = model.reimbursementStatus.roundFolder, !folder.isEmpty {
            return folder
        }
        if let folder = model.reimbursementStatus.latestRound?.invoiceFolder, !folder.isEmpty {
            return folder
        }
        if let folder = model.reimbursementStatus.latestRound?.roundFolder, !folder.isEmpty {
            return folder
        }
        return nil
    }

    private func noticeView(title: String, message: String, systemImage: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(message).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct ICloudExchangeView: View {
    @ObservedObject var model: InvoiceAppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                statusView
                actionView
                if let summary = model.lastICloudScan {
                    scanSummaryView(summary)
                } else if !model.iCloudError.isEmpty {
                    noticeView(title: "需要处理", message: model.iCloudError, systemImage: "exclamationmark.triangle.fill", color: .orange)
                }
                logView
            }
            .padding(24)
            .padding(.top, 12)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItemGroup {
                Button {
                    model.loadICloudStatus()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                Button {
                    model.openURL(path: model.iCloudStatus.resultPagePath)
                } label: {
                    Label("结果页", systemImage: "doc.richtext")
                }
                Button {
                    model.openURL(path: model.iCloudStatus.archivePath)
                } label: {
                    Label("总清单", systemImage: "tablecells")
                }
                if model.isICloudScanning {
                    Button(role: .destructive) {
                        model.stopICloudScan()
                    } label: {
                        Label("停止", systemImage: "stop.fill")
                    }
                } else {
                    Button {
                        model.confirmAndRunICloudReadonlyScan()
                    } label: {
                        Label("只读扫描", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Apple / iCloud 换开")
                    .font(.largeTitle.weight(.semibold))
                Text("单独管理 iCloud 发票换开线索、官方查询结果和归档清单。第一阶段只读，不提交开票申请。")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isICloudScanning {
                VStack(alignment: .trailing, spacing: 6) {
                    ProgressView()
                        .controlSize(.large)
                    Text("只读扫描中")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var statusView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("当前结果", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.title3.weight(.semibold))
                Spacer()
                Text("2024-01 至 2026-05")
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 14) {
                metric("已归档公司抬头", "\(model.iCloudStatus.archivedCount) 张")
                metric("归档金额", money(model.iCloudStatus.archivedAmount))
                metric("补漏新增", model.iCloudStatus.supplementSummary.contains("新凭证 0 条") ? "0 条" : "看报告")
            }
            Text(model.iCloudStatus.supplementSummary)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var actionView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("资料入口")
                .font(.headline)
            HStack {
                Button {
                    model.openURL(path: model.iCloudStatus.resultPagePath)
                } label: {
                    Label("打开 iCloud 结果页", systemImage: "doc.richtext")
                }
                Button {
                    model.openURL(path: model.iCloudStatus.supplementReportPath)
                } label: {
                    Label("打开补漏报告", systemImage: "doc.plaintext")
                }
                Button {
                    model.openURL(path: model.iCloudStatus.archivePath)
                } label: {
                    Label("打开总归档清单", systemImage: "tablecells")
                }
                Button {
                    model.openFolder(iCloudPackURL)
                } label: {
                    Label("打开资料包", systemImage: "folder")
                }
            }
            HStack {
                Button {
                    model.confirmAndRunICloudReadonlyScan()
                } label: {
                    Label("扫描 iCloud 新凭证", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isICloudScanning)
                Text("只读：不提交申请，不发送公司抬头、税号或收票邮箱。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func scanSummaryView(_ summary: ICloudScanSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("只读扫描完成", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title3.weight(.semibold))
            HStack(spacing: 14) {
                metric("补漏命中邮件", "\(summary.highRelevanceMailHits ?? 0) 封")
                metric("新凭证", "\(summary.newIcloudCredentials ?? 0) 条")
                metric("已看过跳过", "\(summary.seenCredentialsSkipped ?? 0) 条")
                metric("本次提交", "\(summary.submittedApplications ?? 0) 次")
            }
            HStack {
                Button {
                    model.openURL(path: summary.resultPage ?? model.iCloudStatus.resultPagePath)
                } label: {
                    Label("结果页", systemImage: "doc.richtext")
                }
                Button {
                    model.openURL(path: summary.summaryPath ?? "")
                } label: {
                    Label("扫描摘要", systemImage: "doc.plaintext")
                }
                .disabled((summary.summaryPath ?? "").isEmpty)
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var logView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("只读扫描日志")
                .font(.headline)
            ScrollView {
                Text(model.iCloudLogText.isEmpty ? "尚未运行。" : model.iCloudLogText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .frame(minHeight: 160, maxHeight: 280)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.monospacedDigit().weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func money(_ value: Double) -> String {
        "¥" + String(format: "%.2f", value)
    }

    private func noticeView(title: String, message: String, systemImage: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(message).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct ReviewWorkbenchView: View {
    @ObservedObject var model: InvoiceAppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                ForEach(model.reviewGroups) { group in
                    groupView(group)
                }
            }
            .padding(24)
            .padding(.top, 12)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItemGroup {
                Button {
                    model.refreshReviewItems()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                Button {
                    model.openFolder(reviewURL)
                } label: {
                    Label("打开复核文件夹", systemImage: "folder")
                }
                Button {
                    model.confirmAndCleanupOutOfYearReviewFiles()
                } label: {
                    Label("移出非本年度", systemImage: "calendar.badge.exclamationmark")
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("人工复核")
                    .font(.largeTitle.weight(.semibold))
                Text("把需要人看一眼的文件分成三类：待判断、二维码线索、非正式发票。")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text("\(model.reviewGroups.reduce(0) { $0 + $1.total })")
                    .font(.title.monospacedDigit().weight(.semibold))
                Text("个复核文件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func groupView(_ group: ReviewGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(group.title, systemImage: group.systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(color(for: group.id))
                Spacer()
                Text("\(group.total) 个")
                    .font(.headline.monospacedDigit())
                Button {
                    model.openFolder(URL(fileURLWithPath: group.folderPath))
                } label: {
                    Label("打开", systemImage: "folder")
                }
            }
            Text(group.subtitle)
                .foregroundStyle(.secondary)
            if group.recentItems.isEmpty {
                Text("当前没有文件。")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(group.recentItems) { item in
                        reviewRow(item)
                        if item.id != (group.recentItems.last?.id ?? "") {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func reviewRow(_ item: RecentLedger) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon(for: item.name))
                .foregroundStyle(.blue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .lineLimit(1)
                Text(item.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                model.openURL(path: item.path)
            } label: {
                Label("打开", systemImage: "arrow.up.forward.square")
            }
        }
        .padding(.vertical, 8)
    }

    private func color(for id: String) -> Color {
        switch id {
        case "pending":
            return .orange
        case "qr":
            return .purple
        case "non_china":
            return .secondary
        case "out_of_year":
            return .red
        default:
            return .blue
        }
    }

    private func icon(for name: String) -> String {
        let lower = name.lowercased()
        if lower.hasSuffix(".pdf") { return "doc.richtext" }
        if lower.hasSuffix(".xml") { return "chevron.left.forwardslash.chevron.right" }
        if lower.hasSuffix(".ofd") { return "doc" }
        if lower.hasSuffix(".csv") { return "doc.plaintext" }
        return "doc"
    }
}

struct FileListView: View {
    var title: String
    var subtitle: String
    var items: [RecentLedger]
    var emptyText: String
    var refresh: () -> Void
    var openFolder: () -> Void
    var openPath: (String) -> Void
    var openRelatedFolder: ((RecentLedger) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.largeTitle.weight(.semibold))
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    refresh()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                Button {
                    openFolder()
                } label: {
                    Label("打开文件夹", systemImage: "folder")
                }
            }

            if items.isEmpty {
                ContentUnavailableView(emptyText, systemImage: "tray")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(items) { item in
                    HStack(spacing: 12) {
                        Image(systemName: icon(for: item.name))
                            .foregroundStyle(.blue)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name)
                                .lineLimit(1)
                            Text(item.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button {
                            openPath(item.path)
                        } label: {
                            Label("打开", systemImage: "arrow.up.forward.square")
                        }
                        if let openRelatedFolder {
                            Button {
                                openRelatedFolder(item)
                            } label: {
                                Label("发票文件夹", systemImage: "folder")
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                .listStyle(.inset)
            }
        }
        .padding(24)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func icon(for name: String) -> String {
        if name.lowercased().hasSuffix(".xlsx") { return "tablecells" }
        if name.lowercased().hasSuffix(".csv") { return "doc.plaintext" }
        if name.lowercased().hasSuffix(".pdf") { return "doc.richtext" }
        return "doc"
    }
}

struct RootView: View {
    @ObservedObject var model: InvoiceAppModel

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(model: model)
                .frame(width: 260)
            Divider()
            detail
                .frame(minWidth: 860, minHeight: 700)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.selectedSection {
        case .run:
            RunCenterView(model: model)
        case .reimbursement:
            ReimbursementView(model: model)
        case .iCloud:
            ICloudExchangeView(model: model)
        case .review:
            ReviewWorkbenchView(model: model)
        case .ledger:
            FileListView(
                title: "台账文件",
                subtitle: "最近生成的 Excel 和 CSV 台账。正式核对时优先打开 Excel。",
                items: model.recentLedgers,
                emptyText: "还没有生成台账。",
                refresh: { model.refreshLedgers() },
                openFolder: { model.openFolder(ledgerURL) },
                openPath: { model.openURL(path: $0) },
                openRelatedFolder: { model.prepareAndOpenLedgerInvoiceFolder(for: $0.path) }
            )
        }
    }
}

@main
struct InvoicePilotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = InvoiceAppModel()

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--self-test") {
            print("发票管家 self-test: binary ok version \(appVersion) build \(appBuild)")
            exit(0)
        }
        if arguments.contains("--version") {
            print("\(appVersion) (\(appEdition), build \(appBuild))")
            exit(0)
        }
        if arguments.contains("--demo-smoke-test") {
            print("INVOICE_APP_SMOKE_TEST=completed")
            exit(0)
        }
        if arguments.contains("--list-accounts") {
            exit(InvoiceAppModel.runAccountListCommand())
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
            .onAppear {
                model.bootstrap()
                if ProcessInfo.processInfo.environment["INVOICE_APP_SMOKE_TEST"] == "1" {
                    model.runDemoForSmokeTestAndQuit()
                }
            }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("关于发票管家") {
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [
                        .applicationName: "发票管家",
                        .applicationVersion: appVersion,
                        .version: appBuild,
                        .credits: NSAttributedString(
                            string: "\(appEdition)\n\n当前版本包含报销运行层自检、累计池质量规则、对应发票文件夹校验。"
                        )
                    ])
                }
            }
            CommandMenu("发票") {
                Button("开始整理") {
                    model.runCollection()
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(model.isRunning || model.selectedAccountIDs.isEmpty)
                Button("打开台账文件夹") {
                    model.openFolder(ledgerURL)
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                Button("打开台账对应发票") {
                    model.openFolder(ledgerInvoiceFoldersURL)
                }
                Button("打开报销管理") {
                    model.openFolder(reimbursementRootURL)
                }
                Button("打开人工复核") {
                    model.openFolder(reviewURL)
                }
            }
        }
    }
}

//  Export.swift
//  Split Rewards
//
//  Created by TeeVee on 3/11/26.
//
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct TransactionExportButton: View {
    let transactions: [WalletManager.TransactionRow]
    let walletManager: WalletManager
    let isLndTransactionList: Bool
    let isNWCTransactionList: Bool
    let lndWalletId: String?
    let nwcWalletId: String?
    let isCoreLightningTransactionList: Bool
    let coreLightningWalletId: String?
    let isEclairTransactionList: Bool
    let eclairWalletId: String?
    let accentColor: Color

    @State private var isPresentingExporter = false

    var body: some View {
        Button {
            isPresentingExporter = true
        } label: {
            HStack(spacing: 8) {
                Text("Export")
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(transactions.isEmpty)
        .opacity(transactions.isEmpty ? 0.45 : 1)
        .sheet(isPresented: $isPresentingExporter) {
            TransactionExportSheet(
                transactions: transactions,
                walletManager: walletManager,
                isLndTransactionList: isLndTransactionList,
                isNWCTransactionList: isNWCTransactionList,
                lndWalletId: lndWalletId,
                nwcWalletId: nwcWalletId,
                isCoreLightningTransactionList: isCoreLightningTransactionList,
                coreLightningWalletId: coreLightningWalletId,
                isEclairTransactionList: isEclairTransactionList,
                eclairWalletId: eclairWalletId
            )
        }
    }
}

private struct TransactionExportSheet: View {
    let transactions: [WalletManager.TransactionRow]
    let walletManager: WalletManager
    let isLndTransactionList: Bool
    let isNWCTransactionList: Bool
    let lndWalletId: String?
    let nwcWalletId: String?
    let isCoreLightningTransactionList: Bool
    let coreLightningWalletId: String?
    let isEclairTransactionList: Bool
    let eclairWalletId: String?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var lndWalletManager: LNDWalletManager
    @EnvironmentObject private var nwcWalletManager: NWCWalletManager
    @EnvironmentObject private var coreLightningWalletManager: CoreLightningWalletManager
    @EnvironmentObject private var eclairWalletManager: EclairWalletManager

    @State private var selectedPreset: TransactionExportPreset = .thisMonth
    @State private var selectedTransactionType: TransactionExportType = .all
    @State private var customStartDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var customEndDate: Date = Calendar.current.startOfDay(for: Date())

    @State private var shareURL: IdentifiableURL?
    @State private var currentExportURL: URL?
    @State private var exportErrorMessage: String?

    private let exportAccentColor = Color.splitBrandPink

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.opacity(0.97)
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 18) {
                    Text("Choose a date range for your CSV export.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.82))

                    VStack(spacing: 12) {
                        ForEach(TransactionExportPreset.allCases) { preset in
                            presetButton(for: preset)
                        }
                    }

                    if selectedPreset == .custom {
                        customDateSection
                    }

                    transactionTypeSection

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Exported files may contain sensitive financial information.")
                            .font(.footnote)
                            .foregroundColor(.white.opacity(0.62))

                        Text(rangeSummaryText)
                            .font(.footnote.weight(.medium))
                            .foregroundColor(.white.opacity(0.80))
                    }

                    Spacer()

                    Button {
                        generateCSV()
                    } label: {
                        Text("Generate CSV")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(exportAccentColor)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
            }
            .navigationTitle("Export Transactions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .sheet(item: $shareURL) { item in
            ShareSheet(fileURL: item.url) {
                cleanupExportFile(item.url)
                shareURL = nil
            }
        }
        .onDisappear {
            cleanupExportFile(currentExportURL)
        }
        .alert("Export Failed", isPresented: Binding(
            get: { exportErrorMessage != nil },
            set: { if !$0 { exportErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(exportErrorMessage ?? "Unable to create CSV.")
        }
    }

    private var customDateSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Custom Range")
                .font(.headline)
                .foregroundColor(.white)

            DatePicker(
                "Start Date",
                selection: $customStartDate,
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .tint(exportAccentColor)
            .colorScheme(.dark)

            DatePicker(
                "End Date",
                selection: $customEndDate,
                in: customStartDate...,
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .tint(exportAccentColor)
            .colorScheme(.dark)
        }
        .padding(14)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func presetButton(for preset: TransactionExportPreset) -> some View {
        Button {
            selectedPreset = preset
            if preset != .custom {
                let today = Calendar.current.startOfDay(for: Date())
                customStartDate = today
                customEndDate = today
            }
        } label: {
            HStack {
                Text(preset.rawValue)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()

                Image(systemName: selectedPreset == preset ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(selectedPreset == preset ? exportAccentColor : .white.opacity(0.45))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var activeRange: TransactionExportRange {
        TransactionExportRange.make(
            preset: selectedPreset,
            customStartDate: customStartDate,
            customEndDate: customEndDate,
            calendar: .current
        )
    }

    private var filteredTransactions: [WalletManager.TransactionRow] {
        transactions
            .filter { tx in
                tx.transactionDate >= activeRange.startDate &&
                tx.transactionDate < activeRange.endDateExclusive
            }
            .filter { tx in
                selectedTransactionType.matches(direction: tx.direction)
            }
            .sorted { $0.transactionDate < $1.transactionDate }
    }

    private var rangeSummaryText: String {
        let formatter = TransactionCSVExporter.metadataDateFormatter
        let range = activeRange
        return "\(range.label) • \(selectedTransactionType.rawValue): \(formatter.string(from: range.startDate)) – \(formatter.string(from: range.endDateInclusive))"
    }

    private func generateCSV() {
        exportErrorMessage = nil

        Task {
            do {
                let metadata: [String: TransactionExportMetadata]

                if isLndTransactionList {
                    guard let nodeId = lndWalletId ?? lndWalletManager.activeNodeIdentifier() else {
                        throw LNDWalletError.noStoredNode
                    }

                    await LNDTransactionMetadataStore.shared.ensureUsdSnapshots(
                        for: filteredTransactions,
                        nodeId: nodeId,
                        currentBtcUsdRate: walletManager.btcUsdRate
                    )

                    let lndMetadata = await LNDTransactionMetadataStore.shared.metadata(
                        nodeId: nodeId,
                        transactionIds: filteredTransactions.map(\.id)
                    )
                    metadata = lndMetadata.mapValues {
                        TransactionExportMetadata(lndMetadata: $0)
                    }
                } else if isNWCTransactionList {
                    guard let walletId = nwcWalletId ?? nwcWalletManager.activeWalletIdentifier() else {
                        throw NWCWalletError.noStoredConnection
                    }

                    await NWCTransactionMetadataStore.shared.ensureUsdSnapshots(
                        for: filteredTransactions,
                        walletId: walletId,
                        currentBtcUsdRate: walletManager.btcUsdRate
                    )

                    let nwcMetadata = await NWCTransactionMetadataStore.shared.metadata(
                        walletId: walletId,
                        transactionIds: filteredTransactions.map(\.id)
                    )
                    metadata = nwcMetadata.mapValues {
                        TransactionExportMetadata(nwcMetadata: $0)
                    }
                } else if isCoreLightningTransactionList {
                    guard let nodeId = coreLightningWalletId ?? coreLightningWalletManager.activeNodeIdentifier() else {
                        throw CoreLightningWalletError.noStoredNode
                    }

                    await CoreLightningTransactionMetadataStore.ensureUsdSnapshots(
                        for: filteredTransactions,
                        nodeId: nodeId,
                        currentBtcUsdRate: walletManager.btcUsdRate
                    )

                    let coreLightningMetadata = await CoreLightningTransactionMetadataStore.metadata(
                        nodeId: nodeId,
                        transactionIds: filteredTransactions.map(\.id)
                    )
                    metadata = coreLightningMetadata.mapValues {
                        TransactionExportMetadata(lndMetadata: $0)
                    }
                } else if isEclairTransactionList {
                    guard let nodeId = eclairWalletId ?? eclairWalletManager.activeNodeIdentifier() else {
                        throw EclairWalletError.noStoredNode
                    }

                    await EclairTransactionMetadataStore.ensureUsdSnapshots(
                        for: filteredTransactions,
                        nodeId: nodeId,
                        currentBtcUsdRate: walletManager.btcUsdRate
                    )

                    let eclairMetadata = await EclairTransactionMetadataStore.metadata(
                        nodeId: nodeId,
                        transactionIds: filteredTransactions.map(\.id)
                    )
                    metadata = eclairMetadata.mapValues {
                        TransactionExportMetadata(lndMetadata: $0)
                    }
                } else {
                    let walletPubkey = try await MessageKeyManager.shared.currentWalletPubkey(walletManager: walletManager)
                    await walletManager.ensureUsdSnapshots(for: filteredTransactions)
                    let snapshots = await PaymentUsdSnapshotStore.shared.snapshots(
                        walletPubkey: walletPubkey,
                        paymentIds: filteredTransactions.map(\.id)
                    )
                    metadata = snapshots.mapValues {
                        TransactionExportMetadata(paymentSnapshot: $0)
                    }
                }

                let url = try TransactionCSVExporter.makeFile(
                    transactions: filteredTransactions,
                    range: activeRange,
                    transactionType: selectedTransactionType,
                    metadata: metadata
                )

                await MainActor.run {
                    cleanupExportFile(currentExportURL)
                    currentExportURL = url
                    shareURL = IdentifiableURL(url: url)
                }
            } catch {
                await MainActor.run {
                    exportErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func cleanupExportFile(_ url: URL?) {
        guard let url else { return }
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            print("⚠️ Failed to remove export file: \(error)")
        }

        if currentExportURL == url {
            currentExportURL = nil
        }
    }

    private var transactionTypeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Transaction Type:")
                .font(.headline)
                .foregroundColor(.white)

            Picker("Transaction Type", selection: $selectedTransactionType) {
                ForEach(TransactionExportType.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .colorScheme(.dark)
        }
        .padding(14)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private enum TransactionExportPreset: String, CaseIterable, Identifiable {
    case thisMonth = "This Month"
    case lastMonth = "Last Month"
    case yearToDate = "Year to Date"
    case custom = "Custom Range"

    var id: String { rawValue }
}

private enum TransactionExportType: String, CaseIterable, Identifiable {
    case all = "All"
    case sent = "Sent"
    case received = "Received"

    var id: String { rawValue }

    func matches(direction: String) -> Bool {
        switch self {
        case .all:
            return true
        case .sent:
            return direction.caseInsensitiveCompare("sent") == .orderedSame
        case .received:
            return direction.caseInsensitiveCompare("received") == .orderedSame
        }
    }
}

private struct TransactionExportRange {
    let label: String
    let startDate: Date
    let endDateInclusive: Date
    let endDateExclusive: Date

    static func make(
        preset: TransactionExportPreset,
        customStartDate: Date,
        customEndDate: Date,
        calendar: Calendar
    ) -> TransactionExportRange {
        let now = Date()

        switch preset {
        case .thisMonth:
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
            let endInclusive = now
            let endExclusive = now.addingTimeInterval(1)
            return TransactionExportRange(
                label: preset.rawValue,
                startDate: start,
                endDateInclusive: endInclusive,
                endDateExclusive: endExclusive
            )

        case .lastMonth:
            let thisMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
            let lastMonthDate = calendar.date(byAdding: .month, value: -1, to: thisMonthStart) ?? thisMonthStart
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: lastMonthDate)) ?? lastMonthDate
            let endExclusive = thisMonthStart
            let endInclusive = endExclusive.addingTimeInterval(-1)

            return TransactionExportRange(
                label: preset.rawValue,
                startDate: start,
                endDateInclusive: endInclusive,
                endDateExclusive: endExclusive
            )

        case .yearToDate:
            let start = calendar.date(from: calendar.dateComponents([.year], from: now)) ?? now
            let endInclusive = now
            let endExclusive = now.addingTimeInterval(1)
            return TransactionExportRange(
                label: preset.rawValue,
                startDate: start,
                endDateInclusive: endInclusive,
                endDateExclusive: endExclusive
            )

        case .custom:
            let start = calendar.startOfDay(for: min(customStartDate, customEndDate))
            let chosenEnd = max(customStartDate, customEndDate)
            let endExclusive = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: chosenEnd)) ?? now.addingTimeInterval(1)
            let endInclusive = endExclusive.addingTimeInterval(-1)

            return TransactionExportRange(
                label: preset.rawValue,
                startDate: start,
                endDateInclusive: endInclusive,
                endDateExclusive: endExclusive
            )
        }
    }
}

private struct TransactionExportMetadata {
    let btcUsdRateAtTransaction: Double?
    let usdValueAtTransaction: Double?
    let isReportable: Bool

    init(paymentSnapshot: PaymentUsdSnapshot) {
        btcUsdRateAtTransaction = paymentSnapshot.btcUsdRateAtTransaction
        usdValueAtTransaction = paymentSnapshot.usdValueAtTransaction
        isReportable = paymentSnapshot.isReportable
    }

    init(lndMetadata: LNDTransactionMetadata) {
        btcUsdRateAtTransaction = lndMetadata.btcUsdRateAtTransaction
        usdValueAtTransaction = lndMetadata.usdValueAtTransaction
        isReportable = lndMetadata.isReportable
    }

    init(nwcMetadata: NWCTransactionMetadata) {
        btcUsdRateAtTransaction = nwcMetadata.btcUsdRateAtTransaction
        usdValueAtTransaction = nwcMetadata.usdValueAtTransaction
        isReportable = nwcMetadata.isReportable
    }
}

private enum TransactionCSVExporter {
    static let metadataDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    static let rowDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter
    }()

    static func makeFile(
        transactions: [WalletManager.TransactionRow],
        range: TransactionExportRange,
        transactionType: TransactionExportType,
        metadata: [String: TransactionExportMetadata]
    ) throws -> URL {
        let csv = makeCSV(
            transactions: transactions,
            range: range,
            transactionType: transactionType,
            metadata: metadata
        )

        let directory = try exportDirectory()
        let fileURL = nextAvailableFileURL(in: directory)

        try csv.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private static func makeCSV(
        transactions: [WalletManager.TransactionRow],
        range: TransactionExportRange,
        transactionType: TransactionExportType,
        metadata: [String: TransactionExportMetadata]
    ) -> String {
        var rows: [String] = [
            csvRow([
                "Export Name",
                "split-transactions"
            ]),
            csvRow([
                "Date Range",
                range.label
            ]),
            csvRow([
                "Transaction Type",
                transactionType.rawValue
            ]),
            csvRow([
                "Start Date",
                metadataDateFormatter.string(from: range.startDate)
            ]),
            csvRow([
                "End Date",
                metadataDateFormatter.string(from: range.endDateInclusive)
            ]),
            csvRow([
                "Generated At",
                metadataDateFormatter.string(from: Date())
            ]),
            "",
            csvRow([
                "Date",
                "Type",
                "Network",
                "Amount Sats",
                "Amount BTC",
                "Fee Sats",
                "Fee BTC",
                "BTC/USD Rate At Transaction",
                "USD Value At Transaction",
                "Reportable Status",
                "Status",
                "Note"
            ])
        ]

        rows.append(
            contentsOf: transactions.map { tx in
                let transactionMetadata = metadata[tx.id]
                return csvRow([
                    rowDateFormatter.string(from: tx.transactionDate),
                    tx.direction.capitalized,
                    tx.network.capitalized,
                    String(tx.amountSats),
                    tx.btcAmount,
                    String(tx.feeSats),
                    tx.feeBtcAmount,
                    transactionMetadata.map(formatRate) ?? "",
                    transactionMetadata.map(formatUsdValue) ?? "",
                    formatReportableStatus(transactionMetadata),
                    tx.status,
                    tx.note
                ])
            }
        )

        return rows.joined(separator: "\n")
    }

    private static func csvRow(_ values: [String]) -> String {
        values.map(csvEscape).joined(separator: ",")
    }

    private static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }

    private static func formatRate(_ metadata: TransactionExportMetadata) -> String {
        guard let rate = metadata.btcUsdRateAtTransaction else { return "" }
        return String(format: "%.8f", rate)
    }

    private static func formatUsdValue(_ metadata: TransactionExportMetadata) -> String {
        guard let usdValue = metadata.usdValueAtTransaction else { return "" }
        return String(format: "%.2f", usdValue)
    }

    private static func formatReportableStatus(_ metadata: TransactionExportMetadata?) -> String {
        metadata?.isReportable == true ? "Reportable" : "Non-reportable"
    }

    private static func exportDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TransactionExports", isDirectory: true)

        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }

        return directory
    }

    private static func nextAvailableFileURL(in directory: URL) -> URL {
        let fileManager = FileManager.default
        let baseName = "split-transactions"
        let fileExtension = "csv"

        var candidate = directory.appendingPathComponent("\(baseName).\(fileExtension)")
        if !fileManager.fileExists(atPath: candidate.path) {
            return candidate
        }

        var suffix = 2
        while true {
            candidate = directory.appendingPathComponent("\(baseName)\(suffix).\(fileExtension)")
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            suffix += 1
        }
    }
}

private struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ShareSheet: UIViewControllerRepresentable {
    let fileURL: URL
    let onComplete: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: [ExportFileActivityItemSource(fileURL: fileURL)],
            applicationActivities: nil
        )
        controller.completionWithItemsHandler = { _, _, _, _ in
            onComplete()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}

private final class ExportFileActivityItemSource: NSObject, UIActivityItemSource {
    private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        fileURL
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        fileURL as NSURL
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        UTType.fileURL.identifier
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        fileURL.lastPathComponent
    }
}

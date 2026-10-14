//
//  ContentView.swift
//  swiftyapp
//
//  Created by Jonathan McKenzie on 7/9/24.
//

import SwiftUI
import Network
import RustyLib

struct ContentView: View {
    private enum MainPaneMode {
        case compose
        case logging
        case topic
        case mempool
        case clock
    }

    private struct ActivityLogEntry: Identifiable {
        let id = UUID()
        let message: String
    }

    private final class ConnectivityMonitor: ObservableObject {
        @Published var statusMessage = "Network status unknown."

        private let monitor = NWPathMonitor()
        private let queue = DispatchQueue(label: "swiftyapp.connectivity-monitor")

        init() {
            monitor.pathUpdateHandler = { [weak self] path in
                let message = path.status == .satisfied ? "Network online." : "Network offline."
                DispatchQueue.main.async {
                    self?.statusMessage = message
                }
            }
            monitor.start(queue: queue)
        }

        deinit {
            monitor.cancel()
        }
    }

    private static let appVersion: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }()

    private let defaultProtocolPrefix = "/gnostr"
    private let defaultProtocolVersion = Self.appVersion

    @State private var txHex = ""
    @State private var torOnly = true
    @State private var relay = true
    @State private var protocolPrefix = "/gnostr"
    @State private var protocolVersion = Self.appVersion
    @State private var statusMessage = "Paste a raw transaction hex, then blast it."
    @State private var autoBroadcastStatus = "Auto-broadcast idle."
    @State private var activityLog: [ActivityLogEntry] = []
    @State private var mainPaneMode: MainPaneMode = .compose
    @State private var didStartAutoBroadcast = false
    @State private var isWorking = false
    @State private var showingSettings = false
    @StateObject private var connectivityMonitor = ConnectivityMonitor()
    @StateObject private var topicManager = TopicManager()
    @StateObject private var mempoolManager = MempoolManager()
    @StateObject private var clockManager = ClockManager()
    @FocusState private var isTxHexFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            let panelWidth = min(proxy.size.width * 0.84, 760)
            let panelHeight = min(proxy.size.height * 0.84, 980)
            let backgroundAlignment: Alignment = proxy.size.width > proxy.size.height ? .top : .center

            ZStack(alignment: .center) {
                Image(torOnly ? "icon-tor" : "icon-tor-gray")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width,
                           height: proxy.size.height,
                           alignment: backgroundAlignment)
                    .scaleEffect(1.1)
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    Group {
                        switch mainPaneMode {
                        case .compose:
                            composePane
                        case .logging:
                            loggingPane
                        case .topic:
                            topicPane
                        case .mempool:
                            mempoolPane
                        case .clock:
                            clockPane
                        }
                    }

                    Picker("Pane", selection: $mainPaneMode) {
                        Text("Compose").tag(MainPaneMode.compose)
                        Text("Log").tag(MainPaneMode.logging)
                        Text("Topic").tag(MainPaneMode.topic)
                        Text("Mempool").tag(MainPaneMode.mempool)
                        Text("Clock").tag(MainPaneMode.clock)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 16) {
                            Button {
                                torOnly.toggle()
                                setTorOnly(enabled: torOnly)
                            } label: {
                                Image("tor-browser-icon")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 42, height: 42)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Tor only")

                            Button {
                                relay.toggle()
                            } label: {
                                Image("libp2p-color-symbol")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 42, height: 42)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Relay")

                            Spacer()
                        }

                        TextField("Protocol prefix (default: \(defaultProtocolPrefix))", text: $protocolPrefix)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("Protocol version (default: \(defaultProtocolVersion))", text: $protocolVersion)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        Button(isWorking ? "Blasting..." : "Blast transaction") {
                            Task { await blastTransaction() }
                        }
                        .disabled(isWorking || !isTransactionHexValid)

                        Text(statusMessage)
                        Text(autoBroadcastStatus)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text(connectivityMonitor.statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .ignoresSafeArea(edges: .bottom)
                    .overlay(alignment: .bottomTrailing) {
                        Button {
                            showingSettings.toggle()
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.primary)
                                .padding(12)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(12)
                    }
                }
                .frame(width: panelWidth)
                .frame(height: panelHeight)
                .padding(.horizontal)
            }
            .overlay(alignment: .bottomTrailing) {
                protocolBadge
                    .padding(.trailing, proxy.size.width < 500 ? 10 : 18)
                    .padding(.bottom, proxy.size.height < 700 ? 10 : 18)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                isTxHexFocused = false
            }
            .onAppear {
                startAutoBroadcastLoopIfNeeded()
            }
            .onChange(of: connectivityMonitor.statusMessage) { _, newValue in
                appendActivityLog("Connectivity status: \(newValue)")
            }
            .sheet(isPresented: $showingSettings) {
                NavigationStack {
                    Form {
                        Section("Controls") {
                            Toggle("Tor only", isOn: $torOnly)
                            Toggle("Relay", isOn: $relay)
                        }

                        Section("Protocol") {
                            TextField("Protocol prefix (default: \(defaultProtocolPrefix))", text: $protocolPrefix)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            TextField("Protocol version (default: \(defaultProtocolVersion))", text: $protocolVersion)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Text("Defaults to \(defaultProtocolPrefix)/\(defaultProtocolVersion).")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(torOnly ? Color.purple.opacity(0.28) : Color.black.opacity(0.12))
                    .navigationTitle("Settings")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                showingSettings = false
                            }
                            .foregroundStyle(torOnly ? Color.purple.opacity(0.75) : Color.gray.opacity(0.75))
                        }
                    }
                }
            }
            .onChange(of: topicManager.lastReceivedMessage) { _, message in
                if let message {
                    mempoolManager.addPeerTx(txid: message.txid, hex: message.hex)
                    appendActivityLog("Consensus mempool received peer tx: \(message.txid)")
                }
            }
        }
    }

    private var composePane: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: $txHex)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 220, maxHeight: .infinity)
                .focused($isTxHexFocused)
                .scrollContentBackground(.hidden)
                .background(isTxHexFocused ? Color.black.opacity(0.18) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(transactionHexBorderColor, lineWidth: transactionHexBorderWidth)
                )
            if let transactionHexValidationMessage {
                Text(transactionHexValidationMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else {
                Text(" ")
                    .font(.footnote)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var loggingPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Network activity log")
                        .font(.headline)
                    Text("Auto rebroadcasting, mempool fetches, and delivery events.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Edit transaction") {
                    mainPaneMode = .compose
                }
                .buttonStyle(.bordered)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(activityLog) { entry in
                        Text(entry.message)
                            .font(.footnote.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(8)
            .background(Color.black.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var topicPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("bitcoin-pigeon topic")
                        .font(.headline)
                    if let peerId = topicManager.peerId {
                        Text("peer: \(peerId)")
                            .font(.caption)
                            .lineLimit(1)
                    } else {
                        Text("Start a topic node to publish and relay transactions.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }

            HStack(spacing: 12) {
                Button(topicManager.isTopicRunning ? "Topic running" : "Start topic node") {
                    Task {
                        do {
                            let prefix = protocolPrefix.isEmpty ? nil : protocolPrefix
                            let version = protocolVersion.isEmpty ? nil : protocolVersion
                            try await topicManager.startTopicNode(
                                torOnly: torOnly,
                                protocolPrefix: prefix,
                                protocolVersion: version
                            )
                            appendActivityLog("Topic node started.")
                        } catch {
                            appendActivityLog("Topic node failed: \(error.localizedDescription)")
                        }
                    }
                }
                .disabled(topicManager.isTopicRunning)
                .buttonStyle(.borderedProminent)

                Button(topicManager.isGossipRunning ? "Gossip running" : "Start gossip client") {
                    Task {
                        do {
                            let prefix = protocolPrefix.isEmpty ? nil : protocolPrefix
                            let version = protocolVersion.isEmpty ? nil : protocolVersion
                            try await topicManager.startGossipClient(
                                torOnly: torOnly,
                                protocolPrefix: prefix,
                                protocolVersion: version
                            )
                            appendActivityLog("Gossip client started.")
                        } catch {
                            appendActivityLog("Gossip client failed: \(error.localizedDescription)")
                        }
                    }
                }
                .disabled(topicManager.isGossipRunning)
                .buttonStyle(.bordered)

                Spacer()

                Button("Publish to topic") {
                    Task {
                        do {
                            try await topicManager.publish(txHex: normalizedTxHex)
                            appendActivityLog("Published transaction to topic.")
                        } catch {
                            appendActivityLog("Publish to topic failed: \(error.localizedDescription)")
                        }
                    }
                }
                .disabled(!topicManager.isTopicRunning || !isTransactionHexValid)
                .buttonStyle(.bordered)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(topicManager.events) { entry in
                        Text(entry.text)
                            .font(.footnote.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(8)
            .background(Color.black.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var mempoolPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mempool")
                        .font(.headline)
                    Text("Shared consensus mempool: public APIs + bitcoin-pigeon peers.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(mempoolManager.isLoading ? "Loading..." : "Refresh") {
                    Task {
                        await mempoolManager.load(limit: 20, torOnly: torOnly)
                    }
                }
                .disabled(mempoolManager.isLoading)
                .buttonStyle(.borderedProminent)
            }

            if let error = mempoolManager.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 8) {
                Text("Blockheight:")
                    .font(.caption.weight(.semibold))
                if let blockheight = mempoolManager.blockheight {
                    Text("\(blockheight)")
                        .font(.caption.monospaced())
                } else {
                    Text("—")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh height") {
                    Task {
                        await mempoolManager.refreshBlockheight(torOnly: torOnly)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(mempoolManager.entries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.txid)
                                .font(.caption.monospaced())
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                Text(entry.source)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(entry.source == "bitcoin-pigeon peer" ? .orange : .secondary)
                                Text("hex: \(entry.hexPreview)...")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color.black.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(8)
            .background(Color.black.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .task {
            await mempoolManager.load(limit: 20, torOnly: torOnly)
        }
    }

    private var clockPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Network Clock")
                        .font(.headline)
                    Text("BFT time consensus across bitcoin-pigeon peers.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(clockManager.isRunning ? "Clock running" : "Start clock sync") {
                    Task {
                        do {
                            let documents = FileManager.default.urls(
                                for: .documentDirectory,
                                in: .userDomainMask
                            ).first
                            let path = documents?.appendingPathComponent("bitcoin_pigeon_time.json").path
                            try await clockManager.start(storagePath: path)
                            appendActivityLog("Network clock sync started.")
                        } catch {
                            appendActivityLog("Network clock sync failed: \(error.localizedDescription)")
                        }
                    }
                }
                .disabled(clockManager.isRunning)
                .buttonStyle(.borderedProminent)

                Button("Refresh") {
                    clockManager.refresh()
                }
                .buttonStyle(.bordered)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Status:")
                        .font(.caption.weight(.semibold))
                    Text(clockManager.status)
                        .font(.caption)
                    Spacer()
                }
                HStack {
                    Text("Slew rate:")
                        .font(.caption.weight(.semibold))
                    Text(String(format: "%.6f", clockManager.slewRate))
                        .font(.caption.monospaced())
                    Spacer()
                }
                HStack {
                    Text("Offset ms:")
                        .font(.caption.weight(.semibold))
                    Text("\(clockManager.offsetMs)")
                        .font(.caption.monospaced())
                    Spacer()
                }
                HStack {
                    Text("Last sync:")
                        .font(.caption.weight(.semibold))
                    Text(clockManager.lastSyncSecsAgo == .max ? "never" : "\(clockManager.lastSyncSecsAgo)s ago")
                        .font(.caption)
                    Spacer()
                }
                HStack {
                    Text("Logical UTC:")
                        .font(.caption.weight(.semibold))
                    Text(clockManager.logicalUtc)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                    Spacer()
                }
            }
            .padding(8)
            .background(Color.black.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func startAutoBroadcastLoopIfNeeded() {
        guard !didStartAutoBroadcast else {
            return
        }
        didStartAutoBroadcast = true
        Task {
            await autoBroadcastLoop()
        }
    }

    private func autoBroadcastLoop() async {
        await MainActor.run {
            autoBroadcastStatus = "Auto-broadcast running."
            appendActivityLog("Auto-broadcast loop started.")
            appendActivityLog("Auto-broadcast connectivity monitor: \(connectivityMonitor.statusMessage)")
        }

        while !Task.isCancelled {
            let torOnly = await MainActor.run { self.torOnly }
            let relay = await MainActor.run { self.relay }
            setTorOnly(enabled: torOnly)
            await MainActor.run {
                appendActivityLog("Auto-broadcast tick: torOnly=\(torOnly) relay=\(relay) connectivity=\(connectivityMonitor.statusMessage)")
            }

            do {
                await MainActor.run {
                    appendActivityLog("Auto-broadcast delegating fetch/broadcast to Rust.")
                    appendActivityLog("Auto-broadcast relay mode is \(relay ? "enabled" : "disabled"); connecting to Libra relays.")
                }
                let count = try await autoBroadcastRecentTransaction(torOnly: torOnly, relay: relay)
                await MainActor.run {
                    autoBroadcastStatus = "Auto-broadcasted to \(count) libre relay nodes."
                    appendActivityLog("Auto-broadcast success: delivered to \(count) nodes.")
                    appendCapturedRustLogs()
                }
            } catch is CancellationError {
                break
            } catch {
                NSLog("Auto-broadcast failed: \(error.localizedDescription)")
                await MainActor.run {
                    autoBroadcastStatus = torOnly
                        ? "autobroadcast waiting for tor connectivity"
                        : "Auto-broadcast temporarily unavailable."
                    appendActivityLog("Auto-broadcast failed: \(self.describeAutoBroadcastError(error, torOnly: torOnly))")
                    appendActivityLog("Connectivity status: \(connectivityMonitor.statusMessage)")
                    appendCapturedRustLogs()
                    appendActivityLog("Auto-broadcast retrying in 3 seconds.")
                }
            }

            await MainActor.run {
                appendActivityLog("Auto-broadcast retrying in 250 ms.")
            }
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
            } catch {
                break
            }
        }
    }

    @MainActor
    private func blastTransaction() async {
        isWorking = true
        defer { isWorking = false }
        setTorOnly(enabled: torOnly)
        mainPaneMode = .logging
        appendActivityLog("Manual blast requested.")
        appendActivityLog("Manual blast opened the network activity log.")
        appendActivityLog("Manual blast torOnly=\(torOnly) relay=\(relay)")
        appendActivityLog("Manual blast relay mode is \(relay ? "enabled" : "disabled"); connecting to Libra relays.")

        do {
            defer {
                appendCapturedRustLogs()
            }
            appendActivityLog("Manual blast submitting transaction hex to the network.")
            let count = try await blastTransactionHex(txHex: normalizedTxHex, torOnly: torOnly, relay: relay)
            statusMessage = "Delivered to \(count) libre relay nodes. relay=\(relay ? "on" : "off") torOnly=\(torOnly ? "on" : "off")\(protocolStatusSuffix)"
            appendActivityLog("Manual blast succeeded: delivered to \(count) nodes.")
            appendActivityLog("Manual blast relay connection cycle completed.")
        } catch {
            statusMessage = error.localizedDescription
            appendActivityLog("Manual blast failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func appendCapturedRustLogs() {
        for line in drainBlastLogs() {
            appendActivityLog(line)
        }
    }

    private func describeAutoBroadcastError(_ error: Error, torOnly: Bool) -> String {
        if let urlError = error as? URLError, urlError.code == .notConnectedToInternet {
            return torOnly
                ? "No internet connection is available for Tor connectivity."
                : "No internet connection is available."
        }
        return error.localizedDescription
    }

    private var normalizedTxHex: String {
        txHex.components(separatedBy: .whitespacesAndNewlines).joined()
    }

    private var isTransactionHexValid: Bool {
        transactionHexValidationMessage == nil
    }

    private var transactionHexValidationMessage: String? {
        let hex = normalizedTxHex
        guard !hex.isEmpty else {
            return "Paste a transaction hex to enable blasting."
        }
        guard hex.count % 2 == 0 else {
            return "Transaction hex must contain an even number of characters."
        }
        guard hex.allSatisfy(\.isHexDigit) else {
            return "Transaction hex can only contain 0-9 and a-f characters."
        }
        return nil
    }

    private var transactionHexBorderColor: Color {
        guard !normalizedTxHex.isEmpty else {
            return isTxHexFocused ? Color.secondary : Color.clear
        }
        return isTransactionHexValid ? (isTxHexFocused ? Color.secondary : Color.green.opacity(0.65)) : Color.red
    }

    private var transactionHexBorderWidth: CGFloat {
        normalizedTxHex.isEmpty ? 1 : 2
    }

    private var protocolBadgeText: String {
        let prefix = protocolPrefix.isEmpty ? defaultProtocolPrefix : protocolPrefix
        let version = protocolVersion.isEmpty ? Self.appVersion : protocolVersion
        return composeProtocolID(prefix: prefix, version: version)
    }

    private var protocolBadge: some View {
        Text(protocolBadgeText)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.16), radius: 6, x: 0, y: 2)
    }

    private var protocolStatusSuffix: String {
        guard !protocolPrefix.isEmpty || !protocolVersion.isEmpty else {
            return ""
        }

        let prefix = protocolPrefix.isEmpty ? defaultProtocolPrefix : protocolPrefix
        let version = protocolVersion.isEmpty ? Self.appVersion : protocolVersion
        return " protocol=\(composeProtocolID(prefix: prefix, version: version))"
    }

    @MainActor
    private func appendActivityLog(_ message: String) {
        let timestamp = Self.activityLogFormatter.string(from: Date())
        activityLog.append(ActivityLogEntry(message: "[\(timestamp)] \(message)"))
        if activityLog.count > 200 {
            activityLog.removeFirst(activityLog.count - 200)
        }
        if mainPaneMode == .compose && message.contains("succeeded") {
            mainPaneMode = .logging
        }
    }

    private static let activityLogFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

@MainActor
final class ClockManager: ObservableObject {
    @Published private(set) var status = "Init"
    @Published private(set) var slewRate = 1.0
    @Published private(set) var offsetMs: Int64 = 0
    @Published private(set) var lastSyncSecsAgo: UInt64 = .max
    @Published private(set) var logicalUtc = ""
    @Published private(set) var isRunning = false

    private var refreshTask: Task<Void, Never>?

    func start(storagePath: String?) async throws {
        guard !isRunning else { return }
        try await startTimeSyncDaemon(storagePath: storagePath)
        isRunning = true
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        isRunning = false
    }

    func refresh() {
        let metrics = getClockMetrics()
        status = metrics.status
        slewRate = metrics.slewRate
        offsetMs = metrics.offsetMs
        lastSyncSecsAgo = metrics.lastSyncSecsAgo
        logicalUtc = getLogicalUtc()
    }
}

#Preview {
    ContentView()
}

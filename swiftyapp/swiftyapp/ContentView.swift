//
//  ContentView.swift
//  swiftyapp
//
//  Created by Jonathan McKenzie on 7/9/24.
//

import SwiftUI
import RustyLib

struct ContentView: View {
    @State private var txHex = ""
    @State private var torOnly = false
    @State private var relay = true
    @State private var protocolPrefix = ""
    @State private var protocolVersion = ""
    @State private var statusMessage = "Paste a raw transaction hex, then blast it."
    @State private var isWorking = false
    @State private var showingSettings = false
    @FocusState private var isTxHexFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            let panelWidth = min(proxy.size.width * 0.84, 760)
            let panelHeight = min(proxy.size.height * 0.84, 980)

            ZStack(alignment: .center) {
                Image(torOnly ? "icon-tor" : "icon-tor-gray")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width,
                           height: proxy.size.height,
                           alignment: .center)
                    .scaleEffect(1.1)
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        //Text("Transaction input")
                        //    .font(.headline)

                        TextEditor(text: $txHex)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 220, maxHeight: .infinity)
                            .focused($isTxHexFocused)
                            .scrollContentBackground(.hidden)
                            .background(isTxHexFocused ? Color.black.opacity(0.18) : Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isTxHexFocused ? Color.secondary : Color.clear)
                            )
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

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

                        TextField("Protocol prefix (e.g. custom_protocol)", text: $protocolPrefix)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("Protocol version (e.g. 0.0.1)", text: $protocolVersion)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        Button(isWorking ? "Blasting..." : "Blast transaction") {
                            Task { await blastTransaction() }
                        }
                        .disabled(isWorking || normalizedTxHex.isEmpty)

                        Text(statusMessage)
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
            .contentShape(Rectangle())
            .onTapGesture {
                isTxHexFocused = false
            }
            .sheet(isPresented: $showingSettings) {
                NavigationStack {
                    Form {
                        Section("Controls") {
                            Toggle("Tor only", isOn: $torOnly)
                            Toggle("Relay", isOn: $relay)
                        }

                        Section("Protocol") {
                            TextField("Protocol prefix", text: $protocolPrefix)
                            TextField("Protocol version", text: $protocolVersion)
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
                        }
                    }
                }
            }
        }
    }

    @MainActor
    private func blastTransaction() async {
        isWorking = true
        defer { isWorking = false }
        setTorOnly(enabled: torOnly)

        do {
            let count = try await blastTransactionHex(txHex: normalizedTxHex, torOnly: torOnly, relay: relay)
            statusMessage = "Delivered to \(count) libre relay nodes. relay=\(relay ? "on" : "off") torOnly=\(torOnly ? "on" : "off")\(protocolStatusSuffix)"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private var normalizedTxHex: String {
        txHex.components(separatedBy: .whitespacesAndNewlines).joined()
    }

    private var protocolStatusSuffix: String {
        guard !protocolPrefix.isEmpty || !protocolVersion.isEmpty else {
            return ""
        }

        let prefix = protocolPrefix.isEmpty ? "custom_protocol" : protocolPrefix
        let version = protocolVersion.isEmpty ? "0.0.1" : protocolVersion
        return " protocol=\(composeProtocolID(prefix: prefix, version: version))"
    }
}

#Preview {
    ContentView()
}

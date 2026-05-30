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
    @FocusState private var isTxHexFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            let panelWidth = proxy.size.width * 0.8 //input box width
            let panelHeight = proxy.size.height * 0.8 //input box height
            let paneGap = proxy.safeAreaInsets.top

            ZStack(alignment: .center) {
                Image(torOnly ? "icon-tor" : "icon-tor-gray")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width,
                           height: proxy.size.height * 1.0,
                    alignment: .center)
                    .scaleEffect(1.1)
                    .offset(y: proxy.size.height * 0.00)
                    //.clipped()
                    //.ignoresSafeArea()

                VStack {
                    TextEditor(text: $txHex)
                        .frame(minHeight: 180, idealHeight: 220, maxHeight: .infinity)
                        .frame(maxWidth: .infinity)
                        .focused($isTxHexFocused)
                        .scrollContentBackground(.hidden)
                        .background(isTxHexFocused ? Color.black.opacity(0.18) : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isTxHexFocused ? Color.secondary : Color.clear)
                        )

                    Button {
                        torOnly.toggle()
                        setTorOnly(enabled: torOnly)
                    } label: {
                        Image("tor-browser-icon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 42, height: 42)
                            //.padding(8)
                            //.background(torOnly ? Color.purple.opacity(0.18) : Color.clear)
                            //.clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Tor only")
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        relay.toggle()
                    } label: {
                        Image("libp2p-color-symbol")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 42, height: 42)
                            //.padding(8)
                            //.background(relay ? Color.blue.opacity(0.18) : Color.clear)
                            //.clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Relay")
                    .frame(maxWidth: .infinity, alignment: .leading)

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
                .frame(width: panelWidth)
                .frame(height: panelHeight)
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.bottom, paneGap)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                isTxHexFocused = false
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

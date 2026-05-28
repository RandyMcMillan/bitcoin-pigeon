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
    @State private var statusMessage = "Paste a raw transaction hex, then blast it."
    @State private var isWorking = false

    var body: some View {
        return VStack {
            TextEditor(text: $txHex)
                .frame(minHeight: 180)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary))

            Toggle("Tor only", isOn: $torOnly)

            Button(isWorking ? "Blasting..." : "Blast transaction") {
                Task { await blastTransaction() }
            }
            .disabled(isWorking || normalizedTxHex.isEmpty)

            Text(statusMessage)
        }
        .padding()
    }

    @MainActor
    private func blastTransaction() async {
        isWorking = true
        defer { isWorking = false }

        do {
            let count = try await blastTransactionHex(txHex: normalizedTxHex, torOnly: torOnly)
            statusMessage = torOnly
                ? "Delivered to \(count) Tor-only libre relay nodes."
                : "Delivered to \(count) libre relay nodes."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private var normalizedTxHex: String {
        txHex.components(separatedBy: .whitespacesAndNewlines).joined()
    }
}

#Preview {
    ContentView()
}

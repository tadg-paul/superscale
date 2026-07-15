// ABOUTME: Presents app-managed generation sessions for recovery, audit, and reuse.
// ABOUTME: Keeps the MVP history surface focused on files, metadata, and core actions.

import AppKit
import SuperscaleUXCore
import SwiftUI

struct HistoryView: View {
    let store: GenerationSessionStore
    let onOpenInGenerate: (GenerationSessionRecord) -> Void
    let onSendToUpscale: (URL) -> Void

    @State private var filter: HistoryFilter = .all
    @State private var sessions: [GenerationSessionRecord] = []
    @State private var selectedID: UUID?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Picker("History filter", selection: $filter) {
                ForEach(HistoryFilter.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("historyFilter")
            .padding(14)

            HStack(spacing: 0) {
                List(filteredSessions, selection: $selectedID) { session in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.prompt.isEmpty ? "Untitled session" : session.prompt)
                            .lineLimit(1)
                        Text("\(session.status.rawValue.capitalized) · \(session.timestamp.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(session.id)
                }
                .frame(minWidth: 260)
                .accessibilityIdentifier("historySessionList")

                Divider()

                sessionDetail
                    .frame(minWidth: 360)
            }
        }
        .onAppear { DispatchQueue.main.async { reload() } }
        .onChange(of: filter) { _, _ in selectFirstIfNeeded() }
        .alert("History Error", isPresented: showError) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var sessionDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let selectedSession {
                if let url = selectedSession.generatedAssetURL,
                   let image = NSImage(contentsOf: url) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView("No image for this session", systemImage: "photo")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Text(selectedSession.prompt).font(.headline)
                Text(selectedSession.modelID).font(.caption).foregroundStyle(.secondary)
                if let diagnostic = selectedSession.safeDiagnostic {
                    Text(diagnostic).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                ContentUnavailableView("No history selected", systemImage: "clock.arrow.circlepath")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack {
                Button("Open in Generate") {
                    if let selectedSession { onOpenInGenerate(selectedSession) }
                }
                .disabled(selectedSession == nil)
                .accessibilityIdentifier("historyOpenInGenerate")
                Button("Send to Upscale") {
                    if let url = selectedSession?.generatedAssetURL { onSendToUpscale(url) }
                }
                .disabled(selectedSession?.generatedAssetURL == nil)
                .accessibilityIdentifier("historySendToUpscale")
                Button("Save As...") { saveSelected() }
                    .disabled(selectedSession?.generatedAssetURL == nil)
                    .accessibilityIdentifier("historySaveAs")
                Button("Reveal") { revealSelected() }
                    .disabled(selectedSession?.generatedAssetURL == nil)
                    .accessibilityIdentifier("historyReveal")
            }
        }
        .padding(16)
    }

    private var filteredSessions: [GenerationSessionRecord] {
        guard let status = filter.status else { return sessions }
        return sessions.filter { $0.status == status }
    }

    private var selectedSession: GenerationSessionRecord? {
        filteredSessions.first { $0.id == selectedID }
    }

    private func reload() {
        do {
            sessions = try store.sessions()
            selectFirstIfNeeded()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func selectFirstIfNeeded() {
        if !filteredSessions.contains(where: { $0.id == selectedID }) {
            selectedID = filteredSessions.first?.id
        }
    }

    private func saveSelected() {
        guard let source = selectedSession?.generatedAssetURL else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = source.lastPathComponent
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func revealSelected() {
        guard let url = selectedSession?.generatedAssetURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private var showError: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}

private enum HistoryFilter: String, CaseIterable, Identifiable {
    case all
    case generated
    case upscaled
    case failed
    case cancelled

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var status: GenerationSessionStatus? {
        self == .all ? nil : GenerationSessionStatus(rawValue: rawValue)
    }
}

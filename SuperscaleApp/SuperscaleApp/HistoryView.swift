// ABOUTME: Presents app-managed generation sessions for recovery, audit, and reuse.
// ABOUTME: Keeps the MVP history surface focused on files, metadata, and core actions.

import AppKit
import SuperscaleUXCore
import SwiftUI

struct HistoryView: View {
    let store: GenerationSessionStore
    let onOpenInGenerate: (GenerationSessionRecord) -> Void
    let onSendToUpscale: (URL, UUID) -> Void

    @State private var filter: HistoryFilter = .all
    @State private var sessions: [GenerationSessionRecord] = []
    @State private var selectedID: UUID?
    @State private var searchText = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("History").font(.title2).fontWeight(.semibold)
                    Text("Generated and locally upscaled sessions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                TextField("Search prompts or models", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                    .accessibilityIdentifier("historySearchField")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            HStack {
                Picker("History filter", selection: $filter) {
                    ForEach(HistoryFilter.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("historyFilter")
                Spacer()
                Text("\(filteredSessions.count) session\(filteredSessions.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)

            HStack(spacing: 0) {
                List(filteredSessions, selection: $selectedID) { session in
                    sessionRow(session)
                    .tag(session.id)
                }
                .frame(minWidth: 300, idealWidth: 340)
                .accessibilityIdentifier("historySessionList")

                Divider()

                sessionDetail
                    .frame(minWidth: 360)
            }
        }
        .onAppear { DispatchQueue.main.async { reload() } }
        .onChange(of: filter) { _, _ in selectFirstIfNeeded() }
        .onChange(of: searchText) { _, _ in selectFirstIfNeeded() }
        .alert("History Error", isPresented: showError) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func sessionRow(_ session: GenerationSessionRecord) -> some View {
        HStack(spacing: 10) {
            Group {
                if let url = session.preferredAssetURL, let image = NSImage(contentsOf: url) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                }
            }
            .frame(width: 52, height: 52)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 4) {
                Text(session.prompt.isEmpty ? "Untitled session" : session.prompt)
                    .fontWeight(.medium)
                    .lineLimit(2)
                HStack(spacing: 5) {
                    Image(systemName: statusIcon(session.status))
                    Text(session.status.rawValue.capitalized)
                    Text("·")
                    Text(session.timestamp.formatted(date: .abbreviated, time: .shortened))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let estimate = session.estimatedCost {
                    Text("Est. \(estimate.formatted(.currency(code: "USD")))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 3)
    }

    private var sessionDetail: some View {
        VStack(spacing: 0) {
            if let selectedSession {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let url = selectedSession.preferredAssetURL,
                           let image = NSImage(contentsOf: url) {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 420)
                        } else {
                            ContentUnavailableView("No image for this session", systemImage: "photo")
                                .frame(maxWidth: .infinity, minHeight: 240)
                        }

                        Text(selectedSession.prompt.isEmpty ? "Untitled session" : selectedSession.prompt)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .textSelection(.enabled)
                        metadataRow("Status", selectedSession.status.rawValue.capitalized)
                        metadataRow("Created", selectedSession.timestamp.formatted(date: .long, time: .standard))
                        metadataRow("Model", selectedSession.modelID)
                        metadataRow(
                            "Estimated cost",
                            selectedSession.estimatedCost?.formatted(.currency(code: "USD")) ?? "Unavailable"
                        )
                        metadataRow("References", "\(selectedSession.referencePaths.count)")
                        if !selectedSession.referencePaths.isEmpty {
                            ForEach(selectedSession.referencePaths, id: \.self) { path in
                                Text(path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        if let diagnostic = selectedSession.safeDiagnostic {
                            Divider()
                            Label("Diagnostic", systemImage: "exclamationmark.triangle")
                                .font(.headline)
                            Text(diagnostic)
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                        if let path = selectedSession.generatedAssetPath {
                            metadataRow("Generated asset", path)
                        }
                        if let path = selectedSession.upscaledAssetPath {
                            metadataRow("Upscaled asset", path)
                        }
                    }
                    .padding(16)
                }
            } else {
                ContentUnavailableView("No history selected", systemImage: "clock.arrow.circlepath")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()
            HStack {
                Button {
                    if let selectedSession { onOpenInGenerate(selectedSession) }
                } label: {
                    Label("Open in Generate", systemImage: "sparkles")
                }
                .disabled(selectedSession == nil)
                .accessibilityIdentifier("historyOpenInGenerate")
                Button {
                    if let session = selectedSession, let url = session.preferredAssetURL {
                        onSendToUpscale(url, session.id)
                    }
                } label: {
                    Label("Send to Upscale", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedSession?.preferredAssetURL == nil)
                .accessibilityIdentifier("historySendToUpscale")
                Button { saveSelected() } label: {
                    Label("Save As...", systemImage: "square.and.arrow.down")
                }
                    .disabled(selectedSession?.preferredAssetURL == nil)
                    .accessibilityIdentifier("historySaveAs")
                Button { revealSelected() } label: {
                    Label("Reveal", systemImage: "folder")
                }
                    .disabled(selectedSession?.preferredAssetURL == nil)
                    .accessibilityIdentifier("historyReveal")
                Spacer()
            }
            .padding(14)
        }
    }

    private var filteredSessions: [GenerationSessionRecord] {
        sessions.filter { session in
            let matchesStatus = filter.status == nil || session.status == filter.status
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = query.isEmpty
                || session.prompt.localizedCaseInsensitiveContains(query)
                || session.modelID.localizedCaseInsensitiveContains(query)
            return matchesStatus && matchesSearch
        }
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
        guard let source = selectedSession?.preferredAssetURL else { return }
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
        guard let url = selectedSession?.preferredAssetURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func metadataRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }

    private func statusIcon(_ status: GenerationSessionStatus) -> String {
        switch status {
        case .generated: return "sparkles"
        case .upscaled: return "arrow.up.left.and.arrow.down.right"
        case .failed: return "exclamationmark.triangle"
        case .cancelled: return "xmark.circle"
        }
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

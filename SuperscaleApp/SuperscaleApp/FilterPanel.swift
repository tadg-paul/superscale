// ABOUTME: The side panel listing the bundled filters by category with the editable prompt area.
// ABOUTME: Selecting is free and sends nothing; Apply sends the text as it stands.

import FalGenerationKit
import SuperscaleUXCore
import SwiftUI

/// The filter catalogue as a panel beside the canvas, not a workspace and not a sheet.
///
/// A sidebar rather than a sheet because browsing eighty-six filters is the primary activity and
/// the prompt area belongs next to the image it will change, which is the open question section
/// 3.9 left for a judgement against something running.
struct FilterPanel: View {
    @Binding var selection: FilterSelection
    let catalogueFailure: String?
    let isGenerationConfigured: Bool
    let hasWorkingImage: Bool
    let isApplying: Bool
    let onApply: () -> Void
    let onCancel: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            catalogue
            Divider()
            promptArea
        }
        .frame(minWidth: 260, idealWidth: 280, maxWidth: 340)
        .accessibilityIdentifier("filterPanel")
    }

    private var header: some View {
        HStack {
            Text("Filters").font(.headline)
            Spacer()
            Text("\(selection.filters.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("filterCount")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var catalogue: some View {
        if let catalogueFailure {
            // An empty list with no explanation reads as a broken application. AC85.9 fixes what
            // the application holds after a failed load; this is what the user is told.
            VStack(alignment: .leading, spacing: 8) {
                Label("Filters unavailable", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                Text(catalogueFailure)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityIdentifier("filterCatalogueFailure")
        } else {
            List {
                ForEach(categories, id: \.self) { category in
                    Section(category) {
                        ForEach(filters(in: category), id: \.id) { filter in
                            filterRow(filter)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .accessibilityIdentifier("filterCatalogue")
        }
    }

    private func filterRow(_ filter: PromptPack) -> some View {
        Button {
            selection.choose(filter.id)
        } label: {
            HStack {
                Text(filter.displayName)
                Spacer()
                if selection.selectedID == filter.id {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("filter-\(filter.id)")
    }

    private var promptArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prompt").font(.headline)

            TextEditor(text: $selection.text)
                .font(.body)
                .frame(minHeight: 110)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.35)))
                .accessibilityIdentifier("generationPromptField")

            if !isGenerationConfigured {
                HStack(spacing: 6) {
                    Label("Add a FAL key to apply filters.", systemImage: "key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Settings", action: onOpenSettings)
                        .accessibilityIdentifier("openGenerationSettings")
                }
            }

            HStack {
                Text(WorkspaceModel.filterCostUSD.formatted(.currency(code: "USD")))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("filterCost")
                Spacer()
                if isApplying {
                    Button("Cancel", action: onCancel)
                        .accessibilityIdentifier("cancelApplyButton")
                }
                Button("Apply", action: onApply)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canApply)
                    .accessibilityIdentifier("applyFilterButton")
            }
        }
        .padding(12)
    }

    private var canApply: Bool {
        selection.canApply && hasWorkingImage && isGenerationConfigured && !isApplying
    }

    private var categories: [String] {
        var seen = Set<String>()
        return selection.filters.compactMap { filter in
            seen.insert(filter.category).inserted ? filter.category : nil
        }
        .sorted()
    }

    private func filters(in category: String) -> [PromptPack] {
        selection.filters
            .filter { $0.category == category }
            .sorted { $0.displayName < $1.displayName }
    }
}

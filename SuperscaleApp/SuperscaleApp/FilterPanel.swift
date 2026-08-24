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
    let canLock: Bool
    let onApply: () -> Void
    let onCancel: () -> Void
    let onLock: () -> Void

    @State private var activeCategory: String?
    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            catalogue
            Divider()
            promptArea
        }
        .frame(minWidth: 260, idealWidth: 280, maxWidth: 340)
        // A container, not an element: the panel's identifier must not absorb the catalogue, the
        // prompt area and the Apply button. AC73.6 states the rule this follows.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("filterPanel")
    }

    private var header: some View {
        HStack {
            Text("Filters").font(.headline)
            Spacer()
            Text("\(visibleFilters.count)")
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
            VStack(spacing: 0) {
                searchField
                categoryChips
                Divider()
                List {
                    ForEach(visibleFilters, id: \.id) { filter in
                        filterRow(filter)
                    }
                }
                .listStyle(.inset)
                .accessibilityIdentifier("filterCatalogue")
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.caption)
            TextField("Search filters", text: $search)
                .textFieldStyle(.plain)
                .accessibilityIdentifier("filterSearchField")
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("clearFilterSearch")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Category chips: one click narrows, the same click again widens.
    ///
    /// A filter bar rather than a drill-down. Narrowing costs one click, clearing costs one
    /// click, and search cuts across categories, so nothing is hidden behind navigation.
    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(title: "All", isOn: activeCategory == nil, identifier: "category-all") {
                    activeCategory = nil
                }
                ForEach(categories, id: \.self) { category in
                    chip(
                        title: category,
                        isOn: activeCategory == category,
                        identifier: "category-\(category.lowercased())"
                    ) {
                        activeCategory = activeCategory == category ? nil : category
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    private func chip(
        title: String,
        isOn: Bool,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(isOn ? Color.accentColor.opacity(0.85) : Color.secondary.opacity(0.15))
                )
                .foregroundStyle(isOn ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    /// What the list shows: the active category if one is chosen, narrowed further by the search
    /// text, which matches a filter's name or its category.
    private var visibleFilters: [PromptPack] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return selection.filters
            .filter { activeCategory == nil || $0.category == activeCategory }
            .filter {
                query.isEmpty
                    || $0.displayName.localizedCaseInsensitiveContains(query)
                    || $0.category.localizedCaseInsensitiveContains(query)
            }
            .sorted { ($0.category, $0.displayName) < ($1.category, $1.displayName) }
    }

    private func filterRow(_ filter: PromptPack) -> some View {
        Button {
            selection.choose(filter.id)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(filter.displayName)
                    // Kept visible even when a category is active, so a search result across
                    // categories still says where each filter came from.
                    Text(filter.category)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
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
                    // `SettingsLink` opens the Settings scene through the supported API. Reaching
                    // it by `NSApp.sendAction(Selector(("showSettingsWindow:")))` works but is a
                    // string naming a method the platform owns, which fails at runtime rather
                    // than at compile time when it changes.
                    SettingsLink {
                        Text("Settings")
                    }
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

            // Lock is the only action that moves the base, which is how filters stack
            // deliberately: noir *then* woodblock, rather than woodblock instead of noir. It
            // promotes the candidate at its own resolution, never the upscaled rendering of it.
            Button {
                onLock()
            } label: {
                Label("Lock", systemImage: "lock")
                    .frame(maxWidth: .infinity)
            }
            .disabled(!canLock)
            .help("Keep this result and build the next filter on it")
            .accessibilityIdentifier("lockButton")
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

}

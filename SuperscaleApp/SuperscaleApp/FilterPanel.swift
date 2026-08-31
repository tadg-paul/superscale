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
    /// Whether the search field has the keyboard, so entering it can widen the search (#141).
    @FocusState private var searchIsFocused: Bool

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
                .focused($searchIsFocused)
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
        // **Entering the search field widens the search to everything (#141, his third raising).**
        //
        // With a chip active, `visibleFilters` ands the two narrowings, so searching only ever
        // reached that chip's filters — with Lighting chosen, 4 of 108, and no sign of why a search
        // for anything else came back empty.
        //
        // On **focus**, not on the first keystroke: he wrote *"clicking in the search box"*, and
        // clearing on a keystroke would leave one keystroke's worth of results filtered by a chip
        // that is about to disappear.
        //
        // The chip is **cleared**, not ignored. Leaving it lit while it no longer applied would be
        // a worse interface than the defect: a control that says it is doing something it is not.
        // The visible change is also the thing that tells him the search now covers all 108.
        .onChange(of: searchIsFocused) { _, isFocused in
            if isFocused { activeCategory = nil }
        }
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
        // **Whether a chip is narrowing was expressed as colour and nothing else**, so it reached
        // neither VoiceOver nor a test — the same gap #95's credential badge had, and #109's, and
        // the reason AC141.3 could not be asserted at all before this line.
        //
        // It matters here beyond accessibility: the cheap implementation of #141 is to make the
        // search ignore the chip while leaving it lit, and the only way to catch that is to be able
        // to ask the chip what it thinks it is doing.
        .accessibilityValue(isOn ? "narrowing" : "not narrowing")
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
                // The mark claims the box holds *this filter's wording*, so it goes the moment the
                // wording is edited and returns if the original is typed back. Read from
                // `selectedID` alone it survived any amount of editing and went on naming a filter
                // whose words were no longer there (#129).
                if selection.selectedID == filter.id, selection.isShowingChosenFilterWording {
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
        // **`hasWorkingImage` is no longer required (#148).** On an empty canvas, Apply sends the
        // prompt with no reference and the provider generates from the words alone — which is what
        // the author asked for and, as he predicted, needed no new surface: the prompt area and the
        // button were already here.
        //
        // What is still required is a prompt and a configured key, so Apply does not offer itself
        // with nothing to say or nowhere to send it.
        selection.canApply && isGenerationConfigured && !isApplying
    }

    private var categories: [String] {
        var seen = Set<String>()
        return selection.filters.compactMap { filter in
            seen.insert(filter.category).inserted ? filter.category : nil
        }
        .sorted()
    }

}

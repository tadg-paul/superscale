// ABOUTME: Defines app-wide workspace modes and navigation state for the GUI.
// ABOUTME: Keeps mode orchestration independently testable from SwiftUI views.

import Combine

public enum AppMode: String, CaseIterable, Identifiable, Sendable {
    case upscale = "Upscale"
    case generate = "Generate"
    case history = "History"
    case settings = "Settings"

    public var id: Self { self }
}

@MainActor
public final class AppNavigation: ObservableObject {
    @Published public private(set) var selectedMode: AppMode

    public init(selectedMode: AppMode = .upscale) {
        self.selectedMode = selectedMode
    }

    public func select(_ mode: AppMode) {
        selectedMode = mode
    }
}

// ABOUTME: SwiftUI app entry point for Superscale GUI.
// ABOUTME: Configures the main window and menu commands.

import SwiftUI
import SuperscaleKit
import SuperscaleUXCore

@main
struct SuperscaleApp: App {
    @StateObject private var viewModel = UpscaleViewModel()
    @StateObject private var settingsState: GenerationSettingsState

    init() {
        let catalogue: PromptPackCatalogue
        let startupError: String?
        do {
            catalogue = try PromptPackCatalogue.bundled()
            startupError = nil
        } catch {
            catalogue = PromptPackCatalogue(packs: [])
            startupError = error.localizedDescription
        }
        _settingsState = StateObject(
            wrappedValue: GenerationSettingsState(
                credentials: GenerationCredentialService(storage: KeychainCredentialStorage()),
                preferencesStore: GenerationPreferencesStore(),
                promptPackCatalogue: catalogue,
                startupError: startupError
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            MainView(viewModel: viewModel, settingsState: settingsState)
                .frame(minWidth: 780, minHeight: 500)
        }
        .commands {
            CommandGroup(replacing: .saveItem) {
                Button("Save As…") {
                    viewModel.saveAs()
                }
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(viewModel.result == nil)
            }
        }
    }
}

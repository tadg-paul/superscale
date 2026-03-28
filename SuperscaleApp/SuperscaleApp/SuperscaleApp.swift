// ABOUTME: SwiftUI app entry point for Superscale GUI.
// ABOUTME: Configures the main window and menu commands.

import SwiftUI
import SuperscaleKit

@main
struct SuperscaleApp: App {
    @StateObject private var viewModel = UpscaleViewModel()

    var body: some Scene {
        WindowGroup {
            MainView(viewModel: viewModel)
                .frame(minWidth: 600, minHeight: 500)
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

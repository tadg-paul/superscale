// ABOUTME: Model selection picker for the toolbar.
// ABOUTME: Lists all models from ModelRegistry plus an auto-detect option.

import SwiftUI

struct ModelPicker: View {
    @Binding var selectedModelName: String
    let options: [UpscaleViewModel.ModelOption]

    var body: some View {
        Picker("Model", selection: $selectedModelName) {
            ForEach(options) { option in
                Text(option.displayName).tag(option.id)
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: 280)
    }
}

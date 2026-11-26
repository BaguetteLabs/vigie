import SwiftUI
import VigieUI

/// `[appearance] theme` as a picker of the built-in and custom themes (Story 18.2).
struct ThemePickerRow: View {
    let controller: SettingsController
    let model: SettingRowModel
    @State private var selection = ThemeLibrary.defaultVariantID

    var body: some View {
        Picker(selection: Binding(get: { selection }, set: { apply($0) })) {
            ForEach((controller.theme?.library.choices(including: selection) ?? [])) { choice in
                Text(verbatim: choice.name).tag(choice.id)
            }
        } label: {
            Text(model.label)
        }
        .onAppear { selection = currentID }
    }

    private var currentID: String {
        if case .string(let id) = model.binding.get() { return id }
        return ThemeLibrary.defaultVariantID
    }

    private func apply(_ id: String) {
        selection = id
        Task { try? await model.binding.set(.string(id)) }
    }
}

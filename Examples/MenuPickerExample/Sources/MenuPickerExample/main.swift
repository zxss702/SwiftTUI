import SwiftTUI

enum Theme: String, Hashable, CaseIterable {
    case light, dark, system
}

enum FontSize: String, Hashable, CaseIterable {
    case small, medium, large
}

struct MenuPickerExampleApp: View {
    @State private var theme: Theme = .system
    @State private var fontSize: FontSize = .medium
    @State private var inlineTheme: Theme = .light
    @State private var radioTheme: Theme = .dark
    @State private var segmentedSize: FontSize = .medium
    @State private var status = "Ready"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                header
                menuSection
                menuPickerSection
                inlineSection
                footer
            }
            .padding(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Menu / Picker").bold()
            Text("Status: \(status)").foregroundColor(.brightBlack)
            Divider()
        }
    }

    private var menuSection: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Menu").bold()
            Menu("Actions") {
                Button("Say Hello") { status = "Hello!" }
                Button("Say Bye") { status = "Bye!" }
                Divider()
                Button("Reset Status") { status = "Ready" }
            }
            Divider()
        }
    }

    private var menuPickerSection: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Picker .menu / .automatic").bold()
            Picker("Theme", selection: $theme) {
                Text("Light").tag(Theme.light)
                Text("Dark").tag(Theme.dark)
                Text("System").tag(Theme.system)
            }
            .pickerStyle(.menu)

            Picker("Font", selection: $fontSize) {
                Text("Small").tag(FontSize.small)
                Text("Medium").tag(FontSize.medium)
                Text("Large").tag(FontSize.large)
            }
            Divider()
        }
    }

    private var inlineSection: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Picker .inline").bold()
            Picker("Inline Theme", selection: $inlineTheme) {
                Text("Light").tag(Theme.light)
                Text("Dark").tag(Theme.dark)
                Text("System").tag(Theme.system)
            }
            .pickerStyle(.inline)

            Divider()

            Text("Picker .radioGroup").bold()
            Picker("Radio Theme", selection: $radioTheme) {
                Text("Light").tag(Theme.light)
                Text("Dark").tag(Theme.dark)
                Text("System").tag(Theme.system)
            }
            .pickerStyle(.radioGroup)

            Divider()

            Text("Picker .segmented").bold()
            Picker("Size", selection: $segmentedSize) {
                Text("S").tag(FontSize.small)
                Text("M").tag(FontSize.medium)
                Text("L").tag(FontSize.large)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 1) {
            Divider()
            Text("Esc or click outside to dismiss · Ctrl+C quit")
                .foregroundColor(.brightBlack)
        }
    }
}

try await Application(rootView: MenuPickerExampleApp()).start()

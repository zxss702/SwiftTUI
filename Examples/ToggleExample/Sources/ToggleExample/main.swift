import SwiftTUI

struct ToggleExampleApp: View {
    @State private var automaticOn = true
    @State private var checkboxOn = false
    @State private var switchOn = true
    @State private var buttonOn = false
    @State private var hiddenOn = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                header
                automaticSection
                checkboxSection
                switchSection
                buttonSection
                labelsHiddenSection
                footer
            }
            .padding(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Toggle").bold()
            Text("Space / Enter / click to flip").foregroundColor(.brightBlack)
            Divider()
        }
    }

    private var automaticSection: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("ToggleStyle.automatic").bold()
            Toggle("Notifications", isOn: $automaticOn)
            Divider()
        }
    }

    private var checkboxSection: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("ToggleStyle.checkbox").bold()
            Toggle("Show sidebar", isOn: $checkboxOn)
                .toggleStyle(.checkbox)
            Divider()
        }
    }

    private var switchSection: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("ToggleStyle.switch").bold()
            Toggle("Dark mode", isOn: $switchOn)
                .toggleStyle(.switch)
            Divider()
        }
    }

    private var buttonSection: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("ToggleStyle.button").bold()
            Toggle("Bold", isOn: $buttonOn)
                .toggleStyle(.button)
            Divider()
        }
    }

    private var labelsHiddenSection: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("labelsHidden").bold()
            Toggle("Wi‑Fi", isOn: $hiddenOn)
                .toggleStyle(.checkbox)
                .labelsHidden()
            Divider()
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Ctrl+C quit").foregroundColor(.brightBlack)
        }
    }
}

try await Application(rootView: ToggleExampleApp()).start()

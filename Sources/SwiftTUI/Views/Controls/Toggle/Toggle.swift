import Foundation

// MARK: - Toggle

/// TUI 版 Toggle。样式由 `.toggleStyle` 决定；可用 `.labelsHidden()` 隐藏标签。
@MainActor public struct Toggle<Label: View>: View {
    @Binding var isOn: Bool
    let label: Label

    @Environment(\.toggleStyleKind) private var styleKind
    @Environment(\.labelsHidden) private var labelsHidden
    @Environment(\.foregroundColor) private var foregroundColor

    public init(isOn: Binding<Bool>, @ViewBuilder label: () -> Label) {
        self._isOn = isOn
        self.label = label()
    }

    public var body: some View {
        Button {
            isOn.toggle()
        } label: {
            switch resolvedKind {
            case .checkbox, .automatic:
                checkboxBody
            case .switch:
                switchBody
            case .button:
                buttonBody
            }
        }
    }

    /// macOS 上 automatic 解析为 checkbox
    private var resolvedKind: ToggleStyleKind {
        styleKind == .automatic ? .checkbox : styleKind
    }

    // MARK: - Styles

    /// on: ◼︎ (U+25FC U+FE0E) / off: ◻︎ (U+25FB U+FE0E)
    private var checkboxBody: some View {
        HStack(spacing: 1) {
            Text(isOn ? "\u{25FC}\u{FE0E}" : "\u{25FB}\u{FE0E}")
            if !labelsHidden {
                label
            }
        }
    }

    /// 占满可用宽度：左 label，右开关
    private var switchBody: some View {
        HStack(spacing: 1) {
            if !labelsHidden {
                label
            }
            Spacer()
            Text(isOn ? "──●" : "○──")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var buttonBody: some View {
        if labelsHidden {
            chrome(Text(isOn ? "On" : "Off"))
        } else {
            chrome(label)
        }
    }

    @ViewBuilder
    private func chrome<V: View>(_ content: V) -> some View {
        if isOn {
            content
                .foregroundColor(selectedForeground)
                .background(selectedBackground)
        } else {
            content
        }
    }

    private var selectedBackground: Color {
        foregroundColor == .default ? .black : foregroundColor
    }

    private var selectedForeground: Color {
        foregroundColor == .default ? .white : .black
    }
}

extension Toggle where Label == Text {
    public init(_ title: String, isOn: Binding<Bool>) {
        self.init(isOn: isOn) { Text(title) }
    }
}

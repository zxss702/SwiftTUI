import Foundation

// MARK: - Menu

/// TUI 版 Menu：悬浮在 Application 最上层，不挤占原布局。
@MainActor public struct Menu<Label: View, Content: View>: View {
    let label: Label
    let content: Content

    @State private var isPresented = false
    @Environment(PopupPresenter.self) private var presenter
    @Environment(\.menuStyleKind) private var styleKind
    @Environment(\.menuIndicatorVisibility) private var indicatorVisibility

    public init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label
    ) {
        self.content = content()
        self.label = label()
    }

    public var body: some View {
        let trigger = PopupAnchorButton(label: triggerLabel, action: toggleMenu)
        switch styleKind {
        case .borderedButton, .button:
            trigger.border()
        case .automatic, .borderlessButton:
            trigger
        }
    }

    private var triggerLabel: some View {
        HStack(spacing: 0) {
            label
            if showsIndicator {
                Text(" ▾")
            }
        }
    }

    private var showsIndicator: Bool {
        switch indicatorVisibility {
        case .hidden: return false
        case .visible, .automatic: return true
        }
    }

    private func toggleMenu(anchor: Rect) {
        if isPresented {
            presenter.dismiss()
            isPresented = false
        } else {
            isPresented = true
            presenter.present(anchor: anchor, onDismiss: { isPresented = false }) {
                content
            }
        }
    }
}

extension Menu where Label == Text {
    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) {
        self.init(content: content, label: { Text(String(title)) })
    }
}

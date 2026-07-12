import Foundation

// MARK: - Picker

/// TUI 版 Picker。选项通过子视图 `.tag(_:)` 关联；样式由 `.pickerStyle` 决定。
@MainActor public struct Picker<Label: View, SelectionValue: Hashable, Content: View>: View {
    @Binding var selection: SelectionValue
    let label: Label
    let content: Content

    @State private var isPresented = false
    @Environment(PopupPresenter.self) private var presenter
    @Environment(\.pickerStyleKind) private var styleKind
    @Environment(\.labelsHidden) private var labelsHidden
    @Environment(\.horizontalRadioGroupLayout) private var horizontalRadio

    public init(
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label
    ) {
        self._selection = selection
        self.content = content()
        self.label = label()
    }

    public var body: some View {
        switch styleKind {
        case .automatic, .menu:
            menuStyleBody
        case .inline:
            inlineBody(chrome: .checkmark)
        case .radioGroup:
            inlineBody(chrome: .radio)
        case .segmented:
            segmentedBody
        }
    }

    // MARK: - Menu / automatic（悬浮层）

    private var menuStyleBody: some View {
        PopupAnchorButton(
            label: HStack(spacing: 0) {
                if !labelsHidden {
                    label
                    Text(": ")
                }
                Text("\(selection)")
                Text(" ▾")
            },
            action: toggleMenu
        )
    }

    private func toggleMenu(anchor: Rect, source: Node) {
        if isPresented {
            presenter.dismiss()
            isPresented = false
            return
        }
        isPresented = true
        let binding = $selection
        presenter.present(
            anchor: anchor,
            environmentSource: source,
            onDismiss: { isPresented = false }
        ) {
            SelectAndDismissContent(
                content: content,
                selection: binding,
                dismiss: { presenter.dismiss() }
            )
        }
    }

    // MARK: - Inline / radioGroup

    @ViewBuilder
    private func inlineBody(chrome: PickerOptionChrome) -> some View {
        let options = content
            .environment(\.pickerSelectAction, PickerSelectAction { tag in
                if let value = tag.base as? SelectionValue {
                    selection = value
                }
            })
            .environment(\.pickerSelectedTag, AnyHashable(selection))
            .environment(\.pickerOptionChrome, chrome)

        VStack(alignment: .leading, spacing: 0) {
            if !labelsHidden {
                label.bold()
            }
            if chrome == .radio && horizontalRadio {
                HStack(spacing: 1) { options }
            } else {
                options
            }
        }
    }

    // MARK: - Segmented

    private var segmentedBody: some View {
        let options = content
            .environment(\.pickerSelectAction, PickerSelectAction { tag in
                if let value = tag.base as? SelectionValue {
                    selection = value
                }
            })
            .environment(\.pickerSelectedTag, AnyHashable(selection))
            .environment(\.pickerOptionChrome, .segmented)

        return VStack(alignment: .leading, spacing: 0) {
            if !labelsHidden {
                label
            }
            HStack(spacing: 1) {
                options
            }
        }
    }
}

extension Picker where Label == Text {
    public init<S: StringProtocol>(
        _ title: S,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content
    ) {
        self.init(selection: selection, content: content, label: { Text(String(title)) })
    }
}

// MARK: - Select + dismiss helper

@MainActor
private struct SelectAndDismissContent<Content: View, SelectionValue: Hashable>: View {
    let content: Content
    @Binding var selection: SelectionValue
    let dismiss: () -> Void

    var body: some View {
        content
            .environment(\.pickerSelectAction, PickerSelectAction { tag in
                if let value = tag.base as? SelectionValue {
                    selection = value
                }
                dismiss()
            })
            .environment(\.pickerSelectedTag, AnyHashable(selection))
            .environment(\.pickerOptionChrome, .plain)
    }
}

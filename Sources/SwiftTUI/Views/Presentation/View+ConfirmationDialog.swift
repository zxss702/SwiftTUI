import Foundation

// MARK: - confirmationDialog

public extension View {
    func confirmationDialog<A: View>(
        _ title: String,
        isPresented: Binding<Bool>,
        titleVisibility: Visibility = .automatic,
        @ViewBuilder actions: @escaping () -> A
    ) -> some View {
        confirmationDialog(title, isPresented: isPresented, titleVisibility: titleVisibility, actions: actions, message: { EmptyView() })
    }

    func confirmationDialog<A: View, M: View>(
        _ title: String,
        isPresented: Binding<Bool>,
        titleVisibility: Visibility = .automatic,
        @ViewBuilder actions: @escaping () -> A,
        @ViewBuilder message: @escaping () -> M
    ) -> some View {
        PresentationBindingModifier(
            kind: .alert,
            isPresented: isPresented,
            onDismiss: nil,
            presented: {
                ConfirmationDialogContent(
                    title: title,
                    titleVisibility: titleVisibility,
                    message: message(),
                    actions: actions()
                )
            },
            content: self
        )
    }
}

@MainActor
struct ConfirmationDialogContent<Message: View, Actions: View>: View {
    let title: String
    let titleVisibility: Visibility
    let message: Message
    let actions: Actions

    var body: some View {
        // 与 alert 共用横排等宽按钮布局（确定 | 取消）
        AlertContent(
            title: titleVisibility == .hidden ? " " : title,
            message: message,
            actions: actions
        )
        .environment(\.buttonDismissesPresentation, true)
    }
}

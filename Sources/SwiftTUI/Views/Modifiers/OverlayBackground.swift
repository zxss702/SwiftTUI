import Foundation

public extension View {
    func overlay<Overlay: View>(
        alignment: Alignment = .center,
        @ViewBuilder content: () -> Overlay
    ) -> some View {
        ZStack(alignment: alignment) {
            self
            content()
        }
    }

    func background<Background: View>(
        alignment: Alignment = .center,
        @ViewBuilder content: () -> Background
    ) -> some View {
        ZStack(alignment: alignment) {
            content()
            self
        }
    }
}

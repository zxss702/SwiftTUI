import Testing
@testable import SwiftTUI

@Suite(.serialized)
@MainActor
struct ScrollViewReaderTests {

    @Test func scrollToMaterializedIdentityAlignsTop() async throws {
        struct Root: View {
            var body: some View {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(0 ..< 30, id: \.self) { i in
                                Text("row-\(i)").id(i)
                            }
                        }
                    }
                    .frame(height: 5)
                    .onAppear { proxy.scrollTo(20, anchor: .top) }
                }
            }
        }

        let app = Application(rootView: Root())
        try await app.testing_prepare(size: Size(width: 40, height: 12))

        let scroll = try #require(findScroll(in: app.testing_rootElement))
        let target = try #require(findText(in: app.testing_rootElement, equalTo: "row-20"))
        let vp = scroll.absoluteFrame
        let frame = target.absoluteFrame
        #expect(vp.contains(frame.position), "target should be in viewport; vp=\(vp) frame=\(frame)")
        #expect(
            frame.position.line == vp.position.line,
            "anchor .top should pin target top to viewport top; line=\(frame.position.line) vp=\(vp.position.line)"
        )
    }

    @Test func scrollToLazyOffscreenIdentity() async throws {
        struct Root: View {
            var body: some View {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0, estimatedItemHeight: 1) {
                            ForEach(0 ..< 50, id: \.self) { i in
                                Text("lazy-\(i)").id(i)
                            }
                        }
                    }
                    .frame(height: 6)
                    .onAppear { proxy.scrollTo(40, anchor: .top) }
                }
            }
        }

        let app = Application(rootView: Root())
        try await app.testing_prepare(size: Size(width: 40, height: 12))

        let scroll = try #require(findScroll(in: app.testing_rootElement))
        let target = try #require(findText(in: app.testing_rootElement, equalTo: "lazy-40"))
        let vp = scroll.absoluteFrame
        #expect(
            vp.intersects(target.absoluteFrame),
            "lazy off-screen id must materialize into viewport; vp=\(vp) frame=\(target.absoluteFrame)"
        )
    }

    private func findScroll(in control: Element?) -> Element? {
        guard let control else { return nil }
        if String(describing: type(of: control)).contains("ScrollElement") { return control }
        for child in control.children {
            if let found = findScroll(in: child) { return found }
        }
        return nil
    }
}

@MainActor
private func findText(in control: Element?, equalTo target: String) -> Element? {
    guard let control else { return nil }
    if ownTextLabel(in: control) == target { return control }
    for child in control.children {
        if let found = findText(in: child, equalTo: target) { return found }
    }
    return nil
}

@MainActor
private func ownTextLabel(in control: Element) -> String? {
    let mirror = Mirror(reflecting: control)
    for child in mirror.children {
        if child.label == "text", let text = child.value as? String {
            return text
        }
    }
    return nil
}

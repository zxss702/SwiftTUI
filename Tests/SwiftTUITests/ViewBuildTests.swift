import XCTest
@testable import SwiftTUI

@MainActor final class ViewBuildTests: XCTestCase {
    func test_VStack_TupleView2() throws {
        struct MyView: View {
            var body: some View {
                VStack {
                    Text("One")
                    Text("Two")
                }
            }
        }

        let control = try buildView(MyView())

        XCTAssertEqual(control.treeDescription, """
            → VStackElement
              → TextElement
              → TextElement
            """)
    }

    func test_conditional_VStack() throws {
        struct MyView: View {
            @State var value = true

            var body: some View {
                if value {
                    VStack {
                        Text("One")
                    }
                }
            }
        }

        let control = try buildView(MyView())

        XCTAssertEqual(control.treeDescription, """
            → VStackElement
              → TextElement
            """)
    }

    func test_GeometryReader_switchesBranchInSameLayoutPass() throws {
        struct MyView: View {
            var body: some View {
                GeometryReader { size in
                    if size.width >= 10 {
                        Text("big")
                    } else {
                        Text("small")
                    }
                }
            }
        }

        let node = Node(view: VStack(content: MyView()).view)
        node.build()
        let root = try XCTUnwrap(node.element)
        let geometryElement = try XCTUnwrap(root.children.first)

        geometryElement.layout(size: Size(width: 20, height: 10))
        let bigLeaf = deepestElement(geometryElement)

        geometryElement.layout(size: Size(width: 5, height: 10))
        let smallLeaf = deepestElement(geometryElement)

        geometryElement.layout(size: Size(width: 40, height: 10))
        let bigAgain = deepestElement(geometryElement)

        // Branch switches recreate the leaf control in the same layout pass.
        XCTAssertTrue(bigLeaf !== smallLeaf)
        XCTAssertTrue(smallLeaf !== bigAgain)
    }

    private func deepestElement(_ control: Element) -> Element {
        var current = control
        while let child = current.children.first {
            current = child
        }
        return current
    }

    private func buildView<V: View>(_ view: V) throws -> Element {
        let node = Node(view: VStack(content: view).view)
        node.build()
        return try XCTUnwrap(node.element?.children.first)
    }

}

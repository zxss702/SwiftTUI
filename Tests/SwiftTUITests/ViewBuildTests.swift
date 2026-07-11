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
            → VStackControl
              → TextControl
              → TextControl
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
            → VStackControl
              → TextControl
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
        let root = try XCTUnwrap(node.control)
        let geometryControl = try XCTUnwrap(root.children.first)

        geometryControl.layout(size: Size(width: 20, height: 10))
        let bigLeaf = deepestControl(geometryControl)

        geometryControl.layout(size: Size(width: 5, height: 10))
        let smallLeaf = deepestControl(geometryControl)

        geometryControl.layout(size: Size(width: 40, height: 10))
        let bigAgain = deepestControl(geometryControl)

        // Branch switches recreate the leaf control in the same layout pass.
        XCTAssertTrue(bigLeaf !== smallLeaf)
        XCTAssertTrue(smallLeaf !== bigAgain)
    }

    private func deepestControl(_ control: Control) -> Control {
        var current = control
        while let child = current.children.first {
            current = child
        }
        return current
    }

    private func buildView<V: View>(_ view: V) throws -> Control {
        let node = Node(view: VStack(content: view).view)
        node.build()
        return try XCTUnwrap(node.control?.children.first)
    }

}

import XCTest
@testable import SwiftTUI

final class LayoutTests: XCTestCase {
    @MainActor
    func testSpacerLayout() {
        let view = VStack {
            Text("Top")
            Spacer()
            Text("Bottom")
        }.padding().border().background(.blue)
        
        let node = Node(view: VStack(content: view).view)
        node.build()
        let control = node.element!
        
        // This is the VStackElement (root)
        // Let's test its size calculation for a fixed terminal size (80x24)
        let size = control.size(proposedSize: Size(width: 80, height: 24))
        XCTAssertEqual(size.height.intValue, 24)
        
        control.layout(size: size)
        
        let bgElement = control.children[0] // BackgroundElement
        let borderElement = bgElement.children[0]
        
        XCTAssertEqual(bgElement.layer.frame.size.height.intValue, 24)
        XCTAssertEqual(borderElement.layer.frame.size.height.intValue, 24)
    }

    @MainActor
    func testPressEnter() async throws {
        struct ToDoMock: Identifiable {
            let id = UUID()
            let text: String
        }
        struct ToDoListMock: View {
            @State var toDos: [ToDoMock] = [ToDoMock(text: "A"), ToDoMock(text: "B")]
            var body: some View {
                VStack(alignment: .leading) {
                    VStack(alignment: .leading) {
                        ForEach(toDos) { todo in
                            Text(todo.text)
                        }
                    }
                    HStack {
                        Text("Add")
                        TextField() { toDos.append(ToDoMock(text: $0)) }
                    }
                    Spacer()
                }
            }
        }
        let app = Application(rootView: ToDoListMock().padding().border().background(.blue))
        try await app.testing_prepare(size: Size(width: 80, height: 24))

        let bgElement = app.window.elements[0].children[0]
        let borderElement = bgElement.children[0]
        XCTAssertEqual(borderElement.layer.frame.size.height.intValue, 24)

        try await app.testing_turn(
            input: .key(KeyEvent(character: "\n", keycode: 0, modifiers: [], type: .press))
        )
        XCTAssertEqual(borderElement.layer.frame.size.height.intValue, 24)
    }
}

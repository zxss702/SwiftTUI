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
        let control = node.control!
        
        // This is the VStackControl (root)
        // Let's test its size calculation for a fixed terminal size (80x24)
        let size = control.size(proposedSize: Size(width: 80, height: 24))
        XCTAssertEqual(size.height.intValue, 24)
        
        control.layout(size: size)
        
        let bgControl = control.children[0] // BackgroundControl
        let borderControl = bgControl.children[0]
        
        XCTAssertEqual(bgControl.layer.frame.size.height.intValue, 24)
        XCTAssertEqual(borderControl.layer.frame.size.height.intValue, 24)
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
        app.updateWindowSize(size: Size(width: 80, height: 24))
        app.window.controls[0].layout(size: Size(width: 80, height: 24))
        
        let bgControl = app.window.controls[0].children[0]
        let borderControl = bgControl.children[0]
        
        XCTAssertEqual(borderControl.layer.frame.size.height.intValue, 24)
        
        // Find the text field and send \n
        app.handleKeyInput(KeyEvent(character: "\n", keycode: 0, modifiers: [], type: .press))
        
        // Flush updates
        try await app.update()
        
        XCTAssertEqual(borderControl.layer.frame.size.height.intValue, 24)
    }
}

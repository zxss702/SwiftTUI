import SwiftTUI
import Foundation

struct ToDoView: View {
    let toDo: ToDo
    let onDelete: ()  -> Void

    @State var deleting = false 

    var body: some View {
        HStack {
            if deleting {
                Text("[x]")
                Text(toDo.text).strikethrough()
            } else {
                Button("[ ]", action: delete)
                Text(toDo.text)
                    .foregroundColor(.white) 
            }
        }
    }

    private func delete() {
        deleting = true
        _ = Task {
            try? await Task.sleep(for: .milliseconds(500))
            onDelete()
        }
    }
}

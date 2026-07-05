import SwiftTUI
import Foundation
#if canImport(SwiftData)
import SwiftData
#else
import JsonData
#endif

@Model
final class TaskItem: @unchecked Sendable {
    @Attribute(.unique)
    var id: UUID
    var title: String
    var isCompleted: Bool
    var createdAt: Date

    init(title: String, isCompleted: Bool = false) {
        self.id = UUID()
        self.title = title
        self.isCompleted = isCompleted
        self.createdAt = Date()
    }
}

@MainActor
struct ContentView: View {
    @Environment(\.modelContext) var modelContext
    
    @SwiftTUI.Query(sort: [SortDescriptor(\TaskItem.createdAt)])
    var tasks: [TaskItem]

    var body: some View {
        VStack {
            Text("JsonData + SwiftTUI TODO List").bold()
            
            Button("Add Task") {
                let task = TaskItem(title: "Task \(tasks.count + 1)")
                modelContext?.insert(task)
            }
            .padding(.bottom, 1)
            
            ScrollView {
                LazyVStack {
                    ForEach(tasks, id: \.id) { task in
                        Button {
                            task.isCompleted.toggle()
                            try? modelContext?.save()
                        } label: {
                            HStack {
                                Text(task.isCompleted ? "[x]" : "[ ]")
                                Text(task.title)
                                Text("Toggle")
                                Spacer()
                            }
                        }
                    }
                }
            }
        }
        .padding()
    }
}

let schema = Schema([TaskItem.self])
let modelConfiguration = ModelConfiguration(schema: schema, url: URL(fileURLWithPath: "todo.db"))
do {
    let modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
    let app = Application(rootView: ContentView()).modelContainer(modelContainer)
    try await app.start()
} catch {
    print("Failed to initialize or run app: \(error)")
}

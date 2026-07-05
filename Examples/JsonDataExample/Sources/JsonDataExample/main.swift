import SwiftTUI
import Foundation
import JsonDataCore

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

// In SwiftTUI, Application needs to be initialized. We can use Application(rootView:).
// However, ModelContext needs to be passed in.

let schema = Schema([TaskItem.self])
let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
do {
    let modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
    let context = ModelContext(modelContainer)

    let app = Application(rootView: ContentView().environment(\.modelContext, context))
    try await app.start()
} catch {
    print("Failed to initialize or run app: \(error)")
}

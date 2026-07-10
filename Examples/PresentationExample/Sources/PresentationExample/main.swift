import SwiftTUI

struct Note: Identifiable, Hashable {
    let id: Int
    let title: String
}

struct PresentationExampleApp: View {
    @State private var showSheet = false
    @State private var showNestedSheet = false
    @State private var showPopover = false
    @State private var showNestedPopover = false
    @State private var showAlert = false
    @State private var sheetItem: Note? = nil
    @State private var status = "Ready"

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Presentation").bold()
            Text("Status: \(status)").foregroundColor(.brightBlack)
            Divider()

            Button("Open Sheet") { showSheet = true }
            Button("Open Sheet (item)") {
                sheetItem = Note(id: 1, title: "Item Sheet")
            }
            Button("Toggle Popover") { showPopover.toggle() }
                .popover(isPresented: $showPopover) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Popover").bold()
                        Text("圆角矩形面板")
                        Button("Nested Popover") { showNestedPopover = true }
                            .popover(isPresented: $showNestedPopover) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Nested Popover").bold()
                                    Text("叠在上一层 popover 上")
                                    Button("Close") { showNestedPopover = false }
                                }
                            }
                        Button("Close") { showPopover = false }
                    }
                }
            Button("Show Alert") { showAlert = true }

            Divider()
            Text("嵌套：sheet→sheet / popover→popover；Esc 只关顶层").foregroundColor(.brightBlack)
            Text("Ctrl+C quit").foregroundColor(.brightBlack)
        }
        .padding(1)
        .sheet(isPresented: $showSheet, onDismiss: {
            showNestedSheet = false
            status = "Sheet dismissed"
        }) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Sheet").bold()
                Text("居中模态面板")
                Button("Set status") { status = "From sheet" }
                Button("Open Nested Sheet") { showNestedSheet = true }
                Button("Close") { showSheet = false }
            }
            .sheet(isPresented: $showNestedSheet, onDismiss: { status = "Nested sheet dismissed" }) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Nested Sheet").bold()
                    Text("压在上一层 sheet 上")
                    Button("Close nested") { showNestedSheet = false }
                    Button("Close all") { showSheet = false }
                }
            }
        }
        .sheet(item: $sheetItem, onDismiss: { status = "Item sheet dismissed" }) { note in
            VStack(alignment: .leading, spacing: 1) {
                Text(note.title).bold()
                Text("id: \(note.id)")
                Button("Close") { sheetItem = nil }
            }
        }
        .alert("Confirm", isPresented: $showAlert) {
            Button("OK", role: nil) { status = "Alert OK" }
            Button("Cancel", role: .cancel) { status = "Alert cancelled" }
        } message: {
            Text("Use Esc or tap a button.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

try await Application(rootView: PresentationExampleApp()).start()

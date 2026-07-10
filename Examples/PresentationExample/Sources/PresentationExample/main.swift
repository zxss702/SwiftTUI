import SwiftTUI

struct Note: Identifiable, Hashable {
    let id: Int
    let title: String
}

struct PresentationExampleApp: View {
    @State private var showSheet = false
    @State private var showPopover = false
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
                        Button("Close") { showPopover = false }
                    }
                }
            Button("Show Alert") { showAlert = true }

            Divider()
            Text("Esc / click outside (menu&popover) / dim (sheet&alert)").foregroundColor(.brightBlack)
            Text("Ctrl+C quit").foregroundColor(.brightBlack)
        }
        .padding(1)
        .sheet(isPresented: $showSheet, onDismiss: { status = "Sheet dismissed" }) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Sheet").bold()
                Text("居中模态面板")
                Button("Set status") { status = "From sheet" }
                Button("Close") { showSheet = false }
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

import SwiftTUI
import Foundation
import Observation

@Observable
class AppState {
    var counter: Int = 0
    var text: String = "Hello"
}

@MainActor
struct ChildView: View {
    @Environment(AppState.self) var state

    var body: some View {
        VStack {
            Text("Count in Child: \(state.counter)")
                .foregroundColor(.cyan)
            
            Button("Increment from Child") {
                state.counter += 1
            }
        }
        .padding()
        .border()
    }
}

@MainActor
struct BindingChildView: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(alignment: .leading) {
            Text("Edit text using @Bindable:")
            // Note: SwiftTUI's TextField or TextEdit should take a Binding
            // Since we don't have the exact API on hand, we mock a button to change it
            Text("Current text: \(state.text)")
                .foregroundColor(.yellow)
            
            Button("Append '!'") {
                state.text += "!"
            }
        }
        .padding()
        .border()
    }
}

@MainActor
struct RootView: View {
    @State var state = AppState()
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .center) {
            Text("SwiftTUI Observation Demo")
                .bold()
                .padding()
            
            Text("Main Count: \(state.counter)")
            
            HStack {
                Button("Decrement") {
                    state.counter -= 1
                }
                
                Button("Increment") {
                    state.counter += 1
                }
            }
            .padding()
            
            ChildView()
            
            BindingChildView(state: state)
            
            Spacer()
            
            Button("Quit") {
                dismiss()
            }
        }
        .environment(state)
    }
}

@MainActor
func main() async {
    let app = await Application(rootView: RootView())
    try? await app.start()
}

Task {
    await main()
}

RunLoop.main.run()

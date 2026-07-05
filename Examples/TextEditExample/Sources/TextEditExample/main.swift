import SwiftTUI
import Foundation

struct ContentView: View {
    @State var text: String = "This is a multiline TextEdit.\nYou can type here, use arrow keys to navigate, and scroll with the mouse wheel.\nThe cursor will automatically stay within the visible bounds when you scroll!"
    
    var body: some View {
        VStack(alignment: .center) {
            Text("TextEdit Example")
                .foregroundColor(.cyan)
                .padding()
            
            TextEdit(text: $text)
                .border()
                .frame(width: 40, height: 10)
                .padding()
            
            Text("Characters: \(text.count)")
                .foregroundColor(.green)
        }
    }
}

try await Application(rootView: ContentView()).start()

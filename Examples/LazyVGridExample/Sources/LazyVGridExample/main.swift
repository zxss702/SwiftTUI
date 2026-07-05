import SwiftTUI
import Foundation

struct ContentView: View {
    var body: some View {
        VStack {
            Text("LazyVGrid Example")
                .foregroundColor(.cyan)
                .padding()
            
            let columns = [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ]
            
            ScrollView {
                LazyVGrid(columns: columns, spacing: 1, estimatedRowHeight: 3) {
                    ForEach(0..<1000, id: \.self) { index in
                        Text("Item \(index)")
                            .border()
                    }
                }
            }
        }
    }
}

try await Application(rootView: ContentView()).start()

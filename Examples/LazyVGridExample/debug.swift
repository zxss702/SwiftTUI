import Foundation
import SwiftTUI

struct ContentView: View {
    var body: some View {
        ScrollView {
            VStack {
                ForEach(0..<100, id: \.self) { i in
                    Text("Line \(i)")
                }
            }
        }
    }
}
try await Application(rootView: ContentView()).start()

import SwiftTUI

do {
    try await Application(rootView: ContentView()).start()
} catch {
    print(error)
}

print("abc")

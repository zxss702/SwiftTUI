import Foundation

var text = "Hello World"
var cursorIndex = text.index(text.startIndex, offsetBy: 5) // At space

let d1 = text.distance(from: text.startIndex, to: cursorIndex)
text.insert("中", at: cursorIndex)
cursorIndex = text.index(text.startIndex, offsetBy: d1 + 1)
print(text)
print("Cursor character:", text[cursorIndex])

let d2 = text.distance(from: text.startIndex, to: cursorIndex)
text.insert("\n", at: cursorIndex)
cursorIndex = text.index(text.startIndex, offsetBy: d2 + 1)
print(text)
print("Cursor character:", text[cursorIndex])

import XCTest
@testable import SwiftTUI

@MainActor
final class FocusStateTests: XCTestCase {
    enum Field: Hashable {
        case a, b
    }

    func test_setFirstResponder_updatesIsFirstResponder() throws {
        struct MyView: View {
            @State var text = ""

            var body: some View {
                TextField("x", text: $text)
                    .focused($focus)
            }

            @FocusState var focus: Bool
        }

        let app = Application(rootView: MyView())
        let field = try XCTUnwrap(findTextField(in: app.window.elements.first))

        app.window.setFirstResponder(nil)
        XCTAssertFalse(field.isFirstResponder)

        app.window.setFirstResponder(field)
        XCTAssertTrue(field.isFirstResponder)
        XCTAssertNotNil(field.focusRegistration)
    }

    func test_focusedEquals_switchesBetweenFields() throws {
        struct MyView: View {
            @FocusState var focused: Field?
            @State var a = ""
            @State var b = ""

            var body: some View {
                VStack {
                    TextField("a", text: $a)
                        .focused($focused, equals: .a)
                    TextField("b", text: $b)
                        .focused($focused, equals: .b)
                }
            }
        }

        let app = Application(rootView: MyView())
        let fields = collectTextFields(in: try XCTUnwrap(app.window.elements.first))
        XCTAssertEqual(fields.count, 2)

        app.window.setFirstResponder(fields[0])
        XCTAssertTrue(fields[0].isFirstResponder)
        XCTAssertFalse(fields[1].isFirstResponder)

        app.window.setFirstResponder(fields[1])
        XCTAssertTrue(fields[1].isFirstResponder)
        XCTAssertFalse(fields[0].isFirstResponder)
    }

    func test_focusableFalse_excludesFromFocus() throws {
        struct MyView: View {
            @State var text = ""

            var body: some View {
                TextField("x", text: $text)
                    .focusable(false)
            }
        }

        let app = Application(rootView: MyView())
        let field = try XCTUnwrap(findTextField(in: app.window.elements.first))
        XCTAssertFalse(field.canReceiveFocus)
        app.window.setFirstResponder(field)
        XCTAssertNil(app.window.firstResponder)
    }

    func test_focusSystemApply_focusesRegisteredElement() throws {
        struct MyView: View {
            @FocusState var focused: Bool
            @State var text = "hi"

            var body: some View {
                TextField("x", text: $text)
                    .focused($focused)
            }
        }

        let app = Application(rootView: MyView())
        let field = try XCTUnwrap(findTextField(in: app.window.elements.first))
        let reg = try XCTUnwrap(field.focusRegistration)

        app.window.setFirstResponder(nil)
        FocusSystem.apply(
            reference: reg.reference,
            value: true,
            unfocusedValue: false,
            window: app.window
        )
        XCTAssertTrue(field.isFirstResponder)
    }

    func test_resignNotifiesFocusRegistration() throws {
        struct MyView: View {
            @FocusState var focused: Bool
            @State var text = ""

            var body: some View {
                TextField("x", text: $text)
                    .focused($focused)
            }
        }

        let app = Application(rootView: MyView())
        let field = try XCTUnwrap(findTextField(in: app.window.elements.first))
        app.window.setFirstResponder(field)
        XCTAssertTrue(field.isFirstResponder)

        app.window.setFirstResponder(nil)
        XCTAssertFalse(field.isFirstResponder)
    }

    // MARK: - Helpers

    private func findTextField(in control: Element?) -> Element? {
        guard let control else { return nil }
        if String(describing: type(of: control)).contains("TextFieldElement") {
            return control
        }
        for child in control.children {
            if let found = findTextField(in: child) { return found }
        }
        return nil
    }

    private func collectTextFields(in control: Element) -> [Element] {
        var result: [Element] = []
        if String(describing: type(of: control)).contains("TextFieldElement") {
            result.append(control)
        }
        for child in control.children {
            result.append(contentsOf: collectTextFields(in: child))
        }
        return result
    }
}

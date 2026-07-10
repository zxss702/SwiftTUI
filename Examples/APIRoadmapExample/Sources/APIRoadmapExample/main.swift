import SwiftTUI
import Foundation

/// 演示 roadmap 中落地的 SwiftUI 风格 API。
struct APIRoadmapExampleApp: View {
    @State private var name = ""
    @State private var password = ""
    @State private var progress: Double = 0.35
    @State private var sliderValue: Double = 0.4
    @State private var stepperValue = 3
    @State private var disabled = false
    @State private var hiddenBadge = false
    @State private var hitTesting = true
    @State private var tapCount = 0
    @State private var dragDelta = "—"
    @State private var status = "Ready"
    @State private var showConfirm = false
    @State private var changeLog = ""
    @State private var taskTick = 0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    header
                    progressAndFields
                    inputsAndHitTest
                    overlayAndScroll(proxy: proxy)
                    gestureAndLayout
                    Text("Ctrl+C quit").foregroundColor(.brightBlack)
                }
                .padding(1)
                .disabled(disabled)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .confirmationDialog("确定删除？", isPresented: $showConfirm, titleVisibility: .visible) {
            Button(role: .destructive) { status = "已确认删除" }
            Button(role: .cancel) { status = "已取消" }
        } message: {
            Text("此操作无法撤销。")
        }
        .onChange(of: name) { old, new in
            changeLog = "name: \(old) → \(new)"
        }
        .task(id: taskTick) {
            try? await Task.sleep(nanoseconds: 800_000_000)
            await MainActor.run {
                if !Task.isCancelled {
                    status = "task #\(taskTick) finished"
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("API Roadmap").bold()
            Text("Status: \(status)").foregroundColor(.brightBlack)
            if !changeLog.isEmpty {
                Text(changeLog).foregroundColor(.cyan)
            }
            HStack {
                Button(disabled ? "启用界面" : "禁用界面") { disabled.toggle() }
                Button("运行 .task") { taskTick += 1 }
                Button("确认…") { showConfirm = true }
            }
            Text(".disabled / .onChange / .task / confirmationDialog")
                .foregroundColor(.brightBlack)
            Divider()
        }
    }

    private var progressAndFields: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("ProgressView").bold()
            ProgressView()
            ProgressView(value: progress, total: 1) {
                Text(String(format: "%.0f%%", progress * 100))
            }
            HStack {
                Button("-") { progress = max(0, progress - 0.1) }
                Button("+") { progress = min(1, progress + 0.1) }
            }
            Text("TextField / SecureField").bold()
            TextField("姓名", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit { status = "已提交: \(name)" }
            SecureField("密码", text: $password)
                .textFieldStyle(.roundedBorder)
            Text("name=\(name)  •=\(String(repeating: "•", count: password.count))")
                .foregroundColor(.brightBlack)
            Divider()
        }
    }

    private var inputsAndHitTest: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Slider / Stepper").bold()
            Slider(value: $sliderValue, in: 0...1) {
                Text(String(format: "%.2f", sliderValue))
            }
            Stepper("Count", value: $stepperValue, in: 0...10)
            Text("Hit testing").bold()
            HStack {
                Button(hitTesting ? "关闭点击 (false)" : "开启点击 (true)") {
                    hitTesting.toggle()
                }
                Text("taps: \(tapCount)")
            }
            Text("点我")
                .padding(1)
                .border()
                .onTapGesture { tapCount += 1 }
                .allowsHitTesting(hitTesting)
            Text(hitTesting ? "当前允许命中" : "当前穿透（点不到）")
                .foregroundColor(.brightBlack)
            Divider()
        }
    }

    private func overlayAndScroll(proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Overlay / Hidden").bold()
            Text("Base")
                .padding(1)
                .border()
                .overlay(alignment: .topTrailing) {
                    Text("[badge]")
                        .foregroundColor(.yellow)
                        .allowsHitTesting(false)
                        .hidden(hiddenBadge)
                }
            Button(hiddenBadge ? "Show badge" : "Hide badge") { hiddenBadge.toggle() }
            Text("ScrollViewReader").bold()
            HStack {
                Button("→ mid") { proxy.scrollTo("mid") }
                Button("→ end") { proxy.scrollTo("end") }
                Button("→ top") { proxy.scrollTo("top") }
            }
            Text("top").id("top").foregroundColor(.brightBlack)
            ForEach(1...12, id: \.self) { i in
                Text(i == 6 ? "row \(i) [mid]" : "row \(i)")
                    .id(i == 6 ? "mid" : "row-\(i)")
            }
            Text("end").id("end").foregroundColor(.brightBlack)
            Divider()
        }
    }

    private var gestureAndLayout: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("DragGesture").bold()
            Text("Drag here: \(dragDelta)")
                .padding(1)
                .frame(width: 36, height: 3)
                .border()
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragDelta = "(\(value.translation.width), \(value.translation.height))"
                        }
                        .onEnded { value in
                            status = "drag ended \(value.translation)"
                        }
                )
            Text("fixedSize / layoutPriority").bold()
            HStack(spacing: 1) {
                Text("flex")
                    .frame(maxWidth: .infinity)
                    .border()
                Text("fixed")
                    .fixedSize()
                    .border()
                Text("prio")
                    .layoutPriority(1)
                    .frame(maxWidth: .infinity)
                    .border()
            }
            .frame(width: 40)
            Divider()
        }
    }
}

try await Application(rootView: APIRoadmapExampleApp()).start()

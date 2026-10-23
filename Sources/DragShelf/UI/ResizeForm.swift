import AppKit
import SwiftUI

/// Resize ▸ Custom… (V2-05), Preview's Adjust Size: shown in the panel in place of the grid, like Recent. Not a
/// sheet or window: those would activate DragShelf. The panel turns key for typing; DragShelf stays inactive.
/// Esc (`ShelfPanel`) and Cancel close it; Resize (Return) runs `.resizeCustom` on the images.
struct ResizeForm: View {
    let store: ShelfStore
    let items: [ShelfItem]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Upright pixel sizes, read once from the image headers; unreadable images are left out.
    @State private var sizes: [(width: Int, height: Int)] = []
    @State private var percent = false
    @State private var width = ""
    @State private var height = ""
    @State private var locked = true
    @State private var error: String?
    @State private var shakes = 0
    @State private var dimmed = false
    @FocusState private var focus: Field?

    private enum Field { case width, height }

    /// One image: its size prefills the fields and drives the aspect lock (AC-3).
    private var single: (width: Int, height: Int)? { items.count == 1 ? sizes.first : nil }

    private var spec: Result<ResizeSpec, ResizeSpec.Invalid> {
        // Several images, lock on: fit each inside the box. One image: the fields already hold its exact size.
        ResizeSpec.parse(width: width, height: height, percent: percent, fit: items.count > 1 && locked)
    }

    /// Custom sizes may upscale; say so (AC-4).
    private var upscales: Bool {
        guard case .success(let spec) = spec else { return false }
        return sizes.contains { s in
            let out = spec.size(width: s.width, height: s.height)
            return out.width > s.width || out.height > s.height
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Unit", selection: $percent) {
                Text("Pixels").tag(false)
                Text("Percent").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Unit")

            HStack(spacing: 8) {
                Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 6) {
                    row("Width", text: $width, field: .width)
                    row("Height", text: $height, field: .height)
                }
                Toggle(isOn: $locked) { Label("Keep aspect ratio", systemImage: "link") }
                    .toggleStyle(.button)
                    .labelStyle(.iconOnly)
                    .help(locked ? "Width and height keep the aspect ratio" : "Width and height change separately")
                    .accessibilityLabel("Keep aspect ratio")
            }
            .modifier(Shake(animatableData: CGFloat(shakes)))
            .opacity(dimmed ? 0.4 : 1)

            Group {
                if let error {
                    Text(error).foregroundStyle(.red)
                } else if upscales {
                    Text("Larger than the original").foregroundStyle(.secondary)
                } else if items.count > 1 {
                    Text("Each of the \(items.count) images fits inside this size").foregroundStyle(.secondary)
                } else {
                    Text(" ")
                }
            }
            .font(.caption)
            .lineLimit(1)
            .truncationMode(.tail)

            HStack {
                Spacer()
                Button("Cancel") { store.resizing = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Resize", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(store.actions.running != nil)
                    .accessibilityHint(items.count == 1 ? "Adds a resized copy" : "Adds a resized copy of each image")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .background { KeyPanel() }
        .onAppear {
            sizes = items.compactMap { if case .file(let url) = $0.kind { ImageConverter.pixelSize(url) } else { nil } }
            reset()
            Task { focus = .width }
        }
        .onChange(of: percent) { reset() }
        .onChange(of: width) { _, text in link(from: .width, text) }
        .onChange(of: height) { _, text in link(from: .height, text) }
        .onChange(of: locked) { _, on in if on { link(from: .width, width, always: true) } }
    }

    private func row(_ title: String, text: Binding<String>, field: Field) -> some View {
        GridRow {
            Text("\(title):")
                .gridColumnAlignment(.trailing)
            TextField(title, text: text, prompt: Text(items.count > 1 && !percent ? "Any" : ""))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 80)
                .focused($focus, equals: field)
                .onSubmit(submit)
                .accessibilityLabel(title)
                .accessibilityHint(percent ? "Percent" : "Pixels")
            Text(percent ? "%" : "px")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    /// Prefill: Percent 100 %, one image its size in px, several images empty (AC-3).
    private func reset() {
        error = nil
        (width, height) = percent ? ("100", "100") : single.map { ("\($0.width)", "\($0.height)") } ?? ("", "")
    }

    /// Aspect lock: typing in one field updates the other (only from the field being edited, so they never fight).
    private func link(from changed: Field, _ text: String, always: Bool = false) {
        error = nil
        guard locked, always || focus == changed, let n = Int(text.trimmingCharacters(in: .whitespaces)), n > 0 else { return }
        let other: String
        if percent {
            other = "\(n)"
        } else if let s = single {
            other = changed == .width ? "\(ResizeSpec.linked(n, from: s.width, to: s.height))"
                : "\(ResizeSpec.linked(n, from: s.height, to: s.width))"
        } else {
            return
        }
        if changed == .width { height = other } else { width = other }
    }

    private func submit() {
        guard store.resizing != nil else { return }
        switch spec {
        case .failure(let invalid): reject(invalid.message)
        case .success(let spec):
            let present = Set(store.items.map(\.id))
            store.resizing = nil
            store.actions.run(.resizeCustom(spec), on: items.filter { present.contains($0.id) }, in: store)
        }
    }

    /// Invalid input (AC-5): shake, or a fade under Reduce Motion; the form stays open.
    private func reject(_ message: String) {
        error = message
        AccessibilityNotification.Announcement(message).post()
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.15)) { dimmed = true } completion: {
                withAnimation(.easeInOut(duration: 0.15)) { dimmed = false }
            }
        } else {
            withAnimation(.linear(duration: 0.3)) { shakes += 1 }
        }
    }
}

/// Two horizontal shakes per step of `animatableData`.
private nonisolated struct Shake: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 6 * sin(animatableData * .pi * 4), y: 0))
    }
}

/// Makes the panel key when the form appears, so the fields take typing (non-activating: DragShelf stays inactive).
private struct KeyPanel: NSViewRepresentable {
    func makeNSView(context: Context) -> KeyPanelView { KeyPanelView() }
    func updateNSView(_ view: KeyPanelView, context: Context) {}
}

final class KeyPanelView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeKey()
    }
}

import ControlBoxCore
import SwiftUI

struct ArrangementEditorSheet: View {
    var session: ArrangementEditorSession
    var onCancel: () -> Void
    var onSave: (ArrangementEditorSession) -> Void

    @State private var name: String
    @State private var screens: [ArrangedScreen]
    @State private var draggingID: String?
    @State private var dragOrigin: CGPoint?
    @State private var cameraScale: CGFloat?
    @State private var frozenOffset: CGSize?

    init(
        session: ArrangementEditorSession,
        onCancel: @escaping () -> Void,
        onSave: @escaping (ArrangementEditorSession) -> Void
    ) {
        self.session = session
        self.onCancel = onCancel
        self.onSave = onSave
        _name = State(initialValue: session.name)
        _screens = State(initialValue: DisplayLayoutMath.normalized(session.screens))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Form {
                    TextField("Name", text: $name)
                    Toggle("Mirror Displays", isOn: mirroredBinding)
                        .disabled(screens.count < 2)
                }
                .formStyle(.grouped)
                .frame(height: 120)

                ArrangementCanvas(
                    screens: screens,
                    interactive: true,
                    draggingID: draggingID,
                    lockedScale: cameraScale,
                    lockedOffset: frozenOffset,
                    onDrag: handleDrag,
                    onMakeMain: { identity in
                        DisplayLayoutMath.makeMain(&screens, identity: identity)
                    },
                    onLayout: { layout in
                        guard cameraScale == nil else { return }
                        DispatchQueue.main.async {
                            if cameraScale == nil {
                                cameraScale = layout.scale
                                frozenOffset = layout.offset
                            }
                        }
                    }
                )
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Text("• Drag to move. Edges snap.\n• Click the menu bar on a display to make it the main screen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }
            .navigationTitle(session.isNew ? "New Arrangement" : "Edit Arrangement")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var next = session
                        next.name = name
                        next.screens = screens
                        onSave(next)
                    }
                    .disabled(screens.isEmpty)
                }
            }
        }
        .frame(minWidth: 680, minHeight: 520)
    }

    private var mirroredBinding: Binding<Bool> {
        Binding(
            get: { screens.contains { $0.mirrorMaster != nil } },
            set: { DisplayLayoutMath.setMirrored(&screens, mirrored: $0) }
        )
    }

    private func handleDrag(identity: String, delta: CGSize, ended: Bool) {
        if draggingID != identity {
            draggingID = identity
            if let screen = screens.first(where: { $0.identity == identity }) {
                dragOrigin = CGPoint(x: CGFloat(screen.x), y: CGFloat(screen.y))
            }
        }
        guard let start = dragOrigin else { return }
        let scale = max(cameraScale ?? 0.08, 0.02)
        DisplayLayoutMath.move(
            &screens,
            identity: identity,
            origin: CGPoint(x: start.x + delta.width, y: start.y + delta.height),
            snapDistance: 36 / scale,
            finalize: ended
        )
        if ended {
            draggingID = nil
            dragOrigin = nil
        }
    }
}

import ControlBoxCore
import SwiftUI

struct ArrangementCanvas: View {
    var screens: [ArrangedScreen]
    var interactive: Bool = false
    var draggingID: String? = nil
    var lockedScale: CGFloat? = nil
    var lockedOffset: CGSize? = nil
    var onDrag: ((String, CGSize, Bool) -> Void)? = nil
    var onMakeMain: ((String) -> Void)? = nil
    var onLayout: ((CanvasLayout) -> Void)? = nil

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: interactive ? 12 : 6, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
            CanvasContent(
                screens: screens,
                interactive: interactive,
                draggingID: draggingID,
                lockedScale: lockedScale,
                lockedOffset: lockedOffset,
                onDrag: onDrag,
                onMakeMain: onMakeMain,
                onLayout: onLayout
            )
        }
    }
}

private struct CanvasContent: View {
    var screens: [ArrangedScreen]
    var interactive: Bool
    var draggingID: String?
    var lockedScale: CGFloat?
    var lockedOffset: CGSize?
    var onDrag: ((String, CGSize, Bool) -> Void)?
    var onMakeMain: ((String) -> Void)?
    var onLayout: ((CanvasLayout) -> Void)?

    var body: some View {
        GeometryReader { geometry in
            let layout = CanvasLayout(
                screens: screens,
                in: geometry.size,
                scale: lockedScale,
                offset: lockedOffset,
                stableScale: interactive
            )
            ZStack(alignment: .topLeading) {
                ForEach(DisplayLayoutMath.visibleScreens(screens)) { screen in
                    screenView(screen, layout: layout)
                }
            }
            .onAppear { onLayout?(layout) }
            .onChange(of: geometry.size) { _, _ in onLayout?(layout) }
        }
    }

    @ViewBuilder
    private func screenView(_ screen: ArrangedScreen, layout: CanvasLayout) -> some View {
        let frame = layout.canvasRect(screen.rect)
        let isDragging = draggingID == screen.identity
        ArrangementScreenShape(
            name: screen.name,
            isMain: screen.isMain,
            isBuiltIn: screen.isBuiltIn,
            compact: !interactive,
            onSelectMain: interactive ? { onMakeMain?(screen.identity) } : nil
        )
        .frame(width: frame.width, height: frame.height)
        .offset(x: frame.minX, y: frame.minY)
        .zIndex(isDragging ? 10 : (screen.isMain ? 2 : 1))
        .modifier(ArrangementDragModifier(enabled: interactive) { translation, ended in
            onDrag?(
                screen.identity,
                CGSize(
                    width: translation.width / layout.scale,
                    height: translation.height / layout.scale
                ),
                ended
            )
        })
    }
}

struct CanvasLayout: Equatable {
    var scale: CGFloat
    var offset: CGSize

    init(screens: [ArrangedScreen], in size: CGSize, scale: CGFloat?, offset: CGSize?, stableScale: Bool = false) {
        let visibleUnion = DisplayLayoutMath.union(of: screens)
        let scaleUnion = stableScale ? DisplayLayoutMath.scaleUnion(of: screens) : visibleUnion
        let padding: CGFloat = size.width < 160 ? 8 : 28
        let avail = CGSize(width: max(size.width - padding * 2, 1), height: max(size.height - padding * 2, 1))
        let fitted = Self.fitScale(union: scaleUnion, available: avail)
        self.scale = scale ?? fitted
        if let offset {
            self.offset = offset
        } else {
            self.offset = Self.centeredOffset(union: visibleUnion, available: avail, padding: padding, scale: self.scale)
        }
    }

    static func fitScale(union: CGRect, available: CGSize) -> CGFloat {
        min(available.width / max(union.width, 1), available.height / max(union.height, 1))
    }

    static func centeredOffset(union: CGRect, available: CGSize, padding: CGFloat, scale: CGFloat) -> CGSize {
        let used = CGSize(width: union.width * scale, height: union.height * scale)
        return CGSize(
            width: padding + (available.width - used.width) / 2 - union.minX * scale,
            height: padding + (available.height - used.height) / 2 - union.minY * scale
        )
    }

    func canvasRect(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX * scale + offset.width,
            y: rect.minY * scale + offset.height,
            width: max(rect.width * scale, 8),
            height: max(rect.height * scale, 8)
        )
    }
}

private struct ArrangementDragModifier: ViewModifier {
    var enabled: Bool
    var onDrag: (CGSize, Bool) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in onDrag(value.translation, false) }
                    .onEnded { value in onDrag(value.translation, true) }
            )
        } else {
            content
        }
    }
}

private struct ArrangementScreenShape: View {
    var name: String
    var isMain: Bool
    var isBuiltIn: Bool
    var compact: Bool
    var onSelectMain: (() -> Void)?

    var body: some View {
        RoundedRectangle(cornerRadius: compact ? 4 : 8, style: .continuous)
            .fill(Color(nsColor: .tertiarySystemFill))
            .overlay {
                RoundedRectangle(cornerRadius: compact ? 4 : 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.22), lineWidth: 1)
            }
            .overlay(alignment: .top) {
                Capsule()
                    .fill(isMain ? Color.white : Color.white.opacity(0.38))
                    .frame(height: compact ? 4 : 8)
                    .padding(.horizontal, compact ? 6 : 10)
                    .padding(.top, compact ? 3 : 6)
                    .shadow(color: isMain ? .black.opacity(0.12) : .clear, radius: 0.5, y: 0.5)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onSelectMain?()
                    }
            }
            .overlay {
                if !compact {
                    VStack(spacing: 2) {
                        Text(name)
                            .font(.caption)
                            .fontWeight(.medium)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                        if isBuiltIn {
                            Text("Built-in")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 12)
                }
            }
    }
}

import SwiftUI

struct GlassPanel<Content: View>: View {
    var tint: Color?
    var cornerRadius: CGFloat
    var padding: CGFloat
    @ViewBuilder var content: Content

    init(
        tint: Color? = nil,
        cornerRadius: CGFloat = 26,
        padding: CGFloat = 16,
        @ViewBuilder content: () -> Content
    ) {
        self.tint = tint
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            content
                .padding(padding)
                .glassEffect(.regular.tint(tint), in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .padding(padding)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.55), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.05), radius: 18, x: 0, y: 10)
        }
    }
}

struct AppBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(.systemBackground),
                Color(.secondarySystemBackground),
                Color(.systemGray6)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

struct GlassIconButton: View {
    var systemName: String
    var tint: Color = Theme.brand
    var size: CGFloat = 48
    var action: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                Image(systemName: systemName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: size, height: size)
            }
            .buttonStyle(.glass)
        } else {
            Button(action: action) {
                Image(systemName: systemName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: size, height: size)
            }
            .background(.ultraThinMaterial, in: Circle())
            .overlay {
                Circle()
                    .strokeBorder(.white.opacity(0.6), lineWidth: 1)
            }
        }
    }
}

struct HeroSendButton<Label: View>: View {
    var isBusy: Bool
    var action: () -> Void
    @ViewBuilder var label: Label

    @State private var isPressed = false

    init(isBusy: Bool = false, action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.isBusy = isBusy
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(action: action) {
            label
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background {
                    ZStack {
                        Capsule().fill(Theme.sendGradient)
                        Capsule()
                            .fill(Theme.glossOverlay)
                            .blendMode(.softLight)
                        Capsule()
                            .strokeBorder(.white.opacity(0.16), lineWidth: 1)
                    }
                }
                .shadow(color: .black.opacity(0.16), radius: 14, x: 0, y: 8)
                .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1)
                .overlay {
                    if isBusy {
                        Capsule().fill(.black.opacity(0.06))
                    }
                }
                .scaleEffect(isPressed ? 0.97 : 1)
                .opacity(isPressed ? 0.92 : 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

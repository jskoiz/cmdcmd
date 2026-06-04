import SwiftUI

struct GlassPanel<Content: View>: View {
    var tint: Color?
    var interactive: Bool
    var cornerRadius: CGFloat
    var padding: CGFloat
    @ViewBuilder var content: Content

    init(
        tint: Color? = nil,
        interactive: Bool = false,
        cornerRadius: CGFloat = 26,
        padding: CGFloat = 16,
        @ViewBuilder content: () -> Content
    ) {
        self.tint = tint
        self.interactive = interactive
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            content
                .padding(padding)
                .glassEffect(.regular.tint(tint).interactive(interactive), in: .rect(cornerRadius: cornerRadius))
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

/// Layered, light-filled backdrop. A near-white base with a few soft colour
/// "blooms" gives the airy, premium depth the brand leans on.
struct AppBackground: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)

            LinearGradient(
                colors: [
                    Color.white,
                    Theme.brandBright.opacity(0.10),
                    Theme.accentBlue.opacity(0.06)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Top-trailing aqua bloom
            RadialGradient(
                colors: [Theme.brandBright.opacity(0.30), .clear],
                center: .init(x: 0.92, y: 0.05),
                startRadius: 4,
                endRadius: 360
            )

            // Lower-leading mint bloom
            RadialGradient(
                colors: [Color.mint.opacity(0.20), .clear],
                center: .init(x: 0.05, y: 0.85),
                startRadius: 4,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
    }
}

struct GlassIconButton: View {
    var systemName: String
    var tint: Color = .teal
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

struct PrimaryGlassButton<Label: View>: View {
    var action: () -> Void
    @ViewBuilder var label: Label

    init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.action = action
        self.label = label()
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                label
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        } else {
            Button(action: action) {
                label
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}

/// The signature call-to-action: a glossy aqua capsule with an inner light
/// highlight and an outer brand glow. Press gives a soft spring + dim.
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
                            .strokeBorder(.white.opacity(0.45), lineWidth: 1)
                    }
                }
                .shadow(color: Theme.brand.opacity(0.42), radius: 18, x: 0, y: 10)
                .shadow(color: Theme.brandBright.opacity(0.32), radius: 5, x: 0, y: 2)
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

struct SecondaryGlassButton<Label: View>: View {
    var action: () -> Void
    @ViewBuilder var label: Label

    init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.action = action
        self.label = label()
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                label
            }
            .buttonStyle(.glass)
        } else {
            Button(action: action) {
                label
            }
            .buttonStyle(.bordered)
        }
    }
}

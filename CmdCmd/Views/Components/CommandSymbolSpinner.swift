import SwiftUI

enum CommandSymbolRotation {
    case none
    case continuous
    case tapOnce
}

struct CommandSymbolMark: View {
    var size: CGFloat = 34
    var tint: Color = Theme.brand
    var rotation: CommandSymbolRotation = .none

    @State private var isContinuouslyRotating = false
    @State private var tapRotation = 0.0

    var body: some View {
        HStack(spacing: size * 0.14) {
            rotatingCommandSymbol

            Text("+")
                .font(.system(size: plusFontSize, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .frame(width: plusFontSize * 0.8, height: size)

            rotatingCommandSymbol
        }
        .frame(width: size * 2.56, height: size)
        .onAppear {
            if rotation == .continuous {
                isContinuouslyRotating = true
            }
        }
        .onTapGesture {
            guard rotation == .tapOnce else {
                return
            }

            withAnimation(.linear(duration: 0.62)) {
                tapRotation += 360
            }
        }
        .accessibilityLabel("cmd plus cmd")
    }

    private var commandFontSize: CGFloat {
        max(size * 0.56, 8)
    }

    private var plusFontSize: CGFloat {
        max(size * 0.38, 8)
    }

    private var commandRotation: Angle {
        switch rotation {
        case .none:
            .degrees(0)
        case .continuous:
            isContinuouslyRotating ? .degrees(360) : .degrees(0)
        case .tapOnce:
            .degrees(tapRotation)
        }
    }

    private var rotatingCommandSymbol: some View {
        Image(systemName: "command")
            .font(.system(size: commandFontSize, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .frame(width: commandFontSize, height: commandFontSize)
            .rotationEffect(commandRotation)
            .animation(
                rotation == .continuous ? .linear(duration: 1.05).repeatForever(autoreverses: false) : nil,
                value: isContinuouslyRotating
            )
    }
}

struct LaunchSplashView: View {
    var body: some View {
        ZStack {
            AppBackground()

            CommandSymbolMark(size: 58, rotation: .continuous)
                .frame(width: 150, height: 76)
        }
    }
}

#Preview("Splash") {
    LaunchSplashView()
}

#Preview("Spinner") {
    CommandSymbolMark(size: 58, rotation: .tapOnce)
        .padding(40)
}

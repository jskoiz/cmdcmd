import SwiftUI

struct ImagePlaceholder: View {
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Theme.brand.opacity(0.18), lineWidth: 1.4)
                    .frame(width: 128, height: 104)

                Image(systemName: "photo")
                    .font(.system(size: 40, weight: .regular))
                    .foregroundStyle(Theme.secondaryText)
            }

            Text("Tap to upload")
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Tap to upload image")
    }
}

#Preview {
    ImagePlaceholder()
        .frame(width: 300, height: 300)
        .padding(40)
        .background(Color(.secondarySystemBackground))
}

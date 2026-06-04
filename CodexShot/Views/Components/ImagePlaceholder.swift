import SwiftUI

struct ImagePlaceholder: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Theme.brand.opacity(0.10), lineWidth: 1.4)
                .frame(width: 128, height: 104)

            Image(systemName: "photo")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Image placeholder")
    }
}

#Preview {
    ImagePlaceholder()
        .frame(width: 300, height: 300)
        .padding(40)
        .background(Color(.secondarySystemBackground))
}

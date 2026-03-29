// GlassProgressStyle.swift — Custom ProgressViewStyle matching Control Center slider aesthetic
import SwiftUI

struct GlassProgressStyle: ProgressViewStyle {
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.15))
                    .frame(height: 6)
                // Fill
                RoundedRectangle(cornerRadius: 3)
                    .fill(tint)
                    .frame(
                        width: geo.size.width * CGFloat(configuration.fractionCompleted ?? 0),
                        height: 6
                    )
                    .animation(Theme.springAnimation, value: configuration.fractionCompleted)
            }
        }
        .frame(height: 6)
    }
}

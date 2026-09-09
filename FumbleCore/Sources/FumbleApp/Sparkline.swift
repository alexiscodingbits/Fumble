import SwiftUI

/// A tiny bar chart for the dropdown: one bar per day of WPM, latest highlighted. No axes, no
/// framework dependency — the shape of the trend is the whole message.
struct Sparkline: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            let low = values.min() ?? 0
            let high = values.max() ?? 1
            // Compress the range a little so a flat-ish trend doesn't render as all-max bars:
            // the floor sits below the minimum, keeping relative differences visible.
            let floor = max(0, low - (high - low) * 0.3 - 2)
            let span = max(high - floor, 1)
            let barWidth = max(3, (geo.size.width - CGFloat(values.count - 1) * 3) / CGFloat(values.count))

            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    Capsule()
                        .fill(index == values.count - 1 ? Color.accentColor : Color.secondary.opacity(0.35))
                        .frame(width: barWidth,
                               height: max(3, geo.size.height * CGFloat((value - floor) / span)))
                        .help("\(Int(value.rounded())) wpm")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
    }
}

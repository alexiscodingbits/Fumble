import Charts
import SwiftUI

/// One day of typing speed, for the dropdown's trend chart.
struct TrendPoint: Identifiable {
    let date: Date
    let wpm: Double
    var id: Date { date }
}

/// A compact, self-explanatory speed-over-time chart (Swift Charts): a line with a soft area
/// fill, real date labels, and a wpm axis — replacing an earlier bar sparkline that read as
/// abstract green blobs.
struct TrendChart: View {
    let points: [TrendPoint]

    var body: some View {
        Chart(points) { point in
            AreaMark(
                x: .value("Day", point.date, unit: .day),
                y: .value("WPM", point.wpm)
            )
            .foregroundStyle(
                LinearGradient(colors: [Color.accentColor.opacity(0.25), .clear],
                               startPoint: .top, endPoint: .bottom)
            )
            .interpolationMethod(.catmullRom)

            LineMark(
                x: .value("Day", point.date, unit: .day),
                y: .value("WPM", point.wpm)
            )
            .foregroundStyle(Color.accentColor)
            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
            .interpolationMethod(.catmullRom)

            if point.id == points.last?.id {
                PointMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("WPM", point.wpm)
                )
                .foregroundStyle(Color.accentColor)
            }
        }
        // A y-domain snug around the data (not zero-based): day-to-day movement is the story,
        // and a 0–85 axis would flatten a 70→80 improvement into an invisible wiggle.
        .chartYScale(domain: yDomain)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel().font(.system(size: 9))
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated), centered: true)
                    .font(.system(size: 9))
            }
        }
    }

    private var yDomain: ClosedRange<Double> {
        let values = points.map(\.wpm)
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let pad = max((high - low) * 0.25, 3)
        return max(0, low - pad)...(high + pad)
    }
}

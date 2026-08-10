import Foundation

/// A fixed-bucket histogram of inter-key latencies, in milliseconds.
///
/// Why a histogram and not a running mean: **means hide fumbles.** A key you hit in 90ms
/// nine times out of ten and 600ms on the tenth has a mean of ~140ms — indistinguishable
/// from a key that is uniformly mediocre. The p95 tells them apart, and the p95 is the
/// thing worth drilling. Storing every sample would be millions of values a day, so we
/// bucket: bounded storage (28 `UInt32`s per key), mergeable, and good enough to
/// interpolate percentiles from.
///
/// Buckets are finer at the low end, where real typing lives, and coarse above ~500ms,
/// where everything is a pause rather than a motor event.
public struct LatencyHistogram: Codable, Equatable, Sendable {

    /// Upper-exclusive bucket edges in ms. `counts[i]` holds samples in `[edges[i-1], edges[i])`,
    /// with `counts[0]` = `[0, edges[0])` and the final bucket catching everything above.
    public static let edges: [Double] = [
        10, 20, 30, 40, 50, 60, 70, 80, 90, 100,
        120, 140, 160, 180, 200, 240, 280, 320, 400, 500,
        650, 800, 1000, 1300, 1600, 2000, 3000,
    ]

    public static let bucketCount = edges.count + 1

    public private(set) var counts: [UInt32]
    public private(set) var total: UInt64
    /// Kept alongside the buckets so `mean` stays exact rather than bucket-approximated.
    public private(set) var sumMilliseconds: Double

    public init() {
        counts = [UInt32](repeating: 0, count: Self.bucketCount)
        total = 0
        sumMilliseconds = 0
    }

    /// Bucket index for a latency, via binary search over `edges`.
    static func bucket(for ms: Double) -> Int {
        var low = 0
        var high = edges.count
        while low < high {
            let mid = (low + high) / 2
            if ms < edges[mid] { high = mid } else { low = mid + 1 }
        }
        return low
    }

    public mutating func add(milliseconds ms: Double) {
        guard ms.isFinite, ms >= 0 else { return }
        counts[Self.bucket(for: ms)] += 1
        total += 1
        sumMilliseconds += ms
    }

    public var mean: Double? {
        total == 0 ? nil : sumMilliseconds / Double(total)
    }

    /// Linearly-interpolated percentile. `p` in 0...1. Nil when there are no samples.
    ///
    /// Interpolation happens *within* the containing bucket, so the result is bounded by
    /// that bucket's edges. The open-ended top bucket reports its lower edge — a floor,
    /// not a guess.
    public func percentile(_ p: Double) -> Double? {
        guard total > 0 else { return nil }
        let clamped = min(max(p, 0), 1)
        let target = clamped * Double(total)

        var cumulative: Double = 0
        for (index, count) in counts.enumerated() where count > 0 {
            let next = cumulative + Double(count)
            if next >= target {
                let lower = index == 0 ? 0 : Self.edges[index - 1]
                // Final bucket is unbounded: report its floor rather than inventing a width.
                guard index < Self.edges.count else { return lower }
                let upper = Self.edges[index]
                let within = (target - cumulative) / Double(count)
                return lower + (upper - lower) * within
            }
            cumulative = next
        }
        return Self.edges.last
    }

    public var p50: Double? { percentile(0.50) }
    public var p95: Double? { percentile(0.95) }

    public mutating func merge(_ other: LatencyHistogram) {
        for index in 0..<Self.bucketCount {
            counts[index] += other.counts[index]
        }
        total += other.total
        sumMilliseconds += other.sumMilliseconds
    }

    public static func merging(_ histograms: [LatencyHistogram]) -> LatencyHistogram {
        var result = LatencyHistogram()
        for histogram in histograms { result.merge(histogram) }
        return result
    }
}

// Compact JSON: buckets as a flat array rather than 28 named keys. Day files are written
// every 30s, so the encoded size matters more than the readability of the raw file.
extension LatencyHistogram {
    private enum CodingKeys: String, CodingKey {
        case counts = "c", total = "n", sumMilliseconds = "s"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try container.decode([UInt32].self, forKey: .counts)
        // Tolerate a bucket-layout change between versions rather than failing the whole day file.
        if decoded.count == Self.bucketCount {
            counts = decoded
        } else {
            counts = [UInt32](repeating: 0, count: Self.bucketCount)
            for (index, value) in decoded.enumerated() where index < Self.bucketCount {
                counts[index] = value
            }
        }
        total = try container.decode(UInt64.self, forKey: .total)
        sumMilliseconds = try container.decode(Double.self, forKey: .sumMilliseconds)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(counts, forKey: .counts)
        try container.encode(total, forKey: .total)
        try container.encode(sumMilliseconds, forKey: .sumMilliseconds)
    }
}

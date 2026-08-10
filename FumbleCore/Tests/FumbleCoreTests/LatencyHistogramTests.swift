import Foundation
import Testing
@testable import FumbleCore

@Suite("LatencyHistogram")
struct LatencyHistogramTests {

    @Test("empty histogram reports no statistics")
    func empty() {
        let histogram = LatencyHistogram()
        #expect(histogram.total == 0)
        #expect(histogram.mean == nil)
        #expect(histogram.p50 == nil)
        #expect(histogram.p95 == nil)
    }

    @Test("mean is exact, not bucket-approximated")
    func meanIsExact() {
        var histogram = LatencyHistogram()
        histogram.add(milliseconds: 10)
        histogram.add(milliseconds: 20)
        histogram.add(milliseconds: 33)
        // 63/3 = 21 exactly; a bucket-midpoint estimate would not land here.
        #expect(histogram.mean == 21)
    }

    @Test("percentile lands inside the containing bucket")
    func percentileBounded() throws {
        var histogram = LatencyHistogram()
        for _ in 0..<100 { histogram.add(milliseconds: 95) }
        let p50 = try #require(histogram.p50)
        // 95 falls in [90, 100).
        #expect(p50 >= 90 && p50 <= 100)
    }

    @Test("p95 catches a tail that the mean hides")
    func p95CatchesTail() throws {
        // The motivating case from the design: mostly fast, with a fumble rate of 1 in 10.
        var histogram = LatencyHistogram()
        for _ in 0..<90 { histogram.add(milliseconds: 90) }
        for _ in 0..<10 { histogram.add(milliseconds: 500) }

        let mean = try #require(histogram.mean)
        let p95 = try #require(histogram.p95)
        #expect(mean < 140)   // mean looks fine
        #expect(p95 >= 400)   // p95 does not
    }

    @Test("a tail of exactly 5% puts p95 at the boundary, not in the tail")
    func p95AtExactBoundary() throws {
        // Documents a real edge of the definition rather than working around it: with exactly
        // 95 of 100 samples at or below 90ms, the 95th percentile *is* the top of that bucket.
        // A 5%-and-under fumble rate is therefore invisible to p95 — which is fine (that is
        // the point of a percentile), but it means p95 measures "how bad are my regular
        // fumbles", not "what is my worst case".
        var histogram = LatencyHistogram()
        for _ in 0..<95 { histogram.add(milliseconds: 90) }
        for _ in 0..<5 { histogram.add(milliseconds: 500) }

        let p95 = try #require(histogram.p95)
        #expect(p95 == 100)   // top of the [90, 100) bucket
        // The samples are not lost — they are still in the histogram and in the mean.
        #expect(histogram.total == 100)
        #expect(try #require(histogram.percentile(0.99)) >= 400)
    }

    @Test("top bucket reports its floor rather than inventing a width")
    func openEndedTopBucket() throws {
        var histogram = LatencyHistogram()
        histogram.add(milliseconds: 99_999)
        let p95 = try #require(histogram.p95)
        #expect(p95 == LatencyHistogram.edges.last)
    }

    @Test("negative and non-finite samples are ignored")
    func rejectsInvalid() {
        var histogram = LatencyHistogram()
        histogram.add(milliseconds: -5)
        histogram.add(milliseconds: .nan)
        histogram.add(milliseconds: .infinity)
        #expect(histogram.total == 0)
    }

    @Test("merge sums counts, totals and the exact sum")
    func merge() {
        var a = LatencyHistogram()
        a.add(milliseconds: 50)
        a.add(milliseconds: 50)
        var b = LatencyHistogram()
        b.add(milliseconds: 200)

        a.merge(b)
        #expect(a.total == 3)
        #expect(a.sumMilliseconds == 300)
    }

    @Test("bucket boundaries are lower-inclusive")
    func bucketEdges() {
        // 10 is the first edge, so it must land in bucket 1, not bucket 0.
        #expect(LatencyHistogram.bucket(for: 9.99) == 0)
        #expect(LatencyHistogram.bucket(for: 10) == 1)
        #expect(LatencyHistogram.bucket(for: 0) == 0)
        #expect(LatencyHistogram.bucket(for: 999_999) == LatencyHistogram.bucketCount - 1)
    }

    @Test("round-trips through JSON")
    func codable() throws {
        var histogram = LatencyHistogram()
        for value in [12.0, 45.0, 300.0, 88.0] { histogram.add(milliseconds: value) }

        let data = try JSONEncoder().encode(histogram)
        let decoded = try JSONDecoder().decode(LatencyHistogram.self, from: data)
        #expect(decoded == histogram)
    }
}

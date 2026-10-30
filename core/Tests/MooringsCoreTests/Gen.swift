import Foundation

@testable import MooringsCore

// Gen is a seeded SplitMix64 generator, so a property that fails replays from the seed it prints.
struct Gen {
    // cases is how many inputs each property tries.
    static let cases = 300
    // seed is the seed the generator started from.
    let seed: UInt64
    // state is the generator's state.
    private var state: UInt64

    // init starts a generator at seed.
    init(seed: UInt64) {
        self.seed = seed
        state = seed
    }

    // seeded starts a generator from MOORINGS_SEED when it is set, else from the time.
    static func seeded() -> Gen {
        if let s = ProcessInfo.processInfo.environment["MOORINGS_SEED"], let seed = UInt64(s) {
            return Gen(seed: seed)
        }
        return Gen(seed: UInt64(Date().timeIntervalSince1970 * 1000))
    }

    // next returns the next 64 random bits.
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    // int returns an integer in range.
    mutating func int(_ range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(next() % UInt64(range.upperBound - range.lowerBound + 1))
    }

    // double returns a whole number of points in range, as screen geometry is.
    mutating func double(_ range: ClosedRange<Double>) -> Double {
        Double(int(Int(range.lowerBound)...Int(range.upperBound)))
    }

    // bool returns true or false evenly.
    mutating func bool() -> Bool {
        next() & 1 == 1
    }

    // pick returns one element of xs, which must not be empty.
    mutating func pick<T>(_ xs: [T]) -> T {
        xs[int(0...(xs.count - 1))]
    }

    // area returns a display-sized frame somewhere on the desktop.
    mutating func area() -> Frame {
        Frame(x: double(-3000...3000), y: double(0...1500), w: double(800...6000), h: double(600...2200))
    }

    // frame returns a frame of at least 100 by 100 inside area.
    mutating func frame(in area: Frame) -> Frame {
        let w = double(100...max(100, area.w))
        let h = double(100...max(100, area.h))
        return Frame(x: area.x + double(0...max(0, area.w - w)), y: area.y + double(0...max(0, area.h - h)), w: w, h: h)
    }

    // point returns a point inside area.
    mutating func point(in area: Frame) -> Point {
        Point(x: area.x + double(0...(area.w - 1)), y: area.y + double(0...(area.h - 1)))
    }

    // label names the seed and case for a failure, so the run replays with MOORINGS_SEED.
    func label(_ i: Int) -> String {
        "MOORINGS_SEED=\(seed) case \(i)"
    }
}

// within reports whether f lies inside area within one point on every edge, the layout's 1 px rule.
func within(_ f: Frame, _ area: Frame) -> Bool {
    f.x >= area.x - 1 && f.y >= area.y - 1 && f.x + f.w <= area.x + area.w + 1 && f.y + f.h <= area.y + area.h + 1
}

import Foundation

/// Spots a handshake in the wrist's vertical acceleration: a short burst of
/// up and down pumping at 2 to 5 Hz that lasts 0.6 to 2 s, mostly vertical,
/// strong enough to be deliberate and regular like a rhythm.
///
/// Pure logic, fed one sample at a time (about 50 a second), so it can be
/// driven by Core Motion on the watch or by a synthetic signal in the
/// simulator. Tuned on the cautious side: the phones must also report the two
/// people within 1 m, and the watch still asks before anything is shared.
///
/// How: the vertical signal is smoothed (low pass, about 7 Hz) and its slow
/// drift removed (high pass, about 1 Hz). Each stretch between sign changes
/// (with a little hysteresis) is a lobe, half a pump. A run of good lobes
/// (each 0.09 to 0.27 s long, peaking at 0.3 to 3.5 g) is judged when it
/// ends: enough lobes, the right total length, strong on average, mostly
/// vertical and evenly paced. Anything that goes on past about 2 s (running,
/// shaking a drink) is thrown away whole.
struct HandshakeDetector {
    struct Tuning {
        var lowPassHz = 7.0
        var highPassHz = 1.0
        /// g: the signal has to cross this far past zero to change sign.
        var hysteresis = 0.06
        /// g: each lobe's peak, and the run's average peak.
        var minPeak = 0.30
        var maxPeak = 3.5
        var minMeanPeak = 0.35
        /// Seconds per lobe (half a pump): 0.09 is about 5.5 Hz, 0.27 about 1.9 Hz.
        var minHalf = 0.09
        var maxHalf = 0.27
        var minLobes = 4
        var minDuration = 0.6
        var maxDuration = 2.0
        /// Share of the run's energy that is vertical.
        var minVertical = 0.6
        /// Lobe lengths may vary this much (standard deviation over the mean).
        var maxRhythm = 0.35
        /// Quiet this long after a lobe ends the run.
        var quiet = 0.3
        /// No second detection this soon after one.
        var cooldown = 8.0
    }

    var tuning = Tuning()

    private struct Lobe {
        var start: Double
        var end: Double
        var peak: Double
        var vertical2: Double
        var horizontal2: Double
    }

    private var low = 0.0, high = 0.0, previousLow = 0.0
    private var sign = 0
    private var lobeStart: Double?
    private var lobePeak = 0.0, lobeV2 = 0.0, lobeH2 = 0.0
    private var run: [Lobe] = []
    private var tooLong = false
    private var lastFire = -Double.infinity
    private var lastTime: Double?

    init(tuning: Tuning = Tuning()) {
        self.tuning = tuning
    }

    /// One sample: time in seconds, vertical acceleration (g, gravity removed)
    /// and the size of the horizontal part (g). True when a handshake just ended.
    mutating func step(time t: Double, vertical v: Double, horizontal h: Double) -> Bool {
        let dt = lastTime.map { max(0.001, min(0.1, t - $0)) } ?? 0.02
        lastTime = t
        let k = 1 - exp(-dt * 2 * Double.pi * tuning.lowPassHz)
        low += (v - low) * k
        let rc = 1 / (2 * Double.pi * tuning.highPassHz)
        high = rc / (rc + dt) * (high + low - previousLow)
        previousLow = low
        let x = high

        var fired = false
        var next = sign
        if x > tuning.hysteresis { next = 1 } else if x < -tuning.hysteresis { next = -1 }
        if next != sign {
            if sign != 0, lobeStart != nil { fired = closeLobe(at: t) }
            sign = next
            lobeStart = t
            lobePeak = 0
            lobeV2 = 0
            lobeH2 = 0
        }
        if sign != 0, let start = lobeStart {
            lobePeak = max(lobePeak, abs(x))
            lobeV2 += x * x
            lobeH2 += h * h
            if t - start > tuning.maxHalf + tuning.quiet {
                fired = finish(at: t) || fired
                sign = 0
                lobeStart = nil
            }
        }
        return fired
    }

    mutating func reset() {
        let fire = lastFire
        self = HandshakeDetector(tuning: tuning)
        lastFire = fire
    }

    private mutating func closeLobe(at t: Double) -> Bool {
        guard let start = lobeStart else { return false }
        let length = t - start
        let good = (tuning.minHalf...tuning.maxHalf).contains(length) && (tuning.minPeak...tuning.maxPeak).contains(lobePeak)
        guard good else { return finish(at: t) }
        run.append(Lobe(start: start, end: t, peak: lobePeak, vertical2: lobeV2, horizontal2: lobeH2))
        if tooLong {
            run = Array(run.suffix(1))
        } else if let first = run.first, t - first.start > tuning.maxDuration + tuning.quiet {
            tooLong = true
        }
        return false
    }

    private mutating func finish(at t: Double) -> Bool {
        let lobes = run
        let discard = tooLong
        run = []
        tooLong = false
        guard !discard, lobes.count >= tuning.minLobes, let first = lobes.first, let last = lobes.last else { return false }
        let duration = last.end - first.start
        guard (tuning.minDuration...tuning.maxDuration).contains(duration) else { return false }
        let meanPeak = lobes.map(\.peak).reduce(0, +) / Double(lobes.count)
        guard meanPeak >= tuning.minMeanPeak else { return false }
        let v2 = lobes.map(\.vertical2).reduce(0, +)
        let h2 = lobes.map(\.horizontal2).reduce(0, +)
        guard v2 / max(1e-9, v2 + h2) >= tuning.minVertical else { return false }
        let halves = lobes.map { $0.end - $0.start }
        let mean = halves.reduce(0, +) / Double(halves.count)
        let sd = (halves.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(halves.count)).squareRoot()
        guard sd / mean <= tuning.maxRhythm else { return false }
        guard t - lastFire >= tuning.cooldown else { return false }
        lastFire = t
        return true
    }

    /// A made up handshake (2.5 Hz, 0.8 g, 1.2 s, then quiet), for the
    /// simulator, where there is no motion: (time, vertical, horizontal).
    static func syntheticHandshake(start: Double = 0, rate: Double = 50) -> [(Double, Double, Double)] {
        let f = 2.5, amp = 0.8, length = 1.2
        return (0..<Int(3 * rate)).map { i in
            let t = Double(i) / rate
            let inside = t >= 0.3 && t <= 0.3 + length
            let envelope = inside ? sin(Double.pi * (t - 0.3) / length).squareRoot() : 0
            let wave = sin(2 * Double.pi * f * (t - 0.3))
            let noise = 0.02 * sin(t * 37) // a touch of texture, deterministic
            return (start + t, amp * envelope * wave + noise, abs(0.15 * amp * envelope * cos(2 * Double.pi * f * t)))
        }
    }
}

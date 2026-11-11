import UIKit

/// The pixels of a rendered image (test-only).
struct Bitmap {
    struct Colour {
        let r: Int, g: Int, b: Int

        init(r: Int, g: Int, b: Int) {
            self.r = r
            self.g = g
            self.b = b
        }

        /// `color` as it is in the light or the dark appearance.
        init?(_ color: UIColor?, style: UIUserInterfaceStyle) {
            var (r, g, b, a) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
            guard let color, color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style)).getRed(&r, green: &g, blue: &b, alpha: &a)
            else { return nil }
            self.init(r: Int((r * 255).rounded()), g: Int((g * 255).rounded()), b: Int((b * 255).rounded()))
        }

        var brightest: Int { max(r, g, b) }
        /// The colour's hue, in degrees (red 0, green 120, blue 240); nil for a grey or one too dark to tell.
        var hue: Double? {
            let (high, low) = (max(r, g, b), min(r, g, b))
            guard high - low >= 12 else { return nil }
            let span = Double(high - low)
            let sixth: Double
            if high == r {
                sixth = (Double(g - b) / span).truncatingRemainder(dividingBy: 6)
            } else if high == g {
                sixth = Double(b - r) / span + 2
            } else {
                sixth = Double(r - g) / span + 4
            }
            return (sixth * 60 + 360).truncatingRemainder(dividingBy: 360)
        }

        /// How far two hues are apart, in degrees, the short way round.
        static func apart(_ a: Double, _ b: Double) -> Double {
            let difference = abs(a - b).truncatingRemainder(dividingBy: 360)
            return min(difference, 360 - difference)
        }
        var isWhite: Bool { r >= 250 && g >= 250 && b >= 250 }
        func distance(to other: Colour) -> Int { max(abs(r - other.r), abs(g - other.g), abs(b - other.b)) }
    }

    let width: Int
    let height: Int
    let scale: Int
    private let data: [UInt8]

    var pointSize: CGSize { CGSize(width: width / scale, height: height / scale) }

    init?(_ image: UIImage) {
        guard let cgImage = image.cgImage, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let (w, h) = (cgImage.width, cgImage.height)
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                    bytesPerRow: w * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        width = w
        height = h
        scale = max(1, Int(image.scale))
        data = bytes
    }

    /// `view` as it draws itself, on white, one pixel a point: its letters and its cursor, cut at its bounds.
    @MainActor
    init?(drawing view: UIView) {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        view.contentScaleFactor = 1
        self.init(UIGraphicsImageRenderer(size: view.bounds.size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(view.bounds)
            context.cgContext.clip(to: view.bounds)
            view.draw(view.bounds)
        })
    }

    /// How many pixels that satisfy `test` differ from `other`'s.
    func count(differingFrom other: Bitmap, where test: (Int, Int) -> Bool) -> Int {
        guard width == other.width, height == other.height else { return width * height }
        var total = 0
        for y in 0..<height {
            for x in 0..<width where test(x, y) && at(x: x, y: y).distance(to: other.at(x: x, y: y)) > 40 { total += 1 }
        }
        return total
    }

    func at(x: Int, y: Int) -> Colour {
        let i = (y * width + x) * 4
        return Colour(r: Int(data[i]), g: Int(data[i + 1]), b: Int(data[i + 2]))
    }

    /// The mean colour of the square of pixels up to `radius` away from (x, y).
    func mean(x: Int, y: Int, radius: Int) -> Colour {
        var (r, g, b, n) = (0, 0, 0, 0)
        for row in max(0, y - radius)...min(height - 1, y + radius) {
            for column in max(0, x - radius)...min(width - 1, x + radius) {
                let colour = at(x: column, y: row)
                r += colour.r
                g += colour.g
                b += colour.b
                n += 1
            }
        }
        return Colour(r: r / n, g: g / n, b: b / n)
    }

    func count(where test: (Colour) -> Bool) -> Int {
        var total = 0
        for y in 0..<height {
            for x in 0..<width where test(at(x: x, y: y)) { total += 1 }
        }
        return total
    }

    /// The longest run of white pixels in pixel row `y`, as points from the left edge.
    func longestWhiteRun(pixelRow y: Int) -> Range<Int> {
        var best = 0..<0
        var start: Int?
        for x in 0...width {
            if x < width, at(x: x, y: y).isWhite {
                if start == nil { start = x }
            } else if let from = start {
                if x - from > best.count { best = from..<x }
                start = nil
            }
        }
        return (best.lowerBound / scale)..<(best.upperBound / scale)
    }

    func longestWhiteRun(row: Int) -> Range<Int> { longestWhiteRun(pixelRow: row * scale) }

    /// The first row, in points from the top, with 200 points of white in one run: the top of the Google button,
    /// the only white thing that wide on the screen in either appearance.
    func firstRowWithAWhiteRun() -> Int? {
        for y in stride(from: 0, to: height, by: scale) where longestWhiteRun(pixelRow: y).count >= 200 { return y / scale }
        return nil
    }

    /// Whether every pixel from point row `row` down is the colour of the bottom left corner: only background.
    func isPlain(fromRow row: Int) -> Bool {
        let background = at(x: 0, y: height - 1)
        for y in (row * scale)..<height {
            for x in 0..<width where at(x: x, y: y).distance(to: background) > 2 { return false }
        }
        return true
    }

    /// How many pixel rows from point row `row` down differ from `other`'s.
    func differingRows(to other: Bitmap, fromRow row: Int) -> Int {
        guard width == other.width, height == other.height else { return height }
        var rows = 0
        for y in max(0, row * scale)..<height {
            for x in 0..<width where at(x: x, y: y).distance(to: other.at(x: x, y: y)) > 2 {
                rows += 1
                break
            }
        }
        return rows
    }

    /// The box, in pixels, around the pixels that differ from `other`; nil when none does.
    func differingBox(to other: Bitmap) -> CGRect? {
        guard width == other.width, height == other.height else { return nil }
        return box { x, y in at(x: x, y: y).distance(to: other.at(x: x, y: y)) > 2 }
    }

    /// The box, in pixels, around everything that is not black; nil on an all-black image.
    func litBox() -> CGRect? {
        box { x, y in at(x: x, y: y).brightest > 6 }
    }

    /// The box, in pixels, around what is drawn over the background (the colour of the bottom left corner) in the
    /// pixel rows `rows` (all of them when nil); nil when nothing is.
    func inkBox(rows: ClosedRange<Int>? = nil) -> CGRect? {
        let background = at(x: 0, y: height - 1)
        return box(rows: rows) { x, y in at(x: x, y: y).distance(to: background) > 40 }
    }

    private func box(rows: ClosedRange<Int>? = nil, where test: (Int, Int) -> Bool) -> CGRect? {
        var (left, right, top, bottom) = (Int.max, Int.min, Int.max, Int.min)
        let rows = (rows ?? 0...(height - 1)).clamped(to: 0...(height - 1))
        for y in rows {
            for x in 0..<width where test(x, y) {
                left = min(left, x)
                right = max(right, x)
                top = min(top, y)
                bottom = max(bottom, y)
            }
        }
        guard left <= right else { return nil }
        return CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
    }

    /// The pixel columns in which this image differs from `other`.
    func differingColumns(to other: Bitmap) -> [Int] {
        guard width == other.width, height == other.height else { return Array(0..<width) }
        return (0..<width).filter { x in
            (0..<height).contains { y in at(x: x, y: y).distance(to: other.at(x: x, y: y)) > 2 }
        }
    }

    /// The side, in points, of the logo's dark square: the longest run of the icon's near-black violet in a row.
    func darkSquareSide() -> Int {
        var best = 0
        for y in stride(from: 0, to: height, by: scale) {
            var run = 0
            for x in 0..<width {
                let colour = at(x: x, y: y)
                // #1C1438 to #0B0716, a little lifted by the inner glow: dark, and more blue than red or green.
                if colour.brightest < 80, colour.b > colour.r + 6, colour.b > colour.g {
                    run += 1
                    best = max(best, run)
                } else {
                    run = 0
                }
            }
        }
        return best / scale
    }

    /// How far this image is from `other`, over the pixels that are not black in one of the two (what is drawn on a
    /// black stage): the mean difference per channel, the share of those pixels with a channel more than 40 away,
    /// and the largest difference of a channel.
    func difference(to other: Bitmap) -> (mean: Double, far: Double, worst: Int) {
        guard width == other.width, height == other.height else { return (255, 1, 255) }
        var sum = 0
        var far = 0
        var worst = 0
        var pixels = 0
        for y in 0..<height {
            for x in 0..<width {
                let (a, b) = (at(x: x, y: y), other.at(x: x, y: y))
                guard a.brightest > 4 || b.brightest > 4 else { continue }
                pixels += 1
                sum += abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b)
                let distance = a.distance(to: b)
                worst = max(worst, distance)
                if distance > 40 { far += 1 }
            }
        }
        guard pixels > 0 else { return (255, 1, 255) }
        return (Double(sum) / Double(pixels * 3), Double(far) / Double(pixels), worst)
    }
}

extension Bitmap {
    /// From the first to the last row (points from the top) that holds a run of at least `points` of `colour` (each
    /// channel within `tolerance`), and the columns (points) of the widest such run; nil when no row has one.
    func band(of colour: Colour, atLeast points: Int = 200, tolerance: Int = 3) -> (rows: ClosedRange<Int>, columns: Range<Int>)? {
        let all = bands(of: colour, atLeast: points, tolerance: tolerance)
        guard let first = all.first, let last = all.last else { return nil }
        let widest = all.map(\.columns).max { $0.count < $1.count } ?? first.columns
        return (first.rows.lowerBound...last.rows.upperBound, widest)
    }

    /// Every group of neighbouring rows (points from the top) that hold a run of at least `points` of `colour`, top to
    /// bottom, each with the columns (points) of its widest run: one per field or button of that colour.
    func bands(of colour: Colour, atLeast points: Int = 200, tolerance: Int = 3) -> [(rows: ClosedRange<Int>, columns: Range<Int>)] {
        var found: [(rows: ClosedRange<Int>, columns: Range<Int>)] = []
        var current: (rows: ClosedRange<Int>, columns: Range<Int>)?
        for row in 0..<(height / scale) {
            let run = longestRun(pixelRow: row * scale + scale / 2) { $0.distance(to: colour) <= tolerance }
            if run.count >= points {
                if let open = current, open.rows.upperBound == row - 1 {
                    current = (open.rows.lowerBound...row, run.count > open.columns.count ? run : open.columns)
                } else {
                    if let open = current { found.append(open) }
                    current = (row...row, run)
                }
            }
        }
        if let open = current { found.append(open) }
        return found
    }

    /// The longest run of pixels that pass `test` in pixel row `y`, as points from the left edge.
    func longestRun(pixelRow y: Int, where test: (Colour) -> Bool) -> Range<Int> {
        var best = 0..<0
        var start: Int?
        for x in 0...width {
            if x < width, test(at(x: x, y: y)) {
                if start == nil { start = x }
            } else if let from = start {
                if x - from > best.count { best = from..<x }
                start = nil
            }
        }
        return (best.lowerBound / scale)..<(best.upperBound / scale)
    }

    /// The top row (points) of the Google button: the second to last band of white, the last one being Apple's button.
    /// (In the light appearance the email field above them is white too.) A run of 60 points is enough, so that the
    /// rows of a button's label, with white on both sides of it, keep the button one band. nil without two bands.
    func googleButtonTop() -> Int? {
        let white = bands(of: Colour(r: 255, g: 255, b: 255), atLeast: 60, tolerance: 5)
        return white.count >= 2 ? white[white.count - 2].rows.lowerBound : nil
    }

    /// `colour` at `opacity` over `background`, as the screen blends it.
    static func blend(_ colour: Colour, _ opacity: Double, over background: Colour) -> Colour {
        func mix(_ a: Int, _ b: Int) -> Int { Int((opacity * Double(a) + (1 - opacity) * Double(b)).rounded()) }
        return Colour(r: mix(colour.r, background.r), g: mix(colour.g, background.g), b: mix(colour.b, background.b))
    }
}

import CoreGraphics
import CatGameCore

/// Pixel registration is immutable; no SpriteKit object crosses the worker boundary.
enum CatAtlasRegistration {
    struct Frame: Sendable {
        let rect: CGRect
        let bounds: CGRect
        let groundCenter: CGFloat
        let groundY: CGFloat
        let frontPaw: CGPoint?
        let rearPaw: CGPoint?

        init(rect: CGRect, bounds: CGRect, groundCenter: CGFloat,
             groundY: CGFloat? = nil, frontPaw: CGPoint? = nil, rearPaw: CGPoint? = nil) {
            self.rect = rect
            self.bounds = bounds
            self.groundCenter = groundCenter
            self.groundY = groundY ?? bounds.maxY
            self.frontPaw = frontPaw
            self.rearPaw = rearPaw
        }
    }

    /// Measured transparent gaps between the 2×4 rest sheet's rows. Re-measure with
    /// `scripts/measure_cat_art.py <appearance>` whenever a breed's rest sheet is redrawn.
    static func restRowCuts(for appearance: CatAppearance) -> [CGFloat] {
        switch appearance {
        case .orange, .cow, .blue, .siamese, .silver: [0, 0.285, 0.515, 0.725, 1]
        }
    }

    static func extract(cgImage: CGImage, appearance: CatAppearance, clip: CatClip? = nil,
                        columns: Int, rows: Int, rowCuts: [CGFloat]? = nil) -> [Frame]? {
        let width = cgImage.width, height = cgImage.height
        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        guard let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        var frames: [Frame] = []
        for row in 0..<rows {
            for column in 0..<columns {
                let left = column * width / columns, right = (column + 1) * width / columns
                // The generated rest sheet is 2×4 but its transparent row gaps
                // are not exactly equidistant. Cut within those measured gaps
                // so a neighbouring stretch tail/paw never leaks into a frame.
                let top = rowCuts.map { Int($0[row] * CGFloat(height)) } ?? row * height / rows
                let bottom = rowCuts.map { Int($0[row + 1] * CGFloat(height)) } ?? (row + 1) * height / rows
                var minX = right, maxX = left, minY = bottom, maxY = top
                for y in top..<bottom {
                    for x in left..<right where bytes[y * bytesPerRow + x * 4 + 3] >= 128 {
                        minX = min(minX, x); maxX = max(maxX, x)
                        minY = min(minY, y); maxY = max(maxY, y)
                    }
                }
                guard minX <= maxX, minY <= maxY else { return nil }
                // Use the lowest paw band, not the entire lower quarter: a
                // lowered cream muzzle must not pull the body's registration
                // sideways during eating. Exclude the far-right nose tip too.
                let footTop = max(minY, maxY - Int(Double(maxY - minY) * 0.10))
                let footLeft = minX + Int(Double(maxX - minX) * 0.10)
                let footRight = minX + Int(Double(maxX - minX) * 0.88)
                var weightedX = 0.0, weight = 0.0
                for y in footTop...maxY {
                    for x in footLeft...footRight {
                        let offset = y * bytesPerRow + x * 4
                        let red = Double(bytes[offset]), green = Double(bytes[offset + 1]), blue = Double(bytes[offset + 2])
                        guard bytes[offset + 3] >= 180, red > 100, green > red * 0.72, blue > green * 0.67 else { continue }
                        let amount = 1 + Double(y - footTop) / Double(max(1, maxY - footTop))
                        weightedX += Double(x) * amount
                        weight += amount
                    }
                }
                let groundCenter = weight > 8 ? CGFloat(weightedX / weight - Double(left)) : CGFloat(minX + maxX) / 2 - CGFloat(left)
                // Tiny padding retains the soft fur edge, without allowing
                // stray low-alpha pixels to move the registration point.
                minX = max(left, minX - 2); maxX = min(right - 1, maxX + 2)
                minY = max(top, minY - 2)
                let crop = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
                let rect = CGRect(x: crop.minX / CGFloat(width), y: 1 - crop.maxY / CGFloat(height),
                                  width: crop.width / CGFloat(width), height: crop.height / CGFloat(height))
                frames.append(Frame(rect: rect,
                                    bounds: CGRect(x: crop.minX - CGFloat(left), y: crop.minY - CGFloat(top), width: crop.width, height: crop.height),
                                    groundCenter: groundCenter))
            }
        }
        if clip == .walk || clip == .play {
            // Extended or airborne paws are not a stable horizontal landmark.
            // Keep the body centered around the clip's median registration;
            // otherwise the leading paw can pull a pounce backward mid-air.
            let offsets = frames.map { $0.groundCenter - $0.bounds.midX }.sorted()
            let bodyOffset = offsets[offsets.count / 2]
            return frames.map {
                Frame(rect: $0.rect, bounds: $0.bounds,
                      groundCenter: $0.bounds.midX + bodyOffset)
            }
        }
        if clip == .rest {
            // A lying body's support is centered beneath the belly, not under
            // the bright front paws. Transition from standing registration;
            // frames 3...6 then share a stable body center while sleeping.
            let standingOffset = frames[0].groundCenter - frames[0].bounds.midX
            let weights: [CGFloat] = [1, 0.75, 0.45, 0, 0, 0, 0, 0.45]
            return frames.enumerated().map { index, frame in
                Frame(rect: frame.rect, bounds: frame.bounds,
                      groundCenter: frame.bounds.midX + standingOffset * weights[index])
            }
        }
        if clip == .step {
            // Measured in the 1774×887 source's 4×2 cells (top-left origin),
            // using alpha >= 180 across each visible paw's last three rows.
            // Frame 1 names the reaching paw; the other forepaw still supports
            // the body. Frames 2/3 keep the rear paw low; 5/6 keep it high.
            let front: [CGPoint], rear: [CGPoint], baselines: [CGFloat]
            switch appearance {
            case .orange:
                front = [CGPoint(x: 261.4, y: 426), CGPoint(x: 390.0, y: 366),
                         CGPoint(x: 318.3, y: 386), CGPoint(x: 321.0, y: 376),
                         CGPoint(x: 272.1, y: 380), CGPoint(x: 323.1, y: 397),
                         CGPoint(x: 289.0, y: 395), CGPoint(x: 275.7, y: 391)]
                rear = [CGPoint(x: 87.2, y: 417), CGPoint(x: 106.3, y: 419),
                         CGPoint(x: 106.5, y: 419), CGPoint(x: 118.0, y: 417),
                         CGPoint(x: 100.1, y: 374), CGPoint(x: 94.0, y: 334),
                         CGPoint(x: 105.3, y: 337), CGPoint(x: 95.3, y: 377)]
                baselines = [426, 425, 419, 417, 380, 334, 337, 391]
            case .cow:
                // Redrawn breed art (0.28.0): re-measured with scripts/measure_cat_art.py.
                front = [CGPoint(x: 269.5, y: 410), CGPoint(x: 346.5, y: 345),
                         CGPoint(x: 313.7, y: 377), CGPoint(x: 315.1, y: 377),
                         CGPoint(x: 300.3, y: 379), CGPoint(x: 324.0, y: 406),
                         CGPoint(x: 293.3, y: 414), CGPoint(x: 276.1, y: 413)]
                rear = [CGPoint(x: 117.7, y: 407), CGPoint(x: 117.4, y: 407),
                         CGPoint(x: 116.9, y: 407), CGPoint(x: 124.5, y: 408),
                         CGPoint(x: 163.5, y: 380), CGPoint(x: 141.0, y: 378),
                         CGPoint(x: 124.8, y: 374), CGPoint(x: 123.4, y: 407)]
                baselines = [410, 409, 407, 408, 380, 378, 374, 413]
            case .blue:
                // Redrawn British Shorthair (0.27.0): re-measured with scripts/measure_cat_art.py.
                front = [CGPoint(x: 258.9, y: 425), CGPoint(x: 380.0, y: 356),
                         CGPoint(x: 298.8, y: 381), CGPoint(x: 305.6, y: 376),
                         CGPoint(x: 275.8, y: 372), CGPoint(x: 311.2, y: 400),
                         CGPoint(x: 274.3, y: 403), CGPoint(x: 272.5, y: 404)]
                rear = [CGPoint(x: 92.9, y: 418), CGPoint(x: 98.0, y: 418),
                         CGPoint(x: 89.5, y: 419), CGPoint(x: 117.2, y: 418),
                         CGPoint(x: 99.0, y: 371), CGPoint(x: 102.5, y: 352),
                         CGPoint(x: 86.8, y: 353), CGPoint(x: 90.1, y: 396)]
                baselines = [425, 422, 419, 418, 372, 352, 353, 404]
            case .siamese:
                // Redrawn breed art (0.28.0): re-measured with scripts/measure_cat_art.py.
                front = [CGPoint(x: 272.2, y: 413), CGPoint(x: 356.5, y: 349),
                         CGPoint(x: 293.0, y: 370), CGPoint(x: 305.2, y: 368),
                         CGPoint(x: 296.8, y: 371), CGPoint(x: 317.8, y: 407),
                         CGPoint(x: 282.6, y: 413), CGPoint(x: 279.2, y: 413)]
                rear = [CGPoint(x: 103.5, y: 414), CGPoint(x: 103.9, y: 414),
                        CGPoint(x: 99.8, y: 414), CGPoint(x: 102.5, y: 412),
                        CGPoint(x: 136.1, y: 372), CGPoint(x: 130.1, y: 372),
                        CGPoint(x: 126.6, y: 372), CGPoint(x: 102.8, y: 413)]
                baselines = [414, 414, 414, 412, 372, 372, 372, 413]
            case .silver:
                // Redrawn breed art (0.28.0): re-measured with scripts/measure_cat_art.py.
                front = [CGPoint(x: 263.3, y: 424), CGPoint(x: 384.0, y: 364),
                         CGPoint(x: 318.9, y: 388), CGPoint(x: 318.4, y: 383),
                         CGPoint(x: 274.2, y: 379), CGPoint(x: 316.4, y: 407),
                         CGPoint(x: 272.5, y: 407), CGPoint(x: 286.1, y: 406)]
                rear = [CGPoint(x: 82.9, y: 419), CGPoint(x: 82.5, y: 420),
                        CGPoint(x: 85.9, y: 421), CGPoint(x: 109.5, y: 418),
                        CGPoint(x: 88.0, y: 378), CGPoint(x: 102.1, y: 349),
                        CGPoint(x: 114.1, y: 349), CGPoint(x: 92.1, y: 393)]
                baselines = [424, 424, 421, 418, 379, 349, 349, 406]
            }
            let bodyOffset = frames[0].groundCenter - frames[0].bounds.midX
            return frames.enumerated().map { index, frame in
                Frame(rect: frame.rect, bounds: frame.bounds,
                      groundCenter: frame.bounds.midX + bodyOffset,
                      groundY: baselines[index], frontPaw: front[index], rearPaw: rear[index])
            }
        }
        return frames
    }
}

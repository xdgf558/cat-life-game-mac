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
                    // The preceding cow meal frame's whiskers extend into this
                    // cell; its own opaque silhouette starts at x >= 27.
                    let scanLeft = left + (appearance == .cow && clip == .meal ? 25 : 0)
                    for x in scanLeft..<right where bytes[y * bytesPerRow + x * 4 + 3] >= 128 {
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
                front = [CGPoint(x: 262.4, y: 428), CGPoint(x: 388.0, y: 367),
                         CGPoint(x: 317.7, y: 387), CGPoint(x: 318.4, y: 378),
                         CGPoint(x: 273.4, y: 381), CGPoint(x: 320.8, y: 398),
                         CGPoint(x: 284.6, y: 398), CGPoint(x: 279.5, y: 395)]
                rear = [CGPoint(x: 88.0, y: 418), CGPoint(x: 107.1, y: 421),
                         CGPoint(x: 106.2, y: 420), CGPoint(x: 116.2, y: 419),
                         CGPoint(x: 98.0, y: 374), CGPoint(x: 92.4, y: 337),
                         CGPoint(x: 104.3, y: 341), CGPoint(x: 96.0, y: 379)]
                baselines = [428, 429, 420, 419, 381, 337, 341, 395]
            case .blue:
                front = [CGPoint(x: 262.462, y: 427), CGPoint(x: 390.5, y: 364),
                         CGPoint(x: 316.673, y: 385), CGPoint(x: 319.234, y: 377),
                         CGPoint(x: 273.362, y: 381), CGPoint(x: 322.602, y: 396),
                         CGPoint(x: 284.104, y: 395), CGPoint(x: 275.966, y: 391)]
                rear = [CGPoint(x: 88.275, y: 418), CGPoint(x: 109.103, y: 420),
                         CGPoint(x: 107.455, y: 419), CGPoint(x: 120.5, y: 417),
                         CGPoint(x: 100.689, y: 374), CGPoint(x: 95.085, y: 333),
                         CGPoint(x: 106.048, y: 336), CGPoint(x: 97.75, y: 377)]
                baselines = [427, 427, 419, 417, 381, 333, 336, 391]
            case .siamese:
                front = [CGPoint(x: 260.025, y: 429), CGPoint(x: 388.823, y: 364),
                         CGPoint(x: 318.574, y: 387), CGPoint(x: 321.198, y: 377),
                         CGPoint(x: 273.129, y: 383), CGPoint(x: 320.722, y: 397),
                         CGPoint(x: 283.268, y: 397), CGPoint(x: 278.069, y: 394)]
                rear = [CGPoint(x: 88.203, y: 419), CGPoint(x: 107.758, y: 420),
                        CGPoint(x: 107.136, y: 420), CGPoint(x: 118.398, y: 419),
                        CGPoint(x: 99.467, y: 376), CGPoint(x: 93.421, y: 334),
                        CGPoint(x: 102.908, y: 339), CGPoint(x: 98.203, y: 379)]
                baselines = [429, 428, 420, 419, 383, 334, 339, 394]
            case .silver:
                front = [CGPoint(x: 262.446, y: 427), CGPoint(x: 390.472, y: 367),
                         CGPoint(x: 317.653, y: 386), CGPoint(x: 319.512, y: 378),
                         CGPoint(x: 273.351, y: 382), CGPoint(x: 321.851, y: 398),
                         CGPoint(x: 281.91, y: 398), CGPoint(x: 275.237, y: 393)]
                rear = [CGPoint(x: 89.772, y: 418), CGPoint(x: 110.179, y: 420),
                        CGPoint(x: 106.448, y: 421), CGPoint(x: 121.341, y: 418),
                        CGPoint(x: 100.316, y: 374), CGPoint(x: 93.282, y: 335),
                        CGPoint(x: 104.29, y: 338), CGPoint(x: 97.088, y: 379)]
                baselines = [427, 428, 421, 418, 382, 335, 338, 393]
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

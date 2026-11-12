import SpriteKit
import CatGameCore

@MainActor
struct CatArtworkStepLandmarks68 {
    let frame: Int
    let frontPaw: CGPoint
    let rearPaw: CGPoint
    let frontUV: CGPoint
    let rearUV: CGPoint
    let spriteSize: CGSize
    let spriteXAxis: CGPoint
    let spriteYAxis: CGPoint
    let spriteID: ObjectIdentifier
}

@MainActor
struct CatArtworkLandmarks68 {
    let poseOrigin: CGPoint
    let visualWidth: CGFloat
    let mealFrame: Int?
    let mouth: CGPoint?
    let meanMouth: CGPoint?
    let step: CatArtworkStepLandmarks68?
}

/// Adapts presentation to mesh surfaces without changing the actor or its route.
@MainActor
final class RoomFurnitureContact68 {
    struct LandmarkCorrections {
        let frontPaw: CGPoint
        let rearPaw: CGPoint
        let frontDelta: CGPoint
        let rearDelta: CGPoint
    }

    private struct PawContext {
        let step: CatArtworkStepLandmarks68
        let frontDelta: CGPoint
        let rearDelta: CGPoint
    }

    private var pawContext: PawContext?
    private(set) var latestLandmarkCorrections: LandmarkCorrections?
    private var mealStage: CGPoint?
    private var mealDock: CGPoint?
    private var mealMouth: CGPoint?
    private var mealStart: TimeInterval?

    func update(cat: CatActor, rest: RoomFurnitureRest?, furniture: SKSpriteNode?,
                variant: FurnitureArtwork68.Variant?, referenceWidth: CGFloat,
                bowl: SKSpriteNode, bowlVariant: FurnitureArtwork68.Variant?, feeding: Bool) -> CGPoint {
        pawContext = nil
        latestLandmarkCorrections = nil
        let landmarks = cat.artworkLandmarks68
        if let rest, let furniture, let variant, cat.isEnteringFurniture,
           let seat = variant.surfaceOffset("seatCenter", referenceWidth: referenceWidth) {
            resetMeal()
            let oldSeat = CGPoint(x: rest.plan.restPoint.x - furniture.position.x,
                                  y: rest.plan.restPoint.y - furniture.position.y + rest.elevation)
            let progress = min(1, max(0, cat.stepProgress))
            let offset = CGPoint(x: (seat.x - oldSeat.x) * progress,
                                 y: (seat.y - oldSeat.y) * progress)
            guard let step = landmarks.step,
                  let rim = variant.surfaceOffset(rest.entryOrientation.rawValue + "EntrySurface", referenceWidth: referenceWidth) else { return offset }
            return preparePaws(cat: cat, rest: rest, furniture: furniture, seat: seat, rim: rim,
                               landmarks: landmarks, step: step, offset: offset, progress: progress)
        }
        guard feeding, cat.isDockingForMeal, let bowlVariant,
              let food = bowlVariant.surfaceOffset("foodSurfaceCenter", referenceWidth: bowl.size.width) else {
            resetMeal()
            return .zero
        }
        if mealStage == nil { mealStage = cat.position }
        if landmarks.mealFrame != nil, let mean = landmarks.meanMouth {
            if mealDock == nil {
                mealDock = cat.position
                mealStart = ProcessInfo.processInfo.systemUptime
            }
            mealMouth = mean
        }
        guard let dock = mealDock, let mouth = mealMouth else { return .zero }
        let oldFood = CGPoint(x: dock.x - bowl.position.x + mouth.x,
                              y: dock.y - bowl.position.y + mouth.y)
        let weight: CGFloat
        if landmarks.mealFrame != nil {
            let duration = 0.1 / max(0.1, Double(cat.speed))
            weight = Self.smooth(CGFloat((ProcessInfo.processInfo.systemUptime - (mealStart ?? 0)) / duration))
        } else {
            let length = max(landmarks.visualWidth * 0.2, hypot((mealStage?.x ?? dock.x) - dock.x, (mealStage?.y ?? dock.y) - dock.y))
            weight = 1 - Self.smooth(hypot(cat.position.x - dock.x, cat.position.y - dock.y) / length)
        }
        return CGPoint(x: (food.x - oldFood.x) * weight, y: (food.y - oldFood.y) * weight)
    }

    private func preparePaws(cat: CatActor, rest: RoomFurnitureRest, furniture: SKSpriteNode,
                             seat: CGPoint, rim: CGPoint, landmarks: CatArtworkLandmarks68,
                             step: CatArtworkStepLandmarks68, offset: CGPoint, progress: CGFloat) -> CGPoint {
        guard step.frame >= 2 else { return offset }
        let relative = CGPoint(x: cat.position.x - furniture.position.x, y: cat.position.y - furniture.position.y)
        let front = Self.add(relative, step.frontPaw), rear = Self.add(relative, step.rearPaw)
        let seatFront = CGPoint(x: seat.x + step.frontPaw.x - landmarks.poseOrigin.x,
                                y: seat.y + (step.frame == 4 ? step.frontPaw.y - landmarks.poseOrigin.y : 0))
        let seatRear = CGPoint(x: seat.x + step.rearPaw.x - landmarks.poseOrigin.x,
                               y: seat.y + (step.frame == 4 ? step.rearPaw.y - landmarks.poseOrigin.y : 0))
        let groundRear = CGPoint(x: rear.x, y: rear.y - landmarks.poseOrigin.y)
        let desiredFront: CGPoint, desiredRear: CGPoint, strength: CGFloat
        if step.frame == 5 || step.frame == 6 {
            // During descent the reaching forepaw follows the original floor
            // motion while the rear paw leaves the new seat surface last.
            desiredFront = front
            desiredRear = Self.mix(groundRear, seatRear, Self.smooth((progress - 0.22) / 0.66))
            strength = 1
        } else if step.frame == 7 {
            desiredFront = CGPoint(x: front.x, y: front.y - landmarks.poseOrigin.y)
            desiredRear = groundRear
            strength = 1
        } else {
            let contact = max(0.026, rest.entryContactProgress)
            strength = Self.smooth((progress - 0.025) / (contact - 0.025))
            let lift = Self.smooth((progress - contact) / max(0.01, 0.78 - contact))
            desiredRear = Self.mix(groundRear, seatRear, lift)
            desiredFront = Self.mix(rim, seatFront, Self.smooth((progress - 0.78) / 0.22))
        }
        let df = Self.scale(Self.subtract(desiredFront, Self.add(front, offset)), strength)
        let dr = Self.scale(Self.subtract(desiredRear, Self.add(rear, offset)), strength)
        // Share the reach between a body weight transfer and the two lower
        // legs; neither the torso nor the original step warp is stretched.
        let transfer = Self.scale(Self.add(df, dr), 0.5)
        pawContext = PawContext(step: step, frontDelta: Self.subtract(df, transfer), rearDelta: Self.subtract(dr, transfer))
        return Self.add(offset, transfer)
    }

    /// Call after copying the current source pose to the renderer's clone.
    func applyPawCorrection(to renderedSprite: SKSpriteNode, sourceSprite: SKSpriteNode) {
        renderedSprite.warpGeometry = sourceSprite.warpGeometry
        guard let context = pawContext, ObjectIdentifier(sourceSprite) == context.step.spriteID else { return }
        let step = context.step
        let determinant = step.spriteXAxis.x * step.spriteYAxis.y - step.spriteXAxis.y * step.spriteYAxis.x
        guard abs(determinant) > 0.000_001, step.spriteSize.width > 0, step.spriteSize.height > 0 else { return }
        func uvDelta(_ delta: CGPoint) -> CGPoint {
            CGPoint(x: (delta.x * step.spriteYAxis.y - delta.y * step.spriteYAxis.x) / determinant / step.spriteSize.width,
                    y: (delta.y * step.spriteXAxis.x - delta.x * step.spriteXAxis.y) / determinant / step.spriteSize.height)
        }
        let base = sourceSprite.warpGeometry as? SKWarpGeometryGrid
        let columns = base?.numberOfColumns ?? 8, rows = base?.numberOfRows ?? 8
        var sources: [SIMD2<Float>] = [], destinations: [SIMD2<Float>] = []
        var frontWeights: [CGFloat] = [], rearWeights: [CGFloat] = []
        for row in 0...rows { for column in 0...columns {
            let index = row * (columns + 1) + column
            let uv = base?.sourcePosition(at: index) ?? SIMD2(Float(column) / Float(columns), Float(row) / Float(rows))
            sources.append(uv)
            destinations.append(base?.destPosition(at: index) ?? uv)
            let x = CGFloat(uv.x), y = CGFloat(uv.y)
            let horizontal = min(1, max(0, (x - step.rearUV.x) / max(0.01, step.frontUV.x - step.rearUV.x)))
            frontWeights.append(horizontal * min(1, max(0, (step.frontUV.y + 0.35 - y) / 0.25)))
            rearWeights.append((1 - horizontal) * min(1, max(0, (step.rearUV.y + 0.35 - y) / 0.25)))
        } }
        let ff = Self.sample(frontWeights, at: step.frontUV, columns: columns, rows: rows)
        let fr = Self.sample(rearWeights, at: step.frontUV, columns: columns, rows: rows)
        let rf = Self.sample(frontWeights, at: step.rearUV, columns: columns, rows: rows)
        let rr = Self.sample(rearWeights, at: step.rearUV, columns: columns, rows: rows)
        let divisor = ff * rr - fr * rf
        guard abs(divisor) > 0.000_001 else { return }
        let front = uvDelta(context.frontDelta), rear = uvDelta(context.rearDelta)
        let a = Self.scale(Self.subtract(Self.scale(front, rr), Self.scale(rear, fr)), 1 / divisor)
        let b = Self.scale(Self.subtract(Self.scale(rear, ff), Self.scale(front, rf)), 1 / divisor)
        var xDeltas: [CGFloat] = [], yDeltas: [CGFloat] = []
        for index in destinations.indices {
            let delta = Self.add(Self.scale(a, frontWeights[index]), Self.scale(b, rearWeights[index]))
            destinations[index] += SIMD2(Float(delta.x), Float(delta.y))
            // Record the values actually stored in Float vertices, so audits
            // see exactly the same bilinear interpolation as the clone.
            let original = base?.destPosition(at: index) ?? sources[index]
            xDeltas.append(CGFloat(destinations[index].x - original.x))
            yDeltas.append(CGFloat(destinations[index].y - original.y))
        }
        renderedSprite.warpGeometry = SKWarpGeometryGrid(columns: columns, rows: rows,
            sourcePositions: sources, destinationPositions: destinations)
        func actorDelta(at point: CGPoint) -> CGPoint {
            let x = Self.sample(xDeltas, at: point, columns: columns, rows: rows) * step.spriteSize.width
            let y = Self.sample(yDeltas, at: point, columns: columns, rows: rows) * step.spriteSize.height
            return CGPoint(x: x * step.spriteXAxis.x + y * step.spriteYAxis.x,
                           y: x * step.spriteXAxis.y + y * step.spriteYAxis.y)
        }
        latestLandmarkCorrections = LandmarkCorrections(frontPaw: step.frontPaw, rearPaw: step.rearPaw,
            frontDelta: actorDelta(at: step.frontUV), rearDelta: actorDelta(at: step.rearUV))
    }

    /// Logical audit points are adjusted only when they identify a real paw.
    func adjustedPoint(_ logical: CGPoint, cat: CatActor) -> CGPoint {
        guard let corrections = latestLandmarkCorrections, let parent = cat.parent else { return logical }
        for (point, delta) in [(corrections.frontPaw, corrections.frontDelta), (corrections.rearPaw, corrections.rearDelta)] {
            let world = cat.convert(point, to: parent)
            if hypot(world.x - logical.x, world.y - logical.y) < 0.001 {
                return cat.convert(Self.add(point, delta), to: parent)
            }
        }
        return logical
    }

    private static func sample(_ values: [CGFloat], at uv: CGPoint, columns: Int, rows: Int) -> CGFloat {
        let gx = min(CGFloat(columns), max(0, uv.x * CGFloat(columns)))
        let gy = min(CGFloat(rows), max(0, uv.y * CGFloat(rows)))
        let column = min(columns - 1, Int(gx)), row = min(rows - 1, Int(gy))
        let fx = gx - CGFloat(column), fy = gy - CGFloat(row)
        let low = values[row * (columns + 1) + column] * (1 - fx) + values[row * (columns + 1) + column + 1] * fx
        let high = values[(row + 1) * (columns + 1) + column] * (1 - fx) + values[(row + 1) * (columns + 1) + column + 1] * fx
        return low * (1 - fy) + high * fy
    }

    private static func add(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    private static func subtract(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    private static func scale(_ p: CGPoint, _ amount: CGFloat) -> CGPoint { CGPoint(x: p.x * amount, y: p.y * amount) }
    private static func mix(_ a: CGPoint, _ b: CGPoint, _ amount: CGFloat) -> CGPoint { add(a, scale(subtract(b, a), amount)) }

    private func resetMeal() {
        mealStage = nil; mealDock = nil; mealMouth = nil; mealStart = nil
    }

    private static func smooth(_ value: CGFloat) -> CGFloat {
        let t = min(1, max(0, value))
        return t * t * (3 - 2 * t)
    }
}

import SpriteKit
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
import CatGameCore

enum CatClip: String, CaseIterable, Sendable {
    case expressions = "cat-expressions"
    case walk = "cat-walk"
    case rise = "cat-rise"
    case meal = "cat-meal"
    case play = "cat-play"
    case rest = "cat-rest"
    case step = "cat-step"
}

/// Atlas registration is computed once, not per animation frame. Cropping uses
/// SpriteKit UV rectangles; generated source images are not modified on disk.
@MainActor
final class CatSpriteLibrary {
    struct Frame {
        let texture: SKTexture
        let bounds: CGRect
        let groundCenter: CGFloat
        let groundY: CGFloat
        let frontPaw: CGPoint?
        let rearPaw: CGPoint?

        init(texture: SKTexture, bounds: CGRect, groundCenter: CGFloat,
             groundY: CGFloat? = nil, frontPaw: CGPoint? = nil, rearPaw: CGPoint? = nil) {
            self.texture = texture
            self.bounds = bounds
            self.groundCenter = groundCenter
            self.groundY = groundY ?? bounds.maxY
            self.frontPaw = frontPaw
            self.rearPaw = rearPaw
        }
    }

    struct Sequence {
        let frames: [Frame]
        let referenceHeight: CGFloat
        let heightRatio: CGFloat
    }

    private static var cache: [String: Sequence] = [:]
    private static var preloadTask: Task<Void, Never>?
#if DEBUG
    private(set) static var backgroundRegistrations = 0
    private(set) static var synchronousRegistrations = 0
#endif
    private(set) var appearance: CatAppearance

    init(appearance: CatAppearance = .orange) {
        self.appearance = appearance
    }

    func setAppearance(_ appearance: CatAppearance) {
        guard self.appearance != appearance else { return }
        self.appearance = appearance
    }

    /// The welcome progress awaits this work before creating the room. All
    /// appearances reuse the already resident atlas textures afterwards.
    static func preload() async {
        if let preloadTask { await preloadTask.value; return }
        let task = Task {
            for appearance in CatAppearance.allCases {
                for clip in CatClip.allCases {
                    let name = CatArtwork.asset(clip.rawValue, appearance: appearance)
                    guard cache[name] == nil, let image = UIImage(named: name)?.cgImage else { continue }
                    let registration = await Task.detached(priority: .userInitiated) {
                        CatAtlasRegistration.extract(cgImage: image, appearance: appearance, clip: clip,
                            columns: clip == .rest ? 2 : 4, rows: clip == .rest ? 4 : 2,
                            rowCuts: clip == .rest ? [0, 0.285, 0.515, 0.725, 1] : nil)
                    }.value
#if DEBUG
                    backgroundRegistrations += 1
#endif
                    if let registration { cache[name] = sequence(registration, name: name, clip: clip) }
                }
            }
        }
        preloadTask = task
        await task.value
        preloadTask = nil
    }

    func sequence(_ clip: CatClip) -> Sequence {
        let assetName = CatArtwork.asset(clip.rawValue, appearance: appearance)
        if let cached = Self.cache[assetName] { return cached }
        // A scene created before welcome preparation still renders correctly;
        // this one-time recovery path never invalidates another appearance.
        let result: Sequence
        if let image = UIImage(named: assetName)?.cgImage,
           let registration = CatAtlasRegistration.extract(cgImage: image, appearance: appearance, clip: clip,
                columns: clip == .rest ? 2 : 4, rows: clip == .rest ? 4 : 2,
                rowCuts: clip == .rest ? [0, 0.285, 0.515, 0.725, 1] : nil) {
#if DEBUG
            Self.synchronousRegistrations += 1
#endif
            result = Self.sequence(registration, name: assetName, clip: clip)
        } else {
            let name = CatArtwork.asset(clip == .meal ? "cat-eating" : "cat-idle", appearance: appearance)
            if let image = UIImage(named: name)?.cgImage,
               let registration = CatAtlasRegistration.extract(cgImage: image, appearance: appearance,
                                                                columns: 1, rows: 1) {
                result = Self.sequence(registration, name: name)
            } else {
                let texture = SKTexture(imageNamed: CatArtwork.asset("cat-idle", appearance: appearance))
                let size = texture.size()
                result = Sequence(frames: [Frame(texture: texture, bounds: CGRect(origin: .zero, size: size),
                                                 groundCenter: size.width / 2)], referenceHeight: max(1, size.height), heightRatio: 1)
            }
        }
        Self.cache[assetName] = result
        return result
    }

    private static func sequence(_ registration: [CatAtlasRegistration.Frame], name: String,
                                 clip: CatClip? = nil) -> Sequence {
        let atlas = SKTexture(imageNamed: name)
        atlas.filteringMode = .linear
        let frames = registration.map { frame in
            let texture = SKTexture(rect: frame.rect, in: atlas)
            texture.filteringMode = .linear
            return Frame(texture: texture, bounds: frame.bounds, groundCenter: frame.groundCenter,
                         groundY: frame.groundY, frontPaw: frame.frontPaw, rearPaw: frame.rearPaw)
        }
        let reference: CGFloat
        if clip == .expressions || clip == .walk {
            let heights = frames.map { $0.bounds.height }.sorted()
            reference = heights[heights.count / 2]
        } else { reference = frames[0].bounds.height }
        let ratio: CGFloat = (clip == .walk || clip == .meal || clip == .play) ? 0.91 : 1
        return Sequence(frames: frames, referenceHeight: reference, heightRatio: ratio)
    }

#if DEBUG
    static func resetCacheForTests() async {
        await preloadTask?.value
        cache.removeAll()
        backgroundRegistrations = 0
        synchronousRegistrations = 0
    }
#endif
}

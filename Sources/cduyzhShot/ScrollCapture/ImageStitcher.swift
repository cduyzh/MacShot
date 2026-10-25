import AppKit
import CoreGraphics

public struct ImageSlice {
    public let image: CGImage
    public let height: Int
}

/// 增量纵向拼接器。由调用方在同一串行队列使用；只保存新增像素，不反复展开整张长图。
public final class ImageStitcher {
    public enum FrameResult: Equatable {
        case appended(Int)
        case unchanged
        case backtracked(Int)
        case unmatched
        case incompatibleFrame
        case limitReached
    }

    public var consecutiveStaticThreshold = 4
    public var maximumHeight = 30_000
    public var maximumPixels = 40_000_000
    public private(set) var lastResult: FrameResult = .unchanged
    public private(set) var fixedTopHeight = 0
    public private(set) var fixedBottomHeight = 0
    public private(set) var currentOffset = 0
    public private(set) var furthestOffset = 0
    public private(set) var earliestOffset = 0
    public private(set) var totalStitchedHeight = 0
    public var hasReachedEnd: Bool { staticFrames >= consecutiveStaticThreshold }

    private var previous: Raster?
    private var first: Raster?
    private var strips: [ImageSlice] = []
    private var header: CGImage?
    private var footer: CGImage?
    private var staticFrames = 0
    private var insetsResolved = false
    private var width = 0
    private var height = 0

    public init() {}

    public func reset() {
        previous = nil
        first = nil
        strips.removeAll()
        header = nil
        footer = nil
        width = 0
        height = 0
        staticFrames = 0
        currentOffset = 0
        furthestOffset = 0
        earliestOffset = 0
        totalStitchedHeight = 0
        fixedTopHeight = 0
        fixedBottomHeight = 0
        insetsResolved = false
        lastResult = .unchanged
    }

    public func start(with image: CGImage) {
        reset()
        guard image.width > 0, image.height > 0,
              image.height <= maximumHeight,
              image.width <= maximumPixels / image.height,
              let raster = Raster(image) else {
            lastResult = .limitReached
            return
        }
        previous = raster
        first = raster
        width = image.width
        height = image.height
        totalStitchedHeight = height
    }

    /// 返回新增行数。上下两个方向都可扩展；已捕获范围内回看不会重复添加。
    @discardableResult
    public func process(newFrame image: CGImage) -> Int {
        guard let previous else {
            start(with: image)
            return totalStitchedHeight
        }
        guard image.width == width, image.height == height, let current = Raster(image) else {
            staticFrames = 0
            lastResult = .incompatibleFrame
            return 0
        }
        let top = insetsResolved ? fixedTopHeight : height / 7
        let bottom = insetsResolved ? fixedBottomHeight : height / 7
        guard let match = Self.registration(previous, current, top: top, bottom: bottom)
                ?? (insetsResolved ? nil : Self.registration(previous, current, top: 0, bottom: 0)) else {
            staticFrames = 0
            lastResult = .unmatched
            return 0
        }
        if match == 0 {
            staticFrames += 1
            lastResult = .unchanged
            return 0
        }
        staticFrames = 0
        if !insetsResolved {
            resolveFixedEdges(previous, current, shift: match)
        }
        let nextOffset = currentOffset + match
        let appendRows = max(0, nextOffset - furthestOffset)
        let prependRows = max(0, earliestOffset - nextOffset)
        let additionalRows = appendRows + prependRows
        let remainingRows = max(0, min(maximumHeight, maximumPixels / width) - totalStitchedHeight)
        guard additionalRows <= remainingRows else {
            lastResult = .limitReached
            return 0
        }
        let bodyBottom = height - fixedBottomHeight
        guard additionalRows <= bodyBottom - fixedTopHeight else {
            lastResult = .unmatched
            return 0
        }
        if appendRows > 0 {
            guard let strip = current.image(rows: (bodyBottom - appendRows)..<bodyBottom) else {
                lastResult = .unmatched
                return 0
            }
            strips.append(ImageSlice(image: strip, height: appendRows))
            furthestOffset = nextOffset
        }
        if prependRows > 0 {
            guard let strip = current.image(rows: fixedTopHeight..<(fixedTopHeight + prependRows)) else {
                lastResult = .unmatched
                return 0
            }
            strips.insert(ImageSlice(image: strip, height: prependRows), at: 0)
            earliestOffset = nextOffset
        }
        totalStitchedHeight += additionalRows
        if nextOffset <= earliestOffset, fixedTopHeight > 0 {
            header = current.image(rows: 0..<fixedTopHeight)
        }
        if nextOffset >= furthestOffset, fixedBottomHeight > 0 {
            footer = current.image(rows: bodyBottom..<height)
        }
        self.previous = current
        currentOffset = nextOffset
        lastResult = additionalRows > 0 ? .appended(additionalRows) : .backtracked(match)
        return additionalRows
    }

    private func resolveFixedEdges(_ old: Raster, _ new: Raster, shift: Int) {
        func stationaryPrefix(fromBottom: Bool) -> Int {
            let cap = min(height / 4, abs(shift) * 2 + 80)
            var count = 0
            var evidence = 0
            for index in 0..<cap {
                let row = fromBottom ? height - 1 - index : index
                if old.rowDifference(new, oldRow: row, newRow: row) > 1.2 { break }
                let movedOld = row + shift
                let movedNew = row - shift
                let difference: Double
                if movedOld >= 0 && movedOld < height {
                    difference = old.rowDifference(new, oldRow: movedOld, newRow: row)
                } else if movedNew >= 0 && movedNew < height {
                    difference = old.rowDifference(new, oldRow: row, newRow: movedNew)
                } else {
                    difference = 0
                }
                if difference > 5 { evidence += 1 }
                count += 1
            }
            // 纯白留白不算固定栏；需要足够多行的“原地相同、随滚动不同”证据。
            return count >= 16 && count < cap && evidence >= 6 ? count : 0
        }
        fixedTopHeight = stationaryPrefix(fromBottom: false)
        fixedBottomHeight = stationaryPrefix(fromBottom: true)
        if let first {
            header = first.image(rows: 0..<fixedTopHeight)
            let end = height - fixedBottomHeight
            footer = first.image(rows: end..<height)
            if let body = first.image(rows: fixedTopHeight..<end) {
                strips = [ImageSlice(image: body, height: end - fixedTopHeight)]
            }
        }
        self.first = nil
        insetsResolved = true
    }

    /// 多行、多列 RGB 匹配，先粗搜索再逐像素校准；对少量动画行做截尾处理。
    private static func registration(_ old: Raster, _ new: Raster, top: Int, bottom: Int) -> Int? {
        let usableHeight = old.height - top - bottom
        guard usableHeight >= 24 else { return nil }
        let minOverlap = max(20, usableHeight / 4)
        let maxShift = usableHeight - minOverlap
        let informativeRows = (top..<(old.height - bottom)).filter { old.saliency[$0] > 0.4 }
        // 行索引保持有序；二分查找重叠区间，避免每个位移重新遍历整张图。
        // 匹配标准不变，但大视口采样不再随高度平方增长。
        func lowerBound(_ row: Int) -> Int {
            var low = 0
            var high = informativeRows.count
            while low < high {
                let middle = (low + high) / 2
                if informativeRows[middle] < row { low = middle + 1 }
                else { high = middle }
            }
            return low
        }
        func score(_ shift: Int, quick: Bool = false) -> Double {
            let start = max(top, top + shift)
            let end = min(old.height - bottom, old.height - bottom + shift)
            guard end - start >= minOverlap else { return .infinity }
            var errors: [Double] = []
            let firstIndex = lowerBound(start)
            let endIndex = lowerBound(end)
            let step = max(1, (endIndex - firstIndex) / (quick ? 20 : 64))
            for index in stride(from: firstIndex, to: endIndex, by: step) {
                let row = informativeRows[index]
                errors.append(old.rowDifference(new, oldRow: row, newRow: row - shift, sampleStride: quick ? 4 : 1))
            }
            // 无纹理无法确认位移；只有完全静止时允许零位移。
            guard errors.count >= 6 else {
                if shift == 0 {
                    let differences = stride(from: start, to: end, by: max(1, (end - start) / 64)).map {
                        old.rowDifference(new, oldRow: $0, newRow: $0)
                    }
                    return (differences.max() ?? .infinity) < 0.5 ? 0 : .infinity
                }
                return .infinity
            }
            errors.sort()
            let count = max(1, errors.count * 4 / 5)
            return errors.prefix(count).reduce(0, +) / Double(count)
        }
        let zero = score(0)
        if zero < 0.45 {
            let step = max(1, usableHeight / 64)
            let rows = Array(stride(from: top, to: old.height - bottom, by: step))
            let changed = rows.filter { old.rowDifference(new, oldRow: $0, newRow: $0) > 2 }.count
            if changed <= max(1, rows.count / 32) { return 0 }
        }
        let coarseStep = 1
        var candidates: [(Int, Double)] = [(0, zero)]
        for shift in stride(from: -maxShift, through: maxShift, by: coarseStep) where shift != 0 {
            candidates.append((shift, score(shift, quick: true)))
        }
        candidates.sort { $0.1 < $1.1 }
        var fine: [Int: Double] = [0: zero]
        for candidate in candidates.prefix(8) {
            for shift in max(-maxShift, candidate.0 - coarseStep)...min(maxShift, candidate.0 + coarseStep) {
                if fine[shift] == nil { fine[shift] = score(shift) }
            }
        }
        let ranked = fine.sorted { $0.value < $1.value }
        guard let best = ranked.first, best.key != 0, best.value < 12,
              zero - best.value > max(0.5, zero * 0.15) else { return nil }
        // 重复条纹/列表可能在多个位移上同分，宁可提示重叠不足也不凭猜测拼接。
        if let other = ranked.first(where: { abs($0.key - best.key) > 3 }),
           other.value - best.value < max(0.6, best.value * 0.15) {
            return nil
        }
        return best.key
    }

    /// 仅完成时合成一次。分条图像拥有独立像素，不通过裁剪引用保留整帧。
    public func finish() -> CGImage? {
        guard totalStitchedHeight > 0 else { return nil }
        if let first { return first.image(rows: 0..<first.height) }
        guard let context = CGContext(data: nil, width: width, height: totalStitchedHeight,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .none
        var top = totalStitchedHeight
        func draw(_ image: CGImage) {
            top -= image.height
            context.draw(image, in: CGRect(x: 0, y: top, width: width, height: image.height))
        }
        if let header { draw(header) }
        for strip in strips { draw(strip.image) }
        if let footer { draw(footer) }
        return context.makeImage()
    }

    /// 统一色彩空间、字节序和行跨度；支持 BGRA、RGB、灰度等屏幕/图片来源。
    private struct Raster {
        static let columns = 28
        let width: Int
        let height: Int
        let bytes: [UInt8]
        let samples: [UInt8]
        let saliency: [Double]

        init?(_ image: CGImage) {
            width = image.width
            height = image.height
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
                  let data = context.data else { return nil }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            bytes = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: width * height * 4))
            var values = [UInt8](repeating: 0, count: height * Self.columns * 3)
            var detail = [Double](repeating: 0, count: height)
            for y in 0..<height {
                var minValue = 255
                var maxValue = 0
                var verticalDifference = 0
                for column in 0..<Self.columns {
                    let x = min(width - 1, max(0, Int(Double(width) * (0.04 + 0.9 * Double(column) / Double(Self.columns - 1)))))
                    let pixel = (y * width + x) * 4
                    for channel in 0..<3 {
                        let value = bytes[pixel + channel]
                        values[(y * Self.columns + column) * 3 + channel] = value
                        minValue = min(minValue, Int(value))
                        maxValue = max(maxValue, Int(value))
                        if y > 0 { verticalDifference += abs(Int(value) - Int(bytes[pixel - width * 4 + channel])) }
                    }
                }
                detail[y] = max(Double(maxValue - minValue), Double(verticalDifference) / Double(Self.columns * 3))
            }
            samples = values
            saliency = detail
        }

        func rowDifference(_ other: Raster, oldRow: Int, newRow: Int, sampleStride: Int = 1) -> Double {
            let count = Self.columns * 3
            var difference = 0
            let oldStart = oldRow * count
            let newStart = newRow * count
            for column in stride(from: 0, to: count, by: sampleStride) {
                difference += abs(Int(samples[oldStart + column]) - Int(other.samples[newStart + column]))
            }
            return Double(difference) / Double((count + sampleStride - 1) / sampleStride)
        }

        func image(rows: Range<Int>) -> CGImage? {
            guard !rows.isEmpty, rows.lowerBound >= 0, rows.upperBound <= height else { return nil }
            let data = Data(bytes[(rows.lowerBound * width * 4)..<(rows.upperBound * width * 4)])
            guard let provider = CGDataProvider(data: data as CFData) else { return nil }
            return CGImage(width: width, height: rows.count, bitsPerComponent: 8, bitsPerPixel: 32,
                           bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                           bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
                           provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        }
    }
}

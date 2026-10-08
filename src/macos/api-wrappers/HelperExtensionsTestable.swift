import Cocoa

// allow using a closure for NSControl action, instead of selector
class SelectorWrapper<T> {
    let selector: Selector
    let closure: (T) -> Void

    init(withClosure closure: @escaping (T) -> Void) {
        selector = #selector(callClosure)
        self.closure = closure
    }

    @objc
    private func callClosure(sender: AnyObject) {
        closure(sender as! T)
    }
}

fileprivate var handle: Int = 0

typealias ActionClosure = (NSControl) -> Void

extension NSControl {
    var onAction: ActionClosure? {
        get {
            return (objc_getAssociatedObject(self, &handle) as? SelectorWrapper<NSControl>)?.closure
        }
        set {
            if let newValue {
                let selectorWrapper = SelectorWrapper<NSControl>(withClosure: newValue)
                objc_setAssociatedObject(self, &handle, selectorWrapper, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                action = selectorWrapper.selector
                target = selectorWrapper
            } else {
                objc_setAssociatedObject(self, &handle, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                action = nil
                target = nil
            }
        }
    }
}

extension CGImage {
    /// Aspect-fit downscale. Returns `self` (no allocation) when the image already fits, `newSize`
    /// is not a finite positive size, or the bitmap copy fails, so a thumbnail is never dropped.
    func resizedCopyWithCoreGraphics(_ newSize: NSSize, _ fixBitmapInfo: Bool) -> CGImage {
        guard let fitted = aspectFitPixelSize(within: newSize),
              fitted.width < width || fitted.height < height else { return self }
        let finalBitmapInfo = fixBitmapInfo
            ? CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue).union(.byteOrder32Little)
            : bitmapInfo
        guard let context = CGContext(data: nil,
            width: fitted.width,
            height: fitted.height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: 0,
            space: colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: finalBitmapInfo.rawValue
        ) else { return self }
        context.interpolationQuality = .high
        context.draw(self, in: CGRect(x: 0, y: 0, width: fitted.width, height: fitted.height))
        return context.makeImage() ?? self
    }

    private func aspectFitPixelSize(within maxSize: NSSize) -> (width: Int, height: Int)? {
        guard maxSize.width.isFinite, maxSize.height.isFinite, maxSize.width >= 1, maxSize.height >= 1,
              width > 0, height > 0 else { return nil }
        let scale = min(1.0, maxSize.width / CGFloat(width), maxSize.height / CGFloat(height))
        let fittedWidth = Int((CGFloat(width) * scale).rounded())
        let fittedHeight = Int((CGFloat(height) * scale).rounded())
        guard fittedWidth > 0, fittedHeight > 0 else { return nil }
        return (fittedWidth, fittedHeight)
    }
}

extension NSWindow {
    /// AppKit persists window frames in `UserDefaults` as space-separated numbers ("x y w h",
    /// optionally followed by the save-time screen "x y w h"). On restore it rejects any frame that
    /// isn't finite or escapes Int32 bounds (CGRectContainsRect against INT_MIN..INT_MAX) by
    /// throwing NSInternalInconsistencyException — which aborts the app. Mirror that exact rule so a
    /// poison value (seen in the field after display reconfiguration) can be dropped before AppKit
    /// ever applies it. See `setFrameAutosaveNameSafely`.
    static func isValidPersistedFrame(_ string: String) -> Bool {
        let n = string.split(separator: " ").compactMap { Double($0) }
        guard n.count >= 4 else { return false } // need at least the window frame
        let lo = Double(Int32.min), hi = Double(Int32.max)
        guard n.allSatisfy({ $0.isFinite && $0 >= lo && $0 <= hi }) else { return false }
        let x = n[0], y = n[1], w = n[2], h = n[3]
        return w >= 0 && h >= 0 && (x + w) <= hi && (y + h) <= hi // w/h non-negative, no overflow
    }
}

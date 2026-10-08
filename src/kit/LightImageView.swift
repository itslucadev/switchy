import Cocoa

/// thin NSView wrapper around LightImageLayer, for use where AppKit requires an NSView (contentView, Auto Layout, NSStackView)
class LightImageView: NSView {
    let imageLayer: LightImageLayer

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    override init(frame frameRect: NSRect = .zero) {
        imageLayer = LightImageLayer()
        super.init(frame: frameRect)
        wantsLayer = true
        layer!.addSublayer(imageLayer)
        layerContentsRedrawPolicy = .never
    }

    override func layout() {
        super.layout()
        imageLayer.frame = bounds
    }

    func updateContents(_ caLayerContents: CALayerContents, _ size: NSSize) {
        imageLayer.updateContents(caLayerContents, size)
        if frame.size != size {
            frame.size = size
        }
    }

    func releaseImage() {
        imageLayer.releaseImage()
    }
}

enum CALayerContents {
    case cgImage(CGImage?)
    case pixelBuffer(CVPixelBuffer?)

    func size() -> NSSize? {
        switch self {
        case .cgImage(let image):
            return image?.size()
        case .pixelBuffer(let pixelBuffer):
            return pixelBuffer?.size()
        }
    }

    var byteSize: UInt64 {
        switch self {
        case .cgImage(let image):
            guard let image, image.bytesPerRow > 0, image.height > 0 else { return 0 }
            let (bytes, overflow) = UInt64(image.bytesPerRow).multipliedReportingOverflow(
                by: UInt64(image.height))
            return overflow ? UInt64.max : bytes
        case .pixelBuffer(let pixelBuffer):
            guard let pixelBuffer else { return 0 }
            return UInt64(CVPixelBufferGetDataSize(pixelBuffer))
        }
    }
}

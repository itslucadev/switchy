import XCTest
import Cocoa

/// Pins `CGImage.resizedCopyWithCoreGraphics` — the aspect-fit downscale used by
/// `WindowCaptureScreenshotsPrivateApi` after `CGSHWCaptureWindowList`, before the frame
/// reaches `Window.thumbnail`. It never upscales, never stretches, and returns the source
/// object when the image already fits, the bound is unusable, or the bitmap copy fails.
///
/// Lives in its own file (not `OnActionExtensionTests.swift`) because the topic is CGImage
/// resizing, not the `NSControl.onAction` extension — even though both extensions are defined in
/// `HelperExtensionsTestable.swift`.
final class ResizedCopyWithCoreGraphicsTests: XCTestCase {

    // MARK: - Helpers

    /// Build a solid-color CGImage with explicit dimensions + a sane sRGB colorspace + an alpha
    /// channel. Used as input to the resize under test.
    private func makeImage(width: Int, height: Int,
                           alphaInfo: CGImageAlphaInfo = .premultipliedLast) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil,
                            width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: space,
                            bitmapInfo: alphaInfo.rawValue)!
        ctx.setFillColor(NSColor.red.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    // MARK: - Dimensions

    func testResizeDownscaleProducesExpectedDimensions() {
        let src = makeImage(width: 200, height: 100)
        let out = src.resizedCopyWithCoreGraphics(NSSize(width: 50, height: 25), false)
        XCTAssertEqual(out.width, 50)
        XCTAssertEqual(out.height, 25)
        XCTAssertFalse(out === src)
    }

    func testAlreadyFittingImageReturnsSameInstance() {
        let src = makeImage(width: 32, height: 32)
        let out = src.resizedCopyWithCoreGraphics(NSSize(width: 128, height: 96), false)
        XCTAssertTrue(out === src)
        XCTAssertEqual(out.width, 32)
        XCTAssertEqual(out.height, 32)
    }

    func testLandscapeAspectFitStaysWithinBound() {
        let src = makeImage(width: 3024, height: 1964)
        let out = src.resizedCopyWithCoreGraphics(NSSize(width: 753, height: 482), false)
        XCTAssertEqual(out.width, 742)
        XCTAssertEqual(out.height, 482)
        XCTAssertFalse(out === src)
    }

    func testPortraitAspectFitStaysWithinBound() {
        let src = makeImage(width: 1964, height: 3024)
        let out = src.resizedCopyWithCoreGraphics(NSSize(width: 753, height: 482), false)
        XCTAssertEqual(out.width, 313)
        XCTAssertEqual(out.height, 482)
        XCTAssertFalse(out === src)
    }

    func testResizeNonSquareBoundPreservesAspectRatio() {
        let src = makeImage(width: 100, height: 100)
        let out = src.resizedCopyWithCoreGraphics(NSSize(width: 80, height: 20), false)
        XCTAssertEqual(out.width, 20)
        XCTAssertEqual(out.height, 20)
        XCTAssertFalse(out === src)
    }

    func testZeroTargetSizeReturnsSameInstance() {
        let src = makeImage(width: 40, height: 30)
        let out = src.resizedCopyWithCoreGraphics(.zero, false)
        XCTAssertTrue(out === src)
    }

    func testNegativeTargetSizeReturnsSameInstance() {
        let src = makeImage(width: 40, height: 30)
        let out = src.resizedCopyWithCoreGraphics(NSSize(width: -10, height: 20), false)
        XCTAssertTrue(out === src)
    }

    // MARK: - Bitmap info

    /// `fixBitmapInfo == true` normalizes alpha to `premultipliedFirst` and byte order to
    /// `byteOrder32Little` on a copy that actually downscales.
    func testFixBitmapInfoNormalizesAlphaAndByteOrder() {
        let src = makeImage(width: 50, height: 50, alphaInfo: .premultipliedLast)
        let out = src.resizedCopyWithCoreGraphics(NSSize(width: 25, height: 25), true)
        // Alpha info is encoded in the low bits of bitmapInfo.
        XCTAssertEqual(out.bitmapInfo.rawValue & CGBitmapInfo.alphaInfoMask.rawValue,
                       CGImageAlphaInfo.premultipliedFirst.rawValue,
                       "fixBitmapInfo must force alpha to premultipliedFirst")
        XCTAssertTrue(out.bitmapInfo.contains(.byteOrder32Little),
                      "fixBitmapInfo must force byteOrder32Little")
    }

    /// `fixBitmapInfo == false` is the private-capture thumbnail path — the source's bitmap
    /// info must be preserved (no silent normalization).
    func testNoFixBitmapInfoPreservesSourceAlpha() {
        let src = makeImage(width: 50, height: 50, alphaInfo: .premultipliedLast)
        let out = src.resizedCopyWithCoreGraphics(NSSize(width: 25, height: 25), false)
        XCTAssertEqual(out.bitmapInfo.rawValue & CGBitmapInfo.alphaInfoMask.rawValue,
                       CGImageAlphaInfo.premultipliedLast.rawValue,
                       "without fixBitmapInfo, the source's alpha info should survive untouched")
    }

    // MARK: - Pixel content sanity

    /// A solid-red source resized stays solid-red — sample a pixel via a CGContext readback to
    /// confirm the draw actually ran (catches a regression where the context is created but
    /// `draw(_:in:)` is omitted).
    func testResizePreservesSolidColor() {
        let src = makeImage(width: 100, height: 100)
        let out = src.resizedCopyWithCoreGraphics(NSSize(width: 10, height: 10), true)
        // Render the resized image into a 1x1 byte buffer at the center and check the red channel.
        var pixel: [UInt8] = [0, 0, 0, 0]
        let ctx = CGContext(data: &pixel,
                            width: 1, height: 1,
                            bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(out, in: CGRect(x: -5, y: -5, width: 10, height: 10))
        // Premultiplied last: layout is R G B A. Red channel should be ~255.
        XCTAssertGreaterThan(pixel[0], 200, "the resized image should still be predominantly red")
    }
}

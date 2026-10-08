import Cocoa
import XCTest

/// Pins the two app-icon raster extents: durable `Application.icon` stays at title-bar size even
/// when thumbnails are larger; the placeholder for tiles with no capture is the thumbnail bound,
/// squared.
///
/// Groups: A durable extent · B placeholder extent · C square.
final class AppIconRasterTests: XCTestCase {

    // MARK: - A. Durable extent

    /// durable extent is the title-bar icon size, not the (larger) thumbnail bound
    func testDurableExtentUsesTheIconSizeEvenWhenThumbnailIsLarger() {
        let iconSize = NSSize(width: 32, height: 32)
        let thumbnailSize = NSSize(width: 480, height: 320)
        XCTAssertEqual(
            AppIconRaster.durableExtent(iconSize: iconSize), NSSize(width: 32, height: 32))
        XCTAssertNotEqual(
            AppIconRaster.durableExtent(iconSize: iconSize),
            AppIconRaster.placeholderExtent(thumbnailSize: thumbnailSize))
    }

    // MARK: - B. Placeholder extent

    /// placeholder for a tile with no capture uses the thumbnail bound (the larger side)
    func testPlaceholderExtentUsesTheThumbnailSize() {
        XCTAssertEqual(
            AppIconRaster.placeholderExtent(thumbnailSize: NSSize(width: 480, height: 320)),
            NSSize(width: 480, height: 480))
    }

    // MARK: - C. Square

    /// durable extent is square on the larger side
    func testDurableExtentIsSquare() {
        XCTAssertEqual(
            AppIconRaster.durableExtent(iconSize: NSSize(width: 24, height: 48)),
            NSSize(width: 48, height: 48))
    }
}

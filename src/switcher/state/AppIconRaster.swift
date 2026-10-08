import Cocoa

/// Pixel extents for app-icon rasters. Durable `Application.icon` is always the title-bar / app-icons
/// tile size. The large placeholder for tiles with no capture is a separate raster
/// (`Application.placeholderIcon`).
enum AppIconRaster {
    /// Durable `Application.icon` extent: the title-bar / app-icons tile icon, never the window thumbnail.
    static func durableExtent(iconSize: NSSize) -> NSSize {
        let s = max(iconSize.width, iconSize.height)
        return NSSize(width: s, height: s)
    }

    /// Large placeholder used for any tile without a capture: a windowless app, or a real window the
    /// capture path cannot serve (screen recording declined or unsupported).
    static func placeholderExtent(thumbnailSize: NSSize) -> NSSize {
        let s = max(thumbnailSize.width, thumbnailSize.height)
        return NSSize(width: s, height: s)
    }
}

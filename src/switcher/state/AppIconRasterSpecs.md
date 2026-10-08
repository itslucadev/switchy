# AppIconRaster - Specs

## Summary

`AppIconRaster` is the pure size helper for app-icon rasters. It allocates no `NSImage` / `CGImage`.
Durable `Application.icon` is always the title-bar / app-icons tile icon, never the window thumbnail.
The large placeholder used for any tile without a capture — a windowless app, or a real window the
capture path cannot serve (screen recording declined or unsupported) — is a separate raster
(`Application.placeholderIcon`).

Thumbnails style used to rasterize every app icon at `TileView.maxThumbnailWidth/Height`. With many
apps and few windows that paid a tile-sized `CGImage` for process life. Tiles without a capture are
the only user-visible reason for a large icon.

## Behavior & edge cases

- **Durable extent** is square on `max(iconSize.width, iconSize.height)`. It does not consult the
  thumbnail bound, so a 32pt title-bar icon stays 32px even when thumbnails are 480x320.
- **Placeholder extent** is square on `max(thumbnailSize.width, thumbnailSize.height)`. A 480x320
  thumbnail bound becomes 480x480.

## Test scenarios

Mirrors `AppIconRasterTests.swift` 1:1.

### A. Durable extent
- **testDurableExtentUsesTheIconSizeEvenWhenThumbnailIsLarger** - durable extent of a 32x32 icon is
  32x32, not the 480x320 thumbnail bound.

### B. Placeholder extent
- **testPlaceholderExtentUsesTheThumbnailSize** - placeholder extent of 480x320 is 480x480.

### C. Square
- **testDurableExtentIsSquare** - durable extent of 24x48 is 48x48.

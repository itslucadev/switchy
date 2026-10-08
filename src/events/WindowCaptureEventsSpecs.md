# WindowCaptureEvents — Specs

## Summary

One-shot window screenshots for thumbnails and Preview. macOS 26+ captures through ScreenCaptureKit
(`WindowCaptureScreenshots`); older versions capture through the private `CGSHWCaptureWindowList`
(`WindowCaptureScreenshotsPrivateApi`), because SCK is unreliable there (macOS 14 crashes inside Apple's
code, macOS 15 leaks). Thumbnail captures are tile-scale on every macOS version: macOS 26+ configures
SCK at thumbnail pixel size, and pre-26 frames (which `CGSHWCaptureWindowList` always returns as a
full Retina raster) are aspect-fit downscaled on `BackgroundWork.screenshotsQueue` before they reach
`Window.thumbnail`. Full-resolution Preview frames are a separate, on-demand capture
(`fullRes: true` on either path) delivered to the session's capped cache instead.

## Pre-macOS-26 thumbnail downscale

`WindowCaptureScreenshotsPrivateApi.oneTimeCapture` calls `CGSHWCaptureWindowList` with
`.ignoreGlobalClipShape`, `.bestResolution`, and `.fullSize`. That API has no thumbnail-size
parameter, so the returned `CGImage` is a full Retina raster. Still on `screenshotsQueue` (the
queue the capture already runs on), the image is passed through
`CGImage.resizedCopyWithCoreGraphics(_:_:)` with `TilesPanel.maxPossibleThumbnailSize` as the
bound, then delivered to `Window.thumbnail`.

`resizedCopyWithCoreGraphics` aspect-fits into the bound (never stretches, never upscales) and
produces integral positive pixel dimensions. An image that already fits, a zero / negative /
non-finite bound, or a failed `CGContext` / `makeImage` returns the original object so a
thumbnail is never dropped because of sizing. After a successful downscale the full-resolution
raster is not retained: only the smaller copy is handed to `Window`.

A 3024x1964 capture into a 753x482 bound yields 742x482 (height-limited, aspect preserved).

## Pre-macOS-26 full-resolution Preview capture

Because the tile capture is downsampled, `WindowThumbnails.fetchPreviewFrames` no longer no-ops
below macOS 26: it routes to `WindowCaptureScreenshotsPrivateApi.oneTimeScreenshots(fullRes: true)`
(same `#available` split as `refreshAsync`). The full-res request mirrors the ScreenCaptureKit
path's semantics:

- **Distinct throttler key**: `preview-wid-<id>` instead of `capture-wid-<id>`, so a preview fetch
  is never coalesced away by the tile capture of the same window submitted milliseconds earlier;
  a tile capture must not stand in for a preview fetch. Preview requests coalesce on the requesting
  session's own throttler instance (kept in `WeakOriginatingSession`, replaced when a different
  session fetches), so a new session's request also cannot be coalesced into a previous session's
  still-pending one; tile captures keep the shared `Applications.screenshotThrottler`.
- **Same schedulers and guards**: the same 200ms per-wid cap and priority scheme (the shared
  screenshot throttler for tiles, the session-owned preview throttler for previews), the 8-wide
  `BackgroundWork.screenshotsQueue`, the
  `ActiveWindowCaptures.runSync` gate, the `App.isTerminating` / `ScreenLockEvents.isScreenLocked`
  guards, and the `SwitcherSession.isActive` re-checks at every hop for
  `.refreshOnlyThumbnailsAfterShowUi` sources.
- **Origin identity**: captures carry the requesting session weakly (`WeakOriginatingSession`), so a
  long/stuck capture retains neither the ended session nor its frame cache. Delivery stores the frame
  only while the origin is still `SwitcherSession.current` (instance identity); a capture completing
  after that session ended, or after a newer session opened, is dropped instead of landing in the
  next session's cache. Tile captures carry no origin and are unchanged. A forgotten window's
  still-pending preview entry is dropped with it via `WindowThumbnails.forgetPreviewCapture`.
- **No downscale**: the raw Retina raster skips `resizedCopyWithCoreGraphics` and goes to the
  session's capped preview cache via the shared `deliverCapture`, never to `Window.thumbnail`, so
  it dies with the session instead of parking a full-resolution raster per window.
- **No downgrade**: delivery is routed by the `fullRes` flag, so a tile-scale capture can never
  enter the preview cache; and `Window.refreshThumbnail` only forwards a tile-scale frame to
  `PreviewPanel.updateIfShowing` while the session has no full-res frame for that wid.
  `SwitcherSession.pinnedPreviewWid` is set before the fetch is enqueued and kept while the image
  is pending, so that guard keeps holding: eviction cannot drop the selected frame and expose a
  late tile-scale refresh on screen.

`isPartialFrame` deliberately does not judge pre-26 frames: `CGSHWCaptureWindowList` sizes its
output itself, so there is no exact pixel expectation to compare against.

## SCK API selection (macOS 26+)

Two public one-shot APIs exist, each broken differently:

- `captureSampleBuffer` returns a zero-copy IOSurface, but Apple implements each call by creating and
  destroying a capture stream. On some machines that churn leaks WindowServer memory until macOS
  force-logs-out the session (#5786). Each call also emits WindowServer `Creating sharing context` events
  and `Screenshots via streams are inefficient` warnings.
- `captureScreenshot` (new in macOS 26) creates no per-call stream (zero of the above events), but:
  - it fails with `SCStreamError -3811` for a fullscreen window whose Space is not frontmost (it succeeds
    when that Space is frontmost, and for minimized, other-Space, partially-offscreen, and tabbed windows);
  - it returns a copied `CGImage` instead of an IOSurface, which measurably slows full-resolution captures
    of large windows (relevant to Preview; at thumbnail sizes it is slightly *faster* than
    `captureSampleBuffer`).

Routing: `captureScreenshot` for every window, except fullscreen windows and, when any shortcut's
effective settings enable preview-selected-window, all windows (full-resolution path) — those use
`captureSampleBuffer`.

## Edge cases

- **Stale fullscreen state**: `isFullscreen` is snapshotted on the main thread when the burst is built, so
  a window mid-transition can be routed to `captureScreenshot` and fail with -3811. Deliberately no
  fallback/retry: the thumbnail keeps its previous contents and the next refresh re-routes. A fallback
  would silently reintroduce stream churn and hide new failure modes.
- **Preview is burst-wide, not per-window**: background captures aren't tied to a shortcut, so if any
  shortcut slot enables preview, every capture in the burst is full-resolution and uses
  `captureSampleBuffer` (`Preferences.anyShortcutUsesPreview`).
- **Privacy attribution cost is API-independent**: both APIs flip replayd's screen-capture attribution
  (~4 `updateScreenCaptureDidStart` events per capture) and cost systemstatusd the same CPU (measured
  within 2%). Switching APIs fixes the WindowServer leak, not the per-capture attribution overhead.

## Measurements (2026-07-11, macOS 26.5.1, M-series, 29-window payload, 10 switcher cycles per run)

| per run (~355 captures) | captureSampleBuffer | captureScreenshot |
|---|---|---|
| WindowServer sharing contexts / warnings | ~355 / ~355 | 0 / 0 |
| capture latency mean (thumbnail sizes) | 706 ms | 644 ms |
| capture latency mean (full-res, ≤5.2 MP) | 709 ms | 664 ms |
| replayd CPU | 2.0 s | 1.8 s |
| systemstatusd CPU | 4.8 s | 4.7 s |
| failures | 0 | only fullscreen-on-inactive-Space, always -3811 |

# SwitcherSession — Specs

## Summary

`SwitcherSession` holds per-summon switcher state. Full-resolution Preview frames live on the session so they die with it. The cache is an LRU with a 10-entry ceiling and a 64 MiB byte ceiling; a single newest frame may exceed 64 MiB because the selected window still has to display. The selected window's id is pinned (`pinnedPreviewWid`, set by `WindowThumbnails.previewSelectedIfNeeded` and by `fetchPreviewFrames` before it enqueues the neighborhood fetch) for as long as a preview selection is eligible, including while its image is still pending. Eviction skips the pinned id, so neighbor prefetch can never discard the displayed (or incoming) sharp Preview and expose a late tile-scale thumbnail instead, which could also overwrite the frame on screen via `Window.refreshThumbnail`'s only-while-cached guard.

## Test scenarios

Mirrors `SwitcherSessionTests.swift` 1:1.

- **testCountEvictionDropsTheLeastRecentlyStoredFrame** — the 11th stored frame drops the least recently used id; the other ten remain.
- **testByteBudgetEvictsLeastRecentlyUsedFrames** — frames whose bytes exceed 64 MiB drop least recently used ids until the remainder fits.
- **testReplacingAFrameReleasesItsOldBytes** — storing a smaller frame for an existing id frees the old bytes so a later frame can fit.
- **testReadingAFrameProtectsItFromCountEviction** — `previewFrame` promotes that id so a later store evicts a different least-recently-used id.
- **testOversizedNewestFrameIsRetainedAlone** — a frame larger than 64 MiB evicts every older id and remains readable.

### Pinned selected frame (`pinnedPreviewWid`)

- **testPinnedSelectedFrameSurvivesByteBudgetEviction** — with the selected frame pinned, neighbor prefetch blowing the 64 MiB budget evicts the LRU neighbors instead of the displayed preview.
- **testMovingThePinReleasesTheOldFrame** — moving the selection moves the pin, making the previously pinned frame evictable again on the next budget breach.
- **testOversizedPinnedFrameIsRetainedAlone** — an oversized pinned frame is retained even though it alone exceeds 64 MiB; later neighbor stores are evicted instead of it.
- **testCountCapStillEvictsAroundThePin** — the 10-entry count cap still evicts the least recently used neighbor; only the pinned id is exempt, not eviction itself.

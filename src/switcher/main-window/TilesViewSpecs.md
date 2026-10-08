# TilesView — Specs

## Summary

`TilesView` lays out recycled `TileView`s for the switcher panel. After hide, pooled tiles drop their `CALayer.contents` so IOSurface copies do not sit in idle RAM until the next summon. `Window.thumbnail` is the durable cache; the next show rebinds it onto the layers.

## Hide-time image release

`TilesView.releasePooledImages()` walks `recycledViews` and calls `releaseImage()` on each tile's thumbnail and app-icon layers. `App.releaseDismissedUiImages()` calls it — together with `WindowThumbnails.evictIdleThumbnails` and `Applications.releasePlaceholderIcons` — at the panel's REAL order-out, via `TilesPanel.onHidden`: with the fade-out animation enabled, `beginHideUi` returns while the fade is still showing those pixels, and releasing there would blank the tiles mid-fade. The no-fade path consumes `onHidden` synchronously inside `orderOut`.

A summon that races the fade owns the tiles: each `orderOut` captures and clears `onHidden` at invocation, so its completion owns only its own dismissal's callback; a stale completion (epoch mismatch against the epoch `show()` bumps) runs nothing and cannot delete a newer dismissal's callback. `App.releaseDismissedUiImages` additionally guards `SwitcherSession.current == nil`, so a summon that raced the fade keeps its tiles and its own dismissal does the release.

It does not nil `window_`, shrink the pool, or drop `Window.thumbnail`. Unused-pool entries still release images during layout when their index is past `Windows.list`; hide covers the tiles that were actually shown.

The Test scheme compiles a stub `TilesView` (`Mocks.swift`) instead of this file, so this behavior is not unit-tested there. The live summon benchmark is the regression check: first-show footprint should fall back toward the pre-show idle after hide, instead of staying at the in-panel peak.

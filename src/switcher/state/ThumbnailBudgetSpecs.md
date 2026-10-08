# ThumbnailBudget - Specs

## Summary

`ThumbnailBudget` caps process-lifetime `Window.thumbnail` byte counts. The cache is an LRU with a 20-entry ceiling and a 32 MiB byte ceiling; a single newest or protected id may exceed 32 MiB because it still has to display. Tests construct a fresh instance.

## Test scenarios

Mirrors `ThumbnailBudgetTests.swift` 1:1.

- **testCountEvictionDropsTheLeastRecentlyStoredId** - the 21st stored id drops the least recently used id; the other twenty remain.
- **testByteBudgetEvictsLeastRecentlyUsedIds** - ids whose bytes exceed 32 MiB drop least recently used ids until the remainder fits.
- **testReplacingAnIdReleasesItsOldBytes** - storing a smaller size for an existing id frees the old bytes so a later size can fit.
- **testTouchProtectsFromCountEviction** - `touch` promotes that id so a later store evicts a different least-recently-used id.
- **testOversizedNewestIdIsRetainedAlone** - an id larger than 32 MiB evicts every older id and remains cached.
- **testProtectedIdsAreNotEvicted** - ids in `protecting` survive a store that would otherwise evict them.
- **testEvictIdleDropsDownToCapWithEmptyProtecting** - `evict(protecting: [])` drops down to the cap after a protecting store overfilled it.

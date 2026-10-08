import Cocoa

class TilesPanel: NSPanel {
 override var canBecomeKey: Bool { true }
 static var maxPossibleThumbnailSize = NSSize.zero
 static var maxPossibleAppIconSize = NSSize.zero
 static var maxPossiblePlaceholderIconSize = NSSize.zero
 static var shared: TilesPanel!
 private var frozenTopCenter: NSPoint?
 private var highWaterHeight: CGFloat = 0
 /// Bookkeeping `App` wants to run when the panel has actually left the screen: the dismissal fade
 /// keeps the pooled images on screen after `beginHideUi`, so their release must wait for the
 /// order-out. Set per dismissal; each `orderOut` captures and clears it at invocation, so its
 /// completion owns exactly the callback of its own dismissal.
 var onHidden: (() -> Void)?
 /// Bumped by `show()`. A fade completion whose epoch is stale lost the race against a new summon
 /// and must neither order the panel out from under it nor run `onHidden`.
 private var showEpoch = 0

 convenience init() {
  self.init(contentRect: .zero, styleMask: .nonactivatingPanel, backing: .buffered, defer: false)
  delegate = self
  isFloatingPanel = true
  animationBehavior = .none
  hidesOnDeactivate = false
  titleVisibility = .hidden
  backgroundColor = .clear
  TilesView.initialize()
  contentView! = TilesView.contentView
  // triggering Switchy before or during Space transition animation brings the window on the Space post-transition
  collectionBehavior = .canJoinAllSpaces
  // 2nd highest level possible; this allows the app to go on top of context menus
  // highest level is .screenSaver but makes drag and drop on top the main window impossible
  level = .popUpMenu
  // helps filter out this window from the thumbnails
  setAccessibilitySubrole(.unknown)
  // for VoiceOver
  setAccessibilityLabel(App.name)
  updateAppearance()
  Self.shared = self
 }

 func updateAppearance() {
  hasShadow = Appearance.enablePanelShadow
  appearance = NSAppearance(named: Appearance.currentTheme == .dark ? .vibrantDark : .vibrantLight)
 }

 func updateContents(_ preservedScrollOrigin: CGPoint?) {
  MainThreadStall.step()
  caTransaction {
   TilesView.updateItemsAndLayout(preservedScrollOrigin)
   guard SwitcherSession.isActive else { return }
   setContentSize(TilesView.contentView.frame.size)
   guard SwitcherSession.isActive else { return }
   repositionOrFreeze()
  }
  // prevent further AppKit work
  TilesView.clearNeedsLayout()
 }

 private func repositionOrFreeze() {
  let size = frame.size
  guard TilesView.isSearchModeOn else {
   NSScreen.preferred.repositionPanel(self)
   resetFrozenPosition()
   return
  }
  if size.height > highWaterHeight {
   NSScreen.preferred.repositionPanel(self)
   highWaterHeight = size.height
   frozenTopCenter = NSPoint(x: frame.midX, y: frame.maxY)
  } else if let topCenter = frozenTopCenter {
   setFrameOrigin(NSPoint(x: topCenter.x - size.width * 0.5, y: topCenter.y - size.height))
  }
 }

 func resetFrozenPosition() {
  frozenTopCenter = nil
  highWaterHeight = 0
 }

 override func orderOut(_ sender: Any?) {
  MainThreadStall.step()
  TilesView.clearNeedsLayout()
  // Captured and cleared at invocation: a completion owns its own dismissal's callback, so a stale
  // completion from an earlier fade can neither run nor delete a newer dismissal's callback.
  let onHidden = self.onHidden
  self.onHidden = nil
  if Preferences.fadeOutAnimation {
   let epoch = showEpoch
   NSAnimationContext.runAnimationGroup(
    { _ in animator().alphaValue = 0 },
    completionHandler: {
     guard epoch == self.showEpoch else { return }
     super.orderOut(sender)
     onHidden?()
    }
   )
  } else {
   // Not a hedge against a slow `orderOut`: both land in the same CoreAnimation transaction, which
   // only commits when this runloop turn ends, so nothing here reaches the screen any earlier.
   // It leaves the panel at alpha 0 for the NEXT summon, which is what lets
   // `showUiOrCycleSelection` mask a cross-shortcut rebuild and `show()` reveal it atomically.
   alphaValue = 0
   super.orderOut(sender)
   onHidden?()
  }
 }

 func show() {
  MainThreadStall.step()
  updateAppearance()
  // A dismissal fade may still be in flight (summon raced the previous hide): the epoch bump
  // invalidates its stale completion, and the zero-duration animator set overrides the fade so the
  // panel is revealed at full alpha in this same transaction.
  showEpoch += 1
  NSAnimationContext.runAnimationGroup { context in
   context.duration = 0
   animator().alphaValue = 1
  }
  makeKeyAndOrderFront(nil)
  // The artificial key-repeat measures its initial-delay grace from when the panel could be SEEN, and this
  // is the only anchor for that which is guaranteed to exist — see `SwitcherSession.panelShownAt`. Set
  // once per summon (a re-show within one session must not restart the grace under the user's fingers).
  if let session = SwitcherSession.current, session.panelShownAt == nil {
   session.panelShownAt = ProcessInfo.processInfo.systemUptime
  }
  ContextMenuEvents.toggle(true)
  CursorEvents.toggle(true)
  DispatchQueue.main.async { TilesView.scrollView.flashScrollers() }
 }

 static func maxThumbnailsWidth(_ screen: NSScreen = NSScreen.preferred) -> CGFloat {
  if Preferences.effectiveAppearanceStyle(SwitcherSession.activeShortcutIndex) == .titles,
   let readableWidth = TilesView.layoutCache.comfortableReadabilityWidth
  {
   return
    (min(
     screen.frame.width * Appearance.maxWidthOnScreen,
     readableWidth + Appearance.intraCellPadding * 2 + Appearance.appIconLabelSpacing
      + Appearance.iconSize
      // widthOfLongestTitle + Appearance.intraCellPadding * 2 + Appearance.appIconLabelSpacing + Appearance.iconSize
    ) - Appearance.windowPadding * 2).rounded()
  }
  return (screen.frame.width * Appearance.maxWidthOnScreen - Appearance.windowPadding * 2).rounded()
 }

 static func maxThumbnailsHeight(_ screen: NSScreen = NSScreen.preferred) -> CGFloat {
  return (screen.frame.height * Appearance.maxHeightOnScreen - Appearance.windowPadding * 2)
   .rounded()
 }

 static func updateMaxPossibleThumbnailSize() {
  let (w, h) = NSScreen.screens.reduce((CGFloat.zero, CGFloat.zero)) { acc, screen in
   (
    max(acc.0, TileView.maxThumbnailWidth(screen) * screen.backingScaleFactor),
    max(acc.1, TileView.maxThumbnailHeight(screen) * screen.backingScaleFactor)
   )
  }
  maxPossibleThumbnailSize = NSSize(width: w.rounded(), height: h.rounded())
  maxPossiblePlaceholderIconSize = maxPossibleThumbnailSize
 }

 static func updateMaxPossibleAppIconSize() {
  let (w, h) = NSScreen.screens.reduce((CGFloat.zero, CGFloat.zero)) { acc, screen in
   let size = TileView.iconSize(screen)
   return (
    max(acc.0, size.width * screen.backingScaleFactor),
    max(acc.1, size.height * screen.backingScaleFactor)
   )
  }
  maxPossibleAppIconSize = NSSize(width: w.rounded(), height: h.rounded())
 }
}

extension TilesPanel: NSWindowDelegate {
 func windowDidResignKey(_ notification: Notification) {
  // other windows can steal key focus from alt-tab; we make sure that if it's active, if keeps key focus
  // dispatching to the main queue is necessary to introduce a delay in scheduling the makeKey; otherwise it is ignored
  DispatchQueue.main.async {
   if SwitcherSession.isActive {
    TilesPanel.shared.makeKeyAndOrderFront(nil)
   }
   MainMenu.toggle(true)
  }
 }

 func windowDidBecomeKey(_ notification: Notification) {
  // we toggle the mainMenu off when showing the main window
  // this avoids command+q from quitting Switchy itself, or command+p from printing
  DispatchQueue.main.async {
   MainMenu.toggle(false)
   if TilesView.isSearchEditing {
    MainMenu.toggleEditMenu(true)
   }
  }
  // Refresh the window model once the main run loop next goes idle after showing — i.e. after AppKit has
  // finished ALL the show's main-thread work for this frame. A one-shot kCFRunLoopBeforeWaiting observer
  // fires only when the loop is about to sleep, so it provably can't preempt the render, yet still runs
  // ASAP with no timer guess. (Replaces a 0.25s timer, then a CATransaction-commit hook that fired mid
  // -render and let the reconcile's re-layout race the first frame.)
  let refreshObserver = CFRunLoopObserverCreateWithHandler(
   nil, CFRunLoopActivity.beforeWaiting.rawValue, false, 0
  ) { observer, _ in
   if let observer { CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes) }
   // The show is its own reason to re-read the world, and it does not wait out any quiet period:
   // a correction that lands after the user has already chosen is worth nothing.
   Applications.manuallyRefreshAllWindows()
  }
  CFRunLoopAddObserver(CFRunLoopGetMain(), refreshObserver, .commonModes)
 }
}

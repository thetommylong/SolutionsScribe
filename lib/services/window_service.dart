import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:window_manager/window_manager.dart';

/// Owns the desktop window's size policy and handles the "auto-resize to fit
/// content" behavior when the transcript is hidden.
///
/// On Linux / macOS / Windows the app window is constrained to
/// [minWindowSize]..[maxWindowSize] and starts at [initialWindowSize]. The
/// transcript view can be collapsed (see the visibility toggle in the header);
/// when it is, the window shrinks down to just the surrounding chrome (header
/// + playback bar) instead of leaving a blank transcript region, and expands
/// back to its previous size when the transcript is shown again.
///
/// Everything is driven through `window_manager` (single source of truth). The
/// native runners still set a default frame for platforms where window_manager
/// may be ignored (e.g. some Wayland compositors), which this class then
/// tightens to the bounds below at startup.
class WindowService {
  static const Size initialWindowSize = Size(1280, 720);
  // The minimum height is the surrounding chrome (header + playback bar) so the
  // collapsed-transcript window can shrink all the way down to just the
  // controls (no blank transcript region). Width stays generous for the bar.
  static const Size minWindowSize = Size(960, _chromeHeight);
  static const Size maxWindowSize = Size(2560, 1600);

  /// Fixed chrome around the transcript: header (48) + playback bar (64).
  static const double _chromeHeight = 48 + 64;
  /// Vertical padding added so the collapsed window doesn't feel cramped.
  static const double _collapsedPadding = 8;
  /// When the transcript is visible and no explicit size was recorded, use
  /// this content height for the transcript region.
  static const double _defaultTranscriptHeight = 480;

  Size? _lastSizeBeforeCollapse;

  static bool get _isSupported =>
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows;

  static final WindowService instance = WindowService._();

  WindowService._();

  /// Called once from `main()` (no-op on unsupported platforms). Applies the
  /// initial size and the min/max constraints, then centers the window.
  Future<void> initialize() async {
    if (!_isSupported) return;
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: initialWindowSize,
        minimumSize: minWindowSize,
        maximumSize: maxWindowSize,
        center: true,
        title: 'SolutionsScribe',
      ),
    );
  }

  /// Expands/shrinks the window to match the transcript's visibility.
  ///
  /// When [visible] is true the window returns to the size it had before the
  /// transcript was collapsed (or to a default transcript size if none was
  /// recorded). When false it shrinks to just the surrounding chrome so no
  /// blank transcript region is shown.
  Future<void> setTranscriptVisible(bool visible) async {
    if (!_isSupported) return;
    if (visible) {
      await _restore();
    } else {
      await _collapse();
    }
  }

  Future<void> _collapse() async {
    final bounds = await windowManager.getBounds();
    final collapsedHeight = (_chromeHeight + _collapsedPadding)
        .clamp(minWindowSize.height, maxWindowSize.height);
    _lastSizeBeforeCollapse = Size(bounds.width, bounds.height);
    await windowManager.setSize(
      Size(bounds.width, collapsedHeight),
      animate: true,
    );
  }

  Future<void> _restore() async {
    final previous = _lastSizeBeforeCollapse;
    final height = previous != null
        ? previous.height.clamp(minWindowSize.height, maxWindowSize.height)
        : (_chromeHeight + _defaultTranscriptHeight)
            .clamp(minWindowSize.height, maxWindowSize.height);
    // Restore the width that was recorded, or fall back to the current one.
    final width = previous?.width ?? (await windowManager.getBounds()).width;
    _lastSizeBeforeCollapse = null;
    await windowManager.setSize(Size(width, height), animate: true);
  }
}
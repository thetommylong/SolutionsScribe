import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:window_manager/window_manager.dart';

/// Owns the desktop window's size policy and the "resize to fit content"
/// behavior across screens.
///
/// On Linux / macOS / Windows the app window is constrained to
/// [minWindowSize]..[maxWindowSize] and starts at [initialWindowSize]. The
/// transcript screen can have its transcript region collapsed (see the
/// visibility toggle in the header); when it is, the window shrinks to a
/// compact height — just the header, the always-on transcribing strip and the
/// playback bar — instead of leaving a blank transcript region, and expands
/// back when the transcript is shown again. The window is also resized once on
/// entering the transcript screen (["enterTranscript"]) and back to a
/// reasonable default when returning to the upload screen
/// (["leaveTranscript"]).
///
/// Everything is driven through `window_manager` (single source of truth). The
/// native runners still set a default frame for platforms where window_manager
/// may be ignored (e.g. some Wayland compositors), which this class then
/// tightens to the bounds below at startup.
class WindowService {
  static const Size initialWindowSize = Size(1280, 720);
  // Width stays generous so the playback bar and status strip have room; the
  // minimum height covers the whole surrounding chrome (header + the always-on
  // transcribing strip + playback bar) so the transcript-hidden window never
  // clips the status.
  static const Size minWindowSize = Size(960, _compactHeight);
  static const Size maxWindowSize = Size(2560, 1600);

  /// Fixed chrome heights in the transcript screen.
  static const double _headerHeight = 48;
  /// The always-visible transcribing status strip (independent of the
  /// hide/show toggle). Public so the transcript view sizes its strip to match
  /// the window's compact-height accounting.
  static const double stripHeight = 48;
  /// The bottom playback bar.
  static const double _playbackBarHeight = 64;
  /// Vertical padding so the compact window doesn't feel cramped.
  static const double _padding = 8;

  /// Height of the transcript-hidden window: header + transcribing strip +
  /// playback bar + padding.
  static const double _compactHeight =
      _headerHeight + stripHeight + _playbackBarHeight + _padding;
  /// When the transcript is shown and no explicit size was recorded, use this
  /// content height for the transcript region.
  static const double _defaultTranscriptHeight = 480;

  /// Reasonable full window size for the transcript screen (and the compare
  /// point used before collapsing).
  static const Size _transcriptSize = Size(1280, 720);

  Size? _lastSizeBeforeCompact;

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
    // Wayland compositors and some window managers ignore geometry max/min
    // hints (`GDK_HINT_MAX_SIZE` etc.), so actively re-clamp the window size
    // whenever the user resizes it. macOS/Windows honor the window-manager
    // hints directly; the clamp is still harmless there.
    windowManager.addListener(_ClampListener());
  }

  static Size _clampSize(Size size) => Size(
        size.width.clamp(minWindowSize.width, maxWindowSize.width),
        size.height.clamp(minWindowSize.height, maxWindowSize.height),
      );

  /// Called when the transcript screen mounts (a file has been opened). Makes
  /// sure the window ends up at a sensible size for the playback screen "once
  /// the media hits": a full transcript size when the transcript is shown, or
  /// a compact height (header + transcribing strip + playback bar) when it is
  /// hidden, so the window is never left at a stale/large upload layout.
  Future<void> enterTranscript({required bool transcriptVisible}) async {
    if (!_isSupported) return;
    if (transcriptVisible) {
      await _expand();
    } else {
      await _compact();
    }
  }

  /// Expands/shrinks the window to match the transcript's visibility.
  ///
  /// When [visible] is true the window returns to the size it had before being
  /// compacted (or to a default transcript size if none was recorded). When
  /// false it shrinks to the compact height — just enough for the chrome plus
  /// the always-on transcribing strip and playback bar, so no blank transcript
  /// region is shown and the status stays legible.
  Future<void> setTranscriptVisible(bool visible) async {
    if (!_isSupported) return;
    if (visible) {
      await _expand();
    } else {
      await _compact();
    }
  }

  /// Resizes the window to a reasonable default size when returning to the
  /// upload / main screen from the transcript screen.
  Future<void> leaveTranscript() async {
    if (!_isSupported) return;
    _lastSizeBeforeCompact = null;
    await windowManager.setSize(_transcriptSize, animate: true);
  }

  Future<void> _compact() async {
    final bounds = await windowManager.getBounds();
    final compactHeight =
        _compactHeight.clamp(minWindowSize.height, maxWindowSize.height);
    _lastSizeBeforeCompact = Size(bounds.width, bounds.height);
    await windowManager.setSize(
      Size(bounds.width, compactHeight),
      animate: true,
    );
  }

  Future<void> _expand() async {
    final previous = _lastSizeBeforeCompact;
    final height = previous != null
        ? previous.height.clamp(minWindowSize.height, maxWindowSize.height)
        : (_headerHeight +
                _defaultTranscriptHeight +
                _playbackBarHeight +
                _padding)
            .clamp(minWindowSize.height, maxWindowSize.height);
    // Restore the width that was recorded, or fall back to the current one,
    // clamped to the allowed range either way.
    final width = (previous?.width ?? (await windowManager.getBounds()).width)
        .clamp(minWindowSize.width, maxWindowSize.width);
    _lastSizeBeforeCompact = null;
    await windowManager.setSize(Size(width, height), animate: true);
  }
}

/// Re-imposes [WindowService]'s min/max bounds after the user resizes the
/// window, covering platforms (notably Wayland) whose compositors ignore GTK
/// geometry size hints. Only acts when the reported size is actually out of
/// bounds, so it never loops.
class _ClampListener with WindowListener {
  @override
  void onWindowResized() {
    unawaited(_clampNow());
  }

  Future<void> _clampNow() async {
    final bounds = await windowManager.getBounds();
    final clamped = WindowService._clampSize(bounds.size);
    if (clamped != bounds.size) {
      await windowManager.setSize(clamped);
    }
  }
}
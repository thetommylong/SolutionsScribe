import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_state_provider.dart';
import '../theme/app_theme.dart';
import '../utils/audio_file_utils.dart';

enum DropzoneState { idle, hover, dragOver, processing, error }

class UploadDropzone extends ConsumerStatefulWidget {
  const UploadDropzone({super.key});

  @override
  ConsumerState<UploadDropzone> createState() => _UploadDropzoneState();
}

class _UploadDropzoneState extends ConsumerState<UploadDropzone> {
  DropzoneState _state = DropzoneState.idle;
  bool _isHovered = false;
  String _errorMessage = '';

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragEntered: (detail) {
        setState(() => _state = DropzoneState.dragOver);
      },
      onDragExited: (detail) {
        setState(() {
          _state = _isHovered ? DropzoneState.hover : DropzoneState.idle;
        });
      },
      onDragDone: (detail) {
        setState(() {
          _state = DropzoneState.idle;
        });
        if (detail.files.isEmpty) {
          // Linux/Wayland: desktop_drop resolves drops through the XDG
          // FileTransfer portal. When the portal is missing/denied it fails
          // (logged as "failed to resolve portal transfer") and reports zero
          // files. Surface that so the drop doesn't silently do nothing.
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Drag & drop isn\'t available on this system — '
                'click to choose a file instead.',
              ),
            ),
          );
          return;
        }
        _handleFile(detail.files.first.path);
      },
      child: MouseRegion(
        cursor: _state == DropzoneState.dragOver
            ? SystemMouseCursors.copy
            : SystemMouseCursors.click,
        onEnter: (_) => setState(() {
          _isHovered = true;
          if (_state == DropzoneState.idle) {
            _state = DropzoneState.hover;
          }
        }),
        onExit: (_) => setState(() {
          _isHovered = false;
          if (_state == DropzoneState.hover) {
            _state = DropzoneState.idle;
          }
        }),
        child: GestureDetector(
          onTap: _state == DropzoneState.processing
              ? null
              : _pickFile,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 260,
            width: 640,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _state == DropzoneState.dragOver
                  ? mochaTeal.withValues(alpha: 0.10)
                  : _state == DropzoneState.hover
                      ? mochaSky.withValues(alpha: 0.05)
                      : mochaSurface0,
              borderRadius: BorderRadius.circular(20),
              border: _state == DropzoneState.dragOver
                  ? Border.all(color: mochaTeal, width: 2)
                  : null,
            ),
            child: _buildContent(),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    final appState = ref.watch(appStateProvider);

    // When a processing or idle dropzone is superseded by a notifier-driven
    // error/reset, prefer the authoritative app stage without mutating state
    // during build.
    final showAppError = appState.stage == AppStage.error;
    final showAppIdle =
        (appState.stage == AppStage.idle || appState.stage == AppStage.ready) &&
            _state == DropzoneState.processing;

    DropzoneState effectiveState;
    if (showAppError) {
      effectiveState = DropzoneState.error;
    } else if (showAppIdle) {
      effectiveState = DropzoneState.idle;
    } else {
      effectiveState = _state;
    }

    switch (effectiveState) {
      case DropzoneState.processing:
        final phase = appState.phase ?? 'Processing…';
        final percent = appState.percent;
        final scheme = Theme.of(context).colorScheme;
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                value: percent > 0 ? percent / 100 : null,
                strokeWidth: 4,
                color: scheme.primary,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 12),
            if (percent > 0)
              Text(
                '$percent%',
                style: TextStyle(
                  color: scheme.primary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            const SizedBox(height: 8),
            Text(
              phase,
              style: const TextStyle(
                color: mochaText,
                fontSize: 16,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        );
      case DropzoneState.error:
        final errorMessage =
            appState.errorMessage ?? _errorMessage;
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: mochaRed),
            const SizedBox(height: 12),
            const Text(
              'An error has occurred.',
              style: TextStyle(color: mochaText, fontSize: 16),
            ),
            if (errorMessage.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                errorMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: mochaSubtext0, fontSize: 12),
              ),
            ],
          ],
        );
      case DropzoneState.dragOver:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Transform.rotate(
              angle: -12 * 3.14159 / 180,
              child: Icon(Icons.upload_file, size: 52, color: mochaTeal),
            ),
            const SizedBox(height: 12),
            const Text(
              'Release to drop your file',
              style: TextStyle(
                color: mochaBlue,
                fontSize: 16,
              ),
            ),
          ],
        );
      case DropzoneState.hover:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.upload_file, size: 64, color: mochaSky),
            const SizedBox(height: 12),
            const Text(
              'Click now to choose a file',
              style: TextStyle(color: mochaText, fontSize: 16),
            ),
          ],
        );
      case DropzoneState.idle:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.upload_file, size: 64, color: mochaText),
            const SizedBox(height: 12),
            const Text(
              'Drag and drop a file, or click to choose',
              style: TextStyle(color: mochaText, fontSize: 16),
            ),
          ],
        );
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: supportedAudioExtensions.toList(),
      );
      if (result.isNotEmpty) {
        _handleFile(result.first.path!);
      }
    } catch (e) {
      _showError(e.toString());
    }
  }

  void _handleFile(String path) {
    if (!isSupportedAudioFile(path)) {
      _showError('Unsupported file type. Use MP3, WAV, or M4A.');
      return;
    }
    setState(() => _state = DropzoneState.processing);
    final name = fileNameFromPath(path);
    ref.read(appStateProvider.notifier).processFile(path, name);
  }

  void _showError(String message) {
    setState(() {
      _state = DropzoneState.error;
      _errorMessage = message;
    });
  }
}

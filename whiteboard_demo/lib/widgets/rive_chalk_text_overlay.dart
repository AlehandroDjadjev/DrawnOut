// ignore_for_file: deprecated_member_use

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:rive/rive.dart' as rive;

/// Renders chalk-style animated text using a Rive state machine.
///
/// Falls back to plain Flutter text if the Rive asset cannot be loaded.
class RiveChalkTextOverlay extends StatefulWidget {
  final String text;
  final double fontSize;
  final int replayToken;
  final bool paused;

  const RiveChalkTextOverlay({
    super.key,
    required this.text,
    required this.fontSize,
    required this.replayToken,
    this.paused = false,
  });

  @override
  State<RiveChalkTextOverlay> createState() => _RiveChalkTextOverlayState();
}

class _RiveChalkTextOverlayState extends State<RiveChalkTextOverlay> {
  static const String _assetPath = 'assets/rive/dynamic_text_animation.riv';
  static const String _preferredArtboard = 'we are plainly simple letters';
  static const String _preferredStateMachine = 'State Machine 2';

  rive.File? _riveFile;
  rive.RiveWidgetController? _riveController;

  @override
  void initState() {
    super.initState();
    _loadRive();
  }

  @override
  void didUpdateWidget(covariant RiveChalkTextOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.replayToken != oldWidget.replayToken) {
      _reloadRive();
      return;
    }

    if (widget.text != oldWidget.text) {
      _applyTextToRuns(widget.text);
    }

    if (widget.paused != oldWidget.paused) {
      final controller = _riveController;
      if (controller != null) {
        controller.active = !widget.paused;
      }
    }
  }

  Future<void> _reloadRive() async {
    _disposeRive();
    await _loadRive();
  }

  Future<void> _loadRive() async {
    try {
      final loadedFile = await rive.File.asset(
        _assetPath,
        riveFactory: rive.Factory.flutter,
      );
      if (!mounted) {
        loadedFile?.dispose();
        return;
      }
      if (loadedFile == null) {
        throw StateError('Unable to decode Rive file: $_assetPath');
      }

      final controller = _buildController(loadedFile);
      _riveFile = loadedFile;
      _riveController = controller;

      _applyTextToRuns(widget.text);
      _fireTriggerInputs();
      controller.active = !widget.paused;

      if (mounted) {
        setState(() {});
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Rive text overlay load failed: $e');
        debugPrint('$st');
      }
      if (mounted) {
        setState(() {});
      }
    }
  }

  rive.RiveWidgetController _buildController(rive.File file) {
    try {
      return rive.RiveWidgetController(
        file,
        artboardSelector: const rive.ArtboardNamed(_preferredArtboard),
        stateMachineSelector: const rive.StateMachineNamed(
          _preferredStateMachine,
        ),
      );
    } catch (_) {
      // Fallback for future asset updates where names are changed.
      return rive.RiveWidgetController(file);
    }
  }

  void _applyTextToRuns(String text) {
    final controller = _riveController;
    if (controller == null) return;

    final runs = controller.artboard.textRuns;
    if (runs.isEmpty) {
      return;
    }

    for (final run in runs) {
      try {
        run.text = text;
      } finally {
        run.dispose();
      }
    }
  }

  void _fireTriggerInputs() {
    final controller = _riveController;
    if (controller == null) return;

    for (final input in controller.stateMachine.inputs) {
      try {
        if (input is rive.TriggerInput) {
          input.fire();
        }
      } finally {
        input.dispose();
      }
    }
  }

  @override
  void dispose() {
    _disposeRive();
    super.dispose();
  }

  void _disposeRive() {
    _riveController?.dispose();
    _riveController = null;
    _riveFile?.dispose();
    _riveFile = null;
  }

  @override
  Widget build(BuildContext context) {
    if (_riveController == null) {
      return _fallbackText();
    }

    return rive.RiveWidget(
      controller: _riveController!,
      fit: rive.Fit.contain,
      alignment: Alignment.centerLeft,
    );
  }

  Widget _fallbackText() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        widget.text,
        maxLines: 1,
        overflow: TextOverflow.visible,
        style: TextStyle(
          fontSize: widget.fontSize,
          color: Colors.black,
          fontFamily: 'Schoolbell',
          fontWeight: FontWeight.w600,
          letterSpacing: 0.35,
        ),
      ),
    );
  }
}

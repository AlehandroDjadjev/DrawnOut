// widgets/debug_panel.dart
//
// Extracted debug/developer panel UI from main.dart.
// Provides sliders, buttons, and controls for the whiteboard developer view.

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

// ============================================================
// Callback types for communicating with the parent
// ============================================================

/// All the state the debug panel needs to read/display.
class DebugPanelState {
  // Busy flag
  final bool busy;

  // Image state
  final bool hasUploadedImage;
  final bool hasPlan;
  final bool hasBoard;

  // Session
  final int? sessionId;
  final bool inLive;
  final bool wantLive;

  // Vectorizer config
  final String edgeMode;
  final double blurK;
  final double cannyLo;
  final double cannyHi;
  final double dogSigma;
  final double dogK;
  final double dogThresh;
  final double epsilon;
  final double resample;
  final double minPerim;
  final bool externalOnly;
  final double worldScale;

  // Stroke shaping
  final double angleThreshold;
  final double angleWindow;
  final double smoothPasses;
  final bool mergeParallel;
  final double mergeMaxDist;
  final double minStrokeLen;
  final double minStrokePoints;

  // Playback
  final double seconds;
  final int passes;
  final double opacity;
  final double width;
  final double jitterAmp;
  final double jitterFreq;
  final bool showRasterUnder;
  final bool debugAllowUnderDiagrams;

  // Layout
  final double cfgHeading;
  final double cfgBody;
  final double cfgLineHeight;
  final double cfgGutterY;
  final double cfgIndent1;
  final double cfgIndent2;
  final double cfgIndent3;
  final double cfgMarginTop;
  final double cfgMarginRight;
  final double cfgMarginBottom;
  final double cfgMarginLeft;
  final int cfgColumnsCount;
  final double cfgColumnsGutter;

  // Centerline
  final double clThreshold;
  final double clEpsilon;
  final double clResample;
  final double clMergeFactor;
  final double clMergeMin;
  final double clMergeMax;
  final double clSmoothPasses;
  final bool preferOutlineHeadings;
  final bool sketchPreferOutline;

  // Planner limits
  final double plMaxItems;
  final double plMaxSentences;
  final double plMaxWords;

  // Tutor
  final bool tutorUseSpeed;
  final double tutorSeconds;
  final double tutorFontScale;
  final bool tutorUseFixedFont;
  final double tutorFixedFont;
  final double tutorMinFont;

  // Text
  final double textFontSize;

  const DebugPanelState({
    required this.busy,
    required this.hasUploadedImage,
    required this.hasPlan,
    required this.hasBoard,
    required this.sessionId,
    required this.inLive,
    required this.wantLive,
    required this.edgeMode,
    required this.blurK,
    required this.cannyLo,
    required this.cannyHi,
    required this.dogSigma,
    required this.dogK,
    required this.dogThresh,
    required this.epsilon,
    required this.resample,
    required this.minPerim,
    required this.externalOnly,
    required this.worldScale,
    required this.angleThreshold,
    required this.angleWindow,
    required this.smoothPasses,
    required this.mergeParallel,
    required this.mergeMaxDist,
    required this.minStrokeLen,
    required this.minStrokePoints,
    required this.seconds,
    required this.passes,
    required this.opacity,
    required this.width,
    required this.jitterAmp,
    required this.jitterFreq,
    required this.showRasterUnder,
    required this.debugAllowUnderDiagrams,
    required this.cfgHeading,
    required this.cfgBody,
    required this.cfgLineHeight,
    required this.cfgGutterY,
    required this.cfgIndent1,
    required this.cfgIndent2,
    required this.cfgIndent3,
    required this.cfgMarginTop,
    required this.cfgMarginRight,
    required this.cfgMarginBottom,
    required this.cfgMarginLeft,
    required this.cfgColumnsCount,
    required this.cfgColumnsGutter,
    required this.clThreshold,
    required this.clEpsilon,
    required this.clResample,
    required this.clMergeFactor,
    required this.clMergeMin,
    required this.clMergeMax,
    required this.clSmoothPasses,
    required this.preferOutlineHeadings,
    required this.sketchPreferOutline,
    required this.plMaxItems,
    required this.plMaxSentences,
    required this.plMaxWords,
    required this.tutorUseSpeed,
    required this.tutorSeconds,
    required this.tutorFontScale,
    required this.tutorUseFixedFont,
    required this.tutorFixedFont,
    required this.tutorMinFont,
    required this.textFontSize,
  });
}

/// All the callbacks the debug panel can trigger.
class DebugPanelCallbacks {
  // Source
  final VoidCallback onPickImage;
  final VoidCallback? onDebugInjectSketchImage;
  final VoidCallback? onDebugInjectSketchImageWithPlacement;

  // Layout
  final ValueChanged<double> onCfgHeadingChanged;
  final ValueChanged<double> onCfgBodyChanged;
  final ValueChanged<double> onCfgLineHeightChanged;
  final ValueChanged<double> onCfgGutterYChanged;
  final ValueChanged<double> onCfgIndent1Changed;
  final ValueChanged<double> onCfgIndent2Changed;
  final ValueChanged<double> onCfgIndent3Changed;
  final ValueChanged<double> onCfgMarginTopChanged;
  final ValueChanged<double> onCfgMarginRightChanged;
  final ValueChanged<double> onCfgMarginBottomChanged;
  final ValueChanged<double> onCfgMarginLeftChanged;
  final ValueChanged<int> onCfgColumnsCountChanged;
  final ValueChanged<double> onCfgColumnsGutterChanged;
  final VoidCallback onApplyLayout;
  final VoidCallback onResetCursor;

  // Planner
  final ValueChanged<double> onPlMaxItemsChanged;
  final ValueChanged<double> onPlMaxSentencesChanged;
  final ValueChanged<double> onPlMaxWordsChanged;

  // Tutor
  final ValueChanged<bool> onTutorUseSpeedChanged;
  final ValueChanged<double> onTutorSecondsChanged;
  final ValueChanged<bool> onTutorUseFixedFontChanged;
  final ValueChanged<double> onTutorFixedFontChanged;
  final ValueChanged<double> onTutorFontScaleChanged;
  final ValueChanged<double> onTutorMinFontChanged;

  // Centerline
  final ValueChanged<double> onClThresholdChanged;
  final ValueChanged<double> onClEpsilonChanged;
  final ValueChanged<double> onClResampleChanged;
  final ValueChanged<double> onClMergeFactorChanged;
  final ValueChanged<double> onClMergeMinChanged;
  final ValueChanged<double> onClMergeMaxChanged;
  final ValueChanged<double> onClSmoothPassesChanged;
  final ValueChanged<bool> onPreferOutlineHeadingsChanged;

  // Orchestrator
  final Future<void> Function(String actionsJson) onRenderActions;
  final VoidCallback onClearAndResetLayout;

  // AI Tutor
  final VoidCallback onStartLessonPipeline;
  final VoidCallback onStartSynchronizedLesson;
  final VoidCallback onStartLessonOld;
  final VoidCallback onNextSegment;
  final Future<void> Function(String question) onAskQuestion;
  final VoidCallback onRaiseHandLive;
  final VoidCallback onStopLiveAndNext;

  // Text
  final ValueChanged<double> onTextFontSizeChanged;
  final ValueChanged<bool> onSketchPreferOutlineChanged;
  final VoidCallback onSketchText;

  // Placement & Vectorization
  final VoidCallback onApplyPlacement;
  final VoidCallback onVectorizeAndSketch;
  final VoidCallback onFetchAndSketchDiagram;

  // Vectorizer config
  final ValueChanged<String> onEdgeModeChanged;
  final ValueChanged<double> onBlurKChanged;
  final ValueChanged<double> onCannyLoChanged;
  final ValueChanged<double> onCannyHiChanged;
  final ValueChanged<double> onDogSigmaChanged;
  final ValueChanged<double> onDogKChanged;
  final ValueChanged<double> onDogThreshChanged;
  final ValueChanged<double> onEpsilonChanged;
  final ValueChanged<double> onResampleChanged;
  final ValueChanged<double> onMinPerimChanged;
  final ValueChanged<bool> onExternalOnlyChanged;
  final ValueChanged<double> onWorldScaleChanged;

  // Stroke shaping
  final ValueChanged<double> onAngleThresholdChanged;
  final ValueChanged<double> onAngleWindowChanged;
  final ValueChanged<double> onSmoothPassesChanged;
  final ValueChanged<bool> onMergeParallelChanged;
  final ValueChanged<double> onMergeMaxDistChanged;
  final ValueChanged<double> onMinStrokeLenChanged;
  final ValueChanged<double> onMinStrokePointsChanged;

  // Board
  final VoidCallback onCommitCurrentSketch;
  final VoidCallback onUndoLast;
  final VoidCallback onClearBoard;

  // Playback
  final ValueChanged<double> onSecondsChanged;
  final ValueChanged<double> onWidthChanged;
  final ValueChanged<double> onPassesChanged;
  final ValueChanged<double> onOpacityChanged;
  final ValueChanged<double> onJitterAmpChanged;
  final ValueChanged<double> onJitterFreqChanged;
  final ValueChanged<bool> onShowRasterUnderChanged;
  final ValueChanged<bool> onDebugAllowUnderDiagramsChanged;
  final VoidCallback onLogSettings;

  const DebugPanelCallbacks({
    required this.onPickImage,
    this.onDebugInjectSketchImage,
    this.onDebugInjectSketchImageWithPlacement,
    required this.onCfgHeadingChanged,
    required this.onCfgBodyChanged,
    required this.onCfgLineHeightChanged,
    required this.onCfgGutterYChanged,
    required this.onCfgIndent1Changed,
    required this.onCfgIndent2Changed,
    required this.onCfgIndent3Changed,
    required this.onCfgMarginTopChanged,
    required this.onCfgMarginRightChanged,
    required this.onCfgMarginBottomChanged,
    required this.onCfgMarginLeftChanged,
    required this.onCfgColumnsCountChanged,
    required this.onCfgColumnsGutterChanged,
    required this.onApplyLayout,
    required this.onResetCursor,
    required this.onPlMaxItemsChanged,
    required this.onPlMaxSentencesChanged,
    required this.onPlMaxWordsChanged,
    required this.onTutorUseSpeedChanged,
    required this.onTutorSecondsChanged,
    required this.onTutorUseFixedFontChanged,
    required this.onTutorFixedFontChanged,
    required this.onTutorFontScaleChanged,
    required this.onTutorMinFontChanged,
    required this.onClThresholdChanged,
    required this.onClEpsilonChanged,
    required this.onClResampleChanged,
    required this.onClMergeFactorChanged,
    required this.onClMergeMinChanged,
    required this.onClMergeMaxChanged,
    required this.onClSmoothPassesChanged,
    required this.onPreferOutlineHeadingsChanged,
    required this.onRenderActions,
    required this.onClearAndResetLayout,
    required this.onStartLessonPipeline,
    required this.onStartSynchronizedLesson,
    required this.onStartLessonOld,
    required this.onNextSegment,
    required this.onAskQuestion,
    required this.onRaiseHandLive,
    required this.onStopLiveAndNext,
    required this.onTextFontSizeChanged,
    required this.onSketchPreferOutlineChanged,
    required this.onSketchText,
    required this.onApplyPlacement,
    required this.onVectorizeAndSketch,
    required this.onFetchAndSketchDiagram,
    required this.onEdgeModeChanged,
    required this.onBlurKChanged,
    required this.onCannyLoChanged,
    required this.onCannyHiChanged,
    required this.onDogSigmaChanged,
    required this.onDogKChanged,
    required this.onDogThreshChanged,
    required this.onEpsilonChanged,
    required this.onResampleChanged,
    required this.onMinPerimChanged,
    required this.onExternalOnlyChanged,
    required this.onWorldScaleChanged,
    required this.onAngleThresholdChanged,
    required this.onAngleWindowChanged,
    required this.onSmoothPassesChanged,
    required this.onMergeParallelChanged,
    required this.onMergeMaxDistChanged,
    required this.onMinStrokeLenChanged,
    required this.onMinStrokePointsChanged,
    required this.onCommitCurrentSketch,
    required this.onUndoLast,
    required this.onClearBoard,
    required this.onSecondsChanged,
    required this.onWidthChanged,
    required this.onPassesChanged,
    required this.onOpacityChanged,
    required this.onJitterAmpChanged,
    required this.onJitterFreqChanged,
    required this.onShowRasterUnderChanged,
    required this.onDebugAllowUnderDiagramsChanged,
    required this.onLogSettings,
  });
}

/// Developer debug panel for the whiteboard.
///
/// Displays all slider controls, buttons, and configuration UI.
/// Communicates changes back to parent via [DebugPanelCallbacks].
class DebugPanel extends StatelessWidget {
  final DebugPanelState state;
  final DebugPanelCallbacks callbacks;

  /// Text editing controllers managed by parent (stateful).
  final TextEditingController textCtrl;
  final TextEditingController xCtrl;
  final TextEditingController yCtrl;
  final TextEditingController wCtrl;
  final TextEditingController diagramCtrl;
  final TextEditingController actionsCtrl;
  final TextEditingController apiUrlCtrl;
  final TextEditingController questionCtrl;

  const DebugPanel({
    super.key,
    required this.state,
    required this.callbacks,
    required this.textCtrl,
    required this.xCtrl,
    required this.yCtrl,
    required this.wCtrl,
    required this.diagramCtrl,
    required this.actionsCtrl,
    required this.apiUrlCtrl,
    required this.questionCtrl,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: ListView(
        children: [
          _buildSourceSection(t),
          if (kDebugMode) _buildDebugSketchImageSection(),
          const SizedBox(height: 16),
          const Divider(height: 24),
          _buildLayoutSection(t),
          const Divider(height: 24),
          _buildPlannerLimitsSection(t),
          const Divider(height: 24),
          _buildTutorSection(t),
          const Divider(height: 24),
          _buildCenterlineSection(t),
          const Divider(height: 24),
          _buildOrchestratorSection(t),
          const Divider(height: 24),
          _buildAiTutorSection(t),
          const Divider(height: 24),
          _buildTextSection(t),
          const SizedBox(height: 16),
          _buildPlacementSection(t),
          const Divider(height: 24),
          _buildDiagramSection(t),
          const Divider(height: 24),
          _buildVectorizationSection(t),
          const Divider(height: 24),
          _buildStrokeShapingSection(t),
          const SizedBox(height: 8),
          _buildBoardActionsSection(),
          const Divider(height: 24),
          _buildPlaybackSection(t),
        ],
      ),
    );
  }

  // ============================================================
  // Section builders
  // ============================================================

  Widget _buildSourceSection(ThemeData t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Source', style: t.textTheme.titleLarge),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: state.busy ? null : callbacks.onPickImage,
              icon: const Icon(Icons.upload),
              label: const Text('Upload Image'),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _buildDebugSketchImageSection() {
    return Column(children: [
      const SizedBox(height: 8),
      Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.orange.shade300, width: 2),
          borderRadius: BorderRadius.circular(8),
          color: Colors.orange.shade50,
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.bug_report, color: Colors.orange.shade700, size: 18),
              const SizedBox(width: 4),
              Text('DEBUG: sketch_image',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade800,
                      fontSize: 12)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: state.busy ? null : callbacks.onDebugInjectSketchImage,
                  icon: const Icon(Icons.image, size: 16),
                  label: const Text('Auto-Place', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade100,
                    foregroundColor: Colors.orange.shade900,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: state.busy ? null : callbacks.onDebugInjectSketchImageWithPlacement,
                  icon: const Icon(Icons.place, size: 16),
                  label: const Text('Positioned', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade100,
                    foregroundColor: Colors.orange.shade900,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                ),
              ),
            ]),
          ],
        ),
      ),
    ]);
  }

  Widget _buildLayoutSection(ThemeData t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Orchestrator Layout', style: t.textTheme.titleLarge),
        const SizedBox(height: 8),
        _slider('Heading size', 18, 72, state.cfgHeading, callbacks.onCfgHeadingChanged),
        _slider('Body size', 14, 48, state.cfgBody, callbacks.onCfgBodyChanged),
        _slider('Line height', 1.0, 1.8, state.cfgLineHeight, callbacks.onCfgLineHeightChanged),
        _slider('Gutter Y', 4, 40, state.cfgGutterY, callbacks.onCfgGutterYChanged),
        _slider('Indent L1', 16, 120, state.cfgIndent1, callbacks.onCfgIndent1Changed),
        _slider('Indent L2', 32, 180, state.cfgIndent2, callbacks.onCfgIndent2Changed),
        _slider('Indent L3', 48, 240, state.cfgIndent3, callbacks.onCfgIndent3Changed),
        _slider('Margin Top', 0, 200, state.cfgMarginTop, callbacks.onCfgMarginTopChanged),
        _slider('Margin Right', 0, 200, state.cfgMarginRight, callbacks.onCfgMarginRightChanged),
        _slider('Margin Bottom', 0, 200, state.cfgMarginBottom, callbacks.onCfgMarginBottomChanged),
        _slider('Margin Left', 0, 200, state.cfgMarginLeft, callbacks.onCfgMarginLeftChanged),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<int>(
              value: state.cfgColumnsCount,
              items: const [
                DropdownMenuItem(value: 1, child: Text('1 column')),
                DropdownMenuItem(value: 2, child: Text('2 columns')),
              ],
              onChanged: (v) => callbacks.onCfgColumnsCountChanged(v ?? 1),
              decoration: const InputDecoration(labelText: 'Columns'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _slider('Col. gutter', 0, 120, state.cfgColumnsGutter, callbacks.onCfgColumnsGutterChanged),
          ),
        ]),
        Row(children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: state.busy ? null : callbacks.onApplyLayout,
              icon: const Icon(Icons.settings_backup_restore),
              label: const Text('Apply Layout (clear page)'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: state.busy ? null : callbacks.onResetCursor,
              icon: const Icon(Icons.vertical_align_top),
              label: const Text('Reset Cursor'),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _buildPlannerLimitsSection(ThemeData t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Planner Limits', style: t.textTheme.titleLarge),
        const SizedBox(height: 8),
        _slider('Max items per plan', 1, 5, state.plMaxItems, callbacks.onPlMaxItemsChanged,
            divisions: 4, display: (v) => v.toStringAsFixed(0)),
        _slider('Max sentences per item', 1, 3, state.plMaxSentences, callbacks.onPlMaxSentencesChanged,
            divisions: 2, display: (v) => v.toStringAsFixed(0)),
        _slider('Max words per sentence', 4, 16, state.plMaxWords, callbacks.onPlMaxWordsChanged,
            divisions: 12, display: (v) => v.toStringAsFixed(0)),
      ],
    );
  }

  Widget _buildTutorSection(ThemeData t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tutor Draw Overrides', style: t.textTheme.titleLarge),
        const SizedBox(height: 8),
        SwitchListTile(
          value: state.tutorUseSpeed,
          onChanged: callbacks.onTutorUseSpeedChanged,
          title: const Text('Override draw speed for tutor'),
          dense: true,
        ),
        _slider('Tutor total time (s)', 5, 120, state.tutorSeconds, callbacks.onTutorSecondsChanged,
            divisions: 23, display: (v) => '${v.toStringAsFixed(0)}s'),
        SwitchListTile(
          value: state.tutorUseFixedFont,
          onChanged: callbacks.onTutorUseFixedFontChanged,
          title: const Text('Use fixed font size for tutor'),
          dense: true,
        ),
        if (state.tutorUseFixedFont)
          _slider('Tutor fixed font (px)', 36, 120, state.tutorFixedFont, callbacks.onTutorFixedFontChanged,
              divisions: 84, display: (v) => v.toStringAsFixed(0))
        else
          _slider('Tutor font scale', 0.5, 2.0, state.tutorFontScale, callbacks.onTutorFontScaleChanged),
        _slider('Tutor min font (px, hard floor)', 36, 120, state.tutorMinFont, callbacks.onTutorMinFontChanged,
            divisions: 84, display: (v) => v.toStringAsFixed(0)),
      ],
    );
  }

  Widget _buildCenterlineSection(ThemeData t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Centerline (Body Text)', style: t.textTheme.titleLarge),
        const SizedBox(height: 8),
        _slider('Centerline threshold (px)', 20, 120, state.clThreshold, callbacks.onClThresholdChanged),
        _slider('Centerline epsilon', 0.3, 1.2, state.clEpsilon, callbacks.onClEpsilonChanged),
        _slider('Centerline resample', 0.5, 1.5, state.clResample, callbacks.onClResampleChanged),
        _slider('Merge factor', 0.3, 1.6, state.clMergeFactor, callbacks.onClMergeFactorChanged),
        Row(children: [
          Expanded(child: _slider('Merge min', 4, 40, state.clMergeMin, callbacks.onClMergeMinChanged)),
          const SizedBox(width: 8),
          Expanded(child: _slider('Merge max', 8, 60, state.clMergeMax, callbacks.onClMergeMaxChanged)),
        ]),
        _slider('Smooth passes', 0, 4, state.clSmoothPasses, callbacks.onClSmoothPassesChanged,
            divisions: 4, display: (v) => v.toStringAsFixed(0)),
        SwitchListTile(
          value: state.preferOutlineHeadings,
          onChanged: callbacks.onPreferOutlineHeadingsChanged,
          title: const Text('Headings keep outline (double stroke)'),
          dense: true,
        ),
      ],
    );
  }

  Widget _buildOrchestratorSection(ThemeData t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Whiteboard Orchestrator', style: t.textTheme.titleLarge),
        const SizedBox(height: 8),
        TextField(
          controller: actionsCtrl,
          maxLines: 6,
          decoration: const InputDecoration(
            labelText: 'Paste actions JSON',
            hintText: '{ "whiteboard_actions": [ {"type":"heading","text":"..."} ] }',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: state.busy
                  ? null
                  : () => callbacks.onRenderActions(actionsCtrl.text.trim()),
              icon: const Icon(Icons.playlist_add_check),
              label: const Text('Render Actions'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: state.busy ? null : callbacks.onClearAndResetLayout,
              icon: const Icon(Icons.refresh),
              label: const Text('Clear & Reset Layout'),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _buildAiTutorSection(ThemeData t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('AI Tutor', style: t.textTheme.titleLarge),
        const SizedBox(height: 8),
        TextField(
          controller: apiUrlCtrl,
          decoration: const InputDecoration(
            labelText: 'Backend URL (e.g. http://localhost:8000)',
          ),
        ),
        const SizedBox(height: 8),
        // Lesson Pipeline
        Row(children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: state.busy ? null : callbacks.onStartLessonPipeline,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('AI LESSON with Images'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple.shade700,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        // Synchronized Timeline
        Row(children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: state.busy ? null : callbacks.onStartSynchronizedLesson,
              icon: const Icon(Icons.sync),
              label: const Text('SYNCHRONIZED Lesson'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: state.busy ? null : callbacks.onStartLessonOld,
              icon: const Icon(Icons.play_circle),
              label: const Text('Start Lesson (Old)'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: state.busy || state.sessionId == null ? null : callbacks.onNextSegment,
              icon: const Icon(Icons.skip_next),
              label: const Text('Next'),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        TextField(
          controller: questionCtrl,
          decoration: const InputDecoration(labelText: 'Ask a question'),
        ),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: state.busy || state.sessionId == null
                  ? null
                  : () => callbacks.onAskQuestion(questionCtrl.text.trim()),
              icon: const Icon(Icons.record_voice_over),
              label: const Text('Ask'),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: state.busy || state.sessionId == null || state.inLive
                  ? null
                  : callbacks.onRaiseHandLive,
              icon: const Icon(Icons.back_hand),
              label: const Text('Raise Hand (Live)'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: state.busy || !state.inLive || state.sessionId == null
                  ? null
                  : callbacks.onStopLiveAndNext,
              icon: const Icon(Icons.stop_circle),
              label: const Text('Stop Live & Next'),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _buildTextSection(ThemeData t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Text', style: t.textTheme.titleLarge),
        const SizedBox(height: 8),
        TextField(
          controller: textCtrl,
          decoration: const InputDecoration(labelText: 'Enter text'),
        ),
        _slider('Font size (px)', 20.0, 400.0, state.textFontSize, callbacks.onTextFontSizeChanged),
        SwitchListTile(
          value: state.sketchPreferOutline,
          onChanged: callbacks.onSketchPreferOutlineChanged,
          title: const Text('Prefer outline for Sketch Text'),
          dense: true,
        ),
        Row(children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: state.busy ? null : callbacks.onSketchText,
              icon: const Icon(Icons.draw),
              label: const Text('Sketch Text'),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _buildPlacementSection(ThemeData t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Placement (world coords, origin center)', style: t.textTheme.titleMedium),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _numField(xCtrl, 'X')),
          const SizedBox(width: 8),
          Expanded(child: _numField(yCtrl, 'Y')),
        ]),
        const SizedBox(height: 8),
        _numField(wCtrl, 'Width'),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: state.busy || !state.hasUploadedImage ? null : callbacks.onApplyPlacement,
              icon: const Icon(Icons.my_location),
              label: const Text('Apply Placement'),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _buildDiagramSection(ThemeData t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Diagram (gpt-image-1)', style: t.textTheme.titleLarge),
        const SizedBox(height: 8),
        TextField(
          controller: diagramCtrl,
          decoration: const InputDecoration(labelText: 'Describe image (prompt)'),
        ),
        Row(children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: state.busy ? null : callbacks.onFetchAndSketchDiagram,
              icon: const Icon(Icons.image_outlined),
              label: const Text('Sketch Diagram'),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _buildVectorizationSection(ThemeData t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Vectorization', style: t.textTheme.titleLarge),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: state.edgeMode,
          items: const [
            DropdownMenuItem(value: 'Canny', child: Text('Canny')),
            DropdownMenuItem(value: 'DoG', child: Text('DoG (Difference of Gaussians)')),
          ],
          onChanged: state.busy ? null : (v) => callbacks.onEdgeModeChanged(v ?? 'Canny'),
          decoration: const InputDecoration(labelText: 'Edge Mode'),
        ),
        const SizedBox(height: 8),
        _slider('Gaussian ksize', 3, 13, state.blurK, callbacks.onBlurKChanged,
            divisions: 5, display: (v) => v.round().toString()),
        if (state.edgeMode == 'Canny') ...[
          _slider('Canny low', 10, 200, state.cannyLo, callbacks.onCannyLoChanged, divisions: 19),
          _slider('Canny high', 40, 300, state.cannyHi, callbacks.onCannyHiChanged, divisions: 26),
        ] else ...[
          _slider('DoG sigma', 0.6, 3.0, state.dogSigma, callbacks.onDogSigmaChanged),
          _slider('DoG k (sigma2 = k*sigma)', 1.2, 2.2, state.dogK, callbacks.onDogKChanged),
          _slider('DoG threshold', 1.0, 30.0, state.dogThresh, callbacks.onDogThreshChanged),
        ],
        _slider('Simplify epsilon (px)', 0.5, 6.0, state.epsilon, callbacks.onEpsilonChanged),
        _slider('Resample spacing (px)', 1.0, 6.0, state.resample, callbacks.onResampleChanged),
        _slider('Min perimeter (px)', 10.0, 300.0, state.minPerim, callbacks.onMinPerimChanged),
        _slider('World scale (px -> world)', 0.3, 3.0, state.worldScale, callbacks.onWorldScaleChanged),
        SwitchListTile(
          value: state.externalOnly,
          onChanged: state.busy ? null : callbacks.onExternalOnlyChanged,
          title: const Text('External contours only'),
          dense: true,
        ),
      ],
    );
  }

  Widget _buildStrokeShapingSection(ThemeData t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Stroke shaping', style: t.textTheme.titleLarge),
        const SizedBox(height: 8),
        _slider('Angle threshold (deg)', 0.0, 90.0, state.angleThreshold, callbacks.onAngleThresholdChanged,
            divisions: 90, display: (v) => v.toStringAsFixed(0)),
        _slider('Angle window (samples)', 1, 6, state.angleWindow, callbacks.onAngleWindowChanged,
            divisions: 5, display: (v) => v.toStringAsFixed(0)),
        _slider('Smoothing passes', 0, 3, state.smoothPasses, callbacks.onSmoothPassesChanged,
            divisions: 3, display: (v) => v.toStringAsFixed(0)),
        SwitchListTile(
          value: state.mergeParallel,
          onChanged: callbacks.onMergeParallelChanged,
          title: const Text('Merge parallel outlines'),
          dense: true,
        ),
        _slider('Merge max distance', 1.0, 12.0, state.mergeMaxDist, callbacks.onMergeMaxDistChanged),
        _slider('Min stroke length', 4.0, 60.0, state.minStrokeLen, callbacks.onMinStrokeLenChanged),
        _slider('Min stroke points', 2, 20, state.minStrokePoints, callbacks.onMinStrokePointsChanged,
            divisions: 18, display: (v) => v.toStringAsFixed(0)),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          onPressed: state.busy || !state.hasUploadedImage ? null : callbacks.onVectorizeAndSketch,
          icon: const Icon(Icons.auto_awesome),
          label: const Text('Vectorize & Draw'),
        ),
      ],
    );
  }

  Widget _buildBoardActionsSection() {
    return Column(children: [
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: state.hasPlan ? callbacks.onCommitCurrentSketch : null,
            icon: const Icon(Icons.push_pin),
            label: const Text('Commit current sketch'),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: state.hasBoard ? callbacks.onUndoLast : null,
            icon: const Icon(Icons.undo),
            label: const Text('Undo last'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: state.hasBoard ? callbacks.onClearBoard : null,
            icon: const Icon(Icons.delete_sweep),
            label: const Text('Clear board'),
          ),
        ),
      ]),
    ]);
  }

  Widget _buildPlaybackSection(ThemeData t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Playback / Texture', style: t.textTheme.titleLarge),
        const SizedBox(height: 8),
        _slider('Total time (s)', 1.0, 30.0, state.seconds, callbacks.onSecondsChanged,
            divisions: 29, display: (v) => '${v.toStringAsFixed(0)}s'),
        _slider('Base width', 0.5, 8.0, state.width, callbacks.onWidthChanged),
        _slider('Passes', 1, 4, state.passes.toDouble(), callbacks.onPassesChanged,
            divisions: 3, display: (v) => v.round().toString()),
        _slider('Pass opacity', 0.2, 1.0, state.opacity, callbacks.onOpacityChanged),
        _slider('Jitter amp', 0.0, 3.0, state.jitterAmp, callbacks.onJitterAmpChanged),
        _slider('Jitter freq', 0.005, 0.08, state.jitterFreq, callbacks.onJitterFreqChanged),
        ElevatedButton.icon(
          onPressed: callbacks.onLogSettings,
          icon: const Icon(Icons.bug_report),
          label: const Text('Log Current Settings'),
        ),
        SwitchListTile(
          value: state.showRasterUnder,
          onChanged: callbacks.onShowRasterUnderChanged,
          title: const Text('Show raster under sketch'),
          dense: true,
        ),
        SwitchListTile(
          value: state.debugAllowUnderDiagrams,
          onChanged: callbacks.onDebugAllowUnderDiagramsChanged,
          title: const Text('Debug: show raster under auto diagrams'),
          dense: true,
        ),
      ],
    );
  }

  // ============================================================
  // Shared helper widgets
  // ============================================================

  Widget _numField(TextEditingController c, String label) {
    return TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
      decoration: InputDecoration(labelText: label),
    );
  }

  Widget _slider(
    String label,
    double min,
    double max,
    double value,
    ValueChanged<double> onChanged, {
    int? divisions,
    String Function(double)? display,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(child: Text(label)),
          Text(display != null
              ? display(value)
              : value.toStringAsFixed((max - min) <= 10 ? 0 : 2)),
        ]),
        Slider(
          min: min,
          max: max,
          divisions: divisions,
          value: value.clamp(min, max),
          onChanged: onChanged,
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}

# 🐛 Complete Debug Guide - Find Why Drawing Isn't Working

## How to Debug

### Step 1: Hot Reload Flutter

```bash
# In Flutter terminal, press:
R  (capital R - hot restart)
```

### Step 2: Open Browser Console

- Press `F12` in Chrome
- Go to "Console" tab
- Clear console (trash icon)

### Step 3: Click Green Button

Click **"🎯 SYNCHRONIZED Lesson"**

### Step 4: Read Debug Output

Look for these specific messages in order:

---

## Expected Debug Output (Success Path)

```
🎬 Starting synchronized lesson...
✅ Session created: 119
⏱️ Generating timeline...
✅ Timeline generated: 8 segments, 65.2s
▶️ Starting synchronized playback...

🎬 Playing segment 0: "Let's start by understanding..."
   🎨 Triggering drawing actions...

═══════════════════════════════════════════════════
🎨 _handleSyncedDrawingActions called with 1 actions
🔍 Step 1: Ensure layout...
✅ Layout ensured: Instance of '_LayoutState'
   📄 Action: type=heading, text="PYTHAGOREAN THEOREM", level=null
✅ Converted to 1 whiteboard action maps
🔍 Current segment: seq=1, duration=4.5
⏱️ Calculated drawing duration: 4.1s
🔍 Step 2: Generating strokes via _placeBlock...
   Processing action 0: heading - PYTHAGOREAN THEOREM
   ✅ Action 0 processed, accum now has 156 strokes
✅ All strokes generated: 156 total strokes
🔍 Step 3: Setting _plan to trigger animation...
   Current _plan before: null
   Current _board.length before: 0
✅ _plan SET! New plan has 156 strokes
   _seconds = 4.1
   _plan.isEmpty = false
   Animation will run until: 2025-10-29 ...
   SketchPlayer should now be animating...
⏳ Waiting 3.9s for animation...

🖼️ RENDERING: SketchPlayer with 156 strokes, duration=4.1s
📊 Board has 0 committed objects
🖼️ RENDERING: SketchPlayer with 156 strokes, duration=4.1s
🖼️ RENDERING: SketchPlayer with 156 strokes, duration=4.1s
   ... (animation frames)

🔍 Step 4: Committing to board...
   _plan exists, calling _commitCurrentSketch()...
✅ _commitCurrentSketch() completed
   _board.length after: 1
   _plan after commit: null
═══════════════════════════════════════════════════

   ✅ Segment 0 audio completed
🎬 Playing segment 1: "The formula is..."
   ... (repeats)
```

---

## Failure Scenarios - What to Look For

### ❌ Scenario 1: No Actions Generated

```
🎨 _handleSyncedDrawingActions called with 1 actions
...
❌ ERROR: No strokes generated! accum is empty!
```

**Problem**: `_placeBlock` isn't generating strokes  
**Check**: Is `_layout` null? Are fonts too small?

---

### ❌ Scenario 2: Plan Not Set

```
✅ All strokes generated: 156 total strokes
🔍 Step 3: Setting _plan to trigger animation...
... (nothing after this)
```

**Problem**: `setState` failed or threw exception  
**Check**: Look for exception message

---

### ❌ Scenario 3: SketchPlayer Not Rendering

```
✅ _plan SET! New plan has 156 strokes
🖼️ RENDERING: No plan, showing 0 board objects
```

**Problem**: `_plan` became null immediately after setting  
**Check**: Is something clearing `_plan`?

---

### ❌ Scenario 4: Commit Failed

```
⏳ Waiting 3.9s for animation...
🔍 Step 4: Committing to board...
❌ ERROR: _plan is null! Cannot commit!
```

**Problem**: `_plan` was cleared before commit  
**Check**: Is another process setting `_plan = null`?

---

## Diagnostic Commands

### Check Current State

Add this button temporarily in the UI:

```dart
ElevatedButton(
  onPressed: () {
    debugPrint('STATE CHECK:');
    debugPrint('  _plan: $_plan');
    debugPrint('  _plan?.isEmpty: ${_plan?.isEmpty}');
    debugPrint('  _plan?.strokes.length: ${_plan?.strokes.length}');
    debugPrint('  _board.length: ${_board.length}');
    debugPrint('  _busy: $_busy');
    debugPrint('  _seconds: $_seconds');
    debugPrint('  _layout: $_layout');
  },
  child: Text('Debug State'),
)
```

### Manual Test Drawing

Try the existing "Sketch Text" button:
1. Enter text: "TEST"
2. Click "Sketch Text"
3. Does it animate? → If yes, SketchPlayer works
4. Does it stay? → If yes, commit works

---

## Common Issues

### Issue: "accum is empty"

**Cause**: `_placeBlock` failed to generate strokes

**Debug**:
```dart
// In _placeBlock, add at start:
debugPrint('_placeBlock called: type=$type, text=$text');
```

### Issue: Build method shows "No plan"

**Cause**: `_plan` is being set but immediately cleared

**Debug**: Search for all places that set `_plan = null`

### Issue: SketchPlayer shows but nothing draws

**Cause**: Strokes might be off-screen or too small

**Debug**:
```dart
// Check stroke coordinates
for (final stroke in _plan!.strokes) {
  debugPrint('Stroke: ${stroke.length} points');
  if (stroke.isNotEmpty) {
    debugPrint('  First point: ${stroke.first}');
    debugPrint('  Last point: ${stroke.last}');
  }
}
```

---

## What to Share

After running with debug, share:

1. **Full console output** from clicking button until first segment plays
2. **Specific error messages** if any
3. **Which scenario** from above matches your output
4. **Does "Sketch Text" button work?** (to verify SketchPlayer works)

---

## Nuclear Option - Test Minimal Case

If still not working, test with hardcoded data:

```dart
Future<void> _testMinimalDraw() async {
  await _ensureLayout();
  
  final accum = <List<Offset>>[];
  await _placeBlock(
    _layout!,
    type: 'heading',
    text: 'TEST DRAW',
    level: 1,
    style: null,
    accum: accum,
    fontScale: 1.0,
  );
  
  debugPrint('Test: Generated ${accum.length} strokes');
  
  if (accum.isNotEmpty) {
    setState(() {
      _seconds = 3.0;
      _plan = StrokePlan(accum);
    });
    
    debugPrint('Test: Plan set, should animate now');
    
    await Future.delayed(Duration(seconds: 3));
    _commitCurrentSketch();
    
    debugPrint('Test: Committed to board, length=${_board.length}');
  }
}
```

Add button:
```dart
ElevatedButton(
  onPressed: _testMinimalDraw,
  child: Text('TEST MINIMAL DRAW'),
)
```

---

**Run with this debug output and share what you see!** 🔍




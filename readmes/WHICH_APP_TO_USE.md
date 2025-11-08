# Which Flutter App Should I Use?

## ⚠️ Important: Two Separate Flutter Apps

Your repository has **TWO different Flutter applications**:

### 1. `whiteboard_demo/` ✅ (Use This One!)

**Location**: `DrawnOut/whiteboard_demo/`

**Features**:
- ✅ Full synchronized timeline system (NEW!)
- ✅ Green "🎯 SYNCHRONIZED Lesson" button
- ✅ Advanced whiteboard with vectorization
- ✅ Image upload and sketching
- ✅ Diagram generation
- ✅ Live Gemini integration
- ✅ Orchestrator layout system

**To Run**:
```bash
cd DrawnOut/whiteboard_demo
flutter run -d chrome
```

**This is the app with all the synchronized timeline features!**

---

### 2. `frontend/` ⚠️ (Older App)

**Location**: `DrawnOut/frontend/`

**Features**:
- ❌ No synchronized timeline
- Basic lesson page
- Simpler structure
- Older codebase

**Status**: This app has import errors because it's using old class names and doesn't have the timeline system.

**To Run** (after fixing):
```bash
cd DrawnOut/frontend
flutter run -d chrome
```

---

## 🎯 Recommendation

**Use `whiteboard_demo/`** - This is where all the synchronized timeline work was implemented!

The synchronized timeline system with perfect speech-drawing synchronization is **ONLY** in the `whiteboard_demo` app.

---

## Error You're Seeing

The error occurs because you're trying to run the `frontend` app, which:
1. Doesn't have the timeline system
2. Has outdated imports
3. Missing helper classes

---

## Quick Fix

Run the correct app:

```bash
cd DrawnOut/whiteboard_demo
flutter run -d chrome
```

Then click the green **"🎯 SYNCHRONIZED Lesson"** button!

---

## If You Need Both Apps

If you want both apps to have the timeline feature, I can:
1. Copy the timeline implementation to the `frontend` app
2. Fix the import errors
3. Add the synchronized lesson button there too

Just let me know!




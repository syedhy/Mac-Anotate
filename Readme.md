# Mac Annotate 🎨

Mac Annotate is a native macOS application that turns your entire screen into an interactive whiteboard. Whether you're presenting, recording a tutorial, or just brainstorming, Mac Annotate lets you draw over any window seamlessly. 

Designed with a playful, hand-drawn "doodle" aesthetic and engineered for extreme performance, it's the perfect tool for educators, developers, and designers.

## ✨ Features

- **Draw Over Everything:** A completely transparent overlay that sits above all your windows, allowing you to annotate live over any application.
- **Beautiful Doodle Aesthetic:** Strokes are rendered using variable width algorithms and Chaikin smoothing, giving everything a natural, organic hand-drawn feel. 
- **Disappearing Laser Pointer:** Highlight important areas during a presentation with a laser pointer that automatically fades away after a few seconds.
- **Rich Native Colors:** Fully integrated with the native macOS Color Panel for a seamless experience when picking custom colors.
- **High Performance:** Built entirely with AppKit and CoreGraphics. Utilizes an intelligent Bezier path caching system and fast-path bounds checking to maintain a buttery smooth 60fps, even with thousands of active annotations on screen.
- **Comprehensive Toolset:**
  - Pen Tool 
  - Arrows & Lines
  - Hollow, Translucent, and Filled Rectangles & Ovals
  - Text Annotations
  - Marquee Selection Tool

## 🚀 Performance Optimizations
Under the hood, Mac Annotate handles intensive spline generation algorithms dynamically. To prevent lag spikes, the rendering engine uses a struct-versioning mechanism that caches `NSBezierPath` generations per-stroke. Hit testing also utilizes optimized bounding-box calculations to avoid expensive geometry math, ensuring the app remains lightweight and snappy no matter how much ink is on the screen.

## 🛠 Installation
1. Clone the repository: `git clone https://github.com/syedhy/Mac-Anotate.git`
2. Open `Mac Annotate.xcodeproj` in Xcode.
3. Build and Run (`Cmd + R`).

*Note: Requires macOS 13.0 or later.*

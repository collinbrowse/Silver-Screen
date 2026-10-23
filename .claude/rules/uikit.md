---
paths:
  - "SilverScreen/**/*.swift"
---

# No UIKit screens

The app UI is SwiftUI. Do not add `UIViewController` subclasses, `UIViewRepresentable` lists, or a UIKit navigation stack.

`AppDelegate` and `SceneDelegate` stay UIKit because iOS requires them. The window's root is a `UIHostingController`. `ImageLoader` may use `UIImage` for decode and cache. Feature screens do not.

Navigation is `NavigationStack` plus `Route`. Views push routes. They do not construct destination view controllers.

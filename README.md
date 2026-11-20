# Usage Shelf

A Mac menu bar app that shows your Claude usage (5-hour and weekly) in one icon, with a notch shelf (Top Shelf) built in.

Usage Shelf is John Hesch's own version of Claude Usage Tracker by Hamed Elfayome (MIT license, v3.3.0). The original license is kept in `LICENSE`.

## What is different from the original

- One menu bar icon with both numbers (ring inside a ring).
- Top Shelf replaces the original notch display.
- No update feed, no usage ping, no support reminders, no GitHub lookups. The app only talks to Claude and to the weather service Top Shelf uses.
- Screenshots: new screenshots are named on the Mac with Apple Intelligence and shrunk, copied pictures are shrunk, and screenshots can be moved off the Desktop (Settings > Screenshots).

## Third-party code

Shrinking uses libimagequant 2.18.0, pngquant's engine, by Kornel Lesiński (GPL v3 or later), source: https://github.com/ImageOptim/libimagequant/tree/2.18.0. Its licence is in `Claude Usage/TopShelf/PNGShrink/libimagequant/libimagequant-LICENSE.txt` and ships inside the app. Because it is GPL, builds of Usage Shelf that include it are distributed under the GPL v3; the rest of the code stays MIT.

## Build

Open `Claude Usage.xcodeproj` in Xcode and build the `Claude Usage` scheme. The product is `Usage Shelf.app`.

On first launch under this name, the app copies settings and history from the earlier "Claude Usage" identity (it never deletes the old data).

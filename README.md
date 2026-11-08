# Usage Shelf

A Mac menu bar app that shows your Claude usage (5-hour and weekly) in one icon, with a notch shelf (Top Shelf) built in.

Usage Shelf is John Hesch's own version of Claude Usage Tracker by Hamed Elfayome (MIT license, v3.3.0). The original license is kept in `LICENSE`.

## What is different from the original

- One menu bar icon with both numbers (ring inside a ring).
- Top Shelf replaces the original notch display.
- No update feed, no usage ping, no support reminders, no GitHub lookups. The app only talks to Claude and to the weather service Top Shelf uses.

## Build

Open `Claude Usage.xcodeproj` in Xcode and build the `Claude Usage` scheme. The product is `Usage Shelf.app`.

On first launch under this name, the app copies settings and history from the earlier "Claude Usage" identity (it never deletes the old data).

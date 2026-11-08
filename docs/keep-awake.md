# Keep awake in Usage Shelf

Approved by John on 2026-11-05:
- Mockup: "Approved"
- Build: "Build everything in the Keep awake mockup."

Source mockup and numbered acceptance checks: `/workspace/usage-tracker/keep-awake-spec.md` and `/workspace/usage-tracker/mockups/keep-awake.html` on the agent box.

Implemented on the `keep-awake` branch from `usage-shelf` at 99ddbdf. The app uses an IOPMAssertion owned by its process, so macOS releases it when the process exits. Manual stop, timer expiry, battery cutoff, and lock all release it. Unlock resumes the remaining time.

The pointer option defaults off and never requests permission at launch. If Accessibility is already granted it can move the pointer slightly. Otherwise the setting stays off and the Settings page offers to open the Accessibility pane. No Mac System Settings are changed.

English strings are in the views directly; the other app languages use this English UI. A global Keep awake shortcut is a separate idea and is not included.

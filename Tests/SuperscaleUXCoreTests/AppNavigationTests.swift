// ABOUTME: Records the removal of GUI mode navigation, which #87 deleted with the four modes.
// ABOUTME: Retained so RT-70.4 and RT-70.5 are visibly superseded rather than silently dropped.

// 🚫 RT-70.4 and RT-70.5, removed by #87. Their identifiers are not reused.
//
// Both exercised `AppNavigation` and `AppMode`, which modelled Upscale, Generate, History and
// Settings as peer surfaces. Section 3.9 of the implementation guide removes that framing: there
// is one workspace, Settings is a `Settings` scene, and prior sessions reach the user through the
// File menu. `AppMode` is deleted rather than reduced to a single case, because a mode
// enumeration with one case is an invitation to add a second.
//
// This is superseded behaviour, not violated behaviour. What replaces it is covered by AC87.1,
// AC87.3 and AC87.9, whose tests assert that no mode list exists, that Settings opens as a scene,
// and that recent sessions are reachable from the File menu.

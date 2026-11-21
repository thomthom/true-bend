# Development tools

## Debugging in SketchUp from VSCode

`debug-sketchup.rb`, `su_debug_bootstrap.rb` and `irb_stub/` are copied unchanged
from the [SketchUp VSCode example project][example] (commit `e13ba9d`). They
launch SketchUp with the `debug` gem's server running, so VSCode can attach with
the Ruby LSP extension:

1. Run the *Launch SketchUp for debugging* task and pick a version.
2. Start the *Attach to SketchUp* launch configuration (<kbd>F5</kbd>).

This needs SketchUp 2024 or newer, the oldest version that bundles the `debug`
gem. The `DEBUGGING.md` the scripts refer to is [the example project's][guide];
it explains how the setup works and how to debug extension startup.

[example]: https://github.com/SketchUp/sketchup-extension-vscode-project
[guide]: https://github.com/SketchUp/sketchup-extension-vscode-project/blob/main/DEBUGGING.md

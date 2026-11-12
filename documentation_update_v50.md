# Version 50

The window manager gains workspaces, a movable bar, touch assist and remote monitor scaling. A fresh v50 looks and behaves like v49 until an option is changed.

## Quick switch

**Settings → Appearance → Desktop → Preset: Tiling bar** sets the bar to the top, centres the clock and enables four workspaces. **Preset: Classic** returns to the bottom bar with one workspace.

## Workspaces

Each monitor shows one workspace at a time. Choose 1 to 9 under **Desktop → Workspaces**.

- The bar starts with one coloured stroke per workspace and no numbers. A solid block is the current workspace, `=` has windows, `-` is empty.
- Colours in order: red, orange, yellow, lime, cyan, blue, purple, magenta, white.
- Tap a stroke to switch. New windows open on the visible workspace.
- Apps keep running while their windows are on a hidden workspace.
- To send a window elsewhere, tap its `#` layout button, then **Workspace** and a number.
- Lowering the count folds higher workspaces into the last one, so no window is lost.
- Window Presets store each window's workspace.

## Bar

| Option | Values |
| --- | --- |
| Bar | Bottom or Top |
| Clock | Right, or Centre with window tabs on both sides |

Order from the left: workspace strokes, the `[+]` launcher, window tabs, clock. The launcher menu opens beside its button, below a top bar. Fullscreen apps still use every row.

## Touch assist

A tap on empty space selects a control when exactly one enabled control touches that cell's edge. Taps between two controls, diagonal misses and taps on a disabled control stay misses. It applies to app screens, Settings and the bar, and can be switched off under **Desktop → Touch assist**. Per-monitor calibration (`clients_monitor_client.lua calibrate`) is unchanged and still the fix for a constant offset.

## Monitor scaling

**Settings → Appearance → Monitors → [monitor]** shows the size in characters and the text scale. **Text -** and **Text +** change it in steps of 0.5 between 0.5 and 5. The monitor computer applies the scale, saves it per side in `configs_monitor.txt` and reports its new size. This needs the v50 monitor client; older clients show "update monitor client".

## Install from v49

Replace your installer paste with the v50 `install.lua`.

```text
Central computer:   cd /   inst server   reboot
Monitor computers:  cd /   inst monitor  reboot
```

Apps, IO, sensor and relay clients need no update.

## Changed and added files

| Area | Files |
| --- | --- |
| OS and shared UI | `main_os.lua`, `lib_desktop.lua`, `lib_gui.lua`, `lib_server.lua`, `lib_settings.lua` |
| Monitor client | `lib_monitor.lua`, `clients_monitor_client.lua` |
| Installer | `install.lua`, `tools_build_installer.py` |
| Tests | `tests_v50.lua`, `tests_run.lua`, `tests_work.lua` |
| Documentation | `README.md`, `documentation_api.md`, `documentation_file_map.md`, `documentation_menu_tree.md`, `documentation_menu_tree.pdf`, `documentation_update_v50.md` |

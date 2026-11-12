# Version 49

This release lives in the fork [vsvito420/TekkitLite_SmartHome](https://github.com/vsvito420/TekkitLite_SmartHome). It is based on [DJDarkMatter/Tekkit-Lite-Smart-Home-V2](https://github.com/DJDarkMatter/Tekkit-Lite-Smart-Home-V2) bundled-v48 and keeps all of its v47 and v48 changes.

## One-command setup

```text
pastebin get CODE inst        (on every computer)
inst monitor --startup        (monitor computers, then reboot)
inst io --startup             (IO computers, then reboot)
inst server --startup --apps  (central computer, then reboot)
```

`--apps` installs the OS and then every app in the catalog. It is accepted for the `server` role only. Without HTTP the OS is installed and the apps are skipped.

## App loader and store

| Command | Result |
| --- | --- |
| `inst apps` | Installs every catalog app. |
| `inst apps clock notes` | Installs the named apps. Names are not case sensitive. |
| `inst apps --ref BRANCH` | Uses another branch or commit. |
| `inst store` | Lists the catalog with `[x]` for installed apps and asks for numbers, names, `all` or `new`. |
| `inst list` | Prints the catalog. Works on any computer. |
| `inst remove NAME` | Disables the app and moves its code to `apps_NAME.lua.pre_update`. Saved app data stays. |

Apps install one at a time. A failed download is reported and the remaining apps continue; the last line prints a retry command for the failures. An app whose code is already identical is left untouched. Settings are written once at the end.

The catalog is `apps_catalog.txt` in the repository root. A copy is bundled into `install.lua` for offline use, and `inst store`, `inst list` and `inst apps` read the newer GitHub copy when HTTP works. To publish a new app, add `apps_NAME.lua` and one catalog line, then run `python3 tools_build_installer.py`.

The repository is set in one place: `local repo` in the runner section of `tools_build_installer.py`.

## Pastebin sharing

| Command | Result |
| --- | --- |
| `inst share NAME` | Uploads `apps_NAME.lua` with the built-in `pastebin put`. Install it elsewhere with `inst app NAME CODE`. |
| `inst backup` | Writes `smarthome_backup.txt` and uploads it. Contains every `configs_*.txt` of this computer and the names of installed apps. |
| `inst backup --apps` | Also embeds the app code. Pastebin accepts up to 512 KB, so large sets need `--local`. |
| `inst backup --local` | Writes the file without uploading. |
| `inst restore CODE` | Downloads a backup, restores its files and reloads missing apps from GitHub. |
| `inst restore --file PATH` | Restores from a local file, for example from a disk drive. |

Backups work on every role. `configs_transport.txt` is never included, since its boot counter must keep counting upwards on each computer. Restore accepts only `configs_*.txt` and `apps_*.lua` targets, checks all files before writing and keeps replaced files as `*.pre_update`. Anyone who has the Pastebin code can read the backup, including the network ID.

**Settings → App data → Backup & restore** remains the in-OS backup for app data on the same computer.

## Net Scope

The new optional app shows SmartHome packets. See [Net Scope](documentation_net_scope.md). It needs the v49 central OS.

## Install from v48 or older

Replace your installer paste with the v49 `install.lua`, then on the central computer:

```text
cd /
inst server
inst apps
reboot
```

IO, monitor, sensor and relay clients on v48 need no update.

## Removed files

`apps_level_emitter.lua`, `documentation_level_emitter.md` and `tests_level_emitter.lua` are gone, as the v46 notes requested.

## Changed and added files

| Area | Files |
| --- | --- |
| Apps | `apps_net_scope.lua`, `apps_catalog.txt` |
| OS and installer | `lib_network.lua`, `lib_server.lua`, `main_os.lua`, `tools_build_installer.py`, `tools_install_github.lua`, `install.lua` |
| Tests | `tests_v49.lua`, `tests_run.lua`, `tests_work.lua` |
| Documentation | `README.md`, `documentation_api.md`, `documentation_file_map.md`, `documentation_net_scope.md`, `documentation_menu_tree.md`, `documentation_menu_tree.pdf`, `documentation_update_v49.md` |

# autolinux

Rebuilds my Ubuntu workstation: **Ubuntu 25.10, GNOME 49 on Wayland**, with Ringboard, Tiling Shell, kitty and the usual apps. Every piece is a small module that checks the live system first, so re-running is always safe. You can pick modules from a checklist or drive everything with flags.

```bash
git clone https://github.com/zudsniper/autolinux && cd autolinux
sudo ./install.sh --dry-run     # what's missing on this machine? (changes nothing)
sudo ./install.sh               # checklist, full profile preselected
```

There are two entry points:

| Script | Use it when |
|---|---|
| [`install.sh`](install.sh) | You're already on GNOME and want the apps, desktop setup and tools. |
| [`bootstrap.sh`](#bootstrapsh-xubuntu--gnome-migration) | You're starting from **Xubuntu** (or a fresh install) and want the full migration: snapshot, package holds, GNOME stack, reboot/resume, Xfce cleanup, system config, then the same modules. |

## Kitty config only

One line, no clone:

```bash
curl -fsSL https://raw.githubusercontent.com/zudsniper/autolinux/master/kitty/install.sh | bash
```

What you get ([`kitty/kitty.conf`](kitty/kitty.conf), [`kitty/window_title_bar.py`](kitty/window_title_bar.py)):
- **No GNOME titlebar.** The OS titlebar is hidden (resize shadows stay). Move windows with **Super+drag**. The active split's title bar shows a gray `super + drag to move` reminder in its right corner.
- **VSCode-style title strip** above every split, lone windows included. The active split gets a blue `●` and a bold title.
- **Tab bar** that only shows once a second tab exists.
- **Splits layout**: `F5` hsplit, `F6` vsplit, `F7` rotate, `Shift+arrows` move a split, `Ctrl+Shift+[`/`]` cycle splits, `Ctrl+Alt+T` rename a split, `Ctrl+Shift+Alt+T` rename a tab.
- Fixed 1500×900 starting window size.

The installer backs up any file it replaces to `<name>.bak-<timestamp>` and live-reloads running kitty windows. It needs **kitty ≥ 0.46**. Distro packages are older, so use the [official installer](https://sw.kovidgoyal.net/kitty/binary/) (the `kitty` module does this for you).

## `install.sh`

```bash
sudo ./install.sh                              # checklist (default in a terminal)
sudo ./install.sh --yes                        # full profile, no questions
sudo ./install.sh --profile minimal --yes      # the essentials only
sudo ./install.sh --only ringboard,kitty       # just these (dependencies are added)
sudo ./install.sh --with portainer --without steam,obs --yes
sudo ./install.sh --without hardware --yes     # groups work anywhere a module name does
sudo ./install.sh --dry-run                    # report only
./install.sh --list-modules                    # the table below, from the source
```

Environment overrides go *after* `sudo` (it drops your environment): `sudo AUTOLINUX_UFW_ENABLE=1 RINGBOARD_VERSION=0.15.0 ./install.sh`.

Selection is applied in order: profile (or `--only`), then `--with`, then `--without`, then the checklist if you're interactive. Dependencies (for example `ringboard` → `rust`) are always added back. Logs and a status file go to `/var/log/autolinux/`.

### Modules

| Group | Module | Profiles | What it does |
|---|---|---|---|
| core | `base-packages` | minimal, full | CLI tools, build essentials, btop/nvtop, runtime libs |
| core | `flatpak` | minimal, full | Flatpak, Flathub, Flatseal |
| core | `rust` | minimal, full | rustup, **stable** toolchain (per user) |
| desktop | `kitty` | minimal, full | Official kitty build plus the config above |
| desktop | **`ringboard`** | minimal, full | Ringboard clipboard manager, see below |
| desktop | `gnome-extensions` | minimal, full | Tiling Shell, Hide Topbar, Clipboard Indicator, plus Tiling Shell layout/gaps |
| desktop | `desktop-settings` | minimal, full | Dark mode, pink accent, Yaru-dark icons, flat mouse, dock size and favorites |
| desktop | `flameshot` | full | Flameshot on `Print` (GNOME's screenshot keys cleared) plus autostart |
| desktop | `normcap` | opt-in | NormCap OCR on `Ctrl+Super+Alt+O` |
| desktop | `kitty-monitor` | opt-in | Opens kitty with btop \| nvtop at login |
| apps | `chrome`, `1password` | minimal, full | Google Chrome, 1Password desktop + CLI |
| apps | `signal`, `discord`, `spotify`, `localsend`, `rustdesk`, `steam`, `obs`, `kate`, `vlc`, `transmission`, `claude-desktop` | full | The rest of the desktop apps (flatpaks where that's how they're installed here) |
| dev | `vscode`, `gh`, `nvm` | minimal, full | VS Code, GitHub CLI, nvm + Node LTS |
| dev | `cursor`, `docker`, `pyenv`, `uv`, `claude-code`, `cloudflared`, `virtualization` | full | Editors, containers, Python tooling, Claude Code, Cloudflare Tunnel, QEMU/libvirt |
| dev | `portainer` | opt-in | Portainer CE container |
| security | `ufw`, `timeshift` | minimal, full | UFW (installed; enabled only with `AUTOLINUX_UFW_ENABLE=1`), Timeshift |
| security | `yubikey`, `openvpn`, `kleopatra` | full | ykman, pcscd, age + age-plugin-yubikey; OpenVPN; Kleopatra |
| hardware | `ckb-next`, `piper` | full | Corsair and gaming-mouse drivers |
| extras | `notify-services` | opt-in | Discord startup ping + disk monitor (gists; needs a webhook) |

### Ringboard

[Ringboard](https://github.com/SUPERCILEX/clipboard-history) mirrors upstream's `install-with-cargo-systemd.sh`, but it's pinned (`RINGBOARD_VERSION`, default `0.15.0`), runs as you from a sudo context, and never pipes a remote script into bash.

- Builds `clipboard-history-server`, the CLI, `-egui` and a watcher with **stable** Rust.
- **Watcher:** GNOME doesn't implement the Wayland data-control protocol, so on GNOME the **X11 watcher** is used even under Wayland. It works through XWayland, exactly like the reference machine. Other Wayland compositors are probed with `wayland-interface-check`, same as upstream.
- Installs the upstream `ringboard-server`, `ringboard-x11`/`-wayland` and `ringboard.slice` systemd **user** units, enables them, and starts them.
- Launcher plus the `Ctrl+Super+Alt+V` → `ringboard-egui toggle` shortcut (`RINGBOARD_SHORTCUT` to change it). Your existing custom shortcuts are kept.

### GNOME extensions

Extensions are installed as **stable releases from extensions.gnome.org** for your GNOME version. There are no git/npm builds anymore. The module also drops stale entries left by older versions (`hidetopbar@mathieu.bidon.ca`, `unite@hardpixel.eu`) and disables Ubuntu's Tiling Assistant, which fights Tiling Shell. On Wayland, newly installed extensions load at your next login.

Tiling Shell's layouts, gaps and snap-assist setting live in [`dconf/tilingshell.ini`](dconf/tilingshell.ini). Desktop settings live in [`dconf/desktop.ini`](dconf/desktop.ini).

### Refreshing the repo from a machine

```bash
./tools/profile.sh                  # Markdown report: extensions, flatpaks, apt repos, cargo, units, shortcuts
./tools/profile.sh --update-dconf   # also re-capture dconf/tilingshell.ini
sudo ./install.sh --dry-run         # anything the modules don't detect yet
```

### Adding a module

Create `modules/<name>.sh` and add `<name>` to `MODULE_ORDER` in [`lib/modules.sh`](lib/modules.sh), after its dependencies:

```bash
# shellcheck shell=bash
# shellcheck disable=SC2034  # MOD_* metadata is read by lib/modules.sh
MOD_DESC="What it installs"
MOD_GROUP="apps"               # core | desktop | apps | dev | security | hardware | extras
MOD_PROFILES="full"            # "" = opt-in only
MOD_DEPENDS="flatpak"          # optional
mod_detect()  { is_flatpak_installed org.example.App; }   # read-only!
mod_install() { flatpak_install org.example.App; }
```

Helpers: `apt_install`, `apt_add_repo`, `flatpak_install`, `deb_install_url` ([`lib/pkg.sh`](lib/pkg.sh)); `as_user`, `as_user_sh`, `user_dconf_load`, `gnome_add_keybinding` ([`lib/user.sh`](lib/user.sh)). `--dry-run` never calls `mod_install`.

## `bootstrap.sh` (Xubuntu → GNOME migration)

> **⚠️ The migration stages (04–07) are UNTESTED ON REAL HARDWARE.** They've only run under `--dry-run` and the unit tests. Test in a VM first.

`bootstrap.sh` runs 16 ordered stages with checkpoints in `/var/lib/autolinux/state.json`. Stages that need a reboot arm a resume hook (autostart `.desktop` + systemd unit) so the next login picks up where it left off. Every stage detects "already satisfied" from the live system, so on a box that's already on GNOME it skips straight to the cleanup and module stages.

```bash
sudo ./bootstrap.sh --dry-run        # show what would happen, change nothing
sudo ./bootstrap.sh                  # run pending stages (module checklist first)
sudo ./bootstrap.sh --yes --profile minimal --without steam
sudo ./bootstrap.sh --status         # state machine + per-stage status
sudo ./bootstrap.sh --list-stages
sudo ./bootstrap.sh --only 08-remove-xfce
sudo ./bootstrap.sh --from 10-system-config
sudo ./bootstrap.sh --force-replay 03-detect-starting-de
sudo ./bootstrap.sh --rollback       # release holds, remove resume hooks, list snapshots
```

The module selection (`--profile`, `--modules`, `--with`, `--without`, `-i`) is saved in `state.json`, so a resume after reboot reuses it.

| # | Stage | Reboots? |
|---|---|---|
| 00 | preflight (Ubuntu? dpkg sane? no pending upgrades? network?) | no |
| 01 | timeshift snapshot tagged `autolinux-pre-migration` | no |
| 02 | `apt-mark hold` ubuntu-desktop, gdm3, gnome-shell, kernel, GRUB, shim | no |
| 03 | record starting DE / DM / session type | no |
| 04 | install the GNOME stack | no |
| 05 | switch the default display manager to gdm3 | no |
| 06 | arm resume hook + reboot, **only if** the running DE isn't GNOME | **yes** |
| 07 | confirm the GNOME session is active | no |
| 08 | purge xfce4/xubuntu/lightdm packages (computed live; GNOME deps excluded) | no |
| 09 | archive `~/.config/xfce4/` | no |
| 10 | `system_config.sh`: swap, Wake-on-LAN/static IP, SSH, passwordless sudo, re-enables Wayland if an old run disabled it | no |
| 11 | app/dev/desktop modules | no |
| 12 | `desktop-settings` module | no |
| 13 | `gnome-extensions` module | no |
| 14 | release the stage-02 package holds | no |
| 15 | remove resume hooks, summary | no |

Safety: XFCE is never purged from inside an XFCE session. Packages are held before any purge, and the purge set is computed rather than taken from a static list. Bootloader integrity is checked before every reboot, state writes are atomic, and `--dry-run` prints every mutating command instead of running it.

## Wayland

Nothing here forces Xorg anymore. If an older autolinux run left `WaylandEnable=false` in `/etc/gdm3/custom.conf`, `system_config.sh` comments it out (with a timestamped backup), and Wayland returns at the next login.

## Warnings

- `system_config.sh --yes` enables **Wake-on-LAN** (wired NICs only) and a **static IP derived from the router's subnet**: it reads the default route (e.g. `192.168.50.1/24`) and picks host `.69` in that subnet, falling back to the current DHCP lease if `.69` is taken. On desktops it's applied to the active NetworkManager connection (old settings saved under `/var/backups/autolinux-nm-*`, undo command printed); without NetworkManager it writes `/etc/netplan/60-autolinux-static.yaml`. Override with `sudo AUTOLINUX_STATIC_IP=no|<addr> AUTOLINUX_STATIC_HOST=<n> AUTOLINUX_DNS="…" ./system_config.sh`. Reserve the address in the router's DHCP settings.
- It also gives the invoking user **passwordless sudo** (`/etc/sudoers.d/<user>`).
- `relink_home.sh` moves `/home` to `/home.bak` when re-attaching an existing home partition.
- A broken desktop after extension changes: `gsettings set org.gnome.shell disable-user-extensions true` (or `./reset_gnome_extensions.sh`).

## Other scripts

- [`headless/`](headless/README.md): server/SSH-only variant.
- `relink_home.sh`: reuse an existing `/home` partition after a reinstall (UID matching, fstab, backups).
- `add_rustdesk_autostart.sh`: optional RustDesk autostart.
- `app_install.sh`, `desktop_config.sh`, `gnome_extensions.sh`: kept as thin wrappers around `install.sh`.

## Tests

```bash
./tests/modules.sh         # module contracts, selection, dry-run safety, stage filters, CLI
./tests/net.sh             # static-IP derivation from the router subnet
./tests/state-machine.sh   # state.json, detect helpers, bootstrap CLI
```

Validation so far is shellcheck, both suites, and `--dry-run` on the reference machine (every module detects as set up). A full fresh install hasn't been run in a VM yet.

## License

MIT

# autolinux

Rebuilds my Ubuntu workstation: **Ubuntu 25.10, GNOME 49 on Wayland**, with Ringboard, Tiling Shell, kitty and the usual apps. Every piece is a small module that checks the live system first, so re-running is always safe. You can pick modules from a checklist or drive everything with flags.

## Quick install (one line)

> **Needs `curl`.** A fresh Ubuntu install may not have it, so run this first:
> ```bash
> sudo apt update && sudo apt install -y curl
> ```

Each line downloads the repo to `~/.local/share/autolinux` (no git needed) and runs [`install.sh`](#installsh) with sudo. It checks what's already installed first, lists those modules as **already installed**, and installs only the rest.

**Everything** (the `full` profile):
```bash
curl -fsSL https://raw.githubusercontent.com/zudsniper/autolinux/master/get.sh | bash -s -- --yes
```

**Just the shell + terminal basics** (`~/.bashrc`, kitty + `kitty.conf`, `curl`, `jq`, `git`, `gh`):
```bash
curl -fsSL https://raw.githubusercontent.com/zudsniper/autolinux/master/get.sh | bash -s -- --only bashrc,kitty,gh --yes
```

**Everything except GNOME extensions**:
```bash
curl -fsSL https://raw.githubusercontent.com/zudsniper/autolinux/master/get.sh | bash -s -- --without gnome-extensions --yes
```

**What's already installed?** (`--doctor`, changes nothing):
```bash
curl -fsSL https://raw.githubusercontent.com/zudsniper/autolinux/master/get.sh | bash -s -- --doctor
```

Notes:
- Drop `--yes` to get the checklist instead. The one-liner hands `install.sh` your terminal, so the checklist works.
- Any `install.sh` flag works after `bash -s --`, for example `--dry-run` or `--with portainer`.
- `curl`, `git` and `jq` come from the `essentials` module. It always runs first because the other modules need it.
- The full profile leaves out the opt-in modules (`normcap`, `kitty-monitor`, `portainer`, `notify-services`). Add them with `--with`.
- To install from a branch or tag instead of `master`, put `AUTOLINUX_REF=<ref>` in front of `bash`: `curl ... | AUTOLINUX_REF=<ref> bash -s -- ...`.

From a clone instead:

```bash
git clone https://github.com/zudsniper/autolinux && cd autolinux
./install.sh --doctor           # what's already installed? (changes nothing)
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
./install.sh --doctor                          # which modules are already installed?
./install.sh --list-modules                    # the table below, from the source
```

Every run goes through the same steps:
1. **Check.** It runs the `--doctor` check on the selected modules. Each one shows as `✔ installed` or `○ not installed`.
2. **Install.** It installs only the missing modules, numbered `[1/n]`, `[2/n]`, and so on.
3. **Summary.** Each module shows as `✔ installed now`, `• already installed` or `✘ failed`. If anything failed, the script exits with status 1, and re-running retries just those modules.

```
━━━ Checking what's already installed ━━━
  ✔ essentials         installed
  ✔ flatpak            installed
  ○ normcap            not installed     NormCap OCR screen-capture (flatpak) on Ctrl+Super+Alt+O

  2 already installed · 1 missing
```

`--doctor` on its own checks every module, opt-in ones included, and exits without changing anything. Combine it with `--only`, `--with`, `--without` or `--profile` to check a subset. It works without sudo, but a few checks (such as `ufw status`) are only accurate as root.

Environment overrides go *after* `sudo` (it drops your environment): `sudo AUTOLINUX_UFW_ENABLE=1 RINGBOARD_VERSION=0.15.0 ./install.sh`.

Selection is applied in order: profile (or `--only`), then `--with`, then `--without`, then the checklist if you're interactive. Dependencies (for example `ringboard` → `rust`) are always added back. Logs and a status file go to `/var/log/autolinux/`.

### Modules

| Group | Module | Profiles | What it does |
|---|---|---|---|
| core | `essentials` | always | curl, git, jq, gnupg, ca-certificates, dconf-cli (always runs first) |
| core | `base-packages` | minimal, full | everything in [`apt-packages.txt`](apt-packages.txt) |
| core | `bashrc` | minimal, full | [`dotfiles/bashrc`](dotfiles/bashrc) → `~/.bashrc`. The old file is backed up to `~/.bashrc.bak-<timestamp>`. It counts as installed when the header and version line match, so lines that nvm or rustup append are left alone. |
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

### Base apt packages

The `base-packages` module installs whatever is listed in [`apt-packages.txt`](apt-packages.txt), one package name per line, read at run time. Edit that file to change the base set; blank lines and `# comments` are ignored, and names apt doesn't know are skipped with a warning instead of failing the whole batch. Point at a different list with `sudo AUTOLINUX_APT_PACKAGES=/path/to/list.txt ./install.sh`. Packages that need a vendor repo (Chrome, VS Code, Docker, ...) stay in their own modules.

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

The module selection (`--profile`, `--modules`, `--with`, `--without`, `-i`) is saved in `state.json`, so a resume after reboot reuses it. So are the network flags (`--static-ip`, `--gateway`, `--dns`, `--wol`), which are handed to `system_config.sh` at stage 10; without them the network is left alone.

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
| 10 | `system_config.sh`: swap, SSH, passwordless sudo, re-enables Wayland if an old run disabled it; static IP / Wake-on-LAN only if flagged | no |
| 11 | app/dev/desktop modules | no |
| 12 | `desktop-settings` module | no |
| 13 | `gnome-extensions` module | no |
| 14 | release the stage-02 package holds | no |
| 15 | remove resume hooks, summary | no |

Safety: XFCE is never purged from inside an XFCE session. Packages are held before any purge, and the purge set is computed rather than taken from a static list. Bootloader integrity is checked before every reboot, state writes are atomic, and `--dry-run` prints every mutating command instead of running it.

## `system_config.sh`

Base system settings, each shown as a numbered step and listed in a summary at the end (✔ changed, • already fine, – skipped, ✘ failed):

```bash
sudo ./system_config.sh                                   # swap ≥ 8 GB, SSH, Wayland, passwordless sudo
./system_config.sh --dry-run                              # preview; works without root (some checks need root)
sudo ./system_config.sh --static-ip 192.168.50.20         # also pin this address
sudo ./system_config.sh --static-ip 10.0.0.5/24 --gateway 10.0.0.1 --dns 1.1.1.1,9.9.9.9
sudo ./system_config.sh --wol                             # Wake-on-LAN on the wired default interface
```

The network is **not touched unless you pass a network flag**. With `--static-ip`, the prefix and gateway default to the current default route, and DNS defaults to the servers DHCP is handing out right now (typically the router), so local DNS keeps working. The address is refused if it's outside the gateway's subnet or another host already answers on it. On desktops the change goes on the active NetworkManager connection (previous settings saved under `/var/backups/autolinux-nm-*`, undo command printed); without NetworkManager it writes `/etc/netplan/60-autolinux-static.yaml`. Reserve the address in the router's DHCP settings too.

## Wayland

Nothing here forces Xorg anymore. If an older autolinux run left `WaylandEnable=false` in `/etc/gdm3/custom.conf`, `system_config.sh` comments it out (with a timestamped backup), and Wayland returns at the next login.

## Warnings

- `system_config.sh` gives the invoking user **passwordless sudo** (`/etc/sudoers.d/<user>`, validated with `visudo`; skipped when an equivalent rule already exists).
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
./tests/net.sh             # network helpers + system_config.sh flags (dry-run)
./tests/state-machine.sh   # state.json, detect helpers, bootstrap CLI
```

Validation so far is shellcheck, both suites, and `--dry-run` on the reference machine (every module detects as set up). A full fresh install hasn't been run in a VM yet.

## License

MIT

# Najm GRUB theme

A pixel-font GRUB theme with Arabic verses in the corners. Dark, quiet, and sharp at every resolution from 1024×768 to 4K and ultrawide.

[العربية](README.ar.md)

![Najm GRUB theme at 1920×1080](docs/preview/hero.png)

Every screenshot in this repo is a **real GRUB** (2.12) running in QEMU, not a mock-up.

## Features

- **15 ready-made resolutions**, plus any other `WxH` built on demand. Layout, decorations and font all scale together.
- **Install-time customisation**: accent colour, Arabic verses (five classical presets or your own text), key-hint bar, countdown bar, menu timeout.
- **One installer for different distros**: finds `/boot/grub` vs `/boot/grub2`, `grub-mkconfig` vs `grub2-mkconfig`, and your screen's native resolution.
- **Safe**: backs up `/etc/default/grub`, edits only a clearly marked block, rolls back if `grub-mkconfig` fails, and `--uninstall` restores your original file exactly.
- **No dependencies for the default look.** Python + Pillow are needed only for customisation, and the installer can fetch them into a throw-away virtualenv.

## Install

```sh
git clone https://github.com/najm-labs/grub-theme.git
cd grub-theme
sudo ./install.sh
```

In a terminal this starts a short wizard (resolution, colour, verses, extras, timeout). Reboot afterwards.

Non-interactive, e.g. for scripts or dotfiles:

```sh
sudo ./install.sh -y                                   # auto-detect resolution, default look
sudo ./install.sh -y -r 2560x1440 --accent cyan --verse stars --timeout 5
sudo ./install.sh -y --no-verses --no-hints            # minimal: menu + countdown only
sudo ./install.sh --dry-run                            # show what would happen
sudo ./install.sh --uninstall
```

Requires `bash`, and GRUB 2 as your bootloader (on Alpine: `apk add bash`).

### Options

| Option | Meaning |
| --- | --- |
| `-r, --resolution WxH` | Screen resolution. Default: detected from the connected monitor. |
| `--accent NAME\|#RRGGBB` | `najm` (default), `gold`, `green`, `cyan`, `blue`, `violet`, `rose`, `white`, or any hex colour. |
| `--verse ID` | `najm` (default), `ships`, `stars`, `dunya`, `qadar`. See `./install.sh --list-verses`. |
| `--vertical TEXT` `--horizontal TEXT` | Your own Arabic text (give both). |
| `--no-verses` `--no-hints` `--no-countdown` | Remove the corner verses / the Enter-E-C hint bar / the countdown bar. |
| `--timeout N` | Set `GRUB_TIMEOUT`. |
| `--show-menu` | Always show the menu (Ubuntu hides it by default). |
| `--name NAME` | Theme directory name (default `najm`). |
| `--themes-dir`, `--grub-cfg` | Override the detected locations. |
| `--no-regenerate` | Edit files but don't run `grub-mkconfig`. |
| `--export DIR` | Only write the finished theme to `DIR` (NixOS, packaging, manual installs). |
| `--detect` | Print what was detected on your machine (include this in bug reports). |
| `-y, --yes` / `--dry-run` / `--no-pip` | No prompts / change nothing / never use pip. |

## Previews

**Accent colours**

![Accent colours](docs/preview/accents.png)

**Layouts and verses**: minimal layout (left), another verse preset with the blue accent (right).

![Layouts](docs/preview/layouts.png)

**Scaling**: 1280×720, 2560×1440, 3840×2160 and 3440×1440 ultrawide, all shown at the same width.

![Resolutions](docs/preview/resolutions.png)

## Resolutions

Ready-made: `1024x768 1280x720 1280x800 1280x1024 1366x768 1440x900 1600x900 1680x1050 1920x1080 1920x1200 2560x1080 2560x1440 2560x1600 3440x1440 3840x2160`.

Anything else (say `1600x1200`) is generated on the fly when Pillow is available. Without Pillow the installer uses the closest ready-made theme and still sets GRUB to your resolution.

`GRUB_GFXMODE` is set to `<res>x32,<res>,auto`. If your firmware doesn't offer that mode GRUB falls back to `auto` and the theme still works, just not pixel-matched. Some BIOS (VBE) setups do not offer modes such as 1366×768 (the QEMU BIOS used for these previews does not); UEFI normally offers the panel's native mode.

## Does it work on my distro?

GRUB's location differs between distributions. The installer handles this:

| Family | GRUB files | Regenerate with |
| --- | --- | --- |
| Debian, Ubuntu, Mint, Pop!_OS, Arch, Manjaro, EndeavourOS, Gentoo, Void, Alpine | `/boot/grub` | `grub-mkconfig` |
| Fedora, RHEL, Alma, Rocky, CentOS Stream, openSUSE | `/boot/grub2` | `grub2-mkconfig` |
| RHEL 8-style UEFI | also the real `grub.cfg` on the ESP | detected and regenerated too |
| NixOS | declarative | refused with instructions, use `--export` |
| systemd-boot, rEFInd, Limine | not GRUB | not supported |

What has actually been tested: rendering in real GRUB under QEMU (BIOS and UEFI), a real `grub-mkconfig` run against an Ubuntu 24.04 userland, and the installer's logic on staged Debian/Ubuntu, Fedora and RHEL-style directory layouts (`tests/test_install.sh`). Other distributions follow the same conventions but have not been run on real installs. Please open an issue with the output of `./install.sh --detect` if something is off.

If `/etc/default/grub.d/*.cfg` drop-ins (common on Ubuntu) also set `GRUB_THEME`, `GRUB_TERMINAL` or `GRUB_GFXMODE`, the installer warns you, because they are read later and can override the theme.

## How it works

The installer copies a theme directory to `/boot/grub{,2}/themes/najm/` and appends a block to the end of `/etc/default/grub`:

```sh
# >>> najm-grub-theme >>>
GRUB_THEME="/boot/grub/themes/najm/theme.txt"
GRUB_GFXMODE="1920x1080x32,1920x1080,auto"
GRUB_GFXPAYLOAD_LINUX=keep
unset GRUB_TERMINAL GRUB_TERMINAL_OUTPUT   # themes need the graphical terminal
# <<< najm-grub-theme <<<
```

then runs `grub-mkconfig`, which emits a `loadfont` line for every `.pf2` font in the theme folder and sets `theme`. Your own lines are never edited; `--uninstall` deletes the block and the theme folder.

Arabic text can't be shaped by GRUB, so the verses are pre-rendered PNGs (with proper joining and right-to-left order). The menu font is a PF2 bitmap font; `tools/pf2.py` can re-draw it at any integer pixel size, which is how large screens get a crisp, correctly sized font.

### Manual install

If you'd rather not run the script:

```sh
sudo cp -r themes/1920x1080 /boot/grub/themes/najm      # /boot/grub2 on Fedora/openSUSE
# add to /etc/default/grub: GRUB_THEME, GRUB_GFXMODE, and remove GRUB_TERMINAL=console
sudo grub-mkconfig -o /boot/grub/grub.cfg                # grub2-mkconfig on Fedora/openSUSE
```

Note: a hand-written `grub.cfg` must contain a `loadfont` for the theme's `.pf2` file; `grub-mkconfig` does it for you.

## Troubleshooting

- **I don't see the theme at boot.** Many distros hide the menu (`GRUB_TIMEOUT_STYLE=hidden` or `GRUB_TIMEOUT=0`). Hold <kbd>Shift</kbd> (BIOS) or tap <kbd>Esc</kbd> (UEFI) while booting, or re-run with `--show-menu`.
- **`error: ... bitmap file ... is of unsupported format`.** A theme file points to an empty or non-image path (for example `desktop-image: ""`). The installer validates themes to prevent this; if you edit `theme.txt` yourself, remove the empty line.
- **Text is tiny or in a different font.** The `.pf2` file wasn't loaded: regenerate with `grub-mkconfig`, don't just copy files.
- **GRUB is stuck at 640×480 / 800×600.** The firmware doesn't offer your mode; check the available ones with `videoinfo` at the GRUB prompt (<kbd>c</kbd>).
- **Black screen right after choosing a kernel.** Remove `GRUB_GFXPAYLOAD_LINUX=keep` from the managed block and re-run `grub-mkconfig`.
- **`/boot` on its own or encrypted partition.** Works as long as GRUB can read it; the theme lives under `/boot`, so it follows `/boot`.

## Building from source

```sh
pip install pillow                            # plus arabic-reshaper python-bidi if Pillow lacks libraqm
./build.py --all                              # rebuild themes/
./build.py -r 2560x1440 --accent "#3BB4C8" --verse ships -o out/
./build.py -r 1920x1080 --vertical "..." --horizontal "..." -o out/
tests/test_install.sh                         # installer tests, no real GRUB touched
tools/preview.py themes/1920x1080 -r 1920x1080 -o shot.png   # real GRUB in QEMU (--uefi for UEFI)
```

Previews need `grub-mkrescue` (+ `grub-pc-bin`, `grub-efi-amd64-bin` for `--uefi`), `xorriso`, `mtools`, `qemu-system-x86_64` and, for `--uefi`, `ovmf`.

Layout of the repo: `build.py` (generator), `install.sh` (installer), `themes/` (pre-built), `data/` (resolutions, accents, verses), `assets/fonts/`, `tools/` (PF2 library, preview), `tests/`.

## Credits

- Verses: al-Mutanabbi (`najm`, `ships`, `stars`), Ahmed Shawqi (`dunya`), Abu al-Qasim al-Shabbi (`qadar`).
- Arabic text rendered in [Amiri](https://github.com/aliftype/amiri) (SIL OFL 1.1).
- Fonts and licences: [assets/fonts/NOTICE.md](assets/fonts/NOTICE.md).

## License

[MIT](LICENSE), except third-party fonts which keep their own licences.

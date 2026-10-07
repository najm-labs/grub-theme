#!/usr/bin/env bash
# Najm GRUB theme installer / uninstaller.
#   sudo ./install.sh            interactive wizard
#   sudo ./install.sh -y         install with auto-detected defaults
#   sudo ./install.sh --help     all options
set -euo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="1.0.0"
MARK_BEGIN="# >>> najm-grub-theme >>>"
MARK_END="# <<< najm-grub-theme <<<"

# ------------------------------------------------------------------ options
RES="" ACCENT="najm" VERSE="najm" VERT="" HORIZ=""
SHOW_VERSES=1 SHOW_HINTS=1 SHOW_COUNTDOWN=1
TIMEOUT="" NAME="najm" THEMES_DIR="" GRUB_CFG="" ROOT_PREFIX="" EXPORT_DIR=""
ASSUME_YES=0 DRY_RUN=0 REGENERATE=1 FORCE_REGEN=0 ACTION="install" ALLOW_PIP=1 SHOW_MENU=0 THEMES_GIVEN=0
PYTHON="${PYTHON:-python3}"
CUSTOM_FLAGS=0   # set when the user asked for anything the pre-built themes can't give

if [[ -t 1 ]]; then
  B=$'\e[1m' D=$'\e[2m' R=$'\e[31m' G=$'\e[32m' Y=$'\e[33m' C=$'\e[36m' Z=$'\e[0m'
else B="" D="" R="" G="" Y="" C="" Z=""; fi
say()  { printf '%s\n' "$*"; }
step() { printf '%s==>%s %s%s%s\n' "$C" "$Z" "$B" "$*" "$Z"; }
ok()   { printf '  %s✓%s %s\n' "$G" "$Z" "$*"; }
warn() { printf '  %s!%s %s\n' "$Y" "$Z" "$*" >&2; }
die()  { printf '%serror:%s %s\n' "$R" "$Z" "$*" >&2; exit 1; }

usage() {
  cat <<EOF
${B}Najm GRUB theme ${VERSION}${Z}

Usage: sudo ./install.sh [options]

With no options in a terminal, an interactive wizard asks for everything.

Look
  -r, --resolution WxH     screen resolution (default: auto-detect)
      --accent NAME|#HEX   $(cut -f1 "$SELF/data/accents.tsv" | paste -sd, - | sed 's/,/, /g') or any #RRGGBB
      --verse ID           $(cut -f1 "$SELF/data/verses.tsv" | paste -sd, - | sed 's/,/, /g')
      --vertical TEXT      custom Arabic text for the vertical verse
      --horizontal TEXT    custom Arabic text for the horizontal verse
      --no-verses          hide the four corner verses
      --no-hints           hide the Enter / E / C key hints
      --no-countdown      hide the boot countdown bar
      --timeout SECONDS    set GRUB_TIMEOUT (default: leave unchanged)
      --show-menu          always show the menu (sets GRUB_TIMEOUT_STYLE=menu; Ubuntu hides it)

Where / how
      --name NAME          theme directory name (default: najm)
      --themes-dir DIR     override <grub dir>/themes
      --grub-cfg FILE      override the grub.cfg that gets regenerated
      --no-regenerate      change files but don't run grub-mkconfig
      --export DIR         only write the finished theme to DIR (NixOS, packaging)
      --root DIR           operate on a staged root (skips grub-mkconfig unless --regenerate)
      --dry-run            show what would happen, change nothing
      --python PATH        python interpreter for custom builds
      --no-pip             never try to pip-install Pillow into a temp venv
  -y, --yes                no questions; use defaults and the flags above

Other
      --uninstall          remove the theme and restore your GRUB settings
      --detect             print what was detected on this machine and exit
      --list-resolutions | --list-accents | --list-verses
  -h, --help | --version
EOF
}

# --------------------------------------------------------------------- args
ORIG_ARGS=("$@")
need() { [[ $# -ge 2 && -n "${2:-}" ]] || die "$1 needs a value"; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--resolution) need "$@"; RES="$2"; shift 2 ;;
    --accent)        need "$@"; ACCENT="$2"; CUSTOM_FLAGS=1; shift 2 ;;
    --verse)         need "$@"; VERSE="$2"; CUSTOM_FLAGS=1; shift 2 ;;
    --vertical)      need "$@"; VERT="$2"; CUSTOM_FLAGS=1; shift 2 ;;
    --horizontal)    need "$@"; HORIZ="$2"; CUSTOM_FLAGS=1; shift 2 ;;
    --no-verses)     SHOW_VERSES=0; CUSTOM_FLAGS=1; shift ;;
    --no-hints)      SHOW_HINTS=0; CUSTOM_FLAGS=1; shift ;;
    --no-countdown)  SHOW_COUNTDOWN=0; CUSTOM_FLAGS=1; shift ;;
    --timeout)       need "$@"; TIMEOUT="$2"; shift 2 ;;
    --show-menu)     SHOW_MENU=1; shift ;;
    --name)          need "$@"; NAME="$2"; shift 2 ;;
    --themes-dir)    need "$@"; THEMES_DIR="$2"; THEMES_GIVEN=1; shift 2 ;;
    --grub-cfg)      need "$@"; GRUB_CFG="$2"; shift 2 ;;
    --no-regenerate) REGENERATE=0; shift ;;
    --export)        need "$@"; EXPORT_DIR="$2"; ACTION="export"; shift 2 ;;
    --root)          need "$@"; ROOT_PREFIX="${2%/}"; shift 2 ;;
    --regenerate)    FORCE_REGEN=1; shift ;;
    --dry-run)       DRY_RUN=1; shift ;;
    --python)        need "$@"; PYTHON="$2"; shift 2 ;;
    --no-pip)        ALLOW_PIP=0; shift ;;
    -y|--yes)        ASSUME_YES=1; shift ;;
    --uninstall)     ACTION="uninstall"; shift ;;
    --detect)        ACTION="detect"; shift ;;
    --list-resolutions) cat "$SELF/data/resolutions.txt"; exit 0 ;;
    --list-accents)  cat "$SELF/data/accents.tsv"; exit 0 ;;
    --list-verses)   awk -F'\t' '{printf "%s\t%s / %s  (%s)\n",$1,$3,$2,$4}' "$SELF/data/verses.tsv"; exit 0 ;;
    -h|--help)       usage; exit 0 ;;
    --version)       echo "$VERSION"; exit 0 ;;
    *) die "unknown option: $1 (try --help)" ;;
  esac
done

[[ "$NAME" =~ ^[A-Za-z0-9._-]+$ ]] || die "--name may only contain letters, digits, . _ -"
[[ -z "$RES" || "$RES" =~ ^[0-9]{3,5}x[0-9]{3,5}$ ]] || die "resolution must look like 1920x1080"
[[ -z "$TIMEOUT" || "$TIMEOUT" =~ ^(-1|[0-9]+)$ ]] || die "--timeout must be a whole number of seconds (or -1)"
[[ -n "$VERT" || -n "$HORIZ" ]] && VERSE=""
[[ -n $ROOT_PREFIX && $FORCE_REGEN -eq 0 ]] && REGENERATE=0
(( DRY_RUN )) && REGENERATE=0

# Re-run through sudo when needed.
if [[ $EUID -ne 0 && $ACTION != detect && $ACTION != export && -z "$ROOT_PREFIX" && $DRY_RUN -eq 0 ]]; then
  if command -v sudo >/dev/null; then
    say "Root is required to edit GRUB; re-running with sudo..."
    exec sudo -E bash "$0" "${ORIG_ARGS[@]}"
  fi
  die "run as root (sudo ./install.sh)"
fi

P() { printf '%s%s' "$ROOT_PREFIX" "$1"; }          # path inside the target root
run() { if (( DRY_RUN )); then say "  [dry-run] $*"; else "$@"; fi; }

# ---------------------------------------------------------------- detection
OS_ID="unknown" OS_NAME="unknown"
# shellcheck source=/dev/null
if [[ -r "$(P /etc/os-release)" ]]; then
  OS_ID="$(. "$(P /etc/os-release)"; echo "${ID:-unknown}${ID_LIKE:+ ($ID_LIKE)}")"
  OS_NAME="$(. "$(P /etc/os-release)"; echo "${PRETTY_NAME:-${NAME:-unknown}}")"
fi

find_mkconfig() {
  command -v grub-mkconfig 2>/dev/null || command -v grub2-mkconfig 2>/dev/null || true
}

# GRUB keeps its files in /boot/grub (Debian, Ubuntu, Arch, Gentoo, Void, Alpine...) or
# /boot/grub2 (Fedora, RHEL family, openSUSE).  Decide by what exists, then by the tool name.
pick_grub_dir() {
  local a b
  a="$(P /boot/grub)"; b="$(P /boot/grub2)"
  if [[ -d $a && ! -d $b ]]; then echo /boot/grub; return; fi
  if [[ -d $b && ! -d $a ]]; then echo /boot/grub2; return; fi
  if [[ -d $a && -d $b ]]; then
    if   [[ -f $a/grub.cfg && ! -f $b/grub.cfg ]]; then echo /boot/grub
    elif [[ -f $b/grub.cfg && ! -f $a/grub.cfg ]]; then echo /boot/grub2
    elif command -v grub2-mkconfig >/dev/null && ! command -v grub-mkconfig >/dev/null; then echo /boot/grub2
    else echo /boot/grub; fi
    return
  fi
  if command -v grub2-mkconfig >/dev/null && ! command -v grub-mkconfig >/dev/null; then echo /boot/grub2
  else echo /boot/grub; fi
}

# Connected monitors' preferred modes straight from the kernel (works from a TTY, no X needed).
detect_modes() {
  local d st m name
  for d in /sys/class/drm/card*-*; do
    [[ -r $d/status && -r $d/modes ]] || continue
    st="$(<"$d/status")"; [[ $st == connected ]] || continue
    m="$(head -n1 "$d/modes" | grep -oE '^[0-9]+x[0-9]+' || true)"
    [[ -n $m ]] && { name="${d##*/}"; echo "${m} ${name#card*-}"; }
  done
  if [[ -r /sys/class/graphics/fb0/virtual_size ]]; then
    m="$(tr ',' 'x' </sys/class/graphics/fb0/virtual_size)"
    [[ $m =~ ^[0-9]+x[0-9]+$ ]] && echo "$m framebuffer"
  fi
}

detect_resolution() {
  local best="" area=0 w h a line
  while read -r line; do
    [[ -n $line ]] || continue
    w="${line%%x*}"; h="${line#*x}"; h="${h%% *}"; a=$((w*h))
    (( a > area )) && { area=$a; best="${w}x${h}"; }
  done < <(detect_modes)
  echo "${best:-1920x1080}"
}

# Closest shipped resolution (log-distance on both axes).
nearest_prebuilt() {
  awk -v W="$1" -v H="$2" '
    function ab(x){return x<0?-x:x}
    { split($1,p,"x"); d=ab(log(p[1]/W))+ab(log(p[2]/H)); if(best==""||d<bd){bd=d;best=$1} }
    END{print best}' "$SELF/data/resolutions.txt"
}

is_prebuilt() { grep -qx "$1" "$SELF/data/resolutions.txt"; }

# Value a GRUB_* variable has in the user's own settings, i.e. *without* our managed block.
read_default() {
  local f clean; f="$(P /etc/default/grub)"; [[ -r $f ]] || return 0
  clean="$(mktemp -t najm-default.XXXXXX)"
  awk -v b="$MARK_BEGIN" -v e="$MARK_END" '$0==b{skip=1;next} $0==e{skip=0;next} !skip' "$f" >"$clean"
  # shellcheck source=/dev/null
  ( set +eu; . "$clean" >/dev/null 2>&1; eval "printf '%s' \"\${$1:-}\"" ) 2>/dev/null || true
  rm -f "$clean"
}

# ---------------------------------------------------------- environment info
MKCONFIG="" GRUB_DIR="" DEFAULTS="" EXTRA_CFGS=()
probe_env() {
  MKCONFIG="$(find_mkconfig)"
  GRUB_DIR="$(pick_grub_dir)"
  [[ -n $THEMES_DIR ]] || THEMES_DIR="$GRUB_DIR/themes"
  [[ -n $GRUB_CFG ]] || GRUB_CFG="$GRUB_DIR/grub.cfg"
  DEFAULTS="$(P /etc/default/grub)"
  EXTRA_CFGS=()
  # Older RHEL-family UEFI installs keep the real config on the ESP (a stub is < 2 KiB).
  local f
  for f in "$(P /boot/efi/EFI)"/*/grub.cfg "$(P /efi/EFI)"/*/grub.cfg; do
    [[ -f $f && $(stat -c %s "$f") -gt 2048 && ${f#"$ROOT_PREFIX"} != "$GRUB_CFG" ]] && EXTRA_CFGS+=("${f#"$ROOT_PREFIX"}")
  done
  return 0
}

print_detect() {
  probe_env
  step "Detected environment"
  say "  distro        : $OS_NAME [$OS_ID]"
  say "  mkconfig      : ${MKCONFIG:-not found}"
  say "  GRUB dir      : $GRUB_DIR"
  say "  grub.cfg      : $GRUB_CFG"
  (( ${#EXTRA_CFGS[@]} )) && say "  extra EFI cfg : ${EXTRA_CFGS[*]}"
  say "  themes dir    : $THEMES_DIR"
  say "  /etc/default  : $([[ -f $DEFAULTS ]] && echo "$DEFAULTS" || echo "missing")"
  say "  firmware      : $([[ -d /sys/firmware/efi ]] && echo UEFI || echo BIOS)"
  say "  monitors      : $(detect_modes | awk '{printf "%s(%s) ",$1,$2}')"
  say "  suggested res : $(detect_resolution)"
  [[ -e $(P /etc/NIXOS) ]] && say "  NixOS         : yes (GRUB is configured declaratively)"
  [[ -d /boot/loader/entries || -f /boot/efi/loader/loader.conf || -f /boot/loader/loader.conf ]] \
    && say "  systemd-boot  : loader entries present"
  return 0
}

check_env() {
  if [[ -e $(P /etc/NIXOS) ]]; then
    cat >&2 <<EOF
${Y}NixOS manages GRUB declaratively, so this script won't edit it.${Z}
Build the theme and point your config at it:

  ./install.sh --export ./najm-theme -r 1920x1080
  # configuration.nix
  boot.loader.grub.theme = ./najm-theme;

EOF
    exit 2
  fi
  [[ -f $DEFAULTS ]] || die "$DEFAULTS not found - this doesn't look like a GRUB system. Try --detect."
  if [[ -z $MKCONFIG && $REGENERATE -eq 1 ]]; then
    die "grub-mkconfig / grub2-mkconfig not found. Is GRUB installed? (systemd-boot and rEFInd are not supported)"
  fi
  if [[ ! -d $(P "$GRUB_DIR") && $THEMES_GIVEN -eq 0 ]]; then
    die "$GRUB_DIR does not exist - is GRUB installed on this system?"
  fi
  if [[ -d /boot/loader/entries || -f /boot/efi/loader/loader.conf ]] && [[ ! -f $(P "$GRUB_CFG") ]]; then
    warn "systemd-boot looks active and no grub.cfg was found; this theme only works with GRUB."
  fi
  # Ubuntu-style drop-ins are sourced *after* /etc/default/grub and can override our settings.
  local dropins d
  dropins=$(grep -lE '^[[:space:]]*(GRUB_THEME|GRUB_TERMINAL(_OUTPUT)?|GRUB_GFXMODE)=' \
            "$(P /etc/default/grub.d)"/*.cfg 2>/dev/null || true)
  for d in $dropins; do
    warn "${d#"$ROOT_PREFIX"} also sets theme/terminal/gfx options and may override this theme."
  done
}

# -------------------------------------------------------- python / Pillow
PY="" TMPDIR_N=""
cleanup() { [[ -n $TMPDIR_N && -d $TMPDIR_N ]] && rm -rf "$TMPDIR_N"; return 0; }
trap cleanup EXIT
mktmp() { [[ -n $TMPDIR_N ]] || TMPDIR_N="$(mktemp -d -t najm-theme.XXXXXX)"; }

py_state() {  # echo: ok | nopython | nopil | noshape
  command -v "$1" >/dev/null 2>&1 || { echo nopython; return; }
  "$1" - <<'EOF' 2>/dev/null || echo nopil
import sys
try:
    from PIL import features
except Exception:
    print("nopil"); sys.exit()
if features.check("raqm"):
    print("ok"); sys.exit()
try:
    import arabic_reshaper, bidi.algorithm
    print("ok")
except Exception:
    print("noshape")
EOF
}

pkg_hint() {
  case "$OS_ID" in
    *arch*)            echo "pacman -S python-pillow" ;;
    *debian*|*ubuntu*) echo "apt install python3-pil" ;;
    *fedora*|*rhel*)   echo "dnf install python3-pillow" ;;
    *suse*)            echo "zypper install python3-Pillow" ;;
    *)                 echo "pip install pillow arabic-reshaper python-bidi" ;;
  esac
}

confirm() {  # confirm "question" default(y|n)
  (( ASSUME_YES )) && return 0
  [[ -t 0 ]] || return 1
  local d="$2" a; a=""; read -r -p "$1 [$( [[ $d == y ]] && echo Y/n || echo y/N )] " a || true
  a="${a:-$d}"; [[ $a =~ ^[Yy] ]]
}

ensure_python() {  # sets PY or returns 1
  local st; st="$(py_state "$PYTHON")"
  if [[ $st == ok ]]; then PY="$PYTHON"; return 0; fi
  warn "custom builds need Python with Pillow (state: $st)."
  if (( ALLOW_PIP )) && command -v "$PYTHON" >/dev/null && "$PYTHON" -m venv --help >/dev/null 2>&1 \
     && confirm "  Create a temporary virtualenv and pip-install Pillow into it?" y; then
    mktmp
    if "$PYTHON" -m venv "$TMPDIR_N/venv" >/dev/null 2>&1 \
       && "$TMPDIR_N/venv/bin/pip" install -q pillow arabic-reshaper python-bidi >/dev/null 2>&1; then
      PY="$TMPDIR_N/venv/bin/python"; ok "temporary virtualenv ready"; return 0
    fi
    warn "pip install failed (offline?)."
  fi
  warn "install it yourself:  $(pkg_hint)   (Arabic text also needs libraqm or: pip install arabic-reshaper python-bidi)"
  return 1
}

# ----------------------------------------------------------------- wizard
menu() {  # menu "title" default item...   -> echoes chosen index (1-based)
  local title="$1" def="$2"; shift 2
  local i=1 it ans
  { printf '\n%s%s%s\n' "$B" "$title" "$Z"
    for it in "$@"; do printf '  %s%d)%s %s%s\n' "$C" "$i" "$Z" "$it" "$([[ $i == "$def" ]] && printf ' %s(default)%s' "$D" "$Z")"; i=$((i+1)); done; } >&2
  while :; do
    read -r -p "  Choose [${def}]: " ans || ans=""
    ans="${ans:-$def}"
    if [[ $ans =~ ^[0-9]+$ ]] && (( ans >= 1 && ans <= $# )); then echo "$ans"; return; fi
    echo "  enter a number between 1 and $#" >&2
  done
}

wizard() {
  local detected modes ans i
  detected="$(detect_resolution)"
  say ""; say "${B}Najm GRUB theme ${VERSION}${Z}  -  ${D}$OS_NAME${Z}"

  # 1. resolution
  modes="$(detect_modes | awk '{printf "%s (%s), ",$1,$2}' | sed 's/, $//')"
  say ""; say "${B}Screen resolution${Z}"
  [[ -n $modes ]] && say "  detected: $modes"
  say "  ready-made: $(paste -sd' ' "$SELF/data/resolutions.txt")"
  say "  any other WxH is built on the fly."
  while :; do
    read -r -p "  Resolution [${RES:-$detected}]: " ans || ans=""
    ans="${ans:-${RES:-$detected}}"
    [[ $ans =~ ^[0-9]{3,5}x[0-9]{3,5}$ ]] && { RES="$ans"; break; }
    echo "  use the form 1920x1080" >&2
  done

  # 2. accent
  local names=() hexes=() n h
  while IFS=$'\t' read -r n h; do names+=("$n"); hexes+=("$h"); done <"$SELF/data/accents.tsv"
  local items=() k
  for k in "${!names[@]}"; do items+=("${names[$k]}  ${hexes[$k]}"); done
  items+=("custom colour (#RRGGBB)")
  i="$(menu "Accent colour (selected entry, countdown bar, vertical verse)" 1 "${items[@]}")"
  if (( i == ${#items[@]} )); then
    while :; do read -r -p "  Hex colour: " ans || ans=""; [[ $ans =~ ^#?[0-9a-fA-F]{6}$ ]] && { ACCENT="$ans"; break; }; echo "  e.g. #3BB4C8" >&2; done
  else ACCENT="${names[$((i-1))]}"; fi
  [[ $ACCENT != najm ]] && CUSTOM_FLAGS=1

  # 3. verses
  local vids=() vitems=() vid vv vh vp
  while IFS=$'\t' read -r vid vv vh vp; do vids+=("$vid"); vitems+=("$vh  /  $vv  ${D}($vp)${Z}"); done <"$SELF/data/verses.tsv"
  vitems+=("write my own" "no corner text")
  i="$(menu "Corner verses (Arabic)" 1 "${vitems[@]}")"
  if (( i == ${#vitems[@]} )); then SHOW_VERSES=0; CUSTOM_FLAGS=1
  elif (( i == ${#vitems[@]} - 1 )); then
    read -r -p "  Horizontal text (top-right / bottom-left): " HORIZ || HORIZ=""
    read -r -p "  Vertical text (top-left / bottom-right):   " VERT || VERT=""
    VERSE=""; CUSTOM_FLAGS=1
    [[ -n $HORIZ && -n $VERT ]] || { warn "both texts are needed - using the default verse"; VERSE=najm; HORIZ=""; VERT=""; }
  else VERSE="${vids[$((i-1))]}"; [[ $VERSE != najm ]] && CUSTOM_FLAGS=1; fi

  # 4. extras
  read -r -p $'\n'"${B}Key hints bar${Z} (Enter / E / C) at the bottom? [Y/n] " ans || ans=""
  [[ ${ans:-y} =~ ^[Nn] ]] && { SHOW_HINTS=0; CUSTOM_FLAGS=1; }
  read -r -p "${B}Boot countdown bar${Z}? [Y/n] " ans || ans=""
  [[ ${ans:-y} =~ ^[Nn] ]] && { SHOW_COUNTDOWN=0; CUSTOM_FLAGS=1; }

  # 5. timeout
  local cur; cur="$(read_default GRUB_TIMEOUT)"
  while :; do
    read -r -p $'\n'"${B}Menu timeout${Z} in seconds [keep ${cur:-current}]: " ans || ans=""
    [[ -z $ans ]] && break
    [[ $ans =~ ^(-1|[0-9]+)$ ]] && { TIMEOUT="$ans"; break; }
    echo "  whole number of seconds (or -1 to wait forever)" >&2
  done
  if [[ "$(read_default GRUB_TIMEOUT_STYLE)" == hidden ]]; then
    read -r -p "${B}Your GRUB menu is hidden at boot.${Z} Always show it? [Y/n] " ans || ans=""
    [[ ${ans:-y} =~ ^[Yy] ]] && SHOW_MENU=1
  fi
  return 0
}

# ------------------------------------------------------------ theme creation
STAGE=""
make_stage() {
  local w h res_pre
  w="${RES%x*}"; h="${RES#*x}"
  local need_build=$CUSTOM_FLAGS
  is_prebuilt "$RES" || need_build=1
  if (( need_build )); then
    if ensure_python; then
      mktmp; STAGE="$TMPDIR_N/stage"
      local args=(-r "$RES" -o "$STAGE" --accent "$ACCENT")
      if [[ -n $VERSE && $VERSE != najm ]]; then args+=(--verse "$VERSE"); fi
      [[ -n $VERT ]] && args+=(--vertical "$VERT")
      [[ -n $HORIZ ]] && args+=(--horizontal "$HORIZ")
      (( SHOW_VERSES ))    || args+=(--no-verses)
      (( SHOW_HINTS ))     || args+=(--no-hints)
      (( SHOW_COUNTDOWN )) || args+=(--no-countdown)
      "$PY" "$SELF/build.py" "${args[@]}" >/dev/null || die "theme build failed"
      ok "built $RES with your options"
      return
    fi
    if (( CUSTOM_FLAGS )); then
      if [[ -t 0 ]] && (( ! ASSUME_YES )); then
        confirm "  Continue with the default look instead?" n || die "aborted - install Pillow and re-run"
      else
        die "your customisation (accent/verses/layout) needs Pillow; install it or drop those options"
      fi
      ACCENT=najm; VERSE=najm; VERT=""; HORIZ=""; SHOW_VERSES=1; SHOW_HINTS=1; SHOW_COUNTDOWN=1
    fi
    res_pre="$(nearest_prebuilt "$w" "$h")"
    [[ $res_pre == "$RES" ]] || warn "no ready-made theme for $RES; using the closest one ($res_pre). GRUB will still run at $RES."
    STAGE="$SELF/themes/$res_pre"
  else
    STAGE="$SELF/themes/$RES"
    ok "using the ready-made $RES theme"
  fi
  [[ -f $STAGE/theme.txt ]] || die "missing $STAGE/theme.txt (run ./build.py --all?)"
}

validate_theme() {  # catches the class of bug that breaks GRUB at boot
  local dir="$1" f bad=0
  [[ -f $dir/theme.txt ]] || die "no theme.txt in $dir"
  if grep -nE '^[[:space:]]*(desktop-image|file)[[:space:]]*[:=][[:space:]]*""' "$dir/theme.txt" >&2; then
    die "theme.txt has an empty image path (GRUB would fail with 'bitmap file ... is of unsupported format')"
  fi
  while IFS= read -r f; do
    [[ -f $dir/$f ]] || { warn "theme.txt references missing file: $f"; bad=1; }
  done < <(grep -oE '^[[:space:]]*(desktop-image[[:space:]]*:|file[[:space:]]*=)[[:space:]]*"[^"]+"' "$dir/theme.txt" | sed -E 's/.*"([^"]+)"/\1/')
  compgen -G "$dir/*.pf2" >/dev/null || { warn "no .pf2 font in theme"; bad=1; }
  for f in "$dir"/*.pf2; do
    [[ $(head -c 12 "$f" | tail -c 4) == PFF2 ]] || { warn "$f is not a valid PF2 font"; bad=1; }
  done
  (( bad == 0 )) || die "theme validation failed"
}

# ---------------------------------------------------- /etc/default/grub edits
strip_block() {  # stdin -> stdout without our managed block
  awk -v b="$MARK_BEGIN" -v e="$MARK_END" '$0==b{skip=1;next} $0==e{skip=0;next} !skip' 
}

write_block() {
  local theme_path gfx blk
  theme_path="$THEMES_DIR/$NAME/theme.txt"
  gfx="${RES}x32,${RES},auto"
  blk="$MARK_BEGIN"$'\n'
  blk+="# Managed by najm-grub-theme (./install.sh --uninstall removes this block)."$'\n'
  blk+="GRUB_THEME=\"$theme_path\""$'\n'
  blk+="GRUB_GFXMODE=\"$gfx\""$'\n'
  blk+="GRUB_GFXPAYLOAD_LINUX=keep"$'\n'
  blk+="unset GRUB_TERMINAL GRUB_TERMINAL_OUTPUT   # themes need the graphical terminal"$'\n'
  (( SHOW_MENU )) && blk+="GRUB_TIMEOUT_STYLE=menu"$'\n'
  [[ -n $TIMEOUT ]] && blk+="GRUB_TIMEOUT=$TIMEOUT"$'\n'
  blk+="$MARK_END"
  local tmp; mktmp; tmp="$TMPDIR_N/grub.new"
  strip_block <"$DEFAULTS" >"$tmp"
  # keep exactly one blank line before the block, and ensure a trailing newline
  [[ -z $(tail -c1 "$tmp") ]] || echo >>"$tmp"
  printf '\n%s\n' "$blk" >>"$tmp"
  if (( DRY_RUN )); then say "  [dry-run] would append to $DEFAULTS:"; say "$blk" | sed 's/^/      /'; return; fi
  if ! grep -qF "$MARK_BEGIN" "$DEFAULTS"; then
    local bak
    bak="$DEFAULTS.najm-backup-$(date +%Y%m%d-%H%M%S)"
    cp -p "$DEFAULTS" "$bak"; ok "backed up $DEFAULTS -> ${bak#"$ROOT_PREFIX"}"
  fi
  cat "$tmp" >"$DEFAULTS"      # keep inode, permissions and ownership
}

regenerate() {
  (( REGENERATE )) || { say "  (skipping grub-mkconfig)"; return 0; }
  local cfg
  for cfg in "$GRUB_CFG" ${EXTRA_CFGS[@]+"${EXTRA_CFGS[@]}"}; do
    step "Regenerating $cfg"
    if ! "$MKCONFIG" -o "$(P "$cfg")" 2>&1 | sed 's/^/    /'; then
      return 1
    fi
  done
}

verify_cfg() {
  (( REGENERATE )) || return 0
  if grep -q "themes/$NAME/theme.txt" "$(P "$GRUB_CFG")" 2>/dev/null; then
    ok "grub.cfg references the theme"
  else
    warn "the theme path is not in $GRUB_CFG. Another file may override GRUB_THEME (see warnings above)."
  fi
}

summary() {
  step "Plan"
  say "  resolution : $RES   (GRUB_GFXMODE ${RES}x32,${RES},auto)"
  say "  accent     : $ACCENT"
  if (( SHOW_VERSES )); then
    if [[ -n $VERT ]]; then say "  verses     : custom"; else say "  verses     : ${VERSE:-najm}"; fi
  else say "  verses     : none"; fi
  say "  hints/bar  : $( ((SHOW_HINTS)) && echo hints || echo no-hints ), $( ((SHOW_COUNTDOWN)) && echo countdown || echo no-countdown )"
  say "  timeout    : ${TIMEOUT:-unchanged}$( ((SHOW_MENU)) && echo ', menu always shown' )"
  say "  install to : $THEMES_DIR/$NAME"
  say "  config     : /etc/default/grub -> $GRUB_CFG"
}

# ------------------------------------------------------------------- actions
do_install() {
  probe_env; check_env
  if [[ -z $RES ]]; then
    if (( ASSUME_YES )) || [[ ! -t 0 ]] || (( DRY_RUN )); then RES="$(detect_resolution)"; fi
  fi
  if [[ -t 0 && -t 1 ]] && (( ! ASSUME_YES )) && (( ! DRY_RUN )) && [[ $CUSTOM_FLAGS -eq 0 && -z $TIMEOUT ]]; then
    wizard
  fi
  [[ -n $RES ]] || RES="$(detect_resolution)"
  if [[ -n $VERSE ]]; then
    awk -F'\t' -v v="$VERSE" '$1==v{f=1} END{exit !f}' "$SELF/data/verses.tsv" || die "unknown verse '$VERSE' (see --list-verses)"
  fi
  [[ -z $VERSE || $VERSE == najm ]] || CUSTOM_FLAGS=1
  [[ -z $VERT$HORIZ || ( -n $VERT && -n $HORIZ ) ]] || die "--vertical and --horizontal must be given together"
  # A visible menu with a 0 s timeout would boot instantly and never show the theme.
  local eff_timeout cur_style
  eff_timeout="${TIMEOUT:-$(read_default GRUB_TIMEOUT)}"; cur_style="$(read_default GRUB_TIMEOUT_STYLE)"
  if (( SHOW_MENU )) && [[ ${eff_timeout:-0} == 0 ]]; then
    TIMEOUT=5; warn "GRUB_TIMEOUT is 0, so the menu would never be visible; using 5 seconds (--timeout N to change)."
  elif (( ! SHOW_MENU )) && [[ $cur_style == hidden || ${eff_timeout:-} == 0 ]]; then
    warn "your GRUB menu is hidden or has a 0 s timeout, so you won't see the theme at boot (hold Shift/Esc to open it). Re-run with --show-menu to change that."
  fi
  summary
  if [[ -t 0 && -t 1 ]] && (( ! ASSUME_YES )) && (( ! DRY_RUN )); then
    confirm $'\n'"Install now?" y || { say "Aborted."; exit 1; }
  fi

  step "Preparing theme"
  make_stage
  validate_theme "$STAGE"

  local dest; dest="$(P "$THEMES_DIR/$NAME")"
  step "Installing to $THEMES_DIR/$NAME"
  mktmp; local old_theme="$TMPDIR_N/previous-theme" old_defaults="$TMPDIR_N/previous-defaults"
  cp -p "$DEFAULTS" "$old_defaults"
  if (( DRY_RUN )); then say "  [dry-run] would copy $STAGE -> $dest"
  else
    if [[ -d $dest ]]; then mv "$dest" "$old_theme"; fi
    mkdir -p "$dest"; cp -r "$STAGE"/. "$dest"/
    find "$dest" -type d -exec chmod 755 {} +; find "$dest" -type f -exec chmod 644 {} +
    ok "theme files copied"
  fi

  step "Configuring /etc/default/grub"
  write_block
  (( DRY_RUN )) || ok "settings written (GRUB_THEME, GRUB_GFXMODE, GRUB_GFXPAYLOAD_LINUX)"

  if ! regenerate; then
    warn "grub-mkconfig failed; restoring your previous settings."
    cat "$old_defaults" >"$DEFAULTS"
    rm -rf "$dest"; [[ -d $old_theme ]] && mv "$old_theme" "$dest"
    die "previous state restored. Run '$MKCONFIG -o $GRUB_CFG' manually to see the underlying error."
  fi
  verify_cfg
  say ""
  say "${G}${B}Done.${Z} Reboot to see it. ${D}Undo any time with: sudo ./install.sh --uninstall${Z}"
}

do_uninstall() {
  probe_env
  [[ -f $DEFAULTS ]] || die "$DEFAULTS not found"
  step "Removing Najm theme '$NAME'"
  local had=0
  grep -qF "$MARK_BEGIN" "$DEFAULTS" && had=1
  [[ -d $(P "$THEMES_DIR/$NAME") ]] && had=1
  (( had )) || { say "  nothing to remove."; return 0; }
  if (( DRY_RUN )); then say "  [dry-run] would remove block, $THEMES_DIR/$NAME and regenerate"; return 0; fi
  mktmp
  strip_block <"$DEFAULTS" | awk '{a[NR]=$0} END{n=NR; while(n>0&&a[n]=="")n--; for(i=1;i<=n;i++)print a[i]}' >"$TMPDIR_N/clean"
  cat "$TMPDIR_N/clean" >"$DEFAULTS"
  rm -rf "$(P "$THEMES_DIR/$NAME")"
  ok "settings block and theme directory removed"
  if (( REGENERATE )); then
    [[ -n $MKCONFIG ]] || die "grub-mkconfig not found; run it yourself to finish"
    regenerate || die "grub-mkconfig failed"
  fi
  say "${G}${B}Done.${Z} Your original GRUB settings are back in effect."
}

do_export() {
  [[ -n $RES ]] || RES="$(detect_resolution)"
  say "exporting $RES theme to $EXPORT_DIR"
  make_stage; validate_theme "$STAGE"
  mkdir -p "$EXPORT_DIR"; cp -r "$STAGE"/. "$EXPORT_DIR"/
  ok "theme written to $EXPORT_DIR  (set GRUB_THEME to <dir>/theme.txt and keep the *.pf2 next to it)"
}

case "$ACTION" in
  install)   do_install ;;
  uninstall) do_uninstall ;;
  detect)    print_detect ;;
  export)    do_export ;;
esac

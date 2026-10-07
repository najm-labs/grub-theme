#!/usr/bin/env bash
# Installer tests on throw-away fake roots (no real GRUB is touched).
#   tests/test_install.sh            run everything
#   NAJM_TEST_PIP=1 tests/test_install.sh   also test the temp-venv pip path (needs network)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="$HERE/install.sh"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
PASS=0 FAIL=0
t()    { printf '\n\033[1m# %s\033[0m\n' "$*"; }
pass() { PASS=$((PASS+1)); printf '  \033[32mok\033[0m   %s\n' "$*"; }
fail() { FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m %s\n' "$*"; }
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$d"; else fail "$d"; fi; }
nocheck() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then fail "$d"; else pass "$d"; fi; }

ubuntu_default='# If you change this file, run update-grub afterwards
GRUB_DEFAULT=0
GRUB_TIMEOUT_STYLE=hidden
GRUB_TIMEOUT=0
GRUB_DISTRIBUTOR=`lsb_release -i -s 2> /dev/null || echo Debian`
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
GRUB_CMDLINE_LINUX=""
GRUB_TERMINAL=console
GRUB_GFXMODE=640x480
'
mkroot() {  # mkroot NAME grubdir
  local r="$WORK/$1"; rm -rf "$r"
  mkdir -p "$r/etc/default" "$r/boot/$2"
  printf '%s' "$ubuntu_default" >"$r/etc/default/grub"
  echo "# stale" >"$r/boot/$2/grub.cfg"
  printf 'ID=%s\nPRETTY_NAME="Test OS"\n' "${3:-ubuntu}" >"$r/etc/os-release"
  echo "$r"
}
count() { grep -c "$1" "$2" || true; }

# ---------------------------------------------------------------------------
t "Debian/Ubuntu layout: /boot/grub"
R="$(mkroot deb grub)"; cp "$R/etc/default/grub" "$WORK/deb.orig"
"$INSTALL" --root "$R" -y -r 1920x1080 >"$WORK/out" 2>&1
check "theme dir created"            test -f "$R/boot/grub/themes/najm/theme.txt"
check "font copied"                  compgen -G "$R/boot/grub/themes/najm/*.pf2"
check "GRUB_THEME path is /boot/grub" grep -q '^GRUB_THEME="/boot/grub/themes/najm/theme.txt"' "$R/etc/default/grub"
check "GFXMODE matches resolution"   grep -q '^GRUB_GFXMODE="1920x1080x32,1920x1080,auto"' "$R/etc/default/grub"
check "console terminal is unset"    grep -q '^unset GRUB_TERMINAL GRUB_TERMINAL_OUTPUT' "$R/etc/default/grub"
check "exactly one managed block"    test "$(count '>>> najm-grub-theme' "$R/etc/default/grub")" = 1
check "original lines untouched"     bash -c "diff <(sed '/>>> najm-grub-theme/,/<<< najm-grub-theme/d' '$R/etc/default/grub' | sed -e :a -e '/^\n*\$/{\$d;N;ba' -e '}') <(cat '$WORK/deb.orig')"
check "backup created"               compgen -G "$R/etc/default/grub.najm-backup-*"
check "drop-in warning absent"       bash -c "! grep -q 'may override' '$WORK/out'"

t "Re-install is idempotent"
"$INSTALL" --root "$R" -y -r 2560x1440 >/dev/null 2>&1
check "still one block"              test "$(count '>>> najm-grub-theme' "$R/etc/default/grub")" = 1
check "block updated to new res"     grep -q '2560x1440x32' "$R/etc/default/grub"
check "no duplicate backup"          test "$(ls "$R"/etc/default/grub.najm-backup-* | wc -l)" = 1
check "old font removed"             bash -c "! ls '$R'/boot/grub/themes/najm/victor_pixel_21.pf2"
check "new font present (42px)"      test -f "$R/boot/grub/themes/najm/victor_pixel_42.pf2"

t "Uninstall restores the original file"
"$INSTALL" --root "$R" --uninstall >/dev/null 2>&1
check "theme dir gone"               bash -c "! test -e '$R/boot/grub/themes/najm'"
check "no marker left"               bash -c "! grep -q najm-grub-theme '$R/etc/default/grub'"
check "file identical to original"   diff -q "$R/etc/default/grub" "$WORK/deb.orig"

# ---------------------------------------------------------------------------
t "Fedora/openSUSE layout: /boot/grub2 only"
R="$(mkroot fed grub2 fedora)"
"$INSTALL" --root "$R" -y -r 1920x1080 >/dev/null 2>&1
check "themes under /boot/grub2"     test -f "$R/boot/grub2/themes/najm/theme.txt"
check "GRUB_THEME uses grub2 path"   grep -q '^GRUB_THEME="/boot/grub2/themes/najm/theme.txt"' "$R/etc/default/grub"
check "no stray /boot/grub created"  bash -c "! test -e '$R/boot/grub'"

t "RHEL-8 style UEFI: real config on the ESP is detected"
R="$(mkroot rhel grub2 rocky)"; mkdir -p "$R/boot/efi/EFI/rocky"; head -c 5000 /dev/zero | tr '\0' '#' >"$R/boot/efi/EFI/rocky/grub.cfg"
out="$("$INSTALL" --root "$R" --detect 2>&1)"
check "ESP grub.cfg listed"          grep -q 'extra EFI cfg : /boot/efi/EFI/rocky/grub.cfg' <<<"$out"
check "grub2 dir chosen"             grep -q 'GRUB dir      : /boot/grub2' <<<"$out"
R="$(mkroot stub grub)"; mkdir -p "$R/boot/efi/EFI/ubuntu"; echo 'configfile ...' >"$R/boot/efi/EFI/ubuntu/grub.cfg"
out="$("$INSTALL" --root "$R" --detect 2>&1)"
nocheck "small ESP stub is ignored"  grep -q 'extra EFI cfg' <<<"$out"

# ---------------------------------------------------------------------------
t "Custom options need Pillow (available here)"
R="$(mkroot cust grub)"
"$INSTALL" --root "$R" -y -r 1920x1080 --accent blue >/dev/null 2>&1
check "accent applied to theme.txt"  grep -q 'selected_item_color = "#4C8DF6"' "$R/boot/grub/themes/najm/theme.txt"
"$INSTALL" --root "$R" -y -r 1920x1080 --accent '#112233' --verse ships --no-hints --no-countdown >/dev/null 2>&1
check "custom hex accepted"          grep -q '#112233' "$R/boot/grub/themes/najm/theme.txt"
check "hints image omitted"          bash -c "! test -e '$R/boot/grub/themes/najm/hints.png'"
check "countdown omitted"            bash -c "! grep -q __timeout__ '$R/boot/grub/themes/najm/theme.txt'"
"$INSTALL" --root "$R" -y -r 1920x1080 --vertical 'خلف الأفق' --horizontal 'نجم في السماء' >/dev/null 2>&1
check "custom Arabic text builds"    test -f "$R/boot/grub/themes/najm/vertical.png"
"$INSTALL" --root "$R" -y -r 1920x1080 --no-verses >/dev/null 2>&1
check "no-verses drops the PNGs"     bash -c "! test -e '$R/boot/grub/themes/najm/vertical.png'"
"$INSTALL" --root "$R" -y -r 1600x1200 >/dev/null 2>&1
check "non-listed resolution built"  grep -q 'Najm GRUB theme - 1600x1200' "$R/boot/grub/themes/najm/theme.txt"
check "GFXMODE is the real one"      grep -q '1600x1200x32,1600x1200,auto' "$R/etc/default/grub"
"$INSTALL" --root "$R" -y -r 1920x1080 --timeout 7 --show-menu >/dev/null 2>&1
check "timeout written"              grep -q '^GRUB_TIMEOUT=7' "$R/etc/default/grub"
check "menu forced visible"          grep -q '^GRUB_TIMEOUT_STYLE=menu' "$R/etc/default/grub"
"$INSTALL" --root "$R" -y -r 1920x1080 --show-menu >/dev/null 2>&1
check "--show-menu never leaves a 0s timeout" grep -q '^GRUB_TIMEOUT=5' "$R/etc/default/grub"
out="$("$INSTALL" --root "$R" -y -r 1920x1080 2>&1)"
check "hidden menu is called out"    grep -q 'hidden or has a 0 s timeout' <<<"$out"

t "Bad input is rejected"
nocheck "unknown verse"              "$INSTALL" --root "$R" -y --verse nope
nocheck "bad accent"                 "$INSTALL" --root "$R" -y -r 1920x1080 --accent notacolor
nocheck "bad resolution"             "$INSTALL" --root "$R" -y -r 19x10
nocheck "bad timeout"                "$INSTALL" --root "$R" -y --timeout abc
nocheck "bad theme name"             "$INSTALL" --root "$R" -y --name 'a b'
nocheck "only one custom text"       "$INSTALL" --root "$R" -y -r 1920x1080 --vertical x
nocheck "missing /etc/default/grub"  "$INSTALL" --root "$WORK/nonexistent" -y

# ---------------------------------------------------------------------------
t "Without Pillow"
python3 -m venv "$WORK/venv-nopil" >/dev/null 2>&1
R="$(mkroot nopil grub)"
nocheck "custom accent refuses (non-interactive)" "$INSTALL" --root "$R" -y --no-pip --python "$WORK/venv-nopil/bin/python" -r 1920x1080 --accent blue
"$INSTALL" --root "$R" -y --no-pip --python "$WORK/venv-nopil/bin/python" -r 1920x1080 >/dev/null 2>&1
check "pre-built default still installs" test -f "$R/boot/grub/themes/najm/theme.txt"
out="$("$INSTALL" --root "$R" -y --no-pip --python "$WORK/venv-nopil/bin/python" -r 1600x1200 2>&1)"
check "unlisted res falls back to nearest with a warning" grep -q 'closest one' <<<"$out"
check "...but GRUB_GFXMODE keeps the real res" grep -q '1600x1200x32' "$R/etc/default/grub"
if [[ ${NAJM_TEST_PIP:-0} == 1 ]]; then
  R="$(mkroot pip grub)"
  "$INSTALL" --root "$R" -y --python "$WORK/venv-nopil/bin/python" -r 1920x1080 --accent gold >/dev/null 2>&1
  check "temp-venv pip path builds the theme" grep -q '#E0A526' "$R/boot/grub/themes/najm/theme.txt"
fi

# ---------------------------------------------------------------------------
t "Safety checks"
R="$(mkroot dry grub)"; cp "$R/etc/default/grub" "$WORK/dry.orig"
"$INSTALL" --root "$R" --dry-run -r 1920x1080 >/dev/null 2>&1
check "dry-run changes nothing"      bash -c "diff -q '$R/etc/default/grub' '$WORK/dry.orig' && ! test -e '$R/boot/grub/themes'"

cp -r "$HERE" "$WORK/broken"; sed -i '1i desktop-image: ""' "$WORK/broken/themes/1920x1080/theme.txt"
out="$("$WORK/broken/install.sh" --root "$R" -y -r 1920x1080 2>&1)"; rc=$?
check "broken theme exits non-zero"  test "$rc" -ne 0
check "empty image path is named in the error" grep -q 'empty image path' <<<"$out"
check "...and nothing was installed" bash -c "! test -e '$R/boot/grub/themes/najm'"

mkdir -p "$R/etc/default/grub.d"; echo 'GRUB_TERMINAL=console' >"$R/etc/default/grub.d/50-cloud.cfg"
out="$("$INSTALL" --root "$R" -y -r 1920x1080 2>&1)"
check "drop-in override is reported" grep -q '50-cloud.cfg also sets' <<<"$out"

# ---------------------------------------------------------------------------
t "grub-mkconfig integration (stub on PATH)"
R="$(mkroot mk grub)"; mkdir -p "$WORK/bin"
cat >"$WORK/bin/grub-mkconfig" <<EOF
#!/usr/bin/env bash
[[ "\$1" == -o ]] || exit 2
echo "set theme=/boot/grub/themes/najm/theme.txt" >"\$2"
EOF
chmod +x "$WORK/bin/grub-mkconfig"
PATH="$WORK/bin:$PATH" "$INSTALL" --root "$R" --regenerate -y -r 1920x1080 >"$WORK/out" 2>&1
check "stub regenerated grub.cfg"    grep -q 'themes/najm/theme.txt' "$R/boot/grub/grub.cfg"
check "verification message shown"   grep -q 'grub.cfg references the theme' "$WORK/out"
cp "$R/etc/default/grub" "$WORK/mk.before"
printf '#!/usr/bin/env bash\necho boom >&2; exit 1\n' >"$WORK/bin/grub-mkconfig"
PATH="$WORK/bin:$PATH" "$INSTALL" --root "$R" --regenerate -y -r 2560x1440 >"$WORK/out" 2>&1; rc=$?
check "failure exits non-zero"       test "$rc" -ne 0
check "settings rolled back"         diff -q "$R/etc/default/grub" "$WORK/mk.before"
check "previous theme restored"      grep -q 'Najm GRUB theme - 1920x1080' "$R/boot/grub/themes/najm/theme.txt"

# ---------------------------------------------------------------------------
t "NixOS is refused with guidance"
R="$(mkroot nix grub)"; touch "$R/etc/NIXOS"
out="$("$INSTALL" --root "$R" -y -r 1920x1080 2>&1)"; rc=$?
check "exit code 2"                  test "$rc" -eq 2
check "points to --export + nix option" grep -q 'boot.loader.grub.theme' <<<"$out"
check "/etc/default/grub untouched"  bash -c "! grep -q najm-grub-theme '$R/etc/default/grub'"
"$INSTALL" --export "$WORK/exported" -r 1920x1080 >/dev/null 2>&1
check "--export writes a usable theme dir" test -f "$WORK/exported/theme.txt"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
exit $((FAIL > 0))

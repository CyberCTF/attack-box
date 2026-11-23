#!/usr/bin/env bash
# shellcheck disable=SC2016 # the scripts' own text, its `$` literal
# The scripts' behaviour, on stand-ins for the tools they call (no root, no VM): what the launcher
# relies on when it downloads them at its pinned commit. Run by ./check.sh. Moved from the
# launcher's own tests (src-tauri/src/runtime/attack_box/tests.rs) when it stopped keeping a copy.
set -euo pipefail
cd "$(dirname "$0")/.."

failed=0
fail() { echo "FAIL: $*" >&2; failed=1; }
ok() { echo "ok: $*"; }
contains() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }
# The position of $2 in $1 (its first), -1 when absent.
at() { local rest="${1%%"$2"*}"; if [ "$rest" = "$1" ]; then echo -1; else echo "${#rest}"; fi; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Stand-in programs in a folder of their own, first on PATH.
stub() { mkdir -p "$1"; printf '%s\n' "$3" > "$1/$2"; chmod 755 "$1/$2"; }

# --- vm/kali.sh: Kali's archive keyring checked before apt trusts it --------------------------
kali="$(cat vm/kali.sh)"
for key in 827C8569F2518CC677FECA1AED65462EC8D5E4C5 44C6513A8E4FB3D30875F758ED444FF07D8D0BF6; do
  contains "$kali" "$key" || fail "kali.sh: Kali's archive key $key"
done
download=$(at "$kali" "archive.kali.org/archive-keyring.gpg")
checked=$(at "$kali" '[ "$k" = "44C6513A8E4FB3D30875F758ED444FF07D8D0BF6 827C8569F2518CC677FECA1AED65462EC8D5E4C5" ]')
refused=$(at "$kali" "Nothing was installed")
trusted=$(at "$kali" "/usr/share/keyrings/kali-archive-keyring.gpg")
used=$(at "$kali" "signed-by=")
if [ "$download" -ge 0 ] && [ "$download" -lt "$checked" ] && [ "$checked" -lt "$trusted" ] && [ "$refused" -lt "$trusted" ] && [ "$trusted" -lt "$used" ]; then
  ok "kali.sh checks the keyring before apt trusts it"
else
  fail "kali.sh: downloaded ($download) < checked ($checked) and refused ($refused) < trusted ($trusted) < used ($used)"
fi
if ! contains "$kali" '-o "$d/key"' || contains "$kali" "-o /usr/share/keyrings"; then fail "kali.sh: the keyring is downloaded into the private folder"; fi

# --- vm/toolset.sh: nothing on Kali's own box, a small fixed set elsewhere -------------------
toolset_calls() { # $1: dpkg-query's answer for the toolset
  local dir="$tmp/toolset-$RANDOM"
  stub "$dir" dpkg-query "#!/bin/sh
printf '%s' '$1'"
  stub "$dir" apt-get "#!/bin/sh
echo \"\$*\" >> '$dir/calls'"
  { echo "keep=''"; cat vm/toolset.sh; } | PATH="$dir:/usr/bin:/bin" sh
  cat "$dir/calls" 2>/dev/null || true
}
if [ -z "$(toolset_calls 'install ok installed')" ]; then ok "a box with the toolset takes nothing from the archive"; else fail "toolset.sh: a box with the toolset called apt-get"; fi
got="$(toolset_calls '')"
first="$(printf '%s\n' "$got" | head -1)"
install="$(printf '%s\n' "$got" | sed -n 2p)"
if [ "$first" = update ] && contains "$install" 'install -y kali-linux-core nmap' && contains "$install" ' sqlmap ' && ! contains "$install" kali-linux-headless; then
  ok "a box without Kali's toolset (Debian made Kali, on Arm) is given the small set, not all of it"
else
  fail "toolset.sh: without the toolset: got [$got]"
fi

# --- player-account.sh: the account, its sudo, its password, the shared folder's group -------
account="$(cat player-account.sh)"
if contains "$account" '{ printf '"'"'%s:'"'"' "$account"; cat "$password_hash"; } | chpasswd -e'; then ok "the password's hash goes to chpasswd on its standard input, never a command line"; else fail "player-account.sh: the hash read from its file into chpasswd -e"; fi
if ! contains "$account" "NOPASSWD: ALL" || ! contains "$account" "--create-home"; then fail "player-account.sh: a home and sudo with no password"; fi
account_calls() { # $1: shared_squashed's value; a shared folder owned by uid/gid 1000 (`vagrant`)
  local dir="$tmp/account-$RANDOM"
  mkdir -p "$dir/shared" "$dir/sudoers.d"
  local record="#!/bin/sh
echo \"\$(basename \"\$0\") \$*\" >> '$dir/calls'"
  stub "$dir/bin" stat "#!/bin/sh
echo 1000"
  stub "$dir/bin" getent "#!/bin/sh
case \"\$1 \$2\" in
  'passwd 1000') echo 'vagrant:x:1000:1000::/home/vagrant:/bin/sh' ;;
  'group 1000') echo 'vagrant:x:1000:' ;;
  *) exit 2 ;;
esac"
  stub "$dir/bin" id "#!/bin/sh
exit 1"
  for t in useradd usermod groupadd; do stub "$dir/bin" "$t" "$record"; done
  # The sudo rule goes to the test's folder, not the computer's.
  sed "s|/etc/sudoers.d|$dir/sudoers.d|g" player-account.sh > "$dir/player-account.sh"
  PATH="$dir/bin:/usr/bin:/bin" account=player shared="$dir/shared" shared_squashed="$1" sh "$dir/player-account.sh"
  [ -f "$dir/sudoers.d/player" ] || fail "player-account.sh: its sudo rule"
  cat "$dir/calls"
}
shell=/bin/sh; [ -x /bin/bash ] && shell=/bin/bash
got="$(account_calls '')"
want="useradd --create-home --shell $shell player"$'\n'"usermod -a -G vagrant player"
if [ "$got" = "$want" ]; then ok "the player joins the shared folder's group"; else fail "player-account.sh: not squashed: got [$got], want [$want]"; fi
# Regression: on QEMU under Linux the player couldn't write in the shared folder through a
# supplementary group, which the unprivileged virtiofsd refuses.
got="$(account_calls 1)"
want="useradd --create-home --shell $shell player"$'\n'"usermod -g vagrant player"
if [ "$got" = "$want" ]; then ok "where the folder is squashed, its group is the player's own"; else fail "player-account.sh: squashed: got [$got], want [$want]"; fi

# --- vm/desktop.sh: XFCE, the player signed in, the screen never locked ----------------------
desktop="$(cat vm/desktop.sh)"
for want in "install -y \$keep kali-desktop-xfce lightdm" "autologin-user=player" "systemctl set-default graphical.target" \
  "xserver-command=X -s 0 -dpms" "for locker in light-locker xfce4-screensaver" "Hidden=true" "xset s off -dpms" \
  "off xfce4-screensaver /lock/enabled" "off xfce4-power-manager /xfce4-power-manager/lock-screen-suspend-hibernate" \
  "off xfce4-session /shutdown/LockScreen" "/etc/xdg/autostart/cyberctf-no-screen-lock.desktop" "/home/player/.config/autostart"; do
  contains "$desktop" "$want" || fail "desktop.sh: $want"
done
# --- nothing accepted on the player's behalf ---------------------------------------------------
# No switch that accepts a licence, an agreement or terms for the player (comments aside): where a
# vendor asks, its own window shows it and the player accepts it there. Moved from the launcher's
# consent scan (src-tauri/src/testing/source_scan/consent.rs).
accepts='--accept-license|--accept-licence|--accept-package-agreements|--accept-source-agreements|--accept-eula|--accept-terms|--agree-tos|-license accept|accepted-license|license select true|accept_eula|accepteula|/eula'
for f in player-account.sh vm/*.sh Dockerfile bashrc.cyberctf; do
  found="$(grep -vE '^[[:space:]]*#' "$f" | grep -inE -e "$accepts" || true)"
  if [ -n "$found" ]; then fail "$f accepts for the player: $found"; fi
done

if [ "$failed" = 0 ]; then ok "the scripts behave as the launcher relies on"; fi

exit "$failed"

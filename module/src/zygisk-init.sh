#!/system/bin/sh

MODDIR=${0%/*}
if [ "$ZYGISK_ENABLED" ]; then
  exit 0
fi

cd "$MODDIR"

TMP_PATH=@WORK_DIRECTORY@

# True when $1 carries a label zygote and system_server can already use for the work
# directory: system_file (the normal relabel) or zygisk_file (the tmpfs fallback below).
# Matches anywhere in the `ls -Z` line so it does not depend on field order, and avoids awk,
# which Android's toybox does not ship.
is_usable_label() {
  case "$(ls -Zd "$1" 2>/dev/null)" in
    *u:object_r:system_file:s0*|*u:object_r:zygisk_file:s0*) return 0 ;;
    *) return 1 ;;
  esac
}

# The work directory has to be traversable by uid 1000: a late-injected system_server
# dlopens the library and connects to the control socket in its own context, and that is a
# DAC check which no SELinux setting relaxes. Hence system:system ownership and a mode that
# grants search to all. Root still writes here through CAP_DAC_OVERRIDE.
#
# It also has to carry a label zygote and system_server can read and execute from. Normally
# that is system_file, set by the chcon below: under /data it just works, and on the /dev
# tmpfs it works wherever the root domain is allowed `relabelfrom device`. On a kernel whose
# policy denies that relabel the chcon is a silent no-op, leaving the library unreadable to
# zygote and injection broken. In that case force a usable label by mounting a dedicated
# tmpfs over the directory with a fixed context=, which needs no relabel at all. The context
# is zygisk_file, not system_file, because a context= mount applies one type to every file
# under it -- including the control socket, which the sepolicy rules expect to be
# zygisk_file -- and a matching `allow zygote/system_server zygisk_file file` rule covers the
# library. The fallback is skipped whenever the directory already reads back as a usable
# label, which covers both the normal case and a tmpfs left mounted by an earlier session, so
# a live control socket is never masked by a second mount and a reached-here directory was
# only just created this run and holds nothing yet.
create_sys_perm() {
  mkdir -p "$1"
  chmod 555 "$1"
  chcon u:object_r:system_file:s0 "$1" 2>/dev/null
  chown system:system "$1"

  if ! is_usable_label "$1"; then
    log -p w -t "zygisk-sh" "could not relabel $1, mounting tmpfs with fixed zygisk_file context"
    mount -t tmpfs -o context=u:object_r:zygisk_file:s0 tmpfs "$1"
    chmod 555 "$1"
    chown system:system "$1"
  fi
}

# Install a library without disturbing the copy a running process may already have mapped.
# Writing in place would either fail with ETXTBSY or mutate a mapped file, renaming over it
# publishes the new inode and leaves existing mappings on the old one, which is released
# when the last of those processes exits.
install_lib() {
  src="$1"
  dst="$2"
  [ -f "$src" ] || return 0
  create_sys_perm "${dst%/*}"
  cp -f "$src" "$dst.new" || return 1
  chmod 644 "$dst.new"
  chcon u:object_r:system_file:s0 "$dst.new"
  chown system:system "$dst.new"
  mv -f "$dst.new" "$dst"
}

# The work directory is deliberately not wiped. On a late load or a soft reboot a monitor
# from the previous root session may still own the control socket here, and removing it
# would leave that monitor unreachable while injected processes keep running. A stale
# socket from a dead monitor is unlinked by the next monitor when it binds.
create_sys_perm "$TMP_PATH"
install_lib "$MODDIR/lib64/libzygisk.so" "$TMP_PATH/lib64/libzygisk.so"
install_lib "$MODDIR/lib/libzygisk.so" "$TMP_PATH/lib/libzygisk.so"

[ "$DEBUG" = true ] && export RUST_BACKTRACE=1

if [ -f "$MODDIR/bin/zygisk-ptrace64" ]; then
  TRACER="$MODDIR/bin/zygisk-ptrace64"
elif [ -f "$MODDIR/bin/zygisk-ptrace32" ]; then
  TRACER="$MODDIR/bin/zygisk-ptrace32"
else
  log -p e -t "zygisk-sh" "No tracer binary found in $MODDIR/bin"
  exit 1
fi

# Unconditional: the monitor enforces the single-owner invariant itself and a redundant
# one exits immediately, so neither this script nor a soft reboot has to probe for it.
"$TRACER" monitor &

#!/bin/sh
# Railway entrypoint for Paperclip.
#
# Same contract as upstream's scripts/docker-entrypoint.sh — remap the node user if the
# runtime asks for it, then drop privileges — with the ownership repair moved OUT of the
# remap branch. On Railway the volume arrives owned by uid 0 while USER_UID/USER_GID are
# already 1000, so upstream's release entrypoint performs no remap, performs no chown,
# and hands an unwritable $PAPERCLIP_HOME to the unprivileged process.
#
# This is upstream commit dd1a7f5 applied ahead of its first tagged release.
set -e

PUID=${USER_UID:-1000}
PGID=${USER_GID:-1000}

# Unprivileged already: we can neither remap nor chown nor gosu. Run as-is, and say so,
# because a volume-permission failure after this point is otherwise undiagnosable.
if [ "$(id -u)" -ne 0 ]; then
    if [ "$(id -u)" -ne "$PUID" ] || [ "$(id -g)" -ne "$PGID" ]; then
        echo "railway-entrypoint: running unprivileged as $(id -u):$(id -g); cannot remap to ${PUID}:${PGID}" >&2
    fi
    exec "$@"
fi

if [ "$(id -u node)" -ne "$PUID" ]; then
    echo "railway-entrypoint: updating node UID to $PUID"
    usermod -o -u "$PUID" node
fi

if [ "$(id -g node)" -ne "$PGID" ]; then
    echo "railway-entrypoint: updating node GID to $PGID"
    groupmod -o -g "$PGID" node
    usermod -g "$PGID" node
fi

# One metadata-only walk that stops at the first entry not owned by node:node. A fresh
# Railway volume matches on its own mount point (and on ext4's root-owned lost+found), so
# the repair runs exactly when it is needed and costs nothing when it is not.
home_dir="${PAPERCLIP_HOME:-/paperclip}"
if [ -d "$home_dir" ] && [ -n "$(find "$home_dir" \( ! -user node -o ! -group node \) -print -quit 2>/dev/null)" ]; then
    echo "railway-entrypoint: repairing ownership of $home_dir for node:node"
    chown -R node:node "$home_dir"
fi

exec gosu node "$@"

# Railway-tuned Paperclip image.
#
# FROM the official upstream image built from the v2026.722.0 release commit, plus one
# fix that release needs to survive a Railway volume:
#
#   Railway mounts a volume owned by uid 0. The entrypoint in this release chowns
#   $PAPERCLIP_HOME only when a UID/GID *remap* was requested (USER_UID/USER_GID differ
#   from the image's node user) — and on Railway they do not, because the image already
#   defaults both to 1000. So the entrypoint drops to `node` with `gosu` onto a
#   root-owned home, and the server dies on its first mkdir:
#
#       Error: EACCES: permission denied, mkdir '/paperclip/instances/default/logs'
#           at <anonymous> (/app/server/src/middleware/logger.ts:22:4)
#
#   Reproduced on Railway 2026-07-31 against ghcr.io/paperclipai/paperclip:sha-e55d702
#   with a volume at /paperclip: crash loop, ten restarts, never healthy.
#
#   Upstream fixed exactly this in dd1a7f5 ("Ensure app-home ownership before the
#   privilege drop, not only on remap", 2026-07-31) — hours after we hit it, and not in
#   any tagged release yet. railway-entrypoint.sh below is that fix applied ahead of the
#   next release, so this image stays on a real release rather than a master build.
FROM ghcr.io/paperclipai/paperclip:sha-e55d702

COPY railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh
RUN chmod +x /usr/local/bin/railway-entrypoint.sh

# Railway probes a service's healthcheck with `Host: healthcheck.railway.app`. Paperclip
# ships PAPERCLIP_DEPLOYMENT_EXPOSURE=private, which enables privateHostnameGuard: every
# request whose Host is outside the allow set is answered 403 — including that probe, so
# the healthcheck never passes, the deploy never goes live, and the edge serves 404 while
# the container logs `GET /api/health 403`. Measured on Railway 2026-07-31.
#
# The allow set is this list plus the hostname parsed out of PAPERCLIP_PUBLIC_URL, so the
# deployer's own Railway domain still gets in without being named here. Baked as ENV
# rather than shipped as a template variable to keep the deploy form empty (a literal
# variable loses its default in templateGenerate and publishes as required-with-no-value).
#
# Deployers adding a custom domain override PAPERCLIP_ALLOWED_HOSTNAMES — keep
# healthcheck.railway.app in the list when you do.
ENV PAPERCLIP_ALLOWED_HOSTNAMES=healthcheck.railway.app

EXPOSE 3100

# Everything else the upstream image already sets stays untouched: HOST=0.0.0.0,
# PORT=3100 (Railway injects its own PORT, which the server honours), SERVE_UI=true,
# HOME=/paperclip, PAPERCLIP_HOME=/paperclip, PAPERCLIP_DEPLOYMENT_MODE=authenticated,
# PAPERCLIP_DEPLOYMENT_EXPOSURE=private. Baking them here rather than shipping them as
# template variables is what keeps the Railway deploy form empty: templateGenerate keeps
# a variable's default only when the live value is a Railway expression, so a literal
# would publish as "required, no value".
#
# Do NOT set a Railway start command on top of this image: a start command REPLACES the
# entrypoint, so it would skip the ownership repair and the drop to the `node` user.
ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]
CMD ["node", "--import", "./server/node_modules/tsx/dist/loader.mjs", "server/dist/index.js"]

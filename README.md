# paperclip-railway

Railway-tuned [Paperclip](https://github.com/paperclipai/paperclip) image:
`ghcr.io/bon5co/paperclip-railway`.

`FROM ghcr.io/paperclipai/paperclip:sha-e55d702` (the official image built from the
`v2026.722.0` release commit) plus one fix.

## The fix

Railway mounts volumes owned by uid 0. The entrypoint shipped in that release repairs
`$PAPERCLIP_HOME` ownership **only when a UID/GID remap was requested** — and on Railway
none is, because `USER_UID`/`USER_GID` already default to the image's `node` user (1000).
So the entrypoint `gosu`-drops onto a root-owned home and the server dies immediately:

```
Error: EACCES: permission denied, mkdir '/paperclip/instances/default/logs'
    at <anonymous> (/app/server/src/middleware/logger.ts:22:4)
```

Reproduced on Railway on 2026-07-31 with a volume mounted at `/paperclip`: crash loop,
ten restarts, never healthy.

Upstream fixed exactly this in
[`dd1a7f5`](https://github.com/paperclipai/paperclip/commit/dd1a7f5) ("Ensure app-home
ownership before the privilege drop, not only on remap"), which is not in a tagged
release yet. `railway-entrypoint.sh` is that fix, applied on top of a real release rather
than tracking a master build.

Nothing else is changed: every environment default the upstream image bakes
(`HOST=0.0.0.0`, `PORT=3100`, `SERVE_UI=true`, `HOME=/paperclip`,
`PAPERCLIP_HOME=/paperclip`, `PAPERCLIP_DEPLOYMENT_MODE=authenticated`,
`PAPERCLIP_DEPLOYMENT_EXPOSURE=private`) is inherited as-is.

## Using it

Do **not** set a Railway start command on this image — a start command replaces the
entrypoint, which would skip both the ownership repair and the drop to the unprivileged
`node` user. Mount a volume at `/paperclip`, point `DATABASE_URL` at a Postgres service,
and set `BETTER_AUTH_SECRET`, `PAPERCLIP_TOOL_ACTION_SIGNING_SECRET` and
`PAPERCLIP_PUBLIC_URL`.

Full template (two services, empty deploy form):
[bon5co/railwaytemplate2 → `paperclip/`](https://github.com/bon5co/railwaytemplate2).

## Upgrading

Bump the base tag in `Dockerfile` to the image built from the release commit you want
(`gh api repos/paperclipai/paperclip/git/ref/tags/<tag>` gives the commit; upstream tags
each image `sha-<short>`). Once a release ships with `dd1a7f5` in it, this wrapper's
entrypoint becomes redundant and the template can point straight at the upstream image.

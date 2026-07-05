# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A single-file MCP server (`server.ts`, run on Bun) that bridges **one** Matrix room to Claude Code's experimental `claude/channel` feature. Incoming Matrix text messages are pushed to the MCP client as `notifications/claude/channel`; the `reply` tool sends text back into the room. The other side of the conversation is a human in a Matrix client (e.g. Element), not the terminal session.

## Commands

```bash
bun server.ts                       # run, stdio transport (default)
bun server.ts --transport http -p 3000   # run over Streamable HTTP instead
bun server.ts --help                # usage + env vars

bun run typecheck                   # tsc --noEmit
bun run lint                        # eslint .   (lint:fix to autofix)
bun run format                      # prettier --write .   (format:check to verify)

docker compose up -d                # local Matrix stack (see below)
```

There are no tests.

## Local Matrix stack

`docker compose up` starts `continuwuity` (a Matrix homeserver) on `localhost:8008` with **open registration** (dev only) and `element-web` on `localhost:8080` (configured by `element-config.json`). Create a bot user + room here, then point the server at it via env. `docker compose ps` to check status.

## Configuration

Transport options come from CLI flags **or** env, with precedence **CLI flag > env var > default**:

- `--transport` / `MCP_TRANSPORT`: `stdio` (default) | `http`
- `--port` / `MCP_PORT`: HTTP port (default 3000)

Matrix creds come from env only (validated by zod at startup; the process `exit(1)`s on a bad/missing value):

- `MATRIX_ACCESS_TOKEN` — **required**
- `MATRIX_ROOM_ID` — **required**
- `MATRIX_BASE_URL` — default `http://localhost:8008`
- `MATRIX_USER_ID` — default `@claude:localhost`

**Launching as an MCP server:** `.mcp.json` registers this as the `matrix` server (`bun server.ts`). The Matrix env must reach that subprocess. The reliable place is `.mcp.json`'s per-server `env` block, or the global `~/.claude/settings.json` `env`. (In practice, project `.claude/settings.local.json` `env` did **not** reliably propagate to the MCP subprocess — prefer the two above.)

## Architecture & non-obvious constraints

Startup order in `server.ts` is deliberate: parse config → build `McpServer` → install the logger → create the Matrix client → register the `reply` tool → **connect the MCP transport, then** `startClient()` + wait for the initial sync → subscribe to the room timeline.

- **The MCP transport is connected _before_ the Matrix sync**, so matrix-js-sdk's startup logs already flow over the MCP channel. The server then requires the bot to be a member of `MATRIX_ROOM_ID` — it throws if `client.getRoom(roomId)` is null after sync.
- **stdio mode: stdout is the JSON-RPC framing channel.** Nothing may write to stdout except the protocol, or the client drops the connection. This is why matrix-js-sdk logging is redirected (see logger note) and why `--help` is the one thing allowed on stdout — it writes there and `exit`s before any transport connects.
- **matrix-js-sdk logging → MCP logging notifications.** `McpLogger implements Logger` forwards every level to `mcp.server.sendLoggingMessage`. It's both injected into `createClient({ logger })` (covers the client's own logs) **and** patched onto matrix's _global_ exported `logger` in place via `Object.assign` (covers the ~80% of log sites that `import { logger }` at module scope — the ESM binding can't be reassigned, but the object's methods can be overwritten, and children created afterward via `getChild` inherit it). Requires `capabilities.logging` on the server, else `sendLoggingMessage` is a silent no-op.
- **Room subscription is on the `Room` object, not the client.** `room.on(RoomEvent.Timeline, …)` after sync — no need to filter by room id. A bounded FIFO `Set` (`SEEN_LIMIT`) dedupes re-emitted events (decryption / echo reconciliation arrive close in time); it is capped so it can't grow unbounded on a long-lived process.

## Gotchas that will bite typecheck / builds

- **zod is deduped via `overrides` in `package.json`.** The MCP SDK depends on zod `^3.25 || ^4.0` and bun otherwise installs a **second, nested** zod v3 under the SDK; the SDK's `registerTool` types then resolve against that copy and reject the app's zod v4 schemas (`ZodString is not assignable to AnySchema`). `overrides.zod` + `bun install --force` collapses it to one zod v4. **Do not remove the override.** Verify with `find node_modules -path '*/zod/package.json'` — there must be exactly one.
- **`tsconfig.json` is Bun-flavored** (`moduleResolution: bundler`, `types: ["bun"]`, `skipLibCheck`). `skipLibCheck` is load-bearing — without it, matrix-js-sdk's crypto-wasm `.d.ts` and the SDK's `.d.ts` throw ~100 errors unrelated to this code. Typecheck only via `bun run typecheck`, never bare `tsc` with default settings.

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A single-file MCP server (`server.py`, run on Python via uv) that bridges **one** Matrix room to Claude Code's experimental `claude/channel` feature. Incoming Matrix text messages are pushed to the MCP client as `notifications/claude/channel`; the `reply` tool sends text back into the room. The other side of the conversation is a human in a Matrix client (e.g. Element), not the terminal session.

Built on the [`mcp`](https://github.com/modelcontextprotocol/python-sdk) SDK (`FastMCP`, with two hooks into its private `_mcp_server` — see Architecture) and [`mautrix`](https://github.com/mautrix/python) as the Matrix client.

## Commands

```bash
uv run server.py                          # run, stdio transport (default)
uv run server.py --transport http -p 3000 # run over Streamable HTTP instead
uv run server.py --help                   # usage + env vars

uv run ty check                     # type check
uv run ruff check                   # lint    (--fix to autofix)
uv run ruff format                  # format  (--check to verify)

docker compose up -d                # local Matrix stack (see below)
```

There are no tests.

## Local Matrix stack

`docker compose up` starts `continuwuity` (a Matrix homeserver) on `localhost:8008` with **open registration** (dev only) and `element-web` on `localhost:8080` (configured by `element-config.json`). Create a bot user + room here, then point the server at it via env. `docker compose ps` to check status.

## Configuration

Transport options come from CLI flags **or** env, with precedence **CLI flag > env var > default**:

- `--transport` / `MCP_TRANSPORT`: `stdio` (default) | `http`
- `--port` / `MCP_PORT`: HTTP port (default 3000)

Matrix creds come from env only (validated by pydantic-settings `BaseSettings` at startup; the process `exit(1)`s on a bad/missing value):

- `MATRIX_ACCESS_TOKEN` — **required**
- `MATRIX_ROOM_ID` — **required**
- `MATRIX_BASE_URL` — default `http://localhost:8008`
- `MATRIX_USER_ID` — default `@claude:localhost`

**Launching as an MCP server:** `.mcp.json` registers this as the `matrix` server (`uv run server.py`). The Matrix env must reach that subprocess. The reliable place is `.mcp.json`'s per-server `env` block, or the global `~/.claude/settings.json` `env`. (In practice, project `.claude/settings.local.json` `env` did **not** reliably propagate to the MCP subprocess — prefer the two above.)

## Architecture & non-obvious constraints

`serve()` drives its own asyncio loop (via `asyncio.run` in `main`), deliberately in this order: create the Matrix client + timeline handler → **start Matrix first** (`get_joined_rooms()` membership check, then `client.start()`) → build `FastMCP` + install two internal hooks → register tools → `mcp.run_stdio_async()` / `mcp.run_streamable_http_async()`. Matrix comes up **before** the MCP transport so a bad token / non-membership fails fast, and messages arriving pre-connection are buffered (see `Outbound`).

- **FastMCP, made to fit via two hooks on `mcp._mcp_server`.** FastMCP gives the easy tool ergonomics (`@mcp.tool()`, schema from signatures, `run_*_async`) but hides two things this server needs, so we reach into its private low-level `_mcp_server`:
  1. **Experimental capability.** `experimental={"claude/channel": {}}` — FastMCP calls `create_initialization_options()` with no args, so we wrap that method (`setdefault` the capability). It's the one injection point.
  2. **Spontaneous session capture.** The server pushes a **custom, non-standard** notification (`notifications/claude/channel`) **outside any tool call**; FastMCP only exposes the session inside a request. So we wrap the `ListToolsRequest` handler in `_mcp_server.request_handlers` to grab `request_context.session` at `tools/list` (fires right after `initialize`, before any Matrix message can need it) and rebind on each call (HTTP makes a new session per connection).
  These are private-attribute pokes — the accepted cost of using FastMCP here. `mcp._mcp_server.version` is also set (FastMCP otherwise reports the SDK version).
- **Spontaneous push = the `Outbound` holder.** Matrix messages arrive with no request in flight. `Outbound` holds the captured session's `send_message` and **buffers** anything sent before capture (or before an MCP client connects — Matrix starts first). Each push is a raw `JSONRPCNotification`.
- **stdio mode: stdout is the JSON-RPC framing channel.** Nothing may write to stdout except the protocol, or the client drops the connection. mautrix logs via stdlib `logging` (namespace `mau`); with no handler configured they fall through to **stderr**, which is safe; FastMCP also logs to stderr. `--help` is the one thing on stdout — argparse writes it there and `exit`s before any transport. (There is intentionally **no** MCP logging bridge / `notifications/message`.)
- **Only live events.** `client.ignore_first_sync = True` + `client.ignore_initial_sync = True` skip the backfill of the first/initial sync (the equivalent of waiting for js-sdk's `Prepared` before subscribing). The timeline handler filters by `room_id` and skips the bot's own messages. Edits are resolved natively by mautrix — `content.get_edit()` flags them and `content.body` already holds the corrected text; `content.get("m.mentions")` carries `user_ids`. (No `SEEN_LIMIT` dedup like the TS version: mautrix delivers each event once.)

## Gotchas that will bite lint / typecheck

- **`mautrix.util.markdown` needs `commonmark`**, which mautrix does **not** pull in itself (`import commonmark` at module load → `ModuleNotFoundError` otherwise). It's an explicit dependency in `pyproject.toml`; don't drop it.
- **Matrix ids are pydantic-typed as mautrix NewTypes.** `MatrixSettings.room_id`/`user_id` use `RoomID`/`UserID` (not bare `str`) so `ty` accepts them at the mautrix call sites. `MatrixSettings()` needs a `# ty: ignore[missing-argument]` — `ty` can't see that pydantic-settings fills the required fields from env.
- **Don't annotate the timeline handler with `mautrix.types.Event`.** `add_event_handler` expects `(Event) -> Awaitable`, but `Event` is a `NewType` over a **Union** — invalid in a type expression for strict checkers ("Variable not allowed in type expression"). Annotate `on_message(evt: MessageEvent)` and `cast(EventHandler, on_message)` at registration.
- **`mcp` is pinned `>=1.27,<2`.** v2 is a rewrite (handlers in the constructor, `mcp_types`, different internals — including the private `_mcp_server` surface these hooks depend on); `uv sync` must not resolve v2.
- **E501 is ignored in ruff** because the channel instructions and tool descriptions are deliberately long single-line prose strings.

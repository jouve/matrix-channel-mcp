# matrix-channel-mcp

A small [MCP](https://modelcontextprotocol.io) server that bridges **one Matrix room** to Claude Code's `claude/channel` feature. Send a message from Matrix (e.g. [Element](https://element.io)) and it reaches your Claude Code session; Claude answers back into the room. It's a way to talk to a running Claude Code session from your chat app.

```
Matrix room  ⇄  server.py (MCP)  ⇄  Claude Code
 (a human)                          (your session)
```

## Requirements

- [uv](https://docs.astral.sh/uv/)
- Docker + Docker Compose (only for the bundled local Matrix homeserver — skip if you already have one)

## Quick start

### 1. Install dependencies

```bash
uv sync
```

### 2. Start a Matrix homeserver

The repo ships a ready-to-run local stack:

```bash
docker compose up -d
```

This starts:

- **continuwuity** — a Matrix homeserver on `http://localhost:8008` (open registration, **local dev only**)
- **element-web** — a Matrix web client on `http://localhost:8080`

### 3. Create a bot account and a room

Open `http://localhost:8080`, register an account for the bot (e.g. `claude`), create a room, and note two things:

- the **access token** — Element → _Settings → Help & About → Access Token_
- the **room ID** (looks like `!abcd…:localhost`) — room _Settings → Advanced → Internal room ID_

Make sure the bot account is a **member of the room**.

### 4. Configure

The server reads Matrix credentials from environment variables:

| Variable              | Required | Default                 |
| --------------------- | -------- | ----------------------- |
| `MATRIX_ACCESS_TOKEN` | ✅       | —                       |
| `MATRIX_ROOM_ID`      | ✅       | —                       |
| `MATRIX_BASE_URL`     |          | `http://localhost:8008` |
| `MATRIX_USER_ID`      |          | `@claude:localhost`     |

Quick check that it starts:

```bash
MATRIX_ACCESS_TOKEN=… MATRIX_ROOM_ID='!…' uv run server.py
```

### 5. Wire it into Claude Code

`.mcp.json` already registers this project as the `matrix` MCP server. Add the credentials to its `env` block so Claude Code passes them to the server:

```json
{
  "mcpServers": {
    "matrix": {
      "command": "uv",
      "args": ["run", "server.py"],
      "env": {
        "MATRIX_ACCESS_TOKEN": "…",
        "MATRIX_ROOM_ID": "!…"
      }
    }
  }
}
```

Restart / reconnect the MCP server in Claude Code (`/mcp`). Now messages posted in the Matrix room show up in your Claude Code session, and Claude replies back into the room.

> Prefer to keep the token out of a committed file? Put the same `env` block in your global `.claude/settings.local.json` instead.

## Transports

Runs over stdio by default (what Claude Code uses). It can also serve over HTTP:

```bash
uv run server.py --transport http --port 3000
uv run server.py --help          # all options
```

## Development

```bash
uv run ty check            # type check
uv run ruff check          # lint       (--fix to autofix)
uv run ruff format         # format     (--check to verify)
```

See [CLAUDE.md](./CLAUDE.md) for the internal architecture and a few sharp edges (why Matrix starts before the MCP transport, and the two hooks into FastMCP's internals that make the experimental capability and spontaneous notifications work).

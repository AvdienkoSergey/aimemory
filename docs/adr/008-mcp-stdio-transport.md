# ADR-008: MCP Integration via stdio JSON-RPC

**Status:** Accepted
**Date:** 2026-03-30

## Context

aimemory has a CLI (`call`, `schemas`, `status`, `reset`) that works, but AI assistants (Claude Code, Claude Desktop) need a live MCP server they can talk to over JSON-RPC 2.0.

Requirements:
- Claude Code discovers tools via `tools/list` and calls them via `tools/call`
- Transport must be stdio (stdin/stdout) — this is what `.mcp.json` expects
- Existing CLI commands must keep working without changes
- Logging must not go to stdout (stdout is the protocol channel)

Options:
1. **HTTP server:** run on a port, clients connect via HTTP
2. **stdio JSON-RPC:** read newline-delimited JSON from stdin, respond on stdout
3. **External wrapper:** separate process that translates MCP to CLI calls

## Decision

Option 2 — stdio JSON-RPC, implemented as `aimemory mcp` subcommand.

New module `Mcp_server` in the API layer handles the protocol. It reuses `Tools.dispatch` for all tool calls and `Tools.tool_schemas` for `tools/list` — no business logic duplication.

Supported methods:
- `initialize` — handshake, returns capabilities and server info
- `notifications/initialized` — client notification, no response
- `tools/list` — converts internal tool schemas to MCP format (name, description, inputSchema)
- `tools/call` — delegates to `Tools.dispatch`, wraps result in MCP content format
- `ping` — liveness check

Message framing: one JSON object per line (newline-delimited JSON). Empty lines are skipped. Server exits cleanly on EOF (stdin closed).

## Results

### Good
- **Zero duplication:** `Mcp_server` is a thin adapter over existing `Tools` module
- **CLI unchanged:** `mcp` is just another subcommand, like `call` or `status`
- **Layer discipline:** `Mcp_server` lives in API layer, depends only on `Tools` and `Log`
- **Testable via pipe:** `echo '{"jsonrpc":"2.0",...}' | aimemory mcp`

### Bad
- **No HTTP:** tools that need HTTP transport cannot use this server
- **Single connection:** stdio is inherently one client at a time

### Trade-offs
- Newline-delimited JSON (not Content-Length framing like LSP). Simpler to implement and debug, matches what Claude Code expects from stdio MCP servers
- `Mcp_server` converts `tool_schemas` format on the fly instead of storing MCP-native schemas. This avoids a second source of truth — if tools change, MCP schemas update automatically

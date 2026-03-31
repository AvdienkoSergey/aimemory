# Usage Guide

## 1. MCP Integration (Model Context Protocol)

MCP is a protocol for connecting tools to AI assistants. aimemory provides tools through JSON-RPC 2.0 stdio transport.

### 1.1 Installation

Download the binary for your platform from [GitHub Releases](https://github.com/AvdienkoSergey/aimemory/releases):

```bash
# macOS (Apple Silicon)
curl -L -o aimemory https://github.com/AvdienkoSergey/aimemory/releases/latest/download/aimemory-macos-arm64
chmod +x aimemory

# Windows (x64, PowerShell)
Invoke-WebRequest -Uri https://github.com/AvdienkoSergey/aimemory/releases/latest/download/aimemory-windows-x86_64.exe -OutFile aimemory.exe

# Linux (x64)
curl -L -o aimemory https://github.com/AvdienkoSergey/aimemory/releases/latest/download/aimemory-linux-x86_64
chmod +x aimemory
```

Move the binary to a directory in your PATH:

```bash
# macOS / Linux
sudo mv aimemory /usr/local/bin/

# Windows (PowerShell as admin)
Move-Item aimemory.exe C:\Windows\System32\
```

Check the installation:

```bash
aimemory --help
```

### 1.2 Setup for Claude Code (VS Code Extension)

**Step 1.** Create a `.mcp.json` file. Two options:

**Option A** — `.mcp.json` next to the project (database files stay outside the project):

```
~/projects/
├── .mcp.json
├── context.db         <-- database and log are created here
├── context.log
└── my-project/
    └── src/
```

```json
{
  "mcpServers": {
    "aimemory": {
      "type": "stdio",
      "command": "aimemory",
      "args": ["--db", "./context.db", "mcp"]
    }
  }
}
```

In VS Code open the folder `~/projects/` (File → Open Folder).

**Option B** — `.mcp.json` inside the project, database in a separate folder:

```
~/my-project/
├── .mcp.json
├── .aimemory/         <-- database and log are isolated
│   ├── context.db
│   └── context.log
└── src/
```

```json
{
  "mcpServers": {
    "aimemory": {
      "type": "stdio",
      "command": "aimemory",
      "args": ["--db", "./.aimemory/context.db", "mcp"]
    }
  }
}
```

> Don't forget to add `.mcp.json` and `.aimemory/` to `.gitignore`.

**Step 2.** Contents of `.mcp.json`:

```json
{
  "mcpServers": {
    "aimemory": {
      "type": "stdio",
      "command": "aimemory",
      "args": ["--db", "...path where database and log files will be stored...", "mcp"]
    }
  }
}
```

> If `aimemory` is not in PATH, use the full path: `"command": "/usr/local/bin/aimemory"`

**Step 3.** Restart the IDE. This is required — Claude Code reads `.mcp.json` only at startup. You need to do this once, when you create `.mcp.json`.

**Step 4.** Make sure Claude Code Extension in VS Code starts from the directory where `.mcp.json` is located. Open that folder in VS Code (File → Open Folder).

**Step 5.** Check the connection. If everything is set up correctly, when you open a chat with Claude Code, a `context.log` file will appear with a line like this:

```
2026-03-30 21:20:51 [INFO ] Logging initialized, file: ./context.log
```

This file means the MCP server has started and is ready for requests.

### 1.3 Setup for Claude Desktop

Add to Claude Desktop configuration:

```json
{
  "mcpServers": {
    "aimemory": {
      "command": "/usr/local/bin/aimemory",
      "args": ["--db", "/path/to/project/context.db", "mcp"],
      "env": {}
    }
  }
}
```

Configuration file paths:
- macOS: ~/Library/Application Support/Claude/claude_desktop_config.json
- Windows: %APPDATA%\Claude\claude_desktop_config.json
- Linux: ~/.config/Claude/claude_desktop_config.json

> If you have never connected local MCP servers before, see the [guide](https://modelcontextprotocol.io/docs/develop/connect-local-servers#enoent-error-and-appdata-in-paths-on-windows)

### 1.4 Available MCP tools

After connection, AI gets access to these tools:

| Tool | Description |
|------|-------------|
| `emit` | Save entities and relations |
| `query_entities` | Find entities by kind/pattern |
| `query_refs` | Find relations between entities |
| `status` | Statistics: how many entities, refs |

AI calls them automatically when it needs to save or recall information about code.

### 1.5 Testing MCP with a prompt

First, create a CLAUDE.md file next to `.mcp.json`. Inside, set a rule for working with `aimemory mcp` so you don't have to write it every time:

```
## MCP: aimemory

For any questions about dependencies, architecture, or relationships between code entities — use aimemory MCP tools (`query_refs`, `query_entities`, `status`) as the primary source. Fall back to grep/glob only if aimemory doesn't have the data.
```

Then run this prompt:

```
Analyze the structure of MY_PROJECT and create an entity map.

Start with:
1. Read package.json — find the framework and dependencies
2. Go through src/ — analyze each file and files in subdirectories one by one
3. For each file:
   - Read the file
   - Save entities to context memory
   - Note the relations

After the analysis show:
- How many entities were created (aimemory status)
- What pending refs are left
- What else should be analyzed
- Give a couple of prompts, one easy and one hard, to test the analysis
```

### 1.6 Adding ctx-scanner for automatic analysis

AI agent analyzes code file by file with grep/glob. On large projects this is slow. [ctx-scanner](https://github.com/AvdienkoSergey/ctx-scanner) parses TypeScript/Vue/React AST in seconds and fills the aimemory database automatically.

```
  source files          ctx-scanner              aimemory
 .ts .tsx .vue  -->  TypeScript AST  -->  fn: entities in SQLite
                       (MCP stdio)               |
                                                 | MCP
                                             AI agent
```

Scanner connects as a second MCP server next to aimemory. AI gets `scan` and `report` tools directly and decides when to run scanning.

#### Installation

```bash
git clone https://github.com/AvdienkoSergey/ctx-scanner.git
cd ctx-scanner
npm install && npm run build
npm link   # makes ctx-scanner command available globally
```

#### Setting up .mcp.json

Add scanner next to aimemory:

```json
{
  "mcpServers": {
    "aimemory": {
      "type": "stdio",
      "command": "aimemory",
      "args": ["--db", "./context.db", "mcp"]
    },
    "scanner": {
      "type": "stdio",
      "command": "ctx-scanner",
      "args": ["mcp"]
    }
  }
}
```

After restarting the IDE, AI will have two sets of tools:

| Server | Tools | Purpose |
|--------|-------|---------|
| aimemory | `emit`, `query_entities`, `query_refs`, `status` | Storage and queries |
| scanner | `scan`, `report` | AST parsing of source files |

#### What scanner extracts

For each exported function:

| Field | Example |
|-------|---------|
| LID | `fn:composables/useAuth/login` |
| file | `src/composables/useAuth.ts` |
| line | `15` |
| signature | `async login(email: string, password: string): Promise<User>` |
| params | `["email", "password"]` |
| paramTypes | `["string", "string"]` |
| returnType | `Promise<User>` |
| isAsync | `true` |
| jsdoc | `"Authenticates user by email..."` |

Supported forms:
- `export function foo() {}` — regular functions
- `export const foo = () => {}` — arrow functions
- `export const foo = function() {}` — function expressions
- Functions inside Vue `<script>` and `<script setup>` blocks

#### Prompt for working with scanner

```
Analyze the structure of MY_PROJECT and create an entity map.

Start with:
1. Run scanner `scan` on the src/ directory with db path ./context.db
   — this will create fn: entities for all exported functions in one pass
2. Check the result with aimemory `status`
3. Go through src/ — for each file add what scanner does not extract:
   - Components (comp:), stores (store:), dependencies (dep:)
   - Relations between entities (calls, depends_on, belongs_to)

After the analysis show:
- How many entities were created (aimemory status)
- What pending refs are left
- What else should be analyzed
- Give a couple of prompts, one easy and one hard, to test the analysis
```

Scanner extracts only `fn:` entities without relations between them. Components, stores, dependencies and relations — AI adds them through aimemory after scanning.

After a deep scan of the project you can build interesting dependency graphs. For example, "Trace the full data path from clicking the Submit button on the IBAN transfer form to showing the status. What entities are in the chain?" or "Show how data flows through the app from this endpoint".

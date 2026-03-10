# Context Hub — BAU Plan

## Project Overview

Context Hub (`chub`) is a CLI + MCP tool that delivers curated, versioned API/SDK documentation to AI agents, preventing hallucinated APIs and enabling agents to learn across sessions.

## Architecture

```
content/ (69 providers, 117 docs)
  → chub build → registry.json + content tree
  → CDN (cdn.aichub.org/v1)
  → CLI / MCP Server → Agent
```

**Key paths:**

| Area | Path |
|------|------|
| CLI source | `cli/src/` |
| Commands | `cli/src/commands/{search,get,build,update,cache,feedback,annotate}.js` |
| MCP server | `cli/src/mcp/server.js`, `cli/src/mcp/tools.js` |
| Core lib | `cli/src/lib/{cache,config,registry,output,frontmatter,normalize,telemetry}.js` |
| Content | `content/<provider>/docs/<name>/[lang/]DOC.md` |
| Tests | `cli/tests/` (Vitest) |
| Agent skill | `cli/skills/get-api-docs/SKILL.md` |
| npm package | `@aisuite/chub` v0.1.1 |

## Integration with Claude

Three integration paths (all set up):

1. **MCP Server** (primary) — `chub-mcp` registered in `~/.claude/settings.json` as `context-hub`. Exposes 5 tools: `chub_search`, `chub_get`, `chub_list`, `chub_annotate`, `chub_feedback`.
2. **Agent Skill** — `~/.claude/skills/get-api-docs.md` teaches Claude to use `chub` CLI before coding against external APIs.
3. **CLI** — `chub search`, `chub get`, etc. available as shell commands.

## Day-to-Day Tasks

### Adding/updating content

1. Create or edit `content/<provider>/docs/<name>/DOC.md`
2. Frontmatter required: `name`, `description`, `metadata.languages`, `metadata.versions`, `metadata.updated-on`, `metadata.source`, `metadata.tags`
3. Keep entry point DOC.md ≤ 500 lines; put details in `references/` subdirectory
4. Validate: `chub build content/ --validate-only`
5. Build: `chub build content/`

### Running tests

```bash
cd cli && npm test
```

### Publishing

- npm: tag a release → `.github/workflows/publish.yml` publishes `@aisuite/chub`
- Content: push to main → `.github/workflows/deploy-content.yml` builds and deploys registry to CDN

### CLI development

- Entry point: `cli/bin/chub` → `cli/src/index.js` (Commander.js)
- MCP entry point: `cli/bin/chub-mcp` → `cli/src/mcp/server.js`
- Dependencies: commander, chalk, yaml, tar, zod, @modelcontextprotocol/sdk, posthog-node

## Content Format

**DOC.md frontmatter:**
```yaml
---
name: chat
description: "OpenAI Chat API reference"
metadata:
  languages: "python,javascript"
  versions: "2.26.0"
  updated-on: "2026-03-06"
  source: maintainer
  tags: "openai,chat,llm"
  revision: 1
---
```

**IDs** are `<author>/<name>` (e.g., `openai/chat`, `stripe/api`). Author = top-level dir name.

## Key Design Decisions

- Docs vs Skills: Docs are large reference material; Skills are small behavioral patterns
- Progressive disclosure: Entry point only by default, `--full` for everything
- Multi-source: Blend public CDN with local/private docs
- Trust filtering: `source: official | maintainer | community`
- Agent learning loop: annotations persist locally, feedback flows to authors

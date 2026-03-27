# DelphiAST_MCP
MCP Server (HTTP) that provides Delphi Abstract Syntax Tree tools

**MCP Tools (18 tools):**
1. `set_project` - Set project root directory, reads `.delphi-ast.json` for library paths
2. `get_status` - Returns server state (idle/parsing), file counts
3. `is_ready` - Poll until background parsing completes
4. `list_files` - List .pas/.dpr/.dpk files under project root
5. `parse_unit` - Parse file, return top-level structure
6. `get_type_detail` - Detailed type info (fields, methods, properties, inheritance)
7. `get_method_body` - Method implementation as simplified AST
8. `find_references` - Search declarations by name pattern
9. `find_usages` - Find all usage sites of an identifier
10. `get_uses_graph` - Unit dependency graph
11. `get_syntax_tree` - Raw AST subtree as compact JSON
12. `get_source` - Return actual source code for a symbol or line range
13. `symbol_at_position` - Find AST node at file position
14. `resolve_inheritance` - Walk inheritance chain across all parsed units
15. `get_call_graph` - Analyze call relationships (callees/callers)
16. `find_descendants` - Find all types that inherit from a given type
17. `search_symbols` - Search symbols by name with relevance ranking
18. `search_pattern` - Structural pattern search via ast-grep (see below)

**Protocol:** HTTP-based MCP server on port 3000 (configurable via `--port`), JSON-RPC 2.0, protocol version `2024-11-05`.

**Key Patterns:**
- Project configuration via `.delphi-ast.json` with `libraryPaths` array
- AST caching with disk persistence (`.dast` files in temp directory)
- File watching with automatic re-parse on changes
- Background eager parsing after `initialized` notification
- Automatic Linux/WSL path conversion (`/mnt/d/...` → `D:\...`)

## ast-grep Integration

`search_pattern` provides fast structural pattern matching across Pascal source using [ast-grep](https://ast-grep.github.io/).

### Requirements

1. **`pascal.dll`** — place next to `DelphiAST_MCP.exe`. This is the tree-sitter-pascal grammar compiled as a Windows shared library. Without it, ast-grep cannot parse `.pas` files and the tool will report unavailable.
2. **`ast-grep` on PATH** — install via npm: `npm install -g @ast-grep/cli`

`sgconfig.yml` is auto-created next to the exe on first `set_project` if `pascal.dll` is present. No manual configuration needed.

### Optional: explicit config in `.delphi-ast.json`

```json
{
  "libraryPaths": ["..."],
  "astGrep": {
    "exe": "ast-grep",
    "configPath": "path/to/sgconfig.yml"
  }
}
```

### Pattern syntax

Patterns must form a **complete syntactic node**. Incomplete fragments produce ERROR nodes and match nothing.

| Pattern | Works? | Notes |
|---------|--------|-------|
| `$A := $B` | ✓ | Any assignment |
| `procedure $NAME` | ✓ | Procedure heading |
| `$A.Free` | ✓ | Method call |
| `raise $E` | ✓ | Raise statement |
| `if $COND then` | ✗ | Incomplete — use `if $COND then $BODY` |
| `procedure $NAME($$$ARGS)` | ✗ | `$$$` unsupported in param lists |

### Hybrid fallback

Files that ast-grep cannot parse (ERROR nodes) are automatically re-analyzed by DelphiAST for simple identifier patterns. The response `_meta` field shows how many matches came from each engine.

## Changes vs upstream

This fork adds the following on top of the original:

- **Linux/WSL path conversion** — all tool parameters accepting file or path now automatically convert `/mnt/d/...` → `D:\...`, so the server works transparently from WSL clients
- **Library path conversion** — paths in `.delphi-ast.json` are also converted, allowing the config file to use either Windows or Linux paths
- **Relative library paths** — `.delphi-ast.json` entries can be relative to the project root
- **Delphi 12 Athens build scripts** — `build-delphi12.bat` and `build-tests-delphi12.bat` for Studio 29.0
- **Live health check** — `GET /mcp` returns a JSON response for easy connectivity verification
- **`find_descendants` tool** — find all types that inherit from a given type
- **`search_symbols` tool** — search symbols by name with relevance ranking (exact > prefix > substring)
- **`search_pattern` tool** — structural ast-grep pattern search with DelphiAST fallback for unparseable files
- **ast-grep pre-filter acceleration** — `search_symbols`, `find_references`, `find_usages` use ast-grep to narrow candidate files before running full DelphiAST queries on large projects
- **ast-grep auto-configuration** — `pascal.dll` + auto-created `sgconfig.yml` next to the exe; no manual setup needed
- **Dependency-driven parsing** — files are parsed in dependency order
- **Crash fix** — "Invalid pointer operation" on second `set_project` call resolved


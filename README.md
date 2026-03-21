# DelphiAST_MCP
MCP Server (HTTP) that provides Delphi Abstract Syntax Tree tools

**MCP Tools (14 tools):**
1. `set_project` - Set project root directory, reads `.delphi-ast.json` for library paths
2. `get_status` - Returns server state (idle/parsing), file counts
3. `list_files` - List .pas/.dpr/.dpk files under project root
4. `parse_unit` - Parse file, return top-level structure
5. `get_type_detail` - Detailed type info (fields, methods, properties, inheritance)
6. `get_method_body` - Method implementation as simplified AST
7. `find_references` - Search declarations by name pattern
8. `find_usages` - Find all usage sites of an identifier
9. `get_uses_graph` - Unit dependency graph
10. `get_syntax_tree` - Raw AST subtree as compact JSON
11. `get_source` - Return actual source code for a symbol or line range
12. `symbol_at_position` - Find AST node at file position
13. `resolve_inheritance` - Walk inheritance chain across all parsed units
14. `get_call_graph` - Analyze call relationships (callees/callers)

**Protocol:** HTTP-based MCP server on port 3000 (configurable via `--port`), JSON-RPC 2.0, protocol version `2024-11-05`.

**Key Patterns:**
- Project configuration via `.delphi-ast.json` with `libraryPaths` array
- AST caching with disk persistence (`.dast` files in temp directory)
- File watching with automatic re-parse on changes
- Background eager parsing after `initialized` notification
- Automatic Linux/WSL path conversion (`/mnt/d/...` → `D:\...`)

## Changes vs upstream

This fork adds the following on top of the original:

- **Linux/WSL path conversion** — all tool parameters accepting file or path now automatically convert `/mnt/d/...` → `D:\...`, so the server works transparently from WSL clients
- **Library path conversion** — paths in `.delphi-ast.json` are also converted, allowing the config file to use either Windows or Linux paths
- **Relative library paths** — `.delphi-ast.json` entries can be relative to the project root
- **Delphi 12 Athens build scripts** — `build-delphi12.bat` and `build-tests-delphi12.bat` for Studio 29.0
- **Live health check** — `GET /mcp` returns a JSON response for easy connectivity verification
- **`find_descendants` tool** — find all types that inherit from a given type
- **`search_symbols` tool** — search symbols by name with relevance ranking (exact > prefix > substring)
- **Dependency-driven parsing** — files are parsed in dependency order
- **Crash fix** — "Invalid pointer operation" on second `set_project` call resolved


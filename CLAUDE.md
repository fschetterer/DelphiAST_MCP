# DelphiAST MCP Server

## Building

Use the batch files in the project root:

Build MCP server:
```bash
"c:/Users/jespe/Documents/Embarcadero/Studio/Projects/DelphiAST_MCP/build.bat"
```

Build test suite:
```bash
"c:/Users/jespe/Documents/Embarcadero/Studio/Projects/DelphiAST_MCP/build-tests.bat"
```

Run the tests:
```bash
"c:/Users/jespe/Documents/Embarcadero/Studio/Projects/DelphiAST_MCP/run-tests.bat"
```


## Architecture

- **6 units**: AST.Parser, AST.Query, AST.AstGrep, MCP.Tools, MCP.Server, DelphiAST_MCP.dpr
- **18 MCP tools**: list_files, parse_unit, get_type_detail, get_method_body, find_references, get_uses_graph, get_syntax_tree, find_usages, get_source, symbol_at_position, resolve_inheritance, get_call_graph, set_project, get_status, is_ready, find_descendants, search_symbols, search_pattern
- Newline-delimited JSON-RPC 2.0 over stdio, protocol version `2024-11-05`
- AST caching via `TObjectDictionary<string, TSyntaxNode>`

## ast-grep Integration

ast-grep provides fast structural pattern matching via tree-sitter. It accelerates search tools but can't handle `{$IFDEF}` or generic ambiguity, so DelphiAST provides fallback.

### Setup

Ship `pascal.dll` (tree-sitter-pascal grammar) next to the MCP server exe. On first `set_project`, the server auto-creates `sgconfig.yml` if missing. Requires `ast-grep` on PATH (`npm install -g @ast-grep/cli`).

Alternatively, configure explicitly in `.delphi-ast.json`:
```json
{
  "astGrep": {
    "exe": "ast-grep",
    "configPath": "path/to/sgconfig.yml"
  }
}
```

### How it works

- **`search_pattern` tool**: Shells out to `ast-grep.exe --json` for structural matching. Files with ERROR nodes (parse failures) are re-analyzed by DelphiAST using `FindUsages` (simple identifiers only). Response includes `_meta` showing engine breakdown.
- **Pre-filter acceleration**: `search_symbols`, `find_references`, `find_usages` use ast-grep to narrow candidate files before running full DelphiAST queries. Only activates when ast-grep is available, pattern is a simple identifier, and project has >20 files. Falls back to full scan on any failure.
- **Graceful degradation**: If ast-grep is unavailable (no DLL, not on PATH), all tools work exactly as before — pure DelphiAST.

## DelphiAST Library Notes

- Field/variable/parameter names stored as `TValuedSyntaxNode` children with `ntName` type (use `.Value`, not `.GetAttribute(anName)`)
- Property read/write accessors stored as `ntIdentifier` children of `ntRead`/`ntWrite` nodes
- Use `TUTF8Encoding.Create(False)` for BOM-free UTF-8 output in TStreamWriter
- Pre-compiled DCUs in DelphiAST source are x86 only; must use `-B` flag for x64 builds
- `ntCall` = method calls WITH parentheses (e.g., `Exit`, `Exception.Create`)
- `ntDot` = parameterless method/property calls (e.g., `FAnimals[I].GetName`)

## Testing

- `tests/test-project/` - Fixture Delphi files
- `tests/MCP.TestServer.pas` - Server process management
- `tests/MCP.TestHelper.pas` - Test helper utilities
- `tests/Tests.*.pas` - Test fixtures for each MCP tool

## Key Files

- `AST.AstGrep.pas` - ast-grep wrapper (CreateProcess, JSON parsing, ERROR detection)
- `AST.Query.pas` - AST query operations including call graph extraction
- `MCP.Tools.pas` - MCP tool implementations (search_pattern, pre-filter, auto-config)
- `MCP.Server.pas` - JSON-RPC server implementation

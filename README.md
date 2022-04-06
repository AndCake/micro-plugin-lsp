# Micro Plugin LSP Client

**Please note:** This software is very much not finished. It is more like a
proof of concept and might break if you call it names.

Provides LSP methods as actions to Micro that can subsequently be mapped to key
bindings.

Currently implemented methods:

- textDocument/hover
- textDocument/definition
- textDocument/completion
- textDocument/formatting
- textDocument/references

If possible, this plugin will register the following shortcuts:

- Alt-k for hover
- Alt-d for definition lookup
- Alt-f for formatting
- Alt-r for looking up references
- Ctrl-space for completion

## Installation

Clone this repo into micro's plug folder:

```
$ git clone https://github.com/AndCake/micro-plugin-lsp ~/.config/micro/plug/lsp
```

## Configuration

In your `settings.json`, you add the `lsp.server` option in order to enable
using it for your languages' server.

Example:

```
{
	"lsp.server": "python=pyls,go=gopls,typescript=deno lsp={\"importMap\": \"./import_map.json\"}",
	"lsp.formatOnSave": true
}
```

The format for the `lsp.server` value is a comma-separated list for each file
type you want to boot up a language server:

```
<file type>=<executable with arguments where necessary>[=<initialization options passed to language server>][,...]
```

If you encounter an issue whereby the `lsp.server` settings configuration is
auto-removed when you change any other configuration option, you can use an
environment variable called `MICRO_LSP` to define the same information. You can
add a line such as the following to your shell profile (e.g. .bashrc):

```
export MICRO_LSP='python=pyls,go=gopls,typescript=deno lsp={"importMap":"import_map.json"},rust=rls'
```

The environment variable is used as a fallback if the `lsp.server` option is not
defined.

## Testing

This plugin has been tested briefly with the following language servers:

- go: gopls
- typescript, javascript (including JSX/TSX): deno
- python: pyls
- rust: rls
- lua: lua-lsp

## Known issues

Not all possible types of modification events to the file are currently being
sent to the language server. Saving the file will re-synchronize it, though.

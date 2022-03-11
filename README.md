Micro Plugin LSP Client
=======================

**Please note:** This software is very much not finished. It is more like a proof of concept and might break if you call it names.

Provides LSP methods as actions to Micro that can subsequently be mapped to key bindings.

Currently implemented methods:

* textDocument/hover
* textDocument/definition
* textDocument/completion

If possible, this plugin will register the following shortcuts:

- Alt-k for hover
- Alt-d for definition lookup
- Ctrl-space for completion

Installation
------------

Clone this repo into micro's plug folder:

```
$ git clone https://github.com/AndCake/micro-plugin-lsp ~/.config/micro/plug/lsp
```

Configuration
-------------

In your `settings.json`, you add the `lsp.server` option in order to enable using it for your languages' server.

Example:

```
{
	"lsp.server": "python=pyls,go=gopls,typescript=deno lsp={\"importMap\": \"./import_map.json\"}"
}
```

The format for the value is a comma-separated list for each file type you want to boot up a language server:

```
<file type>=<executable with arguments where necessary>[=<initialization options passed to language server>][,...]
```

Testing
-------

This plugin has been tested briefly with the following language servers:

* go: gopls
* typescript, javascript (including JSX/TSX): deno
* python: pyls
* lua: lua-lsp

Known issues
------------

For some unknown reason, the rust language server "rls" is not able to parse any JSON messages sent to it, whereas the other servers don't have issues in that regard.

Not all possible types of modification events to the file are currently being sent to the language server. Saving the file will re-synchronize it, though.

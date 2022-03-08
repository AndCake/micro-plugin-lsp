LSP Client
==========

Provides LSP methods as actions to Micro that can subsequently be mapped to key bindings.

Currently implemented methods:

* textDocument/hover
* textDocument/definition

If possible, this plugin will register the following shortcuts:

- Alt-k for hover
- Alt-d for definition lookup

Installation
------------

Clone this repo into micro's plug folder:

```
$ git clone https://github.com/AndCake/micro-plugin-lsp ~/.config/micro/plug/lsp
```

Configuration
-------------

In your `settings.json`, you add the `lsp.server` option in order to enable the LSP function for your languages' LSP.

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

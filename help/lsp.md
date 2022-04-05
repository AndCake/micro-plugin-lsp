# Micro Plugin LSP Client

LSP is a Language Server Protocol client. Features include function signatures
and jump to definition.

This help page can be viewed in Micro editor with Ctrl-E 'help lsp'

## Features and Shortcuts

- Show function signature on status bar (alt-K) (textDocument/hover)
- Open function definition in a new tab (alt-D) (textDocument/definition)
- Format document (alt-F) (textDocument/formatting)
- Show references to the current symbol in a buffer (alt-R) (textDocument/references), 
  pressing return on the reference line, the reference's location is opened in a new tab

There is initial support for completion (ctrl-space) (textDocument/completion).

## Supported languages

Installation instructions for Go and Python are provided below. LSP Plugin has
been briefly tested with

- go: gopls
- typescript, javascript (including JSX/TSX): deno
- python: pyls and pylsp
- rust: rls
- lua: lua-lsp

## Install LSP plugin

    $ micro --plugin install lsp

To enable LSP Plugin, you must add two lines to settings.json

    $ micro settings.json

Add lines

```json
{
  "lsp.server": "python=pylsp,go=gopls,typescript=deno lsp={\"importMap\": \"./import_map.json\"}",
  "lsp.formatOnSave": true
}
```

Remember to add comma to previous line. Depending on the language server,
automatic code formating can be quite opinionated. In that case, you can simply
set lsp.formatOnSave to false.

For Python language server, the currently maintained fork is 'pylsp'. If you
wish to use the Palantir version (last updated in 2020) instead, set
"python=pyls" in lsp.server.

If your lsp.server settings are autoremoved, you can

    $ export MICRO_LSP='python=pylsp,go=gopls,typescript=deno lsp={"importMap":"import_map.json"},rust=rls'

## Install Language Server

To support each language, LSP plugin uses language servers. To use LSP plugin,
you must install at least one language server.

If you want to quickly test LSP plugin, Go language server gopls is simple to
install.

### gopls, Go language server

You will need command 'gopls'

    $ gopls version
    golang.org/x/tools/gopls v0.7.3

In Debian, this is installed with

    $ sudo apt-get update
    $ sudo apt-get -y install golang-go gopls

To test it, write a short go program

    $ micro hello.go

```go
package main

import "fmt"

func main() {
	fmt.Println("hello world")
}
```

Move cursor over Println and press alt-k. The function signature is shown on the
bottom of the screen, in Micro status bar. It shows you what parameters the
function can take. The signature should look similar to this: "func
fmt.Println(a ...interface{}) (n int, err error)Println formats using the
default formats..."

Can you see the function signature with alt-k? If you can, you have succesfully
installed Micro LSP plugin and GoPLS language server.

Keep your cursor over Println, and press alt-d. The file defining Println opens.
In this case, it's fmt/print.go. As Go reference documentation is in code
comments, this is very convenient. You can navigate between tabs with atl-,
(alt-comma) and alt-. (alt - full stop). To close the tab, press Ctrl-Q.

### pylsp, Python language server

Installing Python language server PyLSP is a bit more involved.

You will need 'virtualenv' command to create virtual environments and 'pip' to
install Python packages. You can also use one of the many other commands for
keeping your 'pip' packages in order.

In Debian, these are installed with

    $ sudo apt-get update
    $ sudo apt-get install python-pip virtualenv

Create a new virtual environment

    $ mkdir somePythonProject; cd somePythonProject
    $ virtualenv -p python3 env/
    $ source env/bin/activate

Your prompt likely shows "(env)" to confirm you're inside your virtual
environment.

List the packages you want installed.

    $ micro requirements.txt

This list is to provide the most useful suggestions. If you would like to get a
lot more opinionated advice, such as adding two empty lines between functions,
you could use "python-lsp-server[all]". The mypy package provides optional
static type checking. requirements.txt:

```
python-lsp-server[rope,pyflakes,mccabe,pylsp-mypy]
pylsp-mypy
```

And actually install

    $ pip install -r requirements.txt

No you can test your Python environment

    $ micro hello.py

```python
def helloWorld():
	return a
```

Save with Ctrl-S. A red warning sign ">>" lists up in the gutter, on the left
side of Micro. Move cursor to the line "return a". The status bar shows the
warning: "undefined name 'a'". Well done, you have now installed Python LSP
support for Micro.

MyPy provides optional static type setting. You can write normally, and type
checking is ignored. You can define types for some functions, and you get
automatic warnings for incorrect use of types. This is how types are marked:

```python
def square(x: int) -> int:
	return x*x
```

## See also

[Official repostory](https://github.com/AndCake/micro-plugin-lsp)

[Usage examples with screenshots](https://terokarvinen.com/2022/micro-editor-lsp-support-python-and-go-jump-to-definition-show-function-signature/)

[Language Server Protocol](https://microsoft.github.io/language-server-protocol/)

[gopls - the Go language server](https://pkg.go.dev/golang.org/x/tools/gopls)

[pylsp - Python LSP Server](https://github.com/python-lsp/python-lsp-server)

[mypy - Optional Static Typing for Python](http://mypy-lang.org/)

[rls - Rust Language Server](https://github.com/rust-lang/rls)

[lua-lsp - A Lua language server](https://github.com/Alloyed/lua-lsp)

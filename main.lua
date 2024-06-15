VERSION = "0.6.3"

local micro = import("micro")
local config = import("micro/config")
local shell = import("micro/shell")
local util = import("micro/util")
local buffer = import("micro/buffer")
local fmt = import("fmt")
local go_os = import("os")
local path = import("path")
local filepath = import("path/filepath")

cmd = {}
currentAction = {}
capabilities = {}
rootUri = ''

local id = {}
local filetype = ''
local message = ''
local splitBP = nil
local tabCount = 0

local json = json

function init()
	-- register all configuration options
	config.RegisterCommonOption("lsp", "server",
		'python=pylsp,go=gopls,typescript=deno lsp={"enable":true},javascript=deno lsp={"enable":true},markdown=deno lsp={"enable":true},json=deno lsp={"enable":true},jsonc=deno lsp={"enable":true},rust=rust-analyzer,lua=lua-language-server,c++=clangd,dart=dart language-server')
	config.RegisterCommonOption("lsp", "formatOnSave", false)
	config.RegisterCommonOption("lsp", "autocompleteDetails", false)
	config.RegisterCommonOption("lsp", "ignoreMessages", "")
	config.RegisterCommonOption("lsp", "tabcompletion", true)
	config.RegisterCommonOption("lsp", "ignoreTriggerCharacters", "completion")
		
	-- example to ignore all LSP server message starting with these strings:
	-- "lsp.ignoreMessages": "Skipping analyzing |See https://"

	-- define all commands added to Micro
	defineActions()

	-- add help documentation
	config.AddRuntimeFile("lsp", config.RTHelp, "help/lsp.md")
end

function parseOptions(inputstr)
	return mysplit(inputstr, ',')
end

function startServer(filetype, callback)
	local wd, _ = go_os.Getwd()
	rootUri = fmt.Sprintf("file://%s", wd)
	local envSettings, _ = go_os.Getenv("MICRO_LSP")
	local settings = config.GetGlobalOption("lsp.server")
	local fallback =
	'python=pylsp,go=gopls,typescript=deno lsp={"enable":true},javascript=deno lsp={"enable":true},markdown=deno lsp={"enable":true},json=deno lsp={"enable":true},jsonc=deno lsp={"enable":true},rust=rust-analyzer,lua=lua-language-server,c++=clangd,dart=dart language-server'
	if envSettings ~= nil and #envSettings > 0 then
		settings = envSettings
	end
	if settings ~= nil and #settings > 0 then
		settings = settings .. "," .. fallback
	else
		settings = fallback
	end
	local server = parseOptions(settings)
	micro.Log("Server Options", server)
	for i in ipairs(server) do
		local part = mysplit(server[i], "=")
		local run = mysplit(part[2] or '', "%s")
		local initOptions = config.GetGlobalOption('lsp.' .. part[1]) or part[3] or '{}'
		local runCmd = table.remove(run, 1)
		local args = run
		for idx, narg in ipairs(args) do
			args[idx] = narg:gsub("%%[a-zA-Z0-9][a-zA-Z0-9]", function(entry)
				return string.char(tonumber(entry:sub(2), 16))
			end)
		end
		if filetype == part[1] then
			local send = withSend(part[1])
			if cmd[part[1]] ~= nil then return; end
			id[part[1]] = 0
			micro.Log("Starting server", part[1])
			cmd[part[1]] = shell.JobSpawn(runCmd, args, onStdout(part[1]), onStderr, onExit(part[1]), {})
			currentAction[part[1]] = {
				method = "initialize",
				response = function(bp, data)
					send("initialized", "{}", true)
					capabilities[filetype] = data.result and data.result.capabilities or {}
					callback(bp.Buf, filetype)
				end
			}
			send(currentAction[part[1]].method,
				fmt.Sprintf(
					'{"processId": %.0f, "rootUri": "%s", "workspaceFolders": [{"name": "root", "uri": "%s"}], "initializationOptions": %s, "capabilities": {"textDocument": {"hover": {"contentFormat": ["plaintext", "markdown"]}, "publishDiagnostics": {"relatedInformation": false, "versionSupport": false, "codeDescriptionSupport": true, "dataSupport": true}, "signatureHelp": {"signatureInformation": {"documentationFormat": ["plaintext", "markdown"]}}}}}',
					go_os.Getpid(), rootUri, rootUri, initOptions))
			return
		end
	end
end

function withSend(filetype)
	return function(method, params, isNotification)
		if cmd[filetype] == nil then
			return
		end

		micro.Log(filetype .. ">>> " .. method)
		local msg = fmt.Sprintf('{"jsonrpc": "2.0", %s"method": "%s", "params": %s}',
			not isNotification and fmt.Sprintf('"id": %.0f, ', id[filetype]) or "", method, params)
		id[filetype] = id[filetype] + 1
		msg = fmt.Sprintf("Content-Length: %.0f\r\n\r\n%s", #msg, msg)
		micro.Log(msg)
		shell.JobSend(cmd[filetype], msg)
	end
end

function handleInitialized(buf, filetype)
	if cmd[filetype] == nil then return; end
	micro.Log("Found running lsp server for ", filetype, "firing textDocument/didOpen...")
	local send = withSend(filetype)
	local uri = getUriFromBuf(buf)
	local content = util.String(buf:Bytes()):gsub("\\", "\\\\"):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub('"', '\\"')
		:gsub("\t", "\\t")
	send("textDocument/didOpen",
		fmt.Sprintf('{"textDocument": {"uri": "%s", "languageId": "%s", "version": 1, "text": "%s"}}', uri, filetype,
			content), true)
end

function isIgnoredMessage(msg)
	-- Return true if msg matches one of the ignored starts of messages
	-- Useful for linters that show spurious, hard to disable warnings
	local ignoreList = mysplit(config.GetGlobalOption("lsp.ignoreMessages"), "|")
	for _, ignore in pairs(ignoreList) do
		if string.match(msg, ignore) then -- match from start of string
			micro.Log("Ignore message: '", msg, "', because it matched: '", ignore, "'.")
			return true             -- ignore this message, dont show to user
		end
	end
	return false -- show this message to user
end

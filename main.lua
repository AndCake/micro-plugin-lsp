VERSION = "0.4.3"

local micro = import("micro")
local config = import("micro/config")
local shell = import("micro/shell")
local util = import("micro/util")
local buffer = import("micro/buffer")
local fmt = import("fmt")
local os = import("os")
local path = import("path")
local filepath = import("path/filepath")

local cmd = {}
local id = {}
local queue = {}
local version = {}
local currentAction = {}
local filetype = ''
local rootUri = ''
local message = ''
local completionCursor = 0
local lastCompletion = {}

local json = {}

function toBytes(str)
	local result = {}
	for i=1,#str do 
		local b = str:byte(i)
		if b < 32 then 
			table.insert(result, b)
		end
	end
	return result
end

function getUriFromBuf(buf)
	if buf == nil then return; end
	local file = buf.AbsPath
	local uri = fmt.Sprintf("file://%s", file)
	return uri
end

function mysplit (inputstr, sep)
        if sep == nil then
                sep = "%s"
        end
        local t={}
        for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
                table.insert(t, str)
        end
        return t
end

function startServers()
	local wd, _ = os.Getwd()
	rootUri = fmt.Sprintf("file://%s", wd)
	local fallback, _ = os.Getenv("MICRO_LSP")
	if ("" == fallback) then
		fallback = 'python=pylsp,go=gopls,typescript=deno lsp,javascript=deno lsp,rust=rls,lua=lua-lsp'
	end
	local server = mysplit(config.GetGlobalOption("lsp.server") or fallback, ",")
	for i in pairs(server) do
		local part = mysplit(server[i], "=")
		local run = mysplit(part[2], "%s")
		local initOptions = part[3] or '{}'
		local runCmd = table.remove(run, 1)
		local args = run
		local send = withSend(part[1])
		if cmd[part[1]] ~= nil then return; end
		id[part[1]] = 0
		queue[part[1]] = {}
		micro.Log("Starting server", part[1])
		cmd[part[1]] = shell.JobSpawn(runCmd, args, onStdout(part[1]), onStderr, onExit, {})
		currentAction = { method = "initialize" }
		send(currentAction.method, fmt.Sprintf('{"processId": %.0f, "rootUri": "%s", "workspaceFolders": [{"name": "root", "uri": "%s"}], "initializationOptions": %s, "capabilities": {"textDocument": {"hover": {"contentFormat": ["plaintext", "markdown"]}, "publishDiagnostics": {"relatedInformation": false, "versionSupport": false, "codeDescriptionSupport": true, "dataSupport": true}, "signatureHelp": {"signatureInformation": {"documentationFormat": ["plaintext", "markdown"]}}}}}', os.Getpid(), rootUri, rootUri, initOptions))
		send("initialized", "{}", true)
	end
end

function init()
	config.RegisterGlobalOption("lsp", "server", "")
	config.RegisterGlobalOption("lsp", "formatOnSave", true)
	config.MakeCommand("hover", hoverAction, config.NoComplete)
	config.MakeCommand("definition", definitionAction, config.NoComplete)
	config.MakeCommand("lspcompletion", completionAction, config.NoComplete)
	config.MakeCommand("format", formatAction, config.NoComplete)
	config.MakeCommand("references", referencesAction, config.NoComplete)

	config.TryBindKey("Alt-k", "command:hover", false)
	config.TryBindKey("Alt-d", "command:definition", false)
	config.TryBindKey("Alt-f", "command:format", false)
	config.TryBindKey("Alt-r", "command:references", false)
	config.TryBindKey("CtrlSpace", "command:lspcompletion", false)

	config.AddRuntimeFile("lsp", config.RTHelp, "help/lsp.md")
		
	-- @TODO register additional actions here
end

function withSend(filetype)
	return function (method, params, isNotification) 
	    if cmd[filetype] == nil then
	    	return
	    end
	    
		local msg = fmt.Sprintf('{"jsonrpc": "2.0", %s"method": "%s", "params": %s}', not isNotification and fmt.Sprintf('"id": %.0f, ', id[filetype]) or "", method, params)
		id[filetype] = id[filetype] + 1
		msg = fmt.Sprintf("Content-Length: %.0f\r\n\r\n%s", #msg, msg)
		if id[filetype] ~= 1 and id[filetype] <= 3 then
			micro.Log("send", filetype, "queueing", method)
			table.insert(queue[filetype], msg)
		else
			micro.Log("send", filetype, "sending", method or msg, msg)
			shell.JobSend(cmd[filetype], msg)
		end
	end
end

-- when a new character is types, the document changes
function onRune(bp, r)
	local filetype = bp.Buf:FileType()
	if cmd[filetype] == nil then
		return
	end
	local send = withSend(filetype)
	local uri = getUriFromBuf(bp.Buf)
	-- allow the document contents to be escaped properly for the JSON string
	local content = util.String(bp.Buf:Bytes()):gsub("\\", "\\\\"):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub('"', '\\"'):gsub("\t", "\\t")
	-- increase change version
	version[uri] = (version[uri] or 0) + 1
	send("textDocument/didChange", fmt.Sprintf('{"textDocument": {"version": %.0f, "uri": "%s"}, "contentChanges": [{"text": "%s"}]}', version[uri], uri, content), true)
end

-- alias functions for any kind of change to the document
-- @TODO: add missing ones
function onBackspace(bp) onRune(bp); end
function onCut(bp) onRune(bp); end
function onCutLine(bp) onRune(bp); end
function onDuplicateLine(bp) onRune(bp); end
function onDeleteLine(bp) onRune(bp); end
function onDelete(bp) onRune(bp); end
function onUndo(bp) onRune(bp); end
function onRedo(bp) onRune(bp); end
function onIndentSelection(bp) onRune(bp); end
function onPaste(bp) onRune(bp); end
function onSave(bp) onRune(bp); end

function preInsertNewline(bp)
	if bp.Buf.Path == "References found" then
		local cur = bp.Buf:GetActiveCursor()
		cur:SelectLine()
		local data = util.String(cur:GetSelection())
		local file, line, character = data:match("(./[^:]+):([^:]+):([^:]+)")
		local doc, _ = file:gsub("^file://", "")
		buf, _ = buffer.NewBufferFromFile(doc)
		bp:AddTab()
		micro.CurPane():OpenBuffer(buf)
		buf:GetActiveCursor():GotoLoc(buffer.Loc(character * 1, line * 1))
		micro.CurPane():Center()
		return false
	end
end

function preSave(bp)
	if config.GetGlobalOption("lsp.formatOnSave") then
		onRune(bp)
		formatAction(bp, function ()
			bp:Save()
		end)
	end
end

function onBufferOpen(buf)
	local filetype = buf:FileType()
	if filetype ~= "unknown" and rootUri == "" then startServers(); end
	micro.Log("ONBUFFEROPEN", filetype)
	if cmd[filetype] == nil then return; end
	micro.Log("Found running lsp server for ", filetype, "firing textDocument/didOpen...")
	local send = withSend(filetype)
	local uri = getUriFromBuf(buf)
	local content = util.String(buf:Bytes()):gsub("\\", "\\\\"):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub('"', '\\"'):gsub("\t", "\\t")
	send("textDocument/didOpen", fmt.Sprintf('{"textDocument": {"uri": "%s", "languageId": "%s", "version": 1, "text": "%s"}}', uri, filetype, content), true)
end

function sendNext(filetype)
	if #queue[filetype] > 0 then
		local msg = table.remove(queue[filetype], 1)
		micro.Log("send", filetype, "sending", msg)
		shell.JobSend(cmd[filetype], msg)
		if msg:find('"method": "initialized"') then
			sendNext(filetype)
		end
	end
end

function string.starts(String, Start)
	return string.sub(String, 1, #Start) == Start
end

function string.ends(String, End)
	return string.sub(String, #String - (#End - 1), #String) == End
end

function string.parse(text)
	if not text:find('"jsonrpc":') then return {}; end
	local start,fin = text:find("\n%s*\n")
	local cleanedText = text
	if fin ~= nil then
		cleanedText = text:sub(fin)
	end
	data = json.parse(cleanedText)
	return data
end

function onStdout(filetype)
	return function (text)
		micro.Log("Received", filetype, text)
		if text:starts("Content-Length:") then
			message = text
		else
			message = message .. text
		end
		if not text:ends("}") then
			return
		end	
		local data = message:parse()
		if data.method == "workspace/configuration" then
		    -- actually needs to respond with the same ID as the received JSON
			local message = fmt.Sprintf('{"jsonrpc": "2.0", "id": %.0f, "result": [{"enable": true}]}', data.id)
			shell.JobSend(cmd[filetype], fmt.Sprintf('Content-Length: %.0f\n\n%s', #message, message))
		elseif data.method == "textDocument/publishDiagnostics" or data.method == "textDocument\\/publishDiagnostics" then
			-- react to server-published event
			local bp = micro.CurPane().Buf
			bp:ClearMessages("lsp")
			local uri = getUriFromBuf(bp)
			if data.params.uri == uri then
				for _, diagnostic in ipairs(data.params.diagnostics) do
					local type = buffer.MTInfo
					if diagnostic.severity == 1 then
						type = buffer.MTError
					elseif diagnostic.severity == 2 then
						type = buffer.MTWarning
					end
					local mstart = buffer.Loc(diagnostic.range.start.character, diagnostic.range.start.line)
		            local mend = buffer.Loc(diagnostic.range["end"].character, diagnostic.range["end"].line)
					msg = buffer.NewMessage("lsp", diagnostic.message, mstart, mend, type)
					bp:AddMessage(msg)
				end
			end
		elseif currentAction and currentAction.method and currentAction.response and text:find('"jsonrpc":') then
			-- react to custom action event
			local data = text:parse()
			local bp = micro.CurPane()
			currentAction.response(bp, data)
			currentAction = {}
		elseif data.method == "window/showMessage" or data.method == "window\\/showMessage" then
			micro.InfoBar():Message(data.params.message)
		elseif data.method == "window/logMessage" or data.method == "window\\/logMessage" then
			micro.Log(data.params.message)
		elseif currentAction.method == "initialize" then
			currentAction = {}
		elseif message:starts("Content-Length:") then
			if message:find('"') and not message:find('"result":null') then
				micro.Log("Unhandled message", filetype, message)
			end
		else
			-- enable for debugging purposes
			micro.Log("Unhandled message", filetype, message)
		end
		sendNext(filetype)
	end
end

function onStderr(text)
	micro.Log("ONSTDERR", text)
	micro.InfoBar():Error(text)
end

function onExit(str)
	micro.Log("ONEXIT", text)
	micro.InfoBar():Error(str)
end

-- the actual hover action request and response
-- the hoverActionResponse is hooked up in 
function hoverAction(bp)
	local filetype = bp.Buf:FileType()
	if cmd[filetype] ~= nil then
		local send = withSend(filetype)
		local file = bp.Buf.AbsPath
		local line = bp.Buf:GetActiveCursor().Y
		local char = bp.Buf:GetActiveCursor().X
		currentAction = { method = "textDocument/hover", response = hoverActionResponse }
		send(currentAction.method, fmt.Sprintf('{"textDocument": {"uri": "file://%s"}, "position": {"line": %.0f, "character": %.0f}}', file, line, char))
	end
end

function hoverActionResponse(buf, data)
	if data.result and data.result.contents ~= nil and data.result.contents ~= "" then
		if data.result.contents.value then
			micro.InfoBar():Message(data.result.contents.value)
		elseif #data.result.contents > 0 then
			micro.InfoBar():Message(data.result.contents[1].value)
		end
	end
end

-- the definition action request and response
function definitionAction(bp)
	local filetype = bp.Buf:FileType()	
	if cmd[filetype] == nil then return; end
	
	local send = withSend(filetype)
	local file = bp.Buf.AbsPath
	local line = bp.Buf:GetActiveCursor().Y
	local char = bp.Buf:GetActiveCursor().X
	currentAction = { method = "textDocument/definition", response = definitionActionResponse }
	send(currentAction.method, fmt.Sprintf('{"textDocument": {"uri": "file://%s"}, "position": {"line": %.0f, "character": %.0f}}', file, line, char))
end

function definitionActionResponse(bp, data)
	local results = data.result or data.partialResult
	if results == nil then return; end
	local file = bp.Buf.AbsPath
	if results.uri ~= nil then
		-- single result
		results = { results }
	end
	if #results <= 0 then return; end
	local uri = (results[1].uri or results[1].targetUri)
	local doc = uri:gsub("^file://", "")
	local buf = bp.Buf
	if file ~= doc then
		-- it's from a different file, so open it as a new tab
		buf, _ = buffer.NewBufferFromFile("." .. uri:sub(#rootUri + 1, #uri))
		bp:AddTab()
		micro.CurPane():OpenBuffer(buf)
	end
	local range = results[1].range or results[1].targetSelectionRange
	buf:GetActiveCursor():GotoLoc(buffer.Loc(range.start.character, range.start.line))
	bp:Center()
end

function completionAction(bp)
	local filetype = bp.Buf:FileType()
	if cmd[filetype] == nil then return; end
	local send = withSend(filetype)
	local file = bp.Buf.AbsPath
	local line = bp.Buf:GetActiveCursor().Y
	local char = bp.Buf:GetActiveCursor().X

	if lastCompletion[1] == file and lastCompletion[2] == line and lastCompletion[3] == char then 
		completionCursor = completionCursor + 1
	else
		completionCursor = 0
	end
	lastCompletion = {file, line, char}
	currentAction = { method = "textDocument/completion", response = completionActionResponse }
	send(currentAction.method, fmt.Sprintf('{"textDocument": {"uri": "file://%s"}, "position": {"line": %.0f, "character": %.0f}}', file, line, char))
end

function completionActionResponse(bp, data)
	local results = data.result
	if results == nil then return; end
	if results.items then
		results = results.items
	end
	entry = results[(completionCursor % #results) + 1]
	if entry == nil then return; end

	local xy = buffer.Loc(bp.Cursor.X, bp.Cursor.Y)
	local start = xy
	if bp.Cursor:HasSelection() then
		bp.Cursor:DeleteSelection()
	end
	if entry.textEdit then
		start = buffer.Loc(entry.textEdit.range.start.character, entry.textEdit.range.start.line)
		bp.Cursor:SetSelectionStart(start)
		bp.Cursor:SetSelectionEnd(xy)
		bp.Cursor:DeleteSelection()
		bp.Cursor:ResetSelection()
	end
	bp.Buf:insert(start, entry.textEdit and entry.textEdit.newText or entry.label)
	bp.Cursor:GotoLoc(start)
	bp.Cursor:SetSelectionStart(start)
	bp.Cursor:SetSelectionEnd(buffer.Loc(start.X + #(entry.textEdit and entry.textEdit.newText or entry.label), start.Y))

	local msg = ''
	if entry.detail or entry.documentation then
		msg = fmt.Sprintf("%s %s", entry.detail or '', entry.documentation or '')
	else
		for idx, result in ipairs(results) do
			if idx >= (completionCursor % #results) + 1 then 
				if msg ~= '' then msg = msg .. '  '; end
				msg = msg .. result.label
			end
		end
	end
	micro.InfoBar():Message(msg)
end

function formatAction(bp, callback)
	local filetype = bp.Buf:FileType()
	if cmd[filetype] == nil then return; end
	local send = withSend(filetype)
	local file = bp.Buf.AbsPath

	currentAction = { method = "textDocument/formatting", response = formatActionResponse(callback) }
	send(currentAction.method, fmt.Sprintf('{"textDocument": {"uri": "file://%s"}, "options": {"tabSize": 4, "insertSpaces": true}}', file))
end

function formatActionResponse(callback)
	return function (bp, data)
		if data.result == nil then return; end
		local edits = data.result
		-- make sure we apply the changes from back to front
		-- this allows for changes to not need position updates
		table.sort(edits, function (left, right)
			-- go by lines first
			return left.range['end'].line > right.range['end'].line or 
				-- if lines match, go by end character
				left.range['end'].line == right.range['end'].line and left.range['end'].character > right.range['end'].character or
				-- if they match too, go by start character
				left.range['end'].line == right.range['end'].line and left.range['end'].character == right.range['end'].character and left.range.start.line == left.range['end'].line and left.range.start.character > right.range.start.character
		end)

		-- save original cursor position
		local xy = buffer.Loc(bp.Cursor.X, bp.Cursor.Y)
		for _idx, edit in ipairs(edits) do
			rangeStart = buffer.Loc(edit.range.start.character, edit.range.start.line)
			rangeEnd = buffer.Loc(edit.range['end'].character, edit.range['end'].line)
			-- apply each change
			bp.Cursor:GotoLoc(rangeStart)
			bp.Cursor:SetSelectionStart(rangeStart)
			bp.Cursor:SetSelectionEnd(rangeEnd)
			bp.Cursor:DeleteSelection()
			bp.Cursor:ResetSelection()
			
			if edit.newText ~= "" then
				bp.Buf:insert(rangeStart, edit.newText)
			end
		end
		-- put the cursor back where it was
		bp.Cursor:GotoLoc(xy)
		-- if any changes were applied
		if #edits > 0 then
			-- tell the server about the changed document
			onRune(bp)
		end

		if callback ~= nil then
			callback(bp)
		end
	end
end

-- the references action request and response
function referencesAction(bp)
	local filetype = bp.Buf:FileType()	
	if cmd[filetype] == nil then return; end
	
	local send = withSend(filetype)
	local file = bp.Buf.AbsPath
	local line = bp.Buf:GetActiveCursor().Y
	local char = bp.Buf:GetActiveCursor().X
	currentAction = { method = "textDocument/references", response = referencesActionResponse }
	send(currentAction.method, fmt.Sprintf('{"textDocument": {"uri": "file://%s"}, "position": {"line": %.0f, "character": %.0f}, "context": {"includeDeclaration":true}}', file, line, char))
end

function referencesActionResponse(bp, data)
	if data.result == nil then return; end
	local results = data.result or data.partialResult
	if results == nil or #results <= 0 then return; end

	local file = bp.Buf.AbsPath
	
	local msg = ''
	for _idx, ref in ipairs(results) do
		if msg ~= '' then msg = msg .. '\n'; end
		local doc = (ref.uri or ref.targetUri)
		msg = msg .. "." .. doc:sub(#rootUri + 1, #doc) .. ":" .. ref.range.start.line .. ":" .. ref.range.start.character
	end

	local logBuf = buffer.NewBuffer(msg, "References found")
	local splitBP = bp:HSplitBuf(logBuf)
end

--
-- @TODO implement additional functions here...
--



--
-- JSON
--
-- Internal functions.

local function kind_of(obj)
  if type(obj) ~= 'table' then return type(obj) end
  local i = 1
  for _ in pairs(obj) do
    if obj[i] ~= nil then i = i + 1 else return 'table' end
  end
  if i == 1 then return 'table' else return 'array' end
end

local function escape_str(s)
  local in_char  = {'\\', '"', '/', '\b', '\f', '\n', '\r', '\t'}
  local out_char = {'\\', '"', '/',  'b',  'f',  'n',  'r',  't'}
  for i, c in ipairs(in_char) do
    s = s:gsub(c, '\\' .. out_char[i])
  end
  return s
end

-- Returns pos, did_find; there are two cases:
-- 1. Delimiter found: pos = pos after leading space + delim; did_find = true.
-- 2. Delimiter not found: pos = pos after leading space;     did_find = false.
-- This throws an error if err_if_missing is true and the delim is not found.
local function skip_delim(str, pos, delim, err_if_missing)
  pos = pos + #str:match('^%s*', pos)
  if str:sub(pos, pos) ~= delim then
    if err_if_missing then
      error('Expected ' .. delim .. ' near position ' .. pos)
    end
    return pos, false
  end
  return pos + 1, true
end

-- Expects the given pos to be the first character after the opening quote.
-- Returns val, pos; the returned pos is after the closing quote character.
local function parse_str_val(str, pos, val)
  val = val or ''
  local early_end_error = 'End of input found while parsing string.'
  if pos > #str then error(early_end_error) end
  local c = str:sub(pos, pos)
  if c == '"'  then return val, pos + 1 end
  if c ~= '\\' then return parse_str_val(str, pos + 1, val .. c) end
  -- We must have a \ character.
  local esc_map = {b = '\b', f = '\f', n = '\n', r = '\r', t = '\t'}
  local nextc = str:sub(pos + 1, pos + 1)
  if not nextc then error(early_end_error) end
  return parse_str_val(str, pos + 2, val .. (esc_map[nextc] or nextc))
end

-- Returns val, pos; the returned pos is after the number's final character.
local function parse_num_val(str, pos)
  local num_str = str:match('^-?%d+%.?%d*[eE]?[+-]?%d*', pos)
  local val = tonumber(num_str)
  if not val then error('Error parsing number at position ' .. pos .. '.') end
  return val, pos + #num_str
end

json.null = {}  -- This is a one-off table to represent the null value.

function json.parse(str, pos, end_delim)
  pos = pos or 1
  if pos > #str then error('Reached unexpected end of input.') end
  local pos = pos + #str:match('^%s*', pos)  -- Skip whitespace.
  local first = str:sub(pos, pos)
  if first == '{' then  -- Parse an object.
    local obj, key, delim_found = {}, true, true
    pos = pos + 1
    while true do
      key, pos = json.parse(str, pos, '}')
      if key == nil then return obj, pos end
      if not delim_found then error('Comma missing between object items.') end
      pos = skip_delim(str, pos, ':', true)  -- true -> error if missing.
      obj[key], pos = json.parse(str, pos)
      pos, delim_found = skip_delim(str, pos, ',')
    end
  elseif first == '[' then  -- Parse an array.
    local arr, val, delim_found = {}, true, true
    pos = pos + 1
    while true do
      val, pos = json.parse(str, pos, ']')
      if val == nil then return arr, pos end
      if not delim_found then error('Comma missing between array items.') end
      arr[#arr + 1] = val
      pos, delim_found = skip_delim(str, pos, ',')
    end
  elseif first == '"' then  -- Parse a string.
    return parse_str_val(str, pos + 1)
  elseif first == '-' or first:match('%d') then  -- Parse a number.
    return parse_num_val(str, pos)
  elseif first == end_delim then  -- End of an object or array.
    return nil, pos + 1
  else  -- Parse true, false, or null.
    local literals = {['true'] = true, ['false'] = false, ['null'] = json.null}
    for lit_str, lit_val in pairs(literals) do
      local lit_end = pos + #lit_str - 1
      if str:sub(pos, lit_end) == lit_str then return lit_val, lit_end + 1 end
    end
    local pos_info_str = 'position ' .. pos .. ': ' .. str:sub(pos, pos + 10)
    error('Invalid json syntax starting at ' .. pos_info_str .. ': ' .. str)
  end
end

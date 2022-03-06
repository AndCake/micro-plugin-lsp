local micro = import("micro")
local config = import("micro/config")
local shell = import("micro/shell")
local util = import("micro/util")
local buffer = import("micro/buffer")
local fmt = import("fmt")
local os = import("os")
local path = import("path")
local filepath = import("path/filepath")

local cmd = nil
local id = 0
local queue = {}
local version = {}
local currentAction = ''
local currentServer = ''

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

function init()
	config.RegisterGlobalOption("lsp", "server", "")
	config.MakeCommand("hover", hoverAction, config.NoComplete)
end

function send(method, params) 
    if cmd == nil then
    	return
    end
    
	local msg = fmt.Sprintf('{"jsonrpc": "2.0", "id": %.0f, "method": "%s", "params": %s}', id, method, params)
	id = id + 1
	msg = fmt.Sprintf("Content-Length: %.0f\n\n%s", #msg, msg)
	if id ~= 1 and id <= 3 then
		table.insert(queue, msg)
	else
		-- micro.TermMessage("SENDING", msg)
		shell.JobSend(cmd, msg)
	end
end

function onRune(bp, r)
	if bp.Buf:FileType() ~= currentServer then
		return
	end
	local file, _ = filepath.Abs(bp.Buf.Path)
	uri = fmt.Sprintf("file://%s", file)
	local content = util.String(bp.Buf:Bytes()):gsub("\\", "\\\\"):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub('"', '\\"'):gsub("\t", "\\t")
	version[uri] = (version[uri] or 0) + 1
	send("textDocument/didChange", fmt.Sprintf('{"textDocument": {"version": %.0f, "uri": "%s"}, "contentChanges": [{"text": "%s"}]}', version[uri], uri, content))
end

function onBackspace(bp)
	onRune(bp)
end
function onCut(bp)
	onRune(bp)
end
function onCutLine(bp)
	onRune(bp)
end
function onDuplicateLine(bp)
	onRune(bp)
end
function onDeleteLine(bp)
	onRune(bp)
end
function onIndentSelection(bp)
	onRune(bp)
end
function onPaste(bp)
	onRune(bp)
end

function onBufPaneOpen(bp)
	local server = mysplit(config.GetGlobalOption("lsp.server"), ",")
	for i in pairs(server) do
		local part = mysplit(server[i], "|")
		if part[1] == bp.Buf:FileType() and part[2] ~= "" and cmd == nil then
			local run = mysplit(part[2], "%s")
			local initOptions = part[3] or '{}'
			local runCmd = table.remove(run, 1)
			local args = run
			cmd = shell.JobSpawn(runCmd, args, onStdout, onStderr, onExit, {})
			local wd, err = os.Getwd()
			local uri = fmt.Sprintf("file://%s", wd)
			currentServer = bp.Buf:FileType()
			currentAction = "initialize"
			send(currentAction, fmt.Sprintf('{"processId": %.0f, "rootUri": "%s", "initializationOptions": %s, "capabilities": {"textDocument": {"hover": {"contentFormat": ["plaintext", "markdown"]}, "publishDiagnostics": {"relatedInformation": false, "versionSupport": false, "codeDescriptionSupport": true, "dataSupport": true}, "signatureHelp": {"signatureInformation": {"documentationFormat": ["plaintext", "markdown"]}}}}}', os.Getpid(), uri, initOptions))
			send("initialized", "{}")
			local file, _ = filepath.Abs(bp.Buf.Path)
			uri = fmt.Sprintf("file://%s", file)
			local content = util.String(bp.Buf:Bytes()):gsub("\\", "\\\\"):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub('"', '\\"'):gsub("\t", "\\t")
			send("textDocument/didOpen", fmt.Sprintf('{"textDocument": {"uri": "%s", "languageId": "%s", "version": 1, "text": "%s"}}', uri, part[1], content))
		end
	end
end

function sendNext()
	if #queue > 0 then
		local msg = table.remove(queue, 1)
		-- micro.TermMessage("SENDING NEXT", msg)
		shell.JobSend(cmd, msg)
		if msg:find('"method": "initialized"') then
			sendNext()
		end
	end
end

function string.starts(String, Start)
	return string.sub(String, 1, #Start) == Start
end

function string.parse(text)
	local start,fin = text:find("\n%s*\n")
	local cleanedText = text
	if fin ~= nil then
		cleanedText = text:sub(fin)
	end
	data = json.parse(cleanedText)
	return data
end

function onStdout(text)
	if text:find('"method":"workspace/configuration"') then
	    -- actually needs to respond with the same ID as the received JSON
		local message = '{"jsonrpc": "2.0", "id": 0, "result": [{"enable": true}]}'
		shell.JobSend(cmd, fmt.Sprintf('Content-Length: %.0f\n\n%s', #message, message))
	elseif text:find('"method":"textDocument/publishDiagnostics"') or text:find('"method":"textDocument\\/publishDiagnostics"') then
		local data = text:parse()
		local bp = micro.CurPane().Buf
		bp:ClearMessages("lsp")
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
	elseif currentAction == "textDocument/hover" and text:find('"jsonrpc":') then
		currentAction = ''
		--micro.TermMessage(text)
		local data = text:parse()
		local bp = micro.CurPane().Buf
		if data.result and data.result.contents ~= nil and data.result.contents ~= "" then
			if data.result.contents.value then
				micro.InfoBar():Message(data.result.contents.value)
			else
				micro.InfoBar():Message(data.result.contents[1].value)
			end
		end
	elseif text:find('"method":"window/showMessage"') or text:find('"method":"window\\/showMessage"') then
		local data = text:parse()
		micro.InfoBar():Message(data.params.message)
	elseif text:find('"method":"window/logMessage"') or text:find('"method":"window\\/logMessage"') then
		local data = text:parse()
		micro.Log(data.params.message)
	elseif currentAction == "initialize" then
		currentAction = ''
	elseif text:starts("Content-Length:") then
		if text:find('"') and not text:find('"result":null') then
			micro.TermMessage("STDOUT2", text)
		end
	else
		micro.TermMessage("STDOUT", text)
	end
	sendNext()
end

function onStderr(text)
	micro.InfoBar():Error(text)
end

function onExit(str)
	micro.TermMessage("EXIT: ", str)
end

function onSave(bp)
	onRune(bp)
end

function hoverAction(bp)
	if cmd ~= nil then
		local file, _ = filepath.Abs(bp.Buf.Path)
		local line = bp.Buf:GetActiveCursor().Y
		local char = bp.Buf:GetActiveCursor().X
		currentAction = "textDocument/hover"
		send(currentAction, fmt.Sprintf('{"textDocument": {"uri": "file://%s"}, "position": {"line": %.0f, "character": %.0f}}', file, line, char))
	end
end



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
    error('Invalid json syntax starting at ' .. pos_info_str)
  end
end

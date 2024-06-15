local micro = import("micro")
local config = import("micro/config")
local shell = import("micro/shell")
local util = import("micro/util")
local buffer = import("micro/buffer")
local fmt = import("fmt")
local go_os = import("os")
local path = import("path")
local filepath = import("path/filepath")

local version = {}

function preRune(bp, r)
	if splitBP ~= nil then
		pcall(function() splitBP:Unsplit(); end)
		splitBP = nil
		local cur = bp.Buf:GetActiveCursor()
		cur:Deselect(false);
		cur:GotoLoc(buffer.Loc(cur.X + 1, cur.Y))
	end
end

-- when a new character is types, the document changes
function onRune(bp, r)
	local filetype = bp.Buf:FileType()
	micro.Log("FILETYPE", filetype)
	if cmd[filetype] == nil then
		return
	end
	if splitBP ~= nil then
		pcall(function() splitBP:Unsplit(); end)
		splitBP = nil
	end

	local send = withSend(filetype)
	local uri = getUriFromBuf(bp.Buf)
	if r ~= nil then
		lastCompletion = {}
	end
	-- allow the document contents to be escaped properly for the JSON string
	local content = util.String(bp.Buf:Bytes()):gsub("\\", "\\\\"):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub('"', '\\"')
		:gsub("\t", "\\t")
	-- increase change version
	version[uri] = (version[uri] or 0) + 1
	send("textDocument/didChange",
		fmt.Sprintf('{"textDocument": {"version": %.0f, "uri": "%s"}, "contentChanges": [{"text": "%s"}]}', version[uri],
			uri, content), true)
	local ignored = mysplit(config.GetGlobalOption("lsp.ignoreTriggerCharacters") or '', ",")
	if r and capabilities[filetype] then
		if not contains(ignored, "completion") and capabilities[filetype].completionProvider and capabilities[filetype].completionProvider.triggerCharacters and contains(capabilities[filetype].completionProvider.triggerCharacters, r) then
			completionAction(bp)
		elseif not contains(ignored, "signature") and capabilities[filetype].signatureHelpProvider and capabilities[filetype].signatureHelpProvider.triggerCharacters and contains(capabilities[filetype].signatureHelpProvider.triggerCharacters, r) then
			hoverAction(bp)
		end
	end
end

function onBeforeTextEvent(bp, textEvent)
	--micro.Log('onBeforeTextEvent', bp, textEvent)
	return
	--[[
	local filetype = bp.Settings["filetype"]
	if cmd[filetype] == nil then
		return
	end
	if splitBP ~= nil then
		pcall(function() splitBP:Unsplit(); end)
		splitBP = nil
	end

	local send = withSend(filetype)
	local uri = getUriFromBuf(bp)
	version[uri] = (version[uri] or 0) + 1

	local changes = ''
	-- send the change message for every delta
	for i = 1, #textEvent.Deltas do
		local delta = textEvent.Deltas[i]
		local startLine = 0 + delta.Start.Y - 1
		local startChar = 0 + delta.Start.X - 1
		local endLine = 0 + delta.End.Y - 1
		local endChar = 0 + delta.End.X - 1
		local change = util.String(delta.Text):gsub("\\", "\\\\"):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub('"', '\\"')
				:gsub("\t", "\\t")
		if #changes > 0 then changes = changes .. ',' end
		changes = changes .. fmt.Sprintf('{"range": {"start": {"line": %d, "character": %d}, "end": {"line": %d, "character": %d}}, "text": "%s"}', startLine, startChar, endLine, endChar, change)
	end	
	if #changes > 0 then
		micro.Log(changes)
		send("textDocument/didChange", fmt.Sprintf('{"textDocument": {"version": "%.0f", "uri": "%s"}, "contentChanges": [%s]', version[uri], uri, changes))
	end
	--]]
end

-- alias functions for any kind of change to the document
function onMoveLinesUp(bp) onRune(bp) end

function onMoveLinesDown(bp) onRune(bp) end

function onDeleteWordRight(bp) onRune(bp) end

function onDeleteWordLeft(bp) onRune(bp) end

function onInsertNewline(bp) onRune(bp) end

function onInsertSpace(bp) onRune(bp) end

function onBackspace(bp) onRune(bp) end

function onDelete(bp) onRune(bp) end

function onInsertTab(bp) onRune(bp) end

function onUndo(bp) onRune(bp) end

function onRedo(bp) onRune(bp) end

function onCut(bp) onRune(bp) end

function onCutLine(bp) onRune(bp) end

function onDuplicateLine(bp) onRune(bp) end

function onDeleteLine(bp) onRune(bp) end

function onIndentSelection(bp) onRune(bp) end

function onOutdentSelection(bp) onRune(bp) end

function onOutdentLine(bp) onRune(bp) end

function onIndentLine(bp) onRune(bp) end

function onPaste(bp) onRune(bp) end

function onPlayMacro(bp) onRune(bp) end

function onAutocomplete(bp) onRune(bp) end

function onEscape(bp)
	if splitBP ~= nil then
		pcall(function() splitBP:Unsplit(); end)
		splitBP = nil
	end
end

function preInsertNewline(bp)
	if bp.Buf.Path == "References found" then
		local cur = bp.Buf:GetActiveCursor()
		cur:SelectLine()
		local data = util.String(cur:GetSelection())
		local file, line, character = data:match("(./[^:]+):([^:]+):([^:]+)")
		if not file then
		
		end
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
		formatAction(bp, function()
			bp:Save()
		end)
	end
end

function onSave(bp)
	local filetype = bp.Buf:FileType()
	if cmd[filetype] == nil then
		return
	end

	local send = withSend(filetype)
	local uri = getUriFromBuf(bp.Buf)

	send("textDocument/didSave", fmt.Sprintf('{"textDocument": {"uri": "%s"}}', uri), true)
end

function onBufferOpen(buf)
	local filetype = buf:FileType()
	micro.Log("ONBUFFEROPEN", filetype)
	if filetype ~= "unknown" and not cmd[filetype] then return startServer(filetype, handleInitialized); end
	if cmd[filetype] then
		handleInitialized(buf, filetype)
	end
end

function onStdout(filetype)
	local nextMessage = ''
	return function(text)
		if text:starts("Content-Length:") then
			message = text
		else
			message = message .. text
		end
		message = message:gsub('}Content%-Length:', '}\0Content-Length:')
		local entries = mysplit(message, '\0')
		if #entries > 1 then
			micro.Log('Found break')
			entries[1] = entries[1]
			entries[2] = entries[2]
			message = entries[1]
			nextMessage = entries[2]
		end
		if not message:ends("}") then
			micro.Log('Message incomplete, ignoring for now...')
			return
		end
		local data = message:parse()
		if data == false then
			micro.Log('Parsing failed', message)
			return
		end

		micro.Log(filetype .. " <<< " .. (data.method or 'no method'))

		if data.method == "workspace/configuration" then
			-- actually needs to respond with the same ID as the received JSON
			local message = fmt.Sprintf('{"jsonrpc": "2.0", "id": %.0f, "result": [{"enable": true}]}', data.id)
			shell.JobSend(cmd[filetype], fmt.Sprintf('Content-Length: %.0f\n\n%s', #message, message))
		elseif data.method == "textDocument/publishDiagnostics" or data.method == "textDocument\\/publishDiagnostics" then
			-- react to server-published event
			local bp = micro.CurPane().Buf
			bp:ClearMessages("lsp")
			bp:AddMessage(buffer.NewMessage("lsp", "", buffer.Loc(0, 10000000), buffer.Loc(0, 10000000), buffer.MTInfo))
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

					if not isIgnoredMessage(diagnostic.message) then
						msg = buffer.NewMessage("lsp", diagnostic.message, mstart, mend, type)
						bp:AddMessage(msg)
					end
				end
			end
		elseif currentAction[filetype] and currentAction[filetype].method and not data.method and currentAction[filetype].response and data.jsonrpc then -- react to custom action event
			local bp = micro.CurPane()
			micro.Log("Received message for ", filetype, data)
			currentAction[filetype].response(bp, data)
			currentAction[filetype] = {}
		elseif data.method == "window/showMessage" or data.method == "window\\/showMessage" then
			if filetype == micro.CurPane().Buf:FileType() then
				micro.InfoBar():Message(data.params.message)
			else
				micro.Log(filetype .. " message " .. data.params.message)
			end
		elseif data.method == "window/logMessage" or data.method == "window\\/logMessage" then
			micro.Log(data.params.message)
		elseif message:starts("Content-Length:") then
			if message:find('"') and not message:find('"result":null') then
				micro.Log("Unhandled message 1", filetype, message, currentAction[filetype])
			end
		else
			-- enable for debugging purposes
			micro.Log("Unhandled message 2", filetype, message)
		end

		if nextMessage then
			local nm = nextMessage
			nextMessage = nil
			onStdout(filetype)(nm)
		end
	end
end

function onStderr(text)
	micro.Log("ONSTDERR", text)
	if not isIgnoredMessage(text) then
		micro.InfoBar():Message(text)
	end
end

function onExit(filetype)
	return function(str)
		currentAction[filetype] = nil
		cmd[filetype] = nil
		micro.Log("ONEXIT", filetype, str)
	end
end

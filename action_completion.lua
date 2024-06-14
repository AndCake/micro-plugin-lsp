local micro = import("micro")
local config = import("micro/config")
local util = import("micro/util")
local buffer = import("micro/buffer")
local fmt = import("fmt")

local lastCompletion = {}
local completionCursor = 0
local doAutoCompletion = nil

function completionAction(bp)
	local filetype = bp.Buf:FileType()
	local send = withSend(filetype)
	local file = bp.Buf.AbsPath
	local line = bp.Buf:GetActiveCursor().Y
	local char = bp.Buf:GetActiveCursor().X

	if lastCompletion[1] == file and lastCompletion[2] == line and lastCompletion[3] == char then
		completionCursor = completionCursor + 1
	else
		completionCursor = 0
		if bp.Cursor:HasSelection() then
			-- we have a selection
			-- assume we want to indent the selection
			bp:IndentSelection()
			return
		end
		if char == 0 then
			-- we are at the very first character of a line
			-- assume we want to indent
			bp:IndentLine()
			return
		end
		local cur = bp.Buf:GetActiveCursor()
		cur:SelectLine()
		local lineContent = util.String(cur:GetSelection())
		cur:ResetSelection()
		cur:GotoLoc(buffer.Loc(char, line))
		local startOfLine = "" .. lineContent:sub(1, char)
		if startOfLine:match("^%s+$") then
			-- we are at the beginning of a line
			-- assume we want to indent the line
			bp:IndentLine()
			return
		end
	end
	if completionCursor == 0 then
		doAutoCompletion = nil
		if cmd[filetype] == nil then return; end
		lastCompletion = { file, line, char }
		currentAction[filetype] = { method = "textDocument/completion", response = completionActionResponse }
		send(currentAction[filetype].method,
			fmt.Sprintf('{"textDocument": {"uri": "file://%s"}, "position": {"line": %.0f, "character": %.0f}}', file,
				line, char))
	elseif doAutoCompletion then
		doAutoCompletion()
	end
end

function findCommon(input, list)
	local commonLen = 0
	local prefixList = {}
	local str = input.textEdit and input.textEdit.newText or input.label
	for i = 1, #str, 1 do
		local prefix = str:sub(1, i)
		prefixList[prefix] = 0
		for idx, entry in ipairs(list) do
			local currentEntry = entry.textEdit and entry.textEdit.newText or entry.label
			if currentEntry:starts(prefix) then
				prefixList[prefix] = prefixList[prefix] + 1
			end
		end
	end
	local longest = ""
	for idx, entry in pairs(prefixList) do
		if entry >= #list then
			if #longest < #idx then
				longest = idx
			end
		end
	end
	if #list == 1 then
		return list[1].textEdit and list[1].textEdit.newText or list[1].label
	end
	return longest
end

function completionActionResponse(bp, data)
	local results = data.result
	if results == nil then
		return
	end
	if results.items then
		results = results.items
	end

	table.sort(results, function(left, right)
		return (left.sortText or left.label) < (right.sortText or right.label)
	end)

	doAutoCompletion = function()
		local buffer_complete = function(buf)
			local completions = {}
			local labels = {}
			for idx, entry in ipairs(results) do
				if idx >= (completionCursor % #results) + 1 then
					completions[#completions + 1] = entry.textEdit and entry.textEdit.newText or entry.label
					labels[#labels + 1] = entry.label
				end
			end

			return completions, labels
		end

		local xy = buffer.Loc(bp.Cursor.X, bp.Cursor.Y)
		local start = xy
		local originalStart = start
		if bp.Cursor:HasSelection() then
			bp.Cursor:DeleteSelection()
		end
		local prefix = ""
		local reversed = ""
		local entry = results[(completionCursor % #results) + 1]

		-- if we have no defined ranges in the result
		-- try to find out what our prefix is we want to filter against
		if not results[1] or not results[1].textEdit or not results[1].textEdit.range then
			if capabilities[bp.Buf:FileType()] and capabilities[bp.Buf:FileType()].completionProvider and capabilities[bp.Buf:FileType()].completionProvider.triggerCharacters then
				local cur = bp.Buf:GetActiveCursor()
				cur:SelectLine()
				local lineContent = util.String(cur:GetSelection())
				reversed = string.reverse(lineContent:gsub("\r?\n$", ""):sub(1, xy.X))
				local triggerChars = capabilities[bp.Buf:FileType()].completionProvider.triggerCharacters
				for i = 1, #reversed, 1 do
					local char = reversed:sub(i, i)
					-- try to find a trigger character or any other non-word character
					if contains(triggerChars, char) or contains({ " ", ":", "/", "-", "\t", ";" }, char) then
						found = true
						start = buffer.Loc(#reversed - (i - 1), bp.Cursor.Y)
						bp.Cursor:SetSelectionStart(start)
						bp.Cursor:SetSelectionEnd(xy)
						prefix = util.String(cur:GetSelection())
						bp.Cursor:DeleteSelection()
						bp.Cursor:ResetSelection()
						break
					end
				end
				if not found then
					prefix = lineContent:gsub("\r?\n$", '')
				end
			end
			-- if we have found a prefix
			if prefix ~= "" then
				-- filter it down to what is suggested by the prefix
				results = table.filter(results, function(entry)
					return entry.label:starts(prefix)
				end)
			end
		else
			if entry and (entry.textEdit and entry.textEdit.range) then
				start = buffer.Loc(entry.textEdit.range.start.character, entry.textEdit.range.start.line)
				bp.Cursor:SetSelectionStart(start)
				bp.Cursor:SetSelectionEnd(xy)
				bp.Cursor:DeleteSelection()
				bp.Cursor:ResetSelection()
			elseif capabilities[bp.Buf:FileType()] and capabilities[bp.Buf:FileType()].completionProvider and capabilities[bp.Buf:FileType()].completionProvider.triggerCharacters then
				if not found then
					-- we found nothing - so assume we need the beginning of the line
					if reversed:starts(" ") or reversed:starts("\t") then
						-- if we end with some indentation, keep it
						start = buffer.Loc(#reversed, bp.Cursor.Y)
					else
						start = buffer.Loc(0, bp.Cursor.Y)
					end
					bp.Cursor:SetSelectionStart(start)
					bp.Cursor:SetSelectionEnd(xy)
					bp.Cursor:DeleteSelection()
					bp.Cursor:ResetSelection()
				end
			end
		end
		if #prefix > 0 then
			xy = buffer.Loc(bp.Cursor.X, bp.Cursor.Y)
			local nstart = buffer.Loc(bp.Cursor.X - #prefix, bp.Cursor.Y)
			bp.Cursor:GotoLoc(nstart)
			bp.Cursor:SetSelectionStart(nstart)
			bp.Cursor:SetSelectionEnd(xy)
			bp.Cursor:DeleteSelection()
		end
		bp.Buf:Autocomplete(buffer_complete)
		local xy = buffer.Loc(bp.Cursor.X + #prefix, bp.Cursor.Y)
		bp.Cursor:GotoLoc(originalStart)
		bp.Cursor:SetSelectionStart(start)
		bp.Cursor:SetSelectionEnd(xy)

		local msg = ''
		local insertion = ''
		if entry and (entry.detail or entry.documentation) then
			msg = fmt.Sprintf("%s\n\n%s", entry.detail or '',
				entry.documentation and entry.documentation.value or entry.documentation or '')
		end
		if config.GetGlobalOption("lsp.autocompleteDetails") then
			if entry and (entry.detail or entry.documentation) then
				if not splitBP then
					local tmpName = ("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"):random(32)
					local logBuf = buffer.NewBuffer(msg, tmpName)
					splitBP = bp:HSplitBuf(logBuf)
					bp:NextSplit()
				else
					splitBP:SelectAll()
					splitBP.Cursor:DeleteSelection()
					splitBP.Cursor:ResetSelection()
					splitBP.Buf:insert(buffer.Loc(1, 1), msg)
				end
			end
		else
			if entry and (entry.detail or entry.documentation) then
				micro.InfoBar():Message(entry.detail or
					(entry.documentation and entry.documentation.value or entry.documentation or ''))
			end
		end --]]
	end
	doAutoCompletion()
end

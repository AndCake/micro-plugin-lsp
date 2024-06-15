local micro = import("micro")
local buffer = import("micro/buffer")
local fmt = import('fmt')

function formatAction(bp, callback)
	local filetype = bp.Buf:FileType()
	if cmd[filetype] == nil then return; end
	local send = withSend(filetype)
	local file = bp.Buf.AbsPath
	local cfg = bp.Buf.Settings

	currentAction[filetype] = { method = "textDocument/formatting", response = formatActionResponse(callback) }
	send(currentAction[filetype].method,
		fmt.Sprintf(
			'{"textDocument": {"uri": "file://%s"}, "options": {"tabSize": %.0f, "insertSpaces": %t, "trimTrailingWhitespace": %t, "insertFinalNewline": %t}}',
			file, cfg["tabsize"], cfg["tabstospaces"], cfg["rmtrailingws"], cfg["eofnewline"]))
end

function formatActionResponse(callback)
	return function(bp, data)
		if data.result == nil then return; end
		local edits = data.result
		-- make sure we apply the changes from back to front
		-- this allows for changes to not need position updates
		table.sort(edits, function(left, right)
			-- go by lines first
			return left.range['end'].line > right.range['end'].line or
				-- if lines match, go by end character
				left.range['end'].line == right.range['end'].line and
				left.range['end'].character > right.range['end'].character or
				-- if they match too, go by start character
				left.range['end'].line == right.range['end'].line and
				left.range['end'].character == right.range['end'].character and
				left.range.start.line == left.range['end'].line and
				left.range.start.character > right.range.start.character
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

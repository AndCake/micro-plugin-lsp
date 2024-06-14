local micro = import("micro")
local fmt = import('fmt')
local config = import('micro/config')
local buffer = import('micro/buffer')

-- the hover action request and response
-- the hoverActionResponse is hooked up in
function hoverAction(bp)
	local filetype = bp.Buf:FileType()
	if cmd[filetype] ~= nil then
		local send = withSend(filetype)
		local file = bp.Buf.AbsPath
		local line = bp.Buf:GetActiveCursor().Y
		local char = bp.Buf:GetActiveCursor().X
		currentAction[filetype] = { method = "textDocument/hover", response = hoverActionResponse }
		send(currentAction[filetype].method,
			fmt.Sprintf('{"textDocument": {"uri": "file://%s"}, "position": {"line": %.0f, "character": %.0f}}', file,
				line, char))
	end
end

function hoverActionResponse(bp, data)
	if data.result and data.result.contents ~= nil and data.result.contents ~= "" then
		local msg = ''
		if data.result.contents.value then
			msg = data.result.contents.value
		elseif #data.result.contents > 0 then
			msg = data.result.contents[1].value
		end
		if config.GetGlobalOption("lsp.autocompleteDetails") and #mysplit(msg, '\n') > 1 then
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
		else
			micro.InfoBar():Message(msg)
		end --]]
	end
end

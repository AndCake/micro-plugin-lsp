local fmt = import('fmt')
local buffer = import('micro/buffer')

-- the references action request and response
function referencesAction(bp)
	local filetype = bp.Buf:FileType()
	if cmd[filetype] == nil then return; end

	local send = withSend(filetype)
	local file = bp.Buf.AbsPath
	local line = bp.Buf:GetActiveCursor().Y
	local char = bp.Buf:GetActiveCursor().X
	currentAction[filetype] = { method = "textDocument/references", response = referencesActionResponse }
	send(currentAction[filetype].method,
		fmt.Sprintf(
			'{"textDocument": {"uri": "file://%s"}, "position": {"line": %.0f, "character": %.0f}, "context": {"includeDeclaration":true}}',
			file, line, char))
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
		msg = msg ..
			"." .. doc:sub(#rootUri + 1, #doc) .. ":" .. ref.range.start.line .. ":" .. ref.range.start.character
	end

	local logBuf = buffer.NewBuffer(msg, "References found")
	local splitBP = bp:HSplitBuf(logBuf)
end

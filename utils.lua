local fmt = import("fmt")

function toBytes(str)
	local result = {}
	for i = 1, #str do
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

function mysplit(inputstr, sep)
	if sep == nil then
		sep = "%s"
	end
	local t = {}
	for str in string.gmatch(inputstr, "([^" .. sep .. "]+)") do
		table.insert(t, str)
	end
	return t
end

function table.join(tbl, sep)
	local result = ''
	for _, value in ipairs(tbl) do
		result = result .. (#result > 0 and sep or '') .. value
	end
	return result
end


function contains(list, x)
	for _, v in pairs(list) do
		if v == x then return true; end
	end
	return false
end

function string.starts(String, Start)
	return string.sub(String, 1, #Start) == Start
end

function string.ends(String, End)
	return string.sub(String, #String - (#End - 1), #String) == End
end

function string.random(CharSet, Length, prefix)
	local _CharSet = CharSet or '.'

	if _CharSet == '' then
		return ''
	else
		local Result = prefix or ""
		math.randomseed(os.time())
		for Loop = 1, Length do
			local char = math.random(1, #CharSet)
			Result = Result .. CharSet:sub(char, char)
		end

		return Result
	end
end

function string.parse(text)
	if not text:find('"jsonrpc":') then return {}; end
	local start, fin = text:find("\n%s*\n")
	local cleanedText = text
	if fin ~= nil then
		cleanedText = text:sub(fin)
	end
	local status, res = pcall(json.parse, cleanedText)
	if status then
		return res
	end
	return false
end

table.filter = function(t, filterIter)
	local out = {}

	for k, v in pairs(t) do
		if filterIter(v, k, t) then table.insert(out, v) end
	end

	return out
end

table.unpack = table.unpack or unpack


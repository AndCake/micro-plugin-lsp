local config = import('micro/config')

local commands = {
	['hover'] = { action = hoverAction, shortcut = 'Alt-k' },
	['definition'] = { action = definitionAction, shortcut = 'Alt-d' },
	['lspcompletion'] = { action = completionAction, shortcut = 'CtrlSpace' },
	['format'] = { action = formatAction, shortcut = 'Alt-f' },
	['references'] = { action = referencesAction, shortcut = 'Alt-r' },
}

function defineActions() 
	for k, v in pairs(commands) do
		config.MakeCommand(k, v.action, config.NoComplete)
		if v.shortcut then
			config.TryBindKey(v.shortcut, "command:" .. k, false)
		end
	end
end

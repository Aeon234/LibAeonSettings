-- The texture and sound pickers' choices: LibSharedMedia's bar textures and sounds by their registered names, read at
-- each call so media registered later appear; Blizzard's own bar textures without LibSharedMedia. Also playing a
-- sound picker's choice.

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

-- Blizzard's own bar textures under LibSharedMedia's names for them, so a saved name means the same either way.
local FALLBACK_TEXTURES = {
	{ "Blizzard", "Interface\\TargetingFrame\\UI-StatusBar" },
	{ "Blizzard Character Skills Bar", "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar" },
	{ "Blizzard Raid Bar", "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
}
-- LibSharedMedia registers its "None" sound as the number 1; a sound picker's setting gives its own None.
local NONE_SOUND = 1
local SOUND_CHANNEL = "Master"

-- A file read from LibSharedMedia's registry directly, so a global override another addon sets with `SetGlobal`
-- does not turn every entry into the same file. An empty file counts as missing.
local function MediaFile(files, name)
	local file = files and files[name]
	if file == "" then
		return nil
	end

	return file
end

---The choices of a texture picker, by name: LibSharedMedia's bar textures, or Blizzard's own.
---@return { value: string, text: string, texture: string }[]
function lib:TextureChoices()
	local choices = {}
	local media = LibStub("LibSharedMedia-3.0", true)
	if media then
		local files = media:HashTable("statusbar")
		for _, name in ipairs(media:List("statusbar")) do
			local file = MediaFile(files, name)
			if file then
				table.insert(choices, { value = name, text = name, texture = file })
			end
		end
	else
		for _, entry in ipairs(FALLBACK_TEXTURES) do
			table.insert(choices, { value = entry[1], text = entry[1], texture = entry[2] })
		end
	end

	return choices
end

---The file a texture picker's saved name stands for, or nil when nothing has that name.
---@param name any
---@return string?
function lib:TextureFile(name)
	local media = LibStub("LibSharedMedia-3.0", true)
	if media then
		return MediaFile(media:HashTable("statusbar"), name)
	end
	for _, entry in ipairs(FALLBACK_TEXTURES) do
		if entry[1] == name then
			return entry[2]
		end
	end
end

---The choices of a sound picker: the setting's own in their order, then LibSharedMedia's sounds by name, leaving out
---its "None" and every name one of the setting's own already uses.
---@param options table[]? the setting's own choices, each `{ value, text, soundKit?, soundFile? }` or a title
---@return table[]
function lib:SoundChoices(options)
	local choices, seen = {}, {}
	for _, option in ipairs(options or {}) do
		table.insert(choices, option)
		if not option.title then
			seen[tostring(option.text)] = true
			seen[tostring(option.value)] = true
		end
	end
	local media = LibStub("LibSharedMedia-3.0", true)
	if media then
		local files = media:HashTable("sound")
		for _, name in ipairs(media:List("sound")) do
			local file = MediaFile(files, name)
			if file and file ~= NONE_SOUND and not seen[name] then
				table.insert(choices, { value = name, text = name, soundFile = file })
			end
		end
	end

	return choices
end

---Plays a sound picker's choice once on the Master channel: a sound kit, or a file. A choice with neither plays
---nothing.
function lib:PlayChoiceSound(choice)
	if choice.soundKit then
		PlaySound(choice.soundKit, SOUND_CHANNEL)
	elseif choice.soundFile and PlaySoundFile then
		PlaySoundFile(choice.soundFile, SOUND_CHANNEL)
	end
end

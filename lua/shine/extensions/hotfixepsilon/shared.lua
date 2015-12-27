--[[
-- This is a hotfix plugin I'll use to realease hotfixes for ns2.
 ]]
local Plugin = {}

local StringExplode = string.Explode
local StringFormat = string.format
local TableConcat = table.concat
local TextWrap = TextWrap

--Hofix for Build 277

--[[
--The following two methods are based on work by Person8880 from https://github.com/Person8880/Shine
]]

--[[
Wraps text to fit the size limit. Used for long words...

Returns two strings, first one fits entirely on one line, the other may not, and should be
added to the next word.
]]
function TextWrap( label, text, xpos, maxWidth )
	local i = 1
	local firstLine = text
	local secondLine = ""
	local textLength = text:UTF8Length()
	local scale = label.GetScale and label:GetScale().x or 1

	--Character by character, extend the text until it exceeds the width limit.
	repeat
		local curText = text:UTF8Sub( 1, i )

		--Once it reaches the limit, we go back a character, and set our first and second line results.
		if xpos + label:GetTextWidth( curText ) * scale > maxWidth then
			firstLine = text:UTF8Sub( 1, math.max(i - 1, 1 ) )
			secondLine = text:UTF8Sub( math.max(i, 2) )

			break
		end

		i = i + 1
	until i >= textLength

	return firstLine, secondLine
end

--[[
    Word wraps text, adding new lines where the text exceeds the width limit.
]]
function WordWrap( label, text, xpos, maxWidth, maxLines )
	if maxWidth <= 0 then return "" end

	local words = StringExplode( text, " " )
	local startIndex = 1
	local lines = {}
	local i = 1
	local scale = label.GetScale and label:GetScale().x or 1

	--While loop, as the size of the words table may increase. But make sure we don't end in a infinite loop
	while i <= #words and i <= 200 do
		local curText = TableConcat( words, " ", startIndex, i )

		if xpos + label:GetTextWidth( curText ) * scale > maxWidth then
			--This means one word is wider than the whole label, so we need to cut it part way through.
			if startIndex == i then
				local firstLine, secondLine = TextWrap( label, curText, xpos, maxWidth )

				lines[ #lines + 1 ] = firstLine

				table.insert(words, i + 1, secondLine )

				startIndex = i + 1
			else
				lines[ #lines + 1 ] = TableConcat( words, " ", startIndex, i - 1 )

				--We need to jump back a step, as we've still got another word to check.
				startIndex = i
				i = i - 1
			end

			if maxLines and maxLines <= #lines then
				break
			end

		elseif i == #words then --We're at the end!
		lines[ #lines + 1 ] = curText
		startIndex = i + 1
		end

		i = i + 1
	end

	return TableConcat( lines, "\n" ), maxLines and TableConcat(words, " ", startIndex)
end

--Plugin Stub
function Plugin:Initialise()
	self.Enabled = true
	return true
end

function Plugin:Cleanup()
	self.BaseClass.Cleanup( self )
	self.Enabled = false
end

Shine:RegisterExtension( "hotfixepsilon", Plugin )
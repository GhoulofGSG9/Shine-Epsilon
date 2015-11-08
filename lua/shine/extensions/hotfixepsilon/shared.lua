--[[
-- This is a hotfix plugin I'll use to realease hotfixes for ns2.
 ]]
local Plugin = {}

local StringExplode = string.Explode
local StringFormat = string.format
local TableConcat = table.concat
local TextWrap = TextWrap

--Hofix for Build 277 infinite WordWrap
function WordWrap( label, text, xpos, maxWidth )
	if maxWidth <= 0 then return "" end

	local words = StringExplode( text, " " )
	local startIndex = 1
	local lines = {}
	local i = 1

	--While loop, as the size of the words table may increase. But make sure we don't end in a infinite loop
	while i <= #words and i <= 100 do
		local curText = TableConcat( words, " ", startIndex, i )

		if xpos + label:GetTextWidth( curText ) * label:GetScale().x > maxWidth then
			--This means one word is wider than the whole label, so we need to cut it part way through.
			if startIndex == i then
				local firstLine, secondLine = TextWrap( label, curText, xpos, maxWidth )

				lines[ #lines + 1 ] = firstLine

				--Add the second line to the next word, or as a new next word if none exists.
				if words[ i + 1 ] then
					words[ i + 1 ] = StringFormat( "%s %s", secondLine, words[ i + 1 ] )
				else
					words[ i + 1 ] = secondLine
				end

				startIndex = i + 1
			else
				lines[ #lines + 1 ] = TableConcat( words, " ", startIndex, i - 1 )

				--We need to jump back a step, as we've still got another word to check.
				startIndex = i
				i = i - 1
			end
		elseif i == #words then --We're at the end!
			lines[ #lines + 1 ] = curText
		end

		i = i + 1
	end

	return TableConcat( lines, "\n" )
end

--Plugin Stub
function Plugin:Initialise()
	self.Enabled = true
	return true
end

function Plugin:Cleanup()
	self.BaseClass.Cleanup()
	self.Enabled = false
end

Shine:RegisterExtension( "hotfixepsilon", Plugin )

--!native
--!strict

--[[
GIF DECODER

require(gifModule): (gifData) -> (file)

file.ReadMatrix: (x, y, width, height) -> (any)
	returns current image (one animated frame) as 2D-matrix of colors (as nested Lua tables)
	by default whole non-clipped picture is returned
	pixels are numbers: (-1) for transparent color, 0..0xFFFFFF for 0xRRGGBB color

file.GetFileParameters()
	returns table with the following fields (these are the properties of the whole file)
	Comment -- text comment inside gif-file
	Looped -- boolean
	NumberOfImages -- == 1 for non-animated gifs, > 1 for animated gifs

file.NextImage(loopingMode)
	switches to next frame, returns false if failed to switch
	loopingMode = "never" (default) - never wrap from the last frame to the first
	"always" - always wrap from the last frame to the first
	"play" - depends on whether or not .gif-file is marked as Looped gif

file.Width: number
file.Height: number
]]

--[[
MIT License

Copyright (c) 2017 Egor Skriptunoff 

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]

local function openGif(data: buffer)
	local offset = 0

	local function readByte()
		offset += 1
		return buffer.readu8(data, offset - 1)
	end
	local function readString(length)
		offset += length
		return buffer.readstring(data, offset - length, offset)
	end
	local function readU16()
		offset += 2
		return buffer.readu16(data, offset - 2)
	end

	local format = readString(6)
	if format ~= "GIF87a" and format ~= "GIF89a" then
		error("wrong file format")
	end

	local gifWidth, gifHeight = readU16(), readU16()
	assert(gifWidth ~= 0 and gifHeight ~= 0, "wrong file format")

	local globalFlags = readByte()
	offset += 2
	local globalPalette -- 0-based global palette array (or nil)
	if globalFlags >= 0x80 then
		local len = 2 ^ (globalFlags % 8 + 1) - 1
		globalPalette = table.create(len)
		for colorIndex = 0, len do
			local r, g, b = readByte(), readByte(), readByte()
			globalPalette[colorIndex] = r * 65536 + g * 256 + b
		end
	end
	local firstFrameOffset = offset

	local fileParameters -- initially nil, filled after finishing first pass
	local fpComment, fpLoopedAnimation -- for storing parameters before first pass completed
	local fpNumberOfFrames = 0
	local fpLastProcessedOffset = 0

	local function fpFirstPass()
		if not fileParameters then
			if offset > fpLastProcessedOffset then
				fpLastProcessedOffset = offset
				return true
			end
		end
		return false
	end

	local function skipToEndOfBlock()
		repeat
			local size = readByte()
			offset += size
		until size == 0
	end

	local function skip2C()
		offset += 8
		local localFlags = readByte()
		if localFlags >= 0x80 then
			offset += 3 * 2 ^ (localFlags % 8 + 1)
		end
		offset += 1
		skipToEndOfBlock()
	end

	local function processBlocks(callback2C: (() -> "OK")?, callback21F9: (() -> ())?): string?
		-- processing blocks of GIF-file
		local callback21F9_or_skipToEndOfBlock = callback21F9 or skipToEndOfBlock
		while true do
			local starter = readByte()
			if starter == 0x3B then -- EOF marker
				if fpFirstPass() then
					fileParameters =
						{ Comment = fpComment, Looped = fpLoopedAnimation, NumberOfImages = fpNumberOfFrames }
				end
				return "EOF"
			elseif starter == 0x2C then -- image marker
				if fpFirstPass() then
					fpNumberOfFrames = fpNumberOfFrames + 1
				end
				if callback2C then
					return callback2C()
				else
					return skip2C()
				end
			elseif starter == 0x21 then
				local fnNo = readByte()
				if fnNo == 0xF9 then
					callback21F9_or_skipToEndOfBlock()
				elseif fnNo == 0xFE and not fpComment then
					local fpCommentTable = {}
					local fpIndex = 0
					repeat
						local size = readByte()
						fpIndex += 1
						fpCommentTable[fpIndex] = readString(size)
					until size == 0
					fpComment = table.concat(fpCommentTable)
				elseif fnNo == 0xFF and readString(readByte()) == "NETSCAPE2.0" then
					fpLoopedAnimation = true
					skipToEndOfBlock()
				else
					skipToEndOfBlock()
				end
			else
				error("wrong file format")
			end
		end
	end

	local loadedFrameNo = 0 --\ frame parameters (frameNo = 1, 2, 3,...)
	local loadedFrameDelay: number? --/
	local loadedFrameActionOnBackground: ("undo" | "combine" | "erase")?
	local loadedFrameTransparentColorIndex: number?
	local loadedFrameMatrix -- picture of the frame\ may be two pointers to the same matrix
	local backgroundMatrixAfterLoadedFrame -- background for next picture /

	local backgroundRectangleToEraseLeft: number?
	local backgroundRectangleToEraseTop: number?
	local backgroundRectangleToEraseWidth: number?
	local backgroundRectangleToEraseHeight: number?

	local function callback2C(): "OK"
		if
			backgroundRectangleToEraseLeft
			and backgroundRectangleToEraseTop
			and backgroundRectangleToEraseWidth
			and backgroundRectangleToEraseHeight
		then
			for row = backgroundRectangleToEraseTop + 1, backgroundRectangleToEraseTop + backgroundRectangleToEraseHeight do
				local line = backgroundMatrixAfterLoadedFrame[row]
				for col = backgroundRectangleToEraseLeft + 1, backgroundRectangleToEraseLeft + backgroundRectangleToEraseWidth do
					line[col] = -1
				end
			end

			backgroundRectangleToEraseLeft = nil
			backgroundRectangleToEraseTop = nil
			backgroundRectangleToEraseWidth = nil
			backgroundRectangleToEraseHeight = nil
		end
		loadedFrameActionOnBackground = loadedFrameActionOnBackground or "combine"
		local left, top, width, height = readU16(), readU16(), readU16(), readU16()
		assert(
			width ~= 0 and height ~= 0 and left + width <= gifWidth and top + height <= gifHeight,
			"wrong file format"
		)
		local localFlags = readByte()
		local interlaced = localFlags % 0x80 >= 0x40
		local palette = globalPalette -- 0-based palette array
		if localFlags >= 0x80 then
			local len = 2 ^ (localFlags % 8 + 1) - 1
			palette = table.create(len)
			for colorIndex = 0, len do
				local r, g, b = readByte(), readByte(), readByte()
				palette[colorIndex] = r * 65536 + g * 256 + b
			end
		end
		assert(palette, "wrong file format")
		local bitsInColor = readByte() -- number of colors in LZW voc

		local bytesInCurrentPartOfStream = 0
		local function readByteFromStream(): number | false -- returns next byte or false
			if bytesInCurrentPartOfStream > 0 then
				bytesInCurrentPartOfStream = bytesInCurrentPartOfStream - 1
				return readByte()
			else
				bytesInCurrentPartOfStream = readByte() - 1
				if bytesInCurrentPartOfStream >= 0 then
					return readByte()
				else
					return false
				end
			end
		end

		local CLEARVOC = 2 ^ bitsInColor
		local ENDOFSTREAM = CLEARVOC + 1

		local LZWVocPrefixCodes
		local LZWVocColorIndices

		local bitsInCode = bitsInColor + 1
		local nextPowerOfTwo = 2 ^ bitsInCode

		local firstUndefinedCode
		local needCompletion = false

		local streamBitBuffer = 0
		local bitsInBuffer = 0
		local function readCodeFromStream()
			while bitsInBuffer < bitsInCode do
				streamBitBuffer = streamBitBuffer + assert(readByteFromStream(), "wrong file format") * 2 ^ bitsInBuffer
				bitsInBuffer = bitsInBuffer + 8
			end
			local code = streamBitBuffer % nextPowerOfTwo
			streamBitBuffer = (streamBitBuffer - code) / nextPowerOfTwo
			bitsInBuffer = bitsInBuffer - bitsInCode
			return code
		end

		assert(readCodeFromStream() == CLEARVOC, "wrong file format")

		local function clearLZWVoc()
			LZWVocPrefixCodes = {}
			LZWVocColorIndices = {}
			bitsInCode = bitsInColor + 1
			nextPowerOfTwo = 2 ^ bitsInCode
			firstUndefinedCode = CLEARVOC + 2
			needCompletion = false
		end

		clearLZWVoc()

		-- Copy matrix backgroundMatrixAfterLoadedFrame to loadedFrameMatrix

		if loadedFrameActionOnBackground == "combine" or loadedFrameActionOnBackground == "erase" then
			loadedFrameMatrix = backgroundMatrixAfterLoadedFrame
		else -- "undo"
			loadedFrameMatrix = table.clone(backgroundMatrixAfterLoadedFrame)
		end

		-- Decode and apply image delta (window: left, top, width, height) on the matrix loadedFrameMatrix

		local pixelsRemained = width * height
		local xInsideWindow: number, yInsideWindow: number -- coordinates inside window
		local function pixelFromStream(colorIndex)
			pixelsRemained = pixelsRemained - 1
			if 0 > pixelsRemained then
				error("wrong file format")
			end
			if xInsideWindow then
				xInsideWindow = xInsideWindow + 1
				if xInsideWindow == width then
					xInsideWindow = 0
					if interlaced then
						repeat
							if yInsideWindow % 8 == 0 then
								yInsideWindow = if yInsideWindow < height then yInsideWindow + 8 else 4
							elseif yInsideWindow % 4 == 0 then
								yInsideWindow = if yInsideWindow < height then yInsideWindow + 8 else 2
							elseif yInsideWindow % 2 == 0 then
								yInsideWindow = if yInsideWindow < height then yInsideWindow + 4 else 1
							else
								yInsideWindow = yInsideWindow + 2
							end
						until yInsideWindow < height
					else
						yInsideWindow = yInsideWindow + 1
					end
				end
			else
				xInsideWindow, yInsideWindow = 0, 0
			end
			if colorIndex ~= loadedFrameTransparentColorIndex then
				loadedFrameMatrix[top + yInsideWindow + 1][left + xInsideWindow + 1] =
					assert(palette[colorIndex], "wrong file format")
			end
		end

		repeat
			-- all the codes (CLEARVOC+2)...(firstUndefinedCode-2) are defined completely
			-- the code (firstUndefinedCode-1) has defined only its first component
			local code = readCodeFromStream()
			if code == CLEARVOC then
				clearLZWVoc()
			elseif code ~= ENDOFSTREAM then
				assert(code < firstUndefinedCode, "wrong file format")
				local stackOfPixels = {}
				local pos = 1
				local firstPixel = code
				while firstPixel >= CLEARVOC do
					firstPixel, stackOfPixels[pos] = LZWVocPrefixCodes[firstPixel], LZWVocColorIndices[firstPixel]
					pos = pos + 1
				end
				stackOfPixels[pos] = firstPixel
				if needCompletion then
					needCompletion = false
					LZWVocColorIndices[firstUndefinedCode - 1] = firstPixel
					if code == firstUndefinedCode - 1 then
						stackOfPixels[1] = firstPixel
					end
				end
				-- send pixels for phrase "code" to result matrix
				for p = pos, 1, -1 do
					pixelFromStream(stackOfPixels[p])
				end
				if firstUndefinedCode < 0x1000 then
					-- create new code
					LZWVocPrefixCodes[firstUndefinedCode] = code
					needCompletion = true
					if firstUndefinedCode == nextPowerOfTwo then
						bitsInCode = bitsInCode + 1
						nextPowerOfTwo = 2 ^ bitsInCode
					end
					firstUndefinedCode = firstUndefinedCode + 1
				end
			end
		until code == ENDOFSTREAM

		assert(pixelsRemained == 0 and streamBitBuffer == 0, "wrong file format")
		local extraByte = readByteFromStream()
		assert(not extraByte or extraByte == 0 and not readByteFromStream(), "wrong file format")

		-- Modify the matrix backgroundMatrixAfterLoadedFrame
		if loadedFrameActionOnBackground == "combine" then
			backgroundMatrixAfterLoadedFrame = loadedFrameMatrix
		elseif loadedFrameActionOnBackground == "erase" then
			backgroundMatrixAfterLoadedFrame = loadedFrameMatrix

			backgroundRectangleToEraseLeft = left
			backgroundRectangleToEraseTop = top
			backgroundRectangleToEraseWidth = width
			backgroundRectangleToEraseHeight = height
		end
		loadedFrameNo = loadedFrameNo + 1
		return "OK"
	end

	local function callback21F9()
		local len, flags = readByte(), readByte()
		local delay = readU16()
		local transparent, terminator = readByte(), readByte()
		assert(len == 4 and terminator == 0, "wrong file format")
		loadedFrameDelay = delay * 10
		if flags % 2 == 1 then
			loadedFrameTransparentColorIndex = transparent
		end
		local method = (flags // 4) % 8
		if method == 2 then
			loadedFrameActionOnBackground = "erase"
		elseif method == 3 then
			loadedFrameActionOnBackground = "undo"
		end
	end

	local function loadNextFrame()
		-- returns true if next frame was loaded (or false if there is no next frame)
		if loadedFrameNo == 0 then
			backgroundMatrixAfterLoadedFrame = table.create(gifHeight)
			for y = 1, gifHeight do
				backgroundMatrixAfterLoadedFrame[y] = {}
			end

			backgroundRectangleToEraseLeft = 0
			backgroundRectangleToEraseTop = 0
			backgroundRectangleToEraseWidth = gifWidth
			backgroundRectangleToEraseHeight = gifHeight
			offset = firstFrameOffset
		end
		loadedFrameDelay = nil
		loadedFrameActionOnBackground = nil
		loadedFrameTransparentColorIndex = nil
		return processBlocks(callback2C, callback21F9) ~= "EOF"
	end

	assert(loadNextFrame(), "wrong file format")

	local gif = {
		Width = gifWidth,
		Height = gifHeight,
	}

	function gif.GetFileParameters()
		if not fileParameters then
			local savedOffset = offset
			processBlocks()
			offset = savedOffset
		end
		return fileParameters
	end

	function gif.ReadMatrix()
		return loadedFrameMatrix
	end

	function gif.GetImageNumber()
		return loadedFrameNo
	end

	function gif.GetFrameDelayInMs()
		return loadedFrameDelay
	end

	local loopingModes = { never = 0, always = 1, play = 2 }
	function gif.NextImage(loopingMode: ("never" | "always" | "play")?)
		-- switches to next image, returns true/false, false means failed to switch
		-- loopingMode = "never"/"always"/"play"
		local loopingModeNo = loopingModes[loopingMode or "never"]
		assert(loopingModeNo, "wrong looping mode")
		if loadNextFrame() then
			return true
		else
			if ({ true, fpLoopedAnimation })[loopingModeNo] then -- looping now
				loadedFrameNo = 0
				return loadNextFrame()
			else
				return false
			end
		end
	end

	return table.freeze(gif)
end

return openGif

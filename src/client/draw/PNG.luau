--!strict

---------------------------------------------------------------------------------------------
--[[
MIT License

Copyright (c) 2019 Max G. (CloneTrooper1019)

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
---------------------------------------------------------------------------------------------
-- [PNG Library]
--
-- A module for opening PNG files into a readable bitmap.
-- This implementation works with most PNG files.
--
---------------------------------------------------------------------------------------------

local band = bit32.band
local rshift = bit32.rshift

local function twosComplementOf(value: number, numBits: number): number
	if value >= (2 ^ (numBits - 1)) then
		return value - (2 ^ numBits)
	end

	return value
end

local decompress = require(script.Parent:WaitForChild("ZLIB")).DecompressZlib

local getBytesPerPixel = {
	[0] = 1,
	[3] = 1,
	[4] = 2,
	[2] = 3,
	[6] = 4,
}
--local function getBytesPerPixel(colorType)
--	if colorType == 0 or colorType == 3 then
--		return 1
--	elseif colorType == 4 then
--		return 2
--	elseif colorType == 2 then
--		return 3
--	elseif colorType == 6 then
--		return 4
--	else
--		return 0
--	end
--end

-- Vector3s represent r, g, b from 0-255
type file = {
	Width: number,
	Height: number,

	Alpha: number | Vector3 | nil,
	AlphaData: { number }?,

	ColorType: number,

	Bitmap: { { number } },
	BitDepth: number,
	BytesPerPixel: number,

	Palette: { Vector3 }?,
	NumChannels: number,

	Hash: number?,

	BackgroundColor: Vector3?,

	Chromaticity: {}?,
	Metadata: {},
	RenderIntent: number?,
	Gamma: number?,
	Methods: {
		Compression: number,
		Filtering: number,
		Interlace: number,
	}?,

	TimeStamp: {
		Year: number,
		Month: number,
		Day: number,

		Hour: number,
		Minute: number,
		Second: number,
	}?,
}

local PNG = {}

function PNG.parse(pngBuffer: string): file
	-- Create the reader.
	local readerLength = #pngBuffer
	local readerPosition = 1

	local function readPngBytes(count: number): ...number
		local from = readerPosition
		local len = math.min(from + count, readerLength)
		readerPosition = len
		return string.byte(pngBuffer, from, len)
	end

	local function readPngUInt16(): number
		local upper, lower = readPngBytes(2)
		return (upper * 256) + lower
	end

	local function readPngUInt32(): number
		local upper = readPngUInt16()
		local lower = readPngUInt16()

		return (upper * 65536) + lower
	end

	local function readPngInt32(): number
		local unsigned = readPngUInt32()
		return twosComplementOf(unsigned, 32)
	end

	local function readPngString(length: number)
		local from = readerPosition
		local nextPos = math.min(readerLength, from + length)

		local result = string.sub(pngBuffer, from, nextPos - 1)
		readerPosition = nextPos

		return result
	end

	-- Create the file object.
	local metadata = {}
	local ZlibStream = ""
	local width, height, bitDepth, colorType, hash, palette, methods, alpha: any, alphaData, timeStamp, renderIntent, gamma, chromaticity, backgroundColor

	-- Verify the file header.
	local header = readPngString(8)

	if header ~= "\137PNG\r\n\26\n" then
		error("PNG - Input data is not a PNG file.", 2)
	end

	while true do
		local length = readPngInt32()
		local chunkType = readPngString(4)

		local dataBuffer, dataLength, dataPosition, readDataByte, readDataUInt16, readDataUInt32, readDataInt32

		local crc

		if length > 0 then
			dataBuffer = readPngString(length)
			dataLength = #dataBuffer
			dataPosition = 1

			readDataByte = function()
				local byte = string.byte(dataBuffer, dataPosition, dataPosition)
				dataPosition += 1
				return byte
			end
			readDataUInt16 = function(): number
				local upper, lower = readDataByte(), readDataByte()
				return (upper * 256) + lower
			end
			readDataUInt32 = function(): number
				local upper = readDataUInt16()
				local lower = readDataUInt16()

				return (upper * 65536) + lower
			end
			readDataInt32 = function(): number
				local unsigned = readDataUInt32()
				return twosComplementOf(unsigned, 32)
			end

			crc = readPngUInt32()
		end

		if chunkType == "IDAT" then
			hash = bit32.bxor(hash or 0, crc)
			ZlibStream ..= dataBuffer
		elseif chunkType == "IEND" then
			break
		elseif chunkType == "tRNS" then
			local _bitDepth = (2 ^ bitDepth) - 1

			if colorType == 3 then
				local paletteLen = #palette
				alphaData = table.create(paletteLen)

				for i = 1, paletteLen do
					-- alpha
					alphaData[i] = readDataByte() or 255
				end
			elseif colorType == 0 then
				local grayAlpha = readDataUInt16()
				alpha = grayAlpha / _bitDepth
			elseif colorType == 2 then
				-- TODO: This seems incorrect...
				local r = readDataUInt16() / _bitDepth
				local g = readDataUInt16() / _bitDepth
				local b = readDataUInt16() / _bitDepth
				alpha = Vector3.new(r * 255, g * 255, b * 255)
			else
				error("PNG - Invalid tRNS chunk")
			end
		elseif chunkType == "tIME" then
			timeStamp = {
				Year = readDataUInt16(),
				Month = readDataByte(),
				Day = readDataByte(),

				Hour = readDataByte(),
				Minute = readDataByte(),
				Second = readDataByte(),
			}
		elseif chunkType == "tEXt" then
			local key, value = "", {}

			while true do
				if not (dataPosition > dataLength) then
					break
				end

				local char = string.byte(dataBuffer, dataPosition, dataPosition)
				dataPosition += 1

				if char == 0 then
					key = table.concat(value, "")
					table.clear(value)
				else
					table.insert(value, char)
				end
			end

			metadata[key] = table.concat(value, "")
		elseif chunkType == "sRGB" then
			renderIntent = readDataByte()
		elseif chunkType == "gAMA" then
			local value = readDataUInt32()
			gamma = value / 10e4
		elseif chunkType == "cHRM" then
			chromaticity = {}

			for _, color in { "White", "Red", "Green", "Blue" } do
				chromaticity[color] = {
					[1] = readDataUInt32() / 10e4,
					[2] = readDataUInt32() / 10e4,
				}
			end
		elseif chunkType == "bKGD" then
			local _bitDepth = (2 ^ bitDepth) - 1

			if colorType == 3 then
				local index = readDataByte()
				backgroundColor = palette[index]
			elseif colorType == 0 or colorType == 4 then
				local gray = readDataUInt16() / _bitDepth
				backgroundColor = Vector3.new(gray * 255, gray * 255, gray * 255)
			elseif colorType == 2 or colorType == 6 then
				local r = readDataUInt16() / _bitDepth
				local g = readDataUInt16() / _bitDepth
				local b = readDataUInt16() / _bitDepth
				backgroundColor = Vector3.new(r * 255, g * 255, b * 255)
			end
		elseif chunkType == "PLTE" then
			local paletteDataLen = dataLength - dataPosition + 1

			if paletteDataLen % 3 ~= 0 then
				error("PNG - Invalid PLTE chunk.")
			end

			palette = palette or table.create(paletteDataLen / 3)

			local paletteIndex = 0
			for i = 1, paletteDataLen, 3 do
				local r, g, b = string.byte(dataBuffer, i, i + 2)

				paletteIndex += 1
				palette[paletteIndex] = Vector3.new(r, g, b)
			end

			dataPosition = dataLength
		elseif chunkType == "IHDR" then
			width = readDataInt32()
			height = readDataInt32()

			bitDepth = readDataByte()

			colorType = readDataByte()

			methods = {
				Compression = readDataByte(),
				Filtering = readDataByte(),
				Interlace = readDataByte(),
			}
		else
			warn("No handler for", chunkType)
		end
	end

	local response = decompress(ZlibStream)

	local bitmap = table.create(height)

	local numChannels = getBytesPerPixel[colorType] or 0

	local bytesPerPixel = math.max(1, numChannels * (bitDepth / 8))

	-- Unfilter the buffer and
	-- load it into the bitmap.

	local index = 0
	for row = 1, height do
		index += 1
		local filterType = string.byte(response, index, index)

		local scanlineLen = width * bytesPerPixel

		local scanline = { string.byte(response, index + 1, index + scanlineLen) }

		index = index + scanlineLen

		if filterType == 0 then
			-- None

			bitmap[row] = scanline
		elseif filterType == 1 then
			local rowPixels = table.move(scanline, 1, bytesPerPixel, 1, table.create(bytesPerPixel))
			bitmap[row] = rowPixels

			-- Sub

			for i = bytesPerPixel + 1, scanlineLen do
				local x = scanline[i]
				local a = rowPixels[i - bytesPerPixel]
				rowPixels[i] = band(x + a, 0xFF)
			end
		elseif filterType == 2 then
			-- Up
			if row > 1 then
				local rowPixels = table.create(scanlineLen)
				bitmap[row] = rowPixels

				local upperRowPixels = bitmap[row - 1]

				for i = 1, scanlineLen do
					local x = scanline[i]
					local b = upperRowPixels[i]
					rowPixels[i] = band(x + b, 0xFF)
				end
			else
				-- None

				bitmap[row] = scanline
			end
		elseif filterType == 3 then
			local rowPixels = table.create(scanlineLen)
			bitmap[row] = rowPixels

			-- Average
			local upperRowPixels = bitmap[row - 1]

			if row > 1 then
				for i = 1, bytesPerPixel do
					local x = scanline[i]
					local b = upperRowPixels[i]

					b = rshift(b, 1)
					rowPixels[i] = band(x + b, 0xFF)
				end

				for i = bytesPerPixel + 1, scanlineLen do
					local x = scanline[i]
					local b = upperRowPixels[i]

					local a = rowPixels[i - bytesPerPixel]
					local ab = rshift(a + b, 1)

					rowPixels[i] = band(x + ab, 0xFF)
				end
			else
				-- Sub
				table.move(scanline, 1, bytesPerPixel, 1, rowPixels)

				for i = bytesPerPixel + 1, scanlineLen do
					local x = scanline[i]
					local b = upperRowPixels[i]

					b = rshift(b, 1)
					rowPixels[i] = band(x + b, 0xFF)
				end
			end
		elseif filterType == 4 then
			local rowPixels = table.create(scanlineLen)
			bitmap[row] = rowPixels

			-- Paeth
			if row > 1 then
				local pr

				local upperRowPixels = bitmap[row - 1]

				for i = 1, bytesPerPixel do
					local x = scanline[i]
					local b = upperRowPixels[i]
					rowPixels[i] = band(x + b, 0xFF)
				end

				for i = bytesPerPixel + 1, scanlineLen do
					local a = rowPixels[i - bytesPerPixel]
					local b = upperRowPixels[i]
					local c = upperRowPixels[i - bytesPerPixel]

					local x = scanline[i]
					local p = a + b - c

					local pa = math.abs(p - a)
					local pb = math.abs(p - b)
					local pc = math.abs(p - c)

					if pa <= pb and pa <= pc then
						pr = a
					elseif pb <= pc then
						pr = b
					else
						pr = c
					end

					rowPixels[i] = band(x + pr, 0xFF)
				end
			else
				-- Sub

				table.move(scanline, 1, bytesPerPixel, 1, rowPixels)

				for i = bytesPerPixel + 1, scanlineLen do
					local x = scanline[i]
					local a = rowPixels[i - bytesPerPixel]
					rowPixels[i] = band(x + a, 0xFF)
				end
			end
		end
	end

	return table.freeze({
		Width = width,
		Height = height,

		Alpha = alpha,
		AlphaData = alphaData,

		ColorType = colorType,

		Bitmap = bitmap,
		BitDepth = bitDepth,
		BytesPerPixel = bytesPerPixel,

		Palette = palette,
		NumChannels = numChannels,

		Hash = hash,

		BackgroundColor = backgroundColor,

		Chromaticity = chromaticity,
		Metadata = metadata,
		RenderIntent = renderIntent,
		Gamma = gamma,
		Methods = methods,

		TimeStamp = timeStamp,
	})
end

-- returns r, g, b, a in range of 0-255
function PNG.getPixel(file: file): (x: number, y: number) -> (number, number, number, number)
	local height = file.Height
	local width = file.Width

	local bytesPerPixel = file.BytesPerPixel
	local bitmap = file.Bitmap
	local colorType = file.ColorType

	local palette = file.Palette

	local alphaData = file.AlphaData

	if colorType == 0 then
		return function(x: number, y: number)
			if 0 > y then
				error("y is negative")
			end
			if 0 > x then
				error("x is negative")
			end

			if x % 1 ~= 0 then
				error("x must be an integer")
			end
			if y % 1 ~= 0 then
				error("x must be an integer")
			end

			if y > height then
				error("y out of range")
			end
			if x > width then
				error("x out of range")
			end

			local i0 = ((x - 1) * bytesPerPixel) + 1
			local i1 = i0 + bytesPerPixel

			local row = assert(bitmap[y])

			local gray = unpack(row, i0, i1)
			return gray * 255, gray * 255, gray * 255, 255
		end
	elseif colorType == 2 then
		return function(x: number, y: number)
			if 0 > y then
				error("y is negative")
			end
			if 0 > x then
				error("x is negative")
			end

			if x % 1 ~= 0 then
				error("x must be an integer")
			end
			if y % 1 ~= 0 then
				error("x must be an integer")
			end

			if y > height then
				error("y out of range")
			end
			if x > width then
				error("x out of range")
			end

			local i0 = ((x - 1) * bytesPerPixel) + 1
			local i1 = i0 + bytesPerPixel

			local row = assert(bitmap[y])

			local r, g, b = unpack(row, i0, i1)
			return r, g, b, 255
		end
	elseif colorType == 3 then
		return function(x: number, y: number)
			if 0 > y then
				error("y is negative")
			end
			if 0 > x then
				error("x is negative")
			end

			if x % 1 ~= 0 then
				error("x must be an integer")
			end
			if y % 1 ~= 0 then
				error("x must be an integer")
			end

			if y > height then
				error("y out of range")
			end
			if x > width then
				error("x out of range")
			end

			local i0 = ((x - 1) * bytesPerPixel) + 1
			local i1 = i0 + bytesPerPixel

			local row = assert(bitmap[y])

			local index = unpack(row, i0, i1)
			index = index + 1

			local r, g, b, alpha

			if palette then
				local color = palette[index]
				r, g, b = color.X, color.Y, color.Z
			end

			if alphaData then
				alpha = alphaData[index]
			end

			return r, g, b, alpha
		end
	elseif colorType == 4 then
		return function(x: number, y: number)
			if 0 > y then
				error("y is negative")
			end
			if 0 > x then
				error("x is negative")
			end

			if x % 1 ~= 0 then
				error("x must be an integer")
			end
			if y % 1 ~= 0 then
				error("x must be an integer")
			end

			if y > height then
				error("y out of range")
			end
			if x > width then
				error("x out of range")
			end

			local i0 = ((x - 1) * bytesPerPixel) + 1
			local i1 = i0 + bytesPerPixel

			local row = assert(bitmap[y])

			local gray, alpha = unpack(row, i0, i1)
			return gray * 255, gray * 255, gray * 255, alpha
		end
	elseif colorType == 6 then
		return function(x: number, y: number)
			if 0 > y then
				error("y is negative")
			end
			if 0 > x then
				error("x is negative")
			end

			if x % 1 ~= 0 then
				error("x must be an integer")
			end
			if y % 1 ~= 0 then
				error("x must be an integer")
			end

			if y > height then
				error("y out of range")
			end
			if x > width then
				error("x out of range")
			end

			local i0 = ((x - 1) * bytesPerPixel) + 1
			local i1 = i0 + bytesPerPixel

			local row = assert(bitmap[y])
			local r, g, b, a = unpack(row, i0, i1)
			return r, g, b, a
		end
	else
		error("Unknown color type")
	end
end

return PNG

--!strict

-- Settings
local useCache = false
local looped = false

local clock = os.clock

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local getDataRemote = ReplicatedStorage:WaitForChild("HttpGet")

local png = require(script:WaitForChild("PNG"))
local pngGetPixels = png.getPixel
local parsePng = png.parse

local gif = require(script:WaitForChild("GIF"))

-- Make controls guis

local controlsGui = Instance.new("ScreenGui")
controlsGui.Name = "Controls"
controlsGui.ResetOnSpawn = false
controlsGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local drawButton = Instance.new("TextButton")
drawButton.Name = "Draw"
drawButton.FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json")
drawButton.Text = "Draw"
drawButton.TextColor3 = Color3.fromRGB(255, 255, 255)
drawButton.TextScaled = true
drawButton.TextSize = 14
drawButton.TextStrokeTransparency = 0.3
drawButton.TextWrapped = true
drawButton.BackgroundColor3 = Color3.fromRGB(255, 85, 0)
drawButton.BorderSizePixel = 0
drawButton.Position = UDim2.fromScale(0.0238, 0.468)
drawButton.Size = UDim2.fromScale(0.108, 0.0626)
drawButton.Parent = controlsGui

local urlInput = Instance.new("TextBox")
urlInput.Name = "URLInput"
urlInput.ClearTextOnFocus = false
urlInput.FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json")
urlInput.Text = ""
urlInput.TextColor3 = Color3.fromRGB(255, 255, 255)
urlInput.TextSize = 18
urlInput.TextStrokeTransparency = 0.3
urlInput.TextWrapped = true
urlInput.BackgroundColor3 = Color3.fromRGB(245, 245, 245)
urlInput.BorderSizePixel = 0
urlInput.Position = UDim2.fromScale(0.0238, 0.345)
urlInput.Size = UDim2.fromScale(0.26, 0.1)

do local textLabel = Instance.new("TextLabel")
textLabel.Name = "TextLabel"
textLabel.FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json")
textLabel.Text = "URL"
textLabel.TextColor3 = Color3.fromRGB(235, 235, 235)
textLabel.TextScaled = true
textLabel.TextSize = 14
textLabel.TextWrapped = true
textLabel.Active = true
textLabel.BackgroundColor3 = Color3.fromRGB(85, 85, 85)
textLabel.BorderSizePixel = 0
textLabel.Position = UDim2.fromScale(0.0815, -0.52)
textLabel.Selectable = true
textLabel.Size = UDim2.fromScale(0.829, 0.514)
textLabel.Parent = urlInput end

urlInput.Parent = controlsGui

local hideButton = Instance.new("TextButton")
hideButton.Name = "Hide"
hideButton.FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json")
hideButton.Text = "Hide"
hideButton.TextColor3 = Color3.fromRGB(255, 255, 255)
hideButton.TextScaled = true
hideButton.TextSize = 14
hideButton.TextStrokeTransparency = 0.3
hideButton.TextWrapped = true
hideButton.BackgroundColor3 = Color3.fromRGB(0, 255, 127)
hideButton.BorderSizePixel = 0
hideButton.Position = UDim2.fromScale(0.172, 0.467)
hideButton.Size = UDim2.fromScale(0.108, 0.0626)
hideButton.Parent = controlsGui

local clearCacheButton = Instance.new("TextButton")
clearCacheButton.Name = "ClearCache"
clearCacheButton.FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json")
clearCacheButton.Text = "Clear Cache"
clearCacheButton.TextColor3 = Color3.fromRGB(255, 255, 255)
clearCacheButton.TextScaled = true
clearCacheButton.TextSize = 14
clearCacheButton.TextStrokeTransparency = 0.3
clearCacheButton.TextWrapped = true
clearCacheButton.BackgroundColor3 = Color3.fromRGB(170, 85, 255)
clearCacheButton.BorderSizePixel = 0
clearCacheButton.Position = UDim2.fromScale(0.0275, 0.753)
clearCacheButton.Size = UDim2.fromScale(0.108, 0.0626)
clearCacheButton.Parent = controlsGui

local useCacheButton = Instance.new("TextButton")
useCacheButton.Name = "UseCache"
useCacheButton.FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json")
useCacheButton.Text = "Use Cache"
useCacheButton.TextColor3 = Color3.fromRGB(255, 255, 255)
useCacheButton.TextScaled = true
useCacheButton.TextSize = 14
useCacheButton.TextStrokeTransparency = 0.3
useCacheButton.TextWrapped = true
useCacheButton.BackgroundColor3 = Color3.fromRGB(85, 170, 255)
useCacheButton.BorderSizePixel = 0
useCacheButton.Position = UDim2.fromScale(0.171, 0.753)
useCacheButton.Size = UDim2.fromScale(0.108, 0.0626)
useCacheButton.Parent = controlsGui

local loopedButton = Instance.new("TextButton")
loopedButton.Name = "Looped"
loopedButton.FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json")
loopedButton.Text = "Looped"
loopedButton.TextColor3 = Color3.fromRGB(255, 255, 255)
loopedButton.TextScaled = true
loopedButton.TextSize = 14
loopedButton.TextStrokeTransparency = 0.3
loopedButton.TextWrapped = true
loopedButton.BackgroundColor3 = Color3.fromRGB(255, 0, 127)
loopedButton.BorderSizePixel = 0
loopedButton.Position = UDim2.fromScale(0.0272, 0.853)
loopedButton.Size = UDim2.fromScale(0.108, 0.0626)
loopedButton.Parent = controlsGui

controlsGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

-- Is it currently working to display frames?
local isDrawing = false

-- Holds the frames
local screenGui = Instance.new("ScreenGui")
screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local function makeImageLabel(widthInPixels: number, heightInPixels: number)
	local imageLabel = Instance.new("ImageLabel")
	imageLabel.Size = UDim2.fromScale(0.6, 0.6)

	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = widthInPixels / heightInPixels
	ratio.Parent = imageLabel

	imageLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	imageLabel.BackgroundTransparency = 0.5
	imageLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	imageLabel.Position = UDim2.fromScale(0.5, 0.5)
	imageLabel.Visible = false

	imageLabel.Parent = screenGui

	return imageLabel
end

local function makeImage(pixels: { number }, xResolution: number, yResolution: number)
	local drawingEditable = Instance.new("EditableImage")

	drawingEditable.Size = Vector2.new(xResolution, yResolution)
	drawingEditable:WritePixels(Vector2.zero, Vector2.new(xResolution, yResolution), pixels)

	return drawingEditable
end

local activeImage: ImageLabel
local function swapCurrentImageFor(image: ImageLabel)
	local oldImage = activeImage
	activeImage = image
	activeImage.Visible = true
	if oldImage then
		oldImage.Visible = false
	end
end

local httpCache = {}
local function httpGet(url)
	if useCache then
		local cached = httpCache[url]
		if cached then
			return unpack(cached)
		end

		local result = { getDataRemote:InvokeServer(url, useCache) }
		httpCache[url] = result
		clearCacheButton.Visible = true

		return unpack(result)
	else
		return getDataRemote:InvokeServer(url, useCache)
	end
end

local function drawFromPngData(data)
	local startTime = clock()

	-- Parse the png data
	local parsed = parsePng(data)
	local width, height = parsed.Width, parsed.Height

	local getPixel = pngGetPixels(parsed)
	print("Decoded in", clock() - startTime, "seconds")

	-- Turn the data into an array of RGBA
	local pixels = table.create(width * height * 4)
	local i = 0
	for y = 1, height do
		for x = 1, width do
			local r, g, b, a = getPixel(x, y)
			pixels[i + 1] = r / 255
			pixels[i + 2] = g / 255
			pixels[i + 3] = b / 255
			pixels[i + 4] = a / 255
			i += 4
		end
	end

	local editable = makeImage(pixels, width, height)
	local image = makeImageLabel(editable.Size.X, editable.Size.Y)
	editable.Parent = image
	swapCurrentImageFor(image)
	isDrawing = false
end

local function parseGifFrames(data): { { image: ImageLabel, delayInMiliseconds: number } }?
	local startTime = clock()

	local parsed = gif(data)
	local width, height = parsed.Width, parsed.Height

	local pixels = table.create(width * height * 4, 0)

	local number = 0
	local frames = {}
	while true do
		local i = 0
		for y, row in parsed.ReadMatrix() do
			for x, hex in row do
				if hex == -1 then -- Transparent color
				else
					local b = hex % 256
					local color = (hex - b) / 256
					local g = color % 256
					local r = (color - g) / 256
					pixels[i + 1] = r / 255
					pixels[i + 2] = g / 255
					pixels[i + 3] = b / 255
					pixels[i + 4] = 1
				end
				i += 4
			end
		end

		local editable = makeImage(pixels, width, height)
		local image = makeImageLabel(width, height)
		editable.Parent = image
		table.insert(frames, {
			image = image,
			delayInMiliseconds = assert(parsed.GetFrameDelayInMs(), "missing frame delay"),
		})

		if not parsed.NextImage() then
			-- Finished all frames
			print("Decoded GIF in", clock() - startTime, "seconds")
			return frames
		end

		if not isDrawing then
			-- Cancelled
			return nil
		end

		table.clear(pixels)
		number += 1
		print("Decoding GIF frame number", number)
		if number % 10 == 0 then
			task.wait()
		end
	end
end

local function drawFromGifData(data)
	local frames = parseGifFrames(data)
	if not frames then
		return
	end

	for _, frame in frames do
		swapCurrentImageFor(frame.image)
		task.wait(assert(frame.delayInMiliseconds) / 1000)

		if not isDrawing then
			-- Cancelled
			return
		end
	end
end

drawButton.Activated:Connect(function()
	if isDrawing then
		isDrawing = false
		return
	end
	isDrawing = true
	screenGui.Enabled = true

	xpcall(function()
		repeat
			local startTime = clock()

			local previousData

			local success, data = httpGet(urlInput.Text)

			if not success then
				error(data)
			end
			print("Fetched in", clock() - startTime, "seconds")

			if string.sub(data, 1, 8) == "\137PNG\r\n\26\n" then
				if data ~= previousData then
					previousData = data
					drawFromPngData(data)
				end
			else
				previousData = data
				drawFromGifData(data)
			end
		until not looped or not isDrawing
	end, warn)
end)

hideButton.Activated:Connect(function()
	screenGui.Enabled = false
	isDrawing = false
end)

useCacheButton.Text = `Cache HTTP: {useCache}`
useCacheButton.Activated:Connect(function()
	useCache = not useCache
	if not useCache then
		table.clear(httpCache)
	end
	clearCacheButton.Visible = useCache
	useCacheButton.Text = `Cache HTTP: {useCache}`
end)

loopedButton.Text = `Looped: {looped}`
loopedButton.Activated:Connect(function()
	looped = not looped
	loopedButton.Text = `Looped: {looped}`
end)

clearCacheButton.Visible = useCache
clearCacheButton.Activated:Connect(function()
	table.clear(httpCache)
end)

local function getNumberInput(input: TextBox, min: number, max: number, set: (number) -> (), get: () -> number)
	input.FocusLost:Connect(function()
		local text = input.Text
		local number = tonumber(text)

		if number then
			local new = math.clamp(number, min, max)
			set(new)

			local new = tostring(new)
			if new ~= text then
				input.Text = new
			end
		else
			input.Text = tostring(get())
		end
	end)
end

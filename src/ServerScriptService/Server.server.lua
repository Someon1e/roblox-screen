--!strict

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local httpGet = Instance.new("RemoteFunction")
httpGet.Name = "HttpGet"
httpGet.Parent = ReplicatedStorage

local cache = {}
httpGet.OnServerInvoke = function(player, url, useCache)
	if useCache then
		local cached = cache[url]
		if cached then
			return cached[1], cached[2]
		end
	end

	local success, data = pcall(HttpService.GetAsync, HttpService, url)
	cache[url] = { success, data }

	return success, data
end

--todo
-- clear recent players button
-- clear all bans button
-- disable recent player list (should also clear list)
-- manual edit buttons for name/account id?

_G.SearchableBanList = SearchableBanList or {}
SearchableBanList.mod_path = ModPath
SearchableBanList.settings_path = SavePath .. "searchable_ban_list_settings.json"
SearchableBanList.recents_path = SavePath .. "searchable_ban_list_recentplayers.json"
SearchableBanList.menu_path = SearchableBanList.mod_path .. "menu/options.json"
SearchableBanList.default_localization_path = SearchableBanList.mod_path .. "localization/english.json"
SearchableBanList.FBI_PROFILES_URL = tweak_data.gui.fbi_files_webpage .. "suspect/$id64"
SearchableBanList.STEAM_PROFILES_URL = "https://steamcommunity.com/profiles/$id64"
SearchableBanList.MAX_ENTRIES_PER_PAGE = 10
SearchableBanList.MAX_RECENT_PLAYERS_CACHE = 50
SearchableBanList.default_options = { --these options are saved between sessions
	case_sensitive = false,
	search_id64s = false,
	show_id64s = true,
	require_match_all = false,
	substitute_lookalike_characters = true,
	record_additional_ban_data = false, -- if true, stores timestamp of ban (not implemented)
	link_behavior = 1, -- 1: open in overlay; 2: copy link to clipboard
	log_results = false
}
SearchableBanList.search_options = table.deep_map_copy(SearchableBanList.default_options)


SearchableBanList._lookalike_characters = {
	["%$"] = "S", -- the dollar sign character "$" has special meaning in patterns
	["%^"] = "%%%^", --same with caret character "^"
	["%."] = "%%%." --same with period character "."
}

SearchableBanList._recent_players = {
				--[[
	{
		name
		id = string
		platform = string "EPIC" || string "STEAM"
		account_id = string?
	}
				--]]
}

function SearchableBanList:OutputResultsToLog(...)
	if self.search_options.log_results then
		return self:_OutputResultsToLog(...)
	end
end
function SearchableBanList:_OutputResultsToLog(...)
	log(...)
end

function SearchableBanList:OpenURL(url)
	if self.search_options.link_behavior == 1 then
		managers.network.account:overlay_activate("url", url)
	else
		Application:set_clipboard(url)
		QuickMenu:new(managers.localization:text("sbl_dialog_success"),managers.localization:text("sbl_dialog_urlcopy_success_desc",{URL=url}),
			{
				text = managers.localization:text("sbl_dialog_ok"),
				is_focused_button = true,
				is_cancel_button = true,
				callback = cb_back
			},
			true
		)
	end
end

function SearchableBanList:SubstituteSimilarCharacters(str)
	for k,v in pairs(self._lookalike_characters) do 
		str = string.gsub(str,k,v)
	end
	return str
end

function SearchableBanList:DoSearchInList(raw_search_text,user_list)
	local search_text = raw_search_text
	local case_sensitive = self.search_options.case_sensitive
	local require_match_all = self.search_options.require_match_all
	local substitute_lookalike_characters = self.search_options.substitute_lookalike_characters
	local search_id64s = self.search_options.search_id64s
	if substitute_lookalike_characters then 
		search_text = self:SubstituteSimilarCharacters(search_text)
	end
	if not case_sensitive then 
		search_text = utf8.to_lower(search_text)
	end
	search_text = string.gsub(search_text,"%%","%%%%")
	search_text = string.gsub(search_text,"\n","")
	local search_keywords = string.split(search_text," ")
	
	local search_results = {}
	
	for i,banned_user in ipairs(user_list) do 
		--do ordered search to preserve sorting by time
		local id64 = banned_user.identifier
		local raw_username = banned_user.name
		local username = raw_username
		if substitute_lookalike_characters then 
			username = self:SubstituteSimilarCharacters(username)
		end
		
		if not case_sensitive then 
			username = utf8.to_lower(username)
		end
		local is_match = false
		local matched_all = true
		for _,_search_text in pairs(search_keywords) do
			if string.find(username,_search_text) or (search_id64s and string.find(id64,_search_text)) then 
				if not require_match_all then 
					is_match = true
					break
				end
			elseif require_match_all then 
				matched_all = false
				break
			end
		end
		if require_match_all and matched_all then 
			is_match = true
		end
		
		if is_match then 
			table.insert(search_results,#search_results + 1,banned_user)
		end
		
	end
	
	return search_results
end

function SearchableBanList:ShowMissingQKIPrompt()
	QuickMenu:new(managers.localization:text("sbl_prompt_missing_qki_title"),managers.localization:text("sbl_prompt_missing_qki_desc"),{
		{
			text = managers.localization:text("menu_ok"),
			is_focused_button = true,
			is_cancel_button = true,
			callback = nil
		}
	},true)
end

function SearchableBanList:OnSearchEntryCallback(search_string,user_list,populate_options_clbk)
	local results = self:DoSearchInList(search_string,user_list)
	if #results > 0 then
	
		self:OutputResultsToLog("============")
		self:OutputResultsToLog("| Ban List: |")
		for _,user in ipairs(results) do 
			local s = "|\t" .. user.name .. "\t" .. user.identifier
			if user.timestamp then
				s = s .. "\t" .. os.date("%x",user.timestamp)
			end
			self:OutputResultsToLog(s)
		end
		self:OutputResultsToLog("============")
		--sbl_dialog_banlist_title
		--sbl_dialog_banlist_desc
		self:ShowEntries(results,1,"sbl_dialog_banlist_title","sbl_dialog_banlist_desc",populate_options_clbk)
	else
		self:OutputResultsToLog("No results found for:" .. tostring(search_string))
		QuickMenu:new("No results","No bans found by search string: " .. tostring(search_string),{
			{
				text = managers.localization:text("menu_ok"),
				is_focused_button = true,
				is_cancel_button = true,
				callback = nil
			}
		},true)
	end
end

Hooks:Add("LocalizationManagerPostInit", "LocalizationManagerPostInit_SBL", function( loc )
	if not BeardLib then 
		--local loc = managers.localization --debug reasons
		loc:load_localization_file( SearchableBanList.default_localization_path )
	end
end)

Hooks:Add( "MenuManagerInitialize", "MenuManagerInitialize_SBL", function(menu_manager)
	MenuCallbackHandler.callback_sbl_is_case_sensitive = function(self,item)
		SearchableBanList.search_options.case_sensitive = item:value() == "on"
		SearchableBanList:SaveSettings()
	end
	MenuCallbackHandler.callback_sbl_require_match_all = function(self,item)
		SearchableBanList.search_options.require_match_all = item:value() == "on"
		SearchableBanList:SaveSettings()
	end
	MenuCallbackHandler.callback_sbl_link_behavior = function(self,item)
		SearchableBanList.search_options.link_behavior = tonumber(item:value())
		SearchableBanList:SaveSettings()
	end
	MenuCallbackHandler.callback_sbl_substitute_lookalike_characters = function(self,item)
		SearchableBanList.search_options.substitute_lookalike_characters = item:value() == "on"
		SearchableBanList:SaveSettings()
	end
	MenuCallbackHandler.callback_sbl_search_id64s = function(self,item)
		SearchableBanList.search_options.search_id64s = item:value() == "on"
		SearchableBanList:SaveSettings()
	end
	MenuCallbackHandler.callback_sbl_show_id64s = function(self,item)
		SearchableBanList.search_options.show_id64s = item:value() == "on"
		SearchableBanList:SaveSettings()
	end

	MenuCallbackHandler.callback_sbl_log_results = function(self,item)
		SearchableBanList.search_options.log_results = item:value() == "on"
		SearchableBanList:SaveSettings()
	end

	MenuCallbackHandler.callback_sbl_record_additional_ban_data = function(self,item)
		SearchableBanList.search_options.record_additional_ban_data = item:value() == "on"
		SearchableBanList:SaveSettings()
	end

	MenuCallbackHandler.callback_sbl_show_all_bans = function(self)
		if not managers.ban_list then 
			SearchableBanList:OutputResultsToLog("[Searchable Ban List] Error 1: No ban list manager")
			return
		end
		
		local results = managers.ban_list._global.banned --table.deep_map_copy(managers.ban_list._global.banned)
		--[[
		-- generate test data
		local results = {}
		for i=1,51 do 
			local s = "" 
			for j = 1,1+math.random(25) do 
				s = s .. string.char(65 + math.random(122-65))
			end
			results[i] = {
				name = s,
				identifier = math.random(12345679)
			}
		end
		--]]
		SearchableBanList:ShowEntries(results,1,"sbl_dialog_banlist_title","sbl_dialog_banlist_desc",callback(SearchableBanList,SearchableBanList,"PopulatePlayerListOptions"))
	end
	
	MenuCallbackHandler.callback_sbl_show_all_recents = function(self)
		local recent_players = SearchableBanList:GetRecentPlayers()
		SearchableBanList:ShowEntries(recent_players,1,"sbl_dialog_recentlist_title","sbl_dialog_recentlist_desc",callback(SearchableBanList,SearchableBanList,"PopulatePlayerListOptions"))
	end
	
	MenuCallbackHandler.callback_sbl_paste_ban = function(self)
		if not managers.ban_list then 
			SearchableBanList:OutputResultsToLog("[Searchable Ban List] Error 3: No ban list manager")
			return
		end
		local clipboard = Application:get_clipboard()
		if clipboard then
			local identifier = string.gsub(clipboard,"%W","") --remove non-alphanumeric characters
		
			QuickMenu:new(managers.localization:text("dialog_sure_to_ban_title"),managers.localization:text("dialog_sure_to_ban_body",{USER=identifier}),{ -- use vanilla ban localization
					{
						text = managers.localization:text("dialog_yes"),
						callback = function() 
							SearchableBanList:BanPlayerById(identifier)
						end
					},
					{
						text = managers.localization:text("dialog_no"),
						is_focused_button = true,
						is_cancel_button = true,
						callback = cb_back
					}
				},
				true
			)
		else
			QuickMenu:new(managers.localization:text("sbl_dialog_invalid_ban_clipboard_title"),managers.localization:text("sbl_dialog_invalid_ban_clipboard_desc"),{
				{
					text = managers.localization:text("dialog_ok"),
					is_cancel_button = true
				}
			},true)
		end
	end
	MenuCallbackHandler.callback_sbl_manual_add_ban = function(self)
		if not _G.QuickKeyboardInput then 
			SearchableBanList:ShowMissingQKIPrompt()
			return
		end
		if not managers.ban_list then 
			SearchableBanList:OutputResultsToLog("[Searchable Ban List] Error 2: No ban list manager")
			return
		end
		_G.QuickKeyboardInput:new(managers.localization:text("sbl_dialog_add_manual_ban_title"),managers.localization:text("sbl_dialog_add_manual_ban_desc"),"",callback(SearchableBanList,SearchableBanList,"BanPlayerById"),nil,true)
	end
	
	MenuCallbackHandler.callback_sbl_init_search_banlist = function(self)
		if not _G.QuickKeyboardInput then 
			SearchableBanList:ShowMissingQKIPrompt()
			return
		end
		if not managers.ban_list then
			-- sbl_dialog_failure
			return
		end
		_G.QuickKeyboardInput:new(managers.localization:text("sbl_prompt_search_banlist_title"),managers.localization:text("sbl_prompt_search_banlist_desc"),"",function(search_string) SearchableBanList:OnSearchEntryCallback(search_string,managers.ban_list._global.banned,callback(SearchableBanList,SearchableBanList,"PopulatePlayerListOptions")) end,nil,true)
	end
	
	MenuCallbackHandler.callback_sbl_init_search_recentlist = function(self)
		if not _G.QuickKeyboardInput then 
			SearchableBanList:ShowMissingQKIPrompt()
			return
		end
		
		_G.QuickKeyboardInput:new(managers.localization:text("sbl_prompt_search_recentlist_title"),managers.localization:text("sbl_prompt_search_recentlist_desc"),"",function(search_string) SearchableBanList:OnSearchEntryCallback(search_string,SearchableBanList:GetRecentPlayers(),callback(SearchableBanList,SearchableBanList,"PopulatePlayerListOptions")) end,nil,true)
	end
	
	
	SearchableBanList:LoadSettings()
	SearchableBanList:LoadRecentPlayers()
	MenuHelper:LoadFromJsonFile(SearchableBanList.menu_path, SearchableBanList, SearchableBanList.search_options)
	
end)

function SearchableBanList:PopulatePlayerListOptions(options,player_data,back_clbk)
	local button_title
	
	if self.search_options.show_id64s then
		button_title = string.format("%s : %s",player_data.name,player_data.account_id or player_data.identifier)
	else
		button_title = player_data.name
	end
	
	table.insert(options,#options+1,{
		text = button_title,
		callback = function()
			self:ShowPlayerEntry(player_data,back_clbk)
		end
	})
	
	return options
end

function SearchableBanList:ShowEntries(page_data,page_num,dialog_title,dialog_desc,populate_player_options_clbk)
	local back_clbk = function()
		self:ShowEntries(page_data,page_num,dialog_title,dialog_desc,populate_player_options_clbk)
	end
	
	page_num = page_num or 1
	local total_num_entries = #page_data
	local total_num_pages = math.ceil(total_num_entries / self.MAX_ENTRIES_PER_PAGE)
	local num_entries_this_page = total_num_entries - (self.MAX_ENTRIES_PER_PAGE * (page_num - 1))
	
	local page_start = self.MAX_ENTRIES_PER_PAGE * (page_num - 1)
	local page_finish = page_start + math.min(total_num_entries - page_start,self.MAX_ENTRIES_PER_PAGE)
	
	local options = {}
	local cancel_button = { -- "ok"/"cancel"/"back" button (end transaction)
		text = managers.localization:text("sbl_dialog_ok"),
		is_focused_button = true,
		is_cancel_button = true,
		callback = nil
	}
	
	for i=page_start,page_finish-1,1 do 
		local banned_data = page_data[i + 1]
		if banned_data then
			populate_player_options_clbk(options,banned_data,back_clbk)
		else
			-- no more banned users to add
			break
		end
	end
	
	if page_num > 1 then
		-- "page back" button
		table.insert(options,#options+1,{
			text = managers.localization:text("sbl_dialog_pageprev"),
			callback = function() self:ShowEntries(page_data,page_num - 1,dialog_title,dialog_desc,populate_player_options_clbk) end
		})
	end
	if page_num < total_num_pages then
		-- "page fwd" button
		table.insert(options,#options+1,{
			text = managers.localization:text("sbl_dialog_pagenext"),
			callback = function() self:ShowEntries(page_data,page_num + 1,dialog_title,dialog_desc,populate_player_options_clbk) end
		})
	end
	
	-- insert cancel button
	table.insert(options,#options+1,cancel_button)
	
	QuickMenu:new(managers.localization:text(dialog_title,{CURRENT=page_num,TOTAL=total_num_pages}),managers.localization:text(dialog_desc,{MIN=page_start + 1,MAX=page_finish,TOTAL=total_num_entries}),options,true)
end

function SearchableBanList:ShowPlayerEntry(player_data,cb_back)
	local name = player_data.name
	local identifier = player_data.identifier
	local account_id = player_data.account_id
	local is_steam 
	if player_data.platform then
		is_steam = player_data.platform == "STEAM"
		account_id = account_id or identifier
	elseif string.find(identifier,"^7656") then
		is_steam = true
		
		-- assume this is a steam account if identifier appears to match id64 format
		account_id = account_id or identifier
	end
	
	local cancel_button = { -- "ok"/"cancel"/"back" button (end transaction)
		text = managers.localization:text("sbl_dialog_ok"),
		is_focused_button = true,
		is_cancel_button = true,
		callback = cb_back
	}
	
	local options = {}
	
	if is_steam then
		table.insert(options,#options+1,
			{
				text = managers.localization:text("sbl_dialog_button_open_profile_steam"),
				callback = function() self:OpenURL(string.gsub(self.STEAM_PROFILES_URL,"$id64",account_id)); self:ShowPlayerEntry(player_data,cb_back) end
			}
		)
		table.insert(options,#options+1,
			{
				text = managers.localization:text("sbl_dialog_button_open_profile_fbi"),
				callback = function() self:OpenURL(string.gsub(self.FBI_PROFILES_URL,"$id64",account_id)); self:ShowPlayerEntry(player_data,cb_back) end
			}
		)
	end
	
	if managers.ban_list:banned(identifier) then
		local function show_success_dialog(name,success)
			if success then 
				QuickMenu:new(managers.localization:text("sbl_dialog_success"),managers.localization:text("sbl_dialog_unban_success_desc",self:GetPlayerEntryMacro(player_data)),{
					cancel_button
				},true)
			else
				QuickMenu:new(managers.localization:text("sbl_dialog_failure"),managers.localization:text("sbl_dialog_unban_failure_desc",self:GetPlayerEntryMacro(player_data)),{
					cancel_button
				},true)
			end
		end
		table.insert(options,#options+1,{
			text = managers.localization:text("sbl_dialog_button_unban_user"),
			callback = function()
				QuickMenu:new(managers.localization:text("dialog_sure_to_unban_title"),managers.localization:text("dialog_sure_to_unban_body",self:GetPlayerEntryMacro(player_data)),{
					{
						text = managers.localization:text("dialog_yes"),
						callback = function() 
							self:OutputResultsToLog("[Searchable Banlist] Unbanning: " .. identifier)
							managers.ban_list:unban(identifier)
							
							show_success_dialog(name,true) -- can't technically detect success actually
						end
					},
					{
						text = managers.localization:text("dialog_no"),
						is_focused_button = true,
						is_cancel_button = true,
						callback = cb_back
					}
				},true)
			end
		})
	else
		table.insert(options,#options+1,
			{
				text = managers.localization:text("sbl_dialog_button_ban_user"),
				callback = function()
					QuickMenu:new(managers.localization:text("dialog_sure_to_ban_title"),managers.localization:text("dialog_sure_to_ban_body",self:GetPlayerEntryMacro(player_data)),{ -- use vanilla ban localization
						{
							text = managers.localization:text("dialog_yes"),
							callback = function() 
								SearchableBanList:BanPlayerByIdName(identifier,name)
							end
						},
						{
							text = managers.localization:text("dialog_no"),
							is_focused_button = true,
							is_cancel_button = true,
							callback = cb_back
						}
					},true)
				end
			}
		)
	end
	
	table.insert(options,#options+1,cancel_button)
	
	local desc = self:MakePlayerEntryString(player_data)
	QuickMenu:new(managers.localization:text("sbl_dialog_banlist_entry_title"),desc,options,true)
end

function SearchableBanList:MakePlayerEntryString(player_data)
	return managers.localization:text("sbl_dialog_banlist_entry_desc",self:GetPlayerEntryMacro(player_data))
end

function SearchableBanList:GetPlayerEntryMacro(player_data)
	return {
		NAME = player_data.name,
		USER = player_data.name, -- for vanilla dialog localization
		ID = player_data.identifier,
		ACCOUNT_ID = player_data.account_id or managers.localization:text("sbl_dialog_banlist_entry_no_data"),
		PLATFORM = player_data.platform or managers.localization:text("sbl_dialog_banlist_entry_no_data"), -- don't bother localizing platform name, just use internal id
		TIMESTAMP_LABEL = managers.ban_list:banned(player_data.identifier) and managers.localization:text("sbl_dialog_banlist_sub_timestamp_label_banned") or managers.localization:text("sbl_dialog_banlist_sub_timestamp_label_recent"),
		DATE = player_data.timestamp and os.date("%x",player_data.timestamp) or managers.localization:text("sbl_dialog_banlist_entry_no_data")
	}
end

-- manually ban steam id or epic id;
	-- automatically find this player's data in recent players, if it exists,
	-- and fill in banned data with it
	-- use this if you only have the identifier and name (eg from clipboard)
function SearchableBanList:BanPlayerByIdName(identifier,name)
	local success,err_code = self:_BanPlayerByIdName(identifier,name)
	if success then
		for _,player_data in pairs(self._recent_players) do 
			if player_data.identifier == identifier or player_data.account_id == identifier then
				
				self:_BanPlayerData(table.deep_map_copy(player_data))
				return success,err_code
			end
		end
	end
	
	if string.find(identifier,"^7656") then
		-- assume steam account if identifier appears to match id64 scheme
		self:_BanPlayerData({
			identifier = identifier,
			platform = "STEAM",
			name = Steam:username(identifier) -- most likely will return "[unknown]"
		})
	end
	
	return success,err_code
end

-- execute actual ban
function SearchableBanList:_BanPlayerByIdName(identifier,name)
	if managers.ban_list:banned(identifier) then
		return false,1
	else
		self:OutputResultsToLog("[Searchable Banlist] Banning: " .. tostring(identifier) .. " / " .. tostring(name))
		managers.ban_list:ban(identifier,name)
		return true
	end
end

-- ban player, then apply extra data; use this if you have a full set of data already
function SearchableBanList:BanPlayerData(player_data)
	self:_BanPlayerByIdName(player_data.identifier,player_data.name)
	self:_BanPlayerData(player_data)
end

-- apply extra data here
function SearchableBanList:_BanPlayerData(player_data)
	local identifier = player_data.identifier
	
	for _,data in pairs(managers.ban_list._global.banned) do 
		if data.identifier == identifier then
			-- overwritee the non-standard values (ie the ones the game did not set, but were set by the mod instead)
			-- with the ones supplied from the caller; assume the caller is working with less stale info
			data.name = player_data.name or data.name
			if self.search_options.record_additional_ban_data then
				data.account_id = player_data.account_id or nil
				data.platform = player_data.platform
				data.timestamp = os.time() or nil
			end
			break
		end
	end
	
end

-- ban player from only one piece of info (identifier)
-- find or fill in the rest of the data from other sources as needed
function SearchableBanList:BanPlayerById(identifier)
	local name = "[unknown]"
	local account_id = identifier
	local platform
		
	-- ban them here to trigger the banlistmanager hook (for mod compatibility),
	-- then go and edit the entry
	local success,err_code = self:BanPlayerByIdName(identifier,name)
	if success then
		for _,data in pairs(managers.ban_list._global.banned) do 
			if data.identifier == identifier then
				QuickMenu:new(managers.localization:text("sbl_manual_ban_success_title"),managers.localization:text("sbl_manual_ban_success_desc",
						{
							PLAYER_STRING = SearchableBanList:MakePlayerEntryString(data)
						}
					),
					{
						text = managers.localization:text("dialog_ok"),
						is_cancel_button = true
					},
					true
				)
				break
			end
		end
	else
		local err_title = managers.localization:text("sbl_dialog_failure",{code=err_code})
		local err_msg = ""
		if err_code == 1 then
			err_msg = managers.localization:text("sbl_dialog_player_already_banned",{id=identifier})
		end
		QuickMenu:new(err_title,err_msg,{
			{
				text = managers.localization:text("dialog_ok"),
				is_cancel_button = true
			}
		},true)
		self:OutputResultsToLog(string.format("[Searchable Ban List] %s: %s",err_title,err_msg))
	end
	
	return success
end

function SearchableBanList:RegisterRecentPlayer(data)
	self:_RegisterRecentPlayer(data)
	self:SaveRecentPlayers()
end

function SearchableBanList:_RegisterRecentPlayer(data)
	if data.identifier then
		for i=#self._recent_players,1,-1 do 
			local v = self._recent_players[i]
			if v.identifier == data.identifier then
				-- clear any duplicates of the new recent player
				table.remove(self._recent_players,i)
			end
		end
	end
	local num_recents = #self._recent_players
	local MAX = self.MAX_RECENT_PLAYERS_CACHE
	if num_recents >= MAX then
		-- check for overflow
		for i=num_recents-MAX,1,-1 do 
			-- remove oldest from list
			table.remove(self._recent_players,i)
		end
	end
	table.insert(self._recent_players,1,data)
	data.timestamp = os.time()
end

function SearchableBanList:ClearRecentPlayers() -- functional but not used
	for k,_ in pairs(self._recent_players) do 
		self._recent_players[k] = nil
	end
end

function SearchableBanList:GetRecentPlayers()
	return self._recent_players
end

function SearchableBanList:LoadSettings()
	local file = io.open(self.settings_path, "r")
	if file then
		for k, v in pairs(json.decode(file:read("*all"))) do
			self.search_options[k] = v
		end
	end
end

function SearchableBanList:SaveSettings()
	local file = io.open(self.settings_path,"w+")
	if file then
		file:write(json.encode(self.search_options))
		file:close()
	end
end


function SearchableBanList:LoadRecentPlayers()
	local file = io.open(self.recents_path, "r")
	if file then
		local data = json.decode(file:read("*all"))
		if not data then return end
		for i, v in ipairs(data) do
			self._recent_players[i] = v
		end
	end
end

function SearchableBanList:SaveRecentPlayers()
	local file = io.open(self.recents_path,"w+")
	if file then
		file:write(json.encode(self._recent_players))
		file:close()
	end
end


--[[



search ->
aggregate results ->
paginate x results ->
<- individual profile ->
unban


--]]




function SearchableBanList:ShowSearchResults(results,search_string) -- deprecated; not interactive
	local options = {
		{
			text = managers.localization:text("menu_ok"),
			is_focused_button = true,
			is_cancel_button = true,
			callback = nil
		}
	}
	
	local show_id64s = self.search_options.show_id64s
	local log_results = self.search_options.log_results
	
	if log_results then 
		self:OutputResultsToLog("<Searchable Ban List: Search results for \"" .. tostring(search_string) .. "\">")
	end
	if not results or #results < 1 then 
		QuickMenu:new(managers.localization:text("sbl_prompt_search_failure_title"),managers.localization:text("sbl_prompt_search_failure_desc"),options,true)
		
		self:OutputResultsToLog(managers.localization:text("sbl_prompt_search_failure_desc"))
		self:OutputResultsToLog("<Search results ended>")
		return
	end
	
	local banlist = {}
	for _,i in ipairs(results) do 
		local banned_user = managers.ban_list._global.banned[i]
		if banned_user then 
			local name_entry = banned_user.name or "[SEARCHABLE BANLIST ERROR]"
			if show_id64s then 
				name_entry = name_entry .. " (" .. tostring(banned_user.identifier) .. ")"
			end
			if log_results then 
				self:OutputResultsToLog(name_entry)
			end
			
			table.insert(banlist,#banlist+1,name_entry)
		end
	end
	if log_results then 
		self:OutputResultsToLog("<Search results ended>")
	end
	local banlist_string = table.concat(banlist,"\n")
	
	QuickMenu:new(string.gsub(managers.localization:text("sbl_prompt_search_success_title"),"$SEARCHSTRING",search_string),banlist_string,options,true)
end




-------------
--generate replacement table for accented letters and letterlike characters for easier searching
--ever so slightly messier code but cleaner to look at this way

SearchableBanList._lookalike_characters_sets = {
	--i pretty much stopped at U+017E. CBA
	--tbh i'm not sure why i did this. most of these won't even show up since they're not in the font
	[""] = "skull", --pd2 specific font glyph
	["æ"] = "ae",
	["Æ"] = "AE",
	["ªàáâãäåͣₐ"] = "a",
	["4ÀÁÂÃÄĀāĂăĄąÅ₳"] = "A",
	["þ"] = "b",
	["8Þß₿"] = "B",
	["ÇĆĈĊČ©₡₵"] = "C",
	["çćĉċč¢ͨↄ"] = "c",
	["℅"] = "c/o",
	["₠"] = "CE",
	["₢"] = "Cr",
	["ĎĐÐ₯"] = "D",
	["ďđͩ₫"] = "d",
	["3ĒĔĖĘĚÈÉÊË£Ξ€∑"] = "E",
	["ēĕėęěèéêëͤ℮ₔₑ"] = "e",
	["ⅎ"] = "F",
	["6ĜĞĠĢ₲"] = "G",
	["9ĝğġģ"] = "g",
	["ĤĦ"] = "H",
	["ĥħͪ"] = "h",
	["1ĨĪĬĮİÌÍÎÏ"] = "I",
	["ĩīĭįıìíîïͥ"] = "i",
	["Ĳ"] = "IJ",
	["ĳ"] = "ij",
	["Ĵ"] = "J",
	["ĵ"] ="j",
	["Ķĸ₭"] = "K",
	["ķ"] = "k",
	["ĹĻĽĿŁ¬"] = "L",
	["ĺļľŀł"] = "l",
	["₶"] = "lt",
	["ͫ₥"] = "m",
	["ŃŅŇŊÑ₦∏"] = "N",
	["№"] = "No",
	["ńņňŉŋñⁿ"] = "n",
	["ŌŎŐÒÓÔÕÖØð"] = "O",
	["ōŏőòóôõöøͦₒ"] = "o",
	["Œ"] = "OE",
	["œ"] = "oe",
	["₱₽℗₰"] = "P",
	["₧"] = "Pts",
	["ŔŖŘ®"] = "R",
	["ŕŗřͬ"] = "r",
	["₨"] = "Rs",
	["5ŚŜŞŠ§₴₷"] = "S",
	["śŝşš"] = "s",
	["7ŢŤŦ₮₸"] = "T",
	["ţťŧ+ͭ"] = "t",
	["™"] = "TM",
	["ŨŪŬŮŰŲÙÚÛÜ"] = "U",
	["ũūŭůűųùúûüµͧ"] = "u",
	["ͮ"] = "v",
	["Ŵ₩"] = "W",
	["ŵ"] = "w",
	["×ͯₓ"] = "x",
	["ŶŸÝ¥"] = "Y",
	["ŷÿý"] = "y",
	["2ŹŻŽ"] = "Z",
	["źżž"] = "z",
	["¹"] = "1",
	["²"] = "2",
	["³"] = "3",
	["⁰"] = "0",
	["⁴"] = "4",
	["⁵"] = "5",
	["⁶"] = "6",
	["⁷"] = "7",
	["⁸"] = "8",
	["⁹"] = "9",
	["‰"] = "0/00",
	["⅓"] = "1/3",
	["⅔"] = "2/3",
	["⅛"] = "1/8",
	["⅜"] = "3/8",
	["⅝"] = "5/8",
	["⅞"] = "7/8",
	["¼"] = "1/4",
	["½"] = "1/2",
	["¾"] = "3/4",
	["⅍"] = "A/S",
	["­"] = "-",
	["¦"] = ":",
	["¿"] = "?"
}

for charset,replacement in pairs(SearchableBanList._lookalike_characters_sets) do 
	local s = utf8.characters(charset)
	for _,character in pairs(s) do 
		SearchableBanList._lookalike_characters[character] = replacement
	end
end



--unused
--[[
local PlayerProfile = blt_class()
SearchableBanList.PlayerProfile = PlayerProfile

function PlayerProfile:init(data)
	self._name = data.name
	self._identifier = data.identifier --primary id; string; can be (hex, egs account id?) or (steam id64)
	self._account_type_str = data.account_type_str -- string "STEAM" or "EPIC"
	self._account_id = data.account_id -- if steam, is string steam id64
	self._timestamp = data.timestamp -- epoch timestamp; if banned, this represents the time/date banned; if not banned, this represents the time last played with this user
end

function PlayerProfile:name()
	return self._name
end

function PlayerProfile:identifier()
	return self._identifier
end

function PlayerProfile:account_type_str()
	return self._account_type_str
end

function PlayerProfile:account_id()
	return self._account_id
end

function PlayerProfile:timestamp()
	return self._timestamp
end

function PlayerProfile:get_player_string()
	return managers.localization:text("sbl_dialog_banlist_entry_desc",self:get_macro())
end

function PlayerProfile:get_macro()
	return {
		NAME = self._name,
		USER = self._name, -- for vanilla dialog localization
		ID = self._identifier,
		ACCOUNT_ID = self._account_id or managers.localization:text("sbl_dialog_banlist_entry_no_data"),
		PLATFORM = self._account_type_str or managers.localization:text("sbl_dialog_banlist_entry_no_data"), -- don't bother localizing platform name, just use internal id
		TIMESTAMP_LABEL = self:is_banned() and managers.localization:text("sbl_dialog_banlist_sub_timestamp_label_banned") or managers.localization:text("sbl_dialog_banlist_sub_timestamp_label_recent"),
		DATE = self._timestamp and os.date("%x",self._timestamp) or managers.localization:text("sbl_dialog_banlist_entry_no_data")
	}
end

function PlayerProfile:is_banned()
	return managers.ban_list and managers.ban_list:banned(self._identifier)
end

-- duplicates data to a new table that can directly be saved to the ban list
function PlayerProfile:to_table()
	return {
		name = self:name(),
		identifier = self:identifier(),
		platform = self:account_type_str(),
		account_id = self:account_id(),
		timestamp = self:timestamp()
	}
end

--]]
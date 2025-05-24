_G.SearchableBanList = SearchableBanList or {}
SearchableBanList.mod_path = ModPath
SearchableBanList.settings_path = SavePath .. "searchable_ban_list_settings.json"
SearchableBanList.menu_path = SearchableBanList.mod_path .. "menu/options.json"
SearchableBanList.default_localization_path = SearchableBanList.mod_path .. "localization/english.json"
SearchableBanList.FBI_PROFILES_URL = tweak_data.gui.fbi_files_webpage .. "/suspect/$id64"
SearchableBanList.STEAM_PROFILES_URL = "https://steamcommunity.com/profiles/$id64"
SearchableBanList.MAX_ENTRIES_PER_PAGE = 10
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

function SearchableBanList:DoSearchInList(raw_search_text)
	if managers.ban_list then 
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
		
		for i,banned_user in ipairs(managers.ban_list._global.banned) do 
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
	else
		self:OutputResultsToLog("ERROR: SearchableBanList: managers.ban_list is not initialized")
		return
	end
	
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

function SearchableBanList:OnSearchEntryCallback(search_string)
	local results = self:DoSearchInList(search_string)
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
		
		self:ShowEntries(results,1)
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
			log("[Searchable Ban List] Error 1: No ban list manager")
			return
		end
		
		local results = table.deep_map_copy(managers.ban_list._global.banned)
		--[[
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
		SearchableBanList:ShowEntries(results,1)
	end

	MenuCallbackHandler.callback_sbl_init_search = function(self)
		if not _G.QuickKeyboardInput then 
			SearchableBanList:ShowMissingQKIPrompt()
			return
		end
		_G.QuickKeyboardInput:new(managers.localization:text("sbl_prompt_search_start_title"),managers.localization:text("sbl_prompt_search_start_desc"),"",callback(SearchableBanList,SearchableBanList,"OnSearchEntryCallback"),nil,true)
	end
	
	MenuCallbackHandler.callback_sbl_manual_add_ban = function(self)
		if not managers.ban_list then 
			log("[Searchable Ban List] Error 2: No ban list manager")
			return
		end
		
		
		if not _G.QuickKeyboardInput then 
			SearchableBanList:ShowMissingQKIPrompt()
			return
		end
		
		local function clbk_identifier_entered(id)
			
			if not id or id == "" then
				return
			end
			
			local str_id = tostring(id)
			
			local name
			if _G.Steam then
				name = Steam:username(str_id)
				-- this fetch will probably only succeed if you have recently played with this player,
				-- or if the player is already on your friends list;
				-- otherwise it will return "[unknown]"
			end
			
			if not (name and name ~= "[unknown]") then
				name = "[" .. str_id .. "]"
			end 
			
			local success,err_code = SearchableBanList:BanPlayerById(id,name)
			if success then
				QuickMenu:new(managers.localization:text("sbl_manual_ban_success_title"),managers.localization:text("sbl_manual_ban_success_desc",{id=id,name=name}),nil,true)
			else
				local err_title = managers.localization:text("sbl_dialog_failure",{code=err_code})
				local err_msg = ""
				if err_code == 1 then
					err_msg = managers.localization:text("sbl_dialog_player_already_banned",{id=str_id})
				end
				QuickMenu:new(err_title,err_msg,nil,true)
				log(string.format("[Searchable Ban List] %s: %s",err_title,err_msg))
				return
			end
			
			
		end
		
		
		
		_G.QuickKeyboardInput:new(managers.localization:text("sbl_dialog_add_manual_ban_title"),managers.localization:text("sbl_dialog_add_manual_ban_desc"),"",clbk_identifier_entered,nil,true)
	end
	
	
	SearchableBanList:LoadSettings()
	MenuHelper:LoadFromJsonFile(SearchableBanList.menu_path, SearchableBanList, SearchableBanList.search_options)
	
end)

function SearchableBanList:ShowEntries(page_data,page_num)
	page_num = page_num or 1
	local total_num_entries = #page_data
	local total_num_pages = math.ceil(total_num_entries / self.MAX_ENTRIES_PER_PAGE)
	local num_entries_this_page = total_num_entries - (self.MAX_ENTRIES_PER_PAGE * (page_num - 1))
	
	local page_start = self.MAX_ENTRIES_PER_PAGE * (page_num - 1)
	local page_finish = page_start + math.min(total_num_entries - page_start,self.MAX_ENTRIES_PER_PAGE)
	
	if total_num_entries == 0 then
		-- assume this check is handled elsewhere
		--return
	end
	local options = {}
	local cancel_button = { -- "ok"/"cancel"/"back" button (end transaction)
		text = managers.localization:text("sbl_dialog_ok"),
		is_focused_button = true,
		is_cancel_button = true,
		callback = nil
	}
	
	local function insert_user_callback(banned_data)
		local button_title
		
		if self.search_options.show_id64s then
			button_title = string.format("%s : %s",banned_data.name,banned_data.identifier)
		else
			button_title = banned_data.name
		end
		
		table.insert(options,#options+1,{
			text = button_title,
			callback = function() self:ShowBannedEntry(banned_data,function() self:ShowEntries(page_data,page_num) end) end
		})
	end
	
	for i=page_start,page_finish-1,1 do 
		local banned_data = page_data[i + 1]
		if banned_data then
			insert_user_callback(banned_data)
		else
			-- no more banned users to add
			break
		end
	end
	
	if page_num > 1 then
		-- "page back" button
		table.insert(options,#options+1,{
			text = managers.localization:text("sbl_dialog_pageprev"),
			callback = function() self:ShowEntries(page_data,page_num - 1) end
		})
	end
	if page_num < total_num_pages then
		-- "page fwd" button
		table.insert(options,#options+1,{
			text = managers.localization:text("sbl_dialog_pagenext"),
			callback = function() self:ShowEntries(page_data,page_num + 1) end
		})
	end
	
	-- insert cancel button
	table.insert(options,#options+1,cancel_button)
	
	QuickMenu:new(managers.localization:text("sbl_dialog_banlist_title",{CURRENT=page_num,TOTAL=total_num_pages}),managers.localization:text("sbl_dialog_banlist_desc",{MIN=page_start + 1,MAX=page_finish,TOTAL=total_num_entries}),options,true)
end

function SearchableBanList:ShowBannedEntry(data,cb_back)
	local name = data.name
	local identifier = data.identifier
	
	local cancel_button = { -- "ok"/"cancel"/"back" button (end transaction)
		text = managers.localization:text("sbl_dialog_ok"),
		is_focused_button = true,
		is_cancel_button = true,
		callback = cb_back
	}
	
	local function show_unbanned_dialog(name,success)
		if success then 
			QuickMenu:new(managers.localization:text("sbl_dialog_success"),managers.localization:text("sbl_dialog_unban_success_desc",{NAME=name}),{
				cancel_button
			},true)
		else
			QuickMenu:new(managers.localization:text("sbl_dialog_failure"),managers.localization:text("sbl_dialog_unban_failure_desc",{NAME=name}),{
				cancel_button
			},true)
		end
	end

	local options = {
		{
			text = managers.localization:text("sbl_dialog_button_open_profile_steam"),
			callback = function() self:OpenURL(string.gsub(self.STEAM_PROFILES_URL,"$id64",identifier)); self:ShowBannedEntry(data,cb_back) end
		},
		{
			text = managers.localization:text("sbl_dialog_button_open_profile_fbi"),
			callback = function() self:OpenURL(string.gsub(self.FBI_PROFILES_URL,"$id64",identifier)); self:ShowBannedEntry(data,cb_back) end
		},
		{
			text = managers.localization:text("sbl_dialog_button_unban_user"),
			callback = function()
				QuickMenu:new(managers.localization:text("dialog_sure_to_unban_title"),managers.localization:text("dialog_sure_to_unban_body",{USER=name}),{
					{
						text = managers.localization:text("dialog_yes"),
						callback = function() 
							managers.ban_list:unban(identifier)
							
							show_unbanned_dialog(name,true) -- can't detect success actually
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
		},
		cancel_button
	}
	
	local desc = managers.localization:text("sbl_dialog_banlist_entry_desc",{
		NAME = name,
		ID = identifier,
		DATE = data.timestamp and os.date("%x",data.timestamp) or  managers.localization:text("sbl_dialog_banlist_entry_no_data")
	})
	QuickMenu:new(managers.localization:text("sbl_dialog_banlist_entry_title"),desc,options,true)
end

function SearchableBanList:BanPlayerById(identifier,name)
	local str_id = tostring(identifier)
	if managers.ban_list:banned(identifier) then
		return false,1
	else
		managers.ban_list:ban(identifier,name)
		return true
	end
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

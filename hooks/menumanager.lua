_G.SearchableBanList = SearchableBanList or {}
SearchableBanList.mod_path = ModPath
SearchableBanList.menu_path = SearchableBanList.mod_path .. "menu/options.json"
SearchableBanList.default_localization_path = SearchableBanList.mod_path .. "localization/english.json"
SearchableBanList.default_options = { --these options are not saved between sessions
	case_sensitive = false,
	search_id64s = false,
	show_id64s = true,
	require_match_all = false,
	substitute_lookalike_characters = true,
	log_results = false
}
SearchableBanList.search_options = table.deep_map_copy(SearchableBanList.default_options)

SearchableBanList._lookalike_characters = {
	["%$"] = "S", -- the dollar sign character "$" has special meaning in patterns
	["%^"] = "%%%^", --same with caret character "^"
	["%."] = "%%%." --same with period character "."
}

function SearchableBanList:OutputResultsToLog(...)
	log(...)
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
				table.insert(search_results,#search_results + 1,i)
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

function SearchableBanList:ShowSearchResults(results,search_string)
	local ok_button = {
		text = managers.localization:text("menu_ok"),
		is_focused_button = true,
		is_cancel_button = true,
		callback = nil
	}
	
	local show_id64s = self.search_options.show_id64s
	local log_results = self.search_options.log_results
	
	if log_results then 
		self:OutputResultsToLog("<Searchable Ban List: Search results for \"" .. tostring(search_string) .. "\">")
	end
	if not results or #results < 1 then 
		QuickMenu:new(managers.localization:text("sbl_prompt_search_failure_title"),managers.localization:text("sbl_prompt_search_failure_desc"),{
			ok_button
		},true)
		
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
	
	QuickMenu:new(string.gsub(managers.localization:text("sbl_prompt_search_success_title"),"$SEARCHSTRING",search_string),banlist_string,{
		ok_button
	},true)
end

function SearchableBanList:OnSearchEntryCallback(search_string)
	local results = self:DoSearchInList(search_string)
	self:ShowSearchResults(results,search_string)
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
	end
	MenuCallbackHandler.callback_sbl_require_match_all = function(self,item)
		SearchableBanList.search_options.require_match_all = item:value() == "on"
	end
	MenuCallbackHandler.callback_sbl_substitute_lookalike_characters = function(self,item)
		SearchableBanList.search_options.substitute_lookalike_characters = item:value() == "on"
	end
	MenuCallbackHandler.callback_sbl_search_id64s = function(self,item)
		SearchableBanList.search_options.search_id64s = item:value() == "on"
	end
	MenuCallbackHandler.callback_sbl_show_id64s = function(self,item)
		SearchableBanList.search_options.show_id64s = item:value() == "on"
	end

	MenuCallbackHandler.callback_sbl_log_results = function(self,item)
		SearchableBanList.search_options.log_results = item:value() == "on"
	end

	MenuCallbackHandler.callback_sbl_show_all_bans = function(self)
		if not managers.ban_list then 
			return
		end
		
		local results = {}
		for i=1,#managers.ban_list._global.banned do 
			results[i] = i
		end
		SearchableBanList:ShowSearchResults(results,"")
	end

	MenuCallbackHandler.callback_sbl_init_search = function(self)
		if not _G.QuickKeyboardInput then 
			SearchableBanList:ShowMissingQKIPrompt()
			return
		end
		_G.QuickKeyboardInput:new(managers.localization:text("sbl_prompt_search_start_title"),managers.localization:text("sbl_prompt_search_start_desc"),"",callback(SearchableBanList,SearchableBanList,"OnSearchEntryCallback"),nil,true)
	end
	
	MenuHelper:LoadFromJsonFile(SearchableBanList.menu_path, SearchableBanList, SearchableBanList.search_options)
	
end)


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

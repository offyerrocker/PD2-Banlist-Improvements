Hooks:PostHook(BanListManager,"ban","onplayerbanned_SBL",function(self, identifier, name)
	if SearchableBanList.search_options.record_additional_ban_data then
		for i,banned in pairs(self._global.banned) do 
			if banned.identifier == identifier then 
				banned.timestamp = os.time()
			end
		end
	end
end)
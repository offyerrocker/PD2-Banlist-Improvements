Hooks:PostHook(ClientNetworkSession,"on_peer_synched","sbl_client_peersync",function(self, peer_id, ...)
	local peer = self._peers[peer_id]
	if peer then
		SearchableBanList:RegisterRecentPlayer({
			name = peer:name(),
			--was_peer_id = peer:id(),
			identifier = peer:user_id(),
			platform = peer:account_type_str(),
			account_id = peer:account_id()
		})
	end
end)
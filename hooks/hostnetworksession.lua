Hooks:PostHook(HostNetworkSession,"on_peer_sync_complete","sbl_host_peersync",function(self, peer, peer_id)
	SearchableBanList:RegisterRecentPlayer({
		name = peer:name(),
		--was_peer_id = peer:id(),
		identifier = peer:user_id(),
		platform = peer:account_type_str(),
		account_id = peer:account_id()
	})
end)
#!/usr/bin/env bats
load helpers
load backend_lib

setup() { setup_root; topo_up; }
teardown() { teardown_root; }

@test "nft: manual ban: monitor passes, block drops, unban restores, counters move" { t_manual_block nft; }
@test "iptables: manual ban: monitor passes, block drops, unban restores, counters move" { t_manual_block iptables; }

@test "nft: allowlist beats a broader ban" { t_allow_wins nft; }
@test "iptables: allowlist beats a broader ban" { t_allow_wins iptables; }

@test "nft: inbound traffic from a banned peer is dropped" { t_inbound_blocked nft; }
@test "iptables: inbound traffic from a banned peer is dropped" { t_inbound_blocked iptables; }

@test "nft: loopback is never touched" { t_loopback_untouched nft; }
@test "iptables: loopback is never touched" { t_loopback_untouched iptables; }

@test "nft: ban TTL expires and the file is pruned" { t_ttl_expires nft; }
@test "iptables: ban TTL expires and the file is pruned" { t_ttl_expires iptables; }

@test "nft: ban with TTL survives a rebuild" { t_ttl_survives_apply nft; }
@test "iptables: ban with TTL survives a rebuild" { t_ttl_survives_apply iptables; }

@test "nft: list: monitor passes, block drops, removal restores" { t_list_block nft; }
@test "iptables: list: monitor passes, block drops, removal restores" { t_list_block iptables; }

@test "nft: list: empty, shrunk and vanished sources keep the old set" { t_list_atomic nft; }
@test "iptables: list: empty, shrunk and vanished sources keep the old set" { t_list_atomic iptables; }

@test "nft: list: overlapping and duplicate networks load" { t_list_overlap nft; }
@test "iptables: list: overlapping and duplicate networks load" { t_list_overlap iptables; }

@test "nft: flow: blocks by full tuple, not by host" { t_flow_tuple nft; }
@test "iptables: flow: blocks by full tuple, not by host" { t_flow_tuple iptables; }

@test "nft: dht: all / except / only port modes" { t_dht_modes nft; }
@test "iptables: dht: all / except / only port modes" { t_dht_modes iptables; }

@test "nft: dht: host names resolved, private and unresolvable dropped" { t_dht_hostnames nft; }
@test "iptables: dht: host names resolved, private and unresolvable dropped" { t_dht_hostnames iptables; }

@test "nft: dht: empty resolution keeps the old set" { t_dht_empty_keeps nft; }
@test "iptables: dht: empty resolution keeps the old set" { t_dht_empty_keeps iptables; }

@test "nft: ipv6 ban" { t_ipv6_block nft; }
@test "iptables: ipv6 ban" { t_ipv6_block iptables; }

@test "nft: guard restores wiped rules" { t_guard_restores nft; }
@test "iptables: guard restores wiped rules" { t_guard_restores iptables; }

@test "nft: removal touches only bb objects and apply brings it back" { t_remove_only_ours nft; }
@test "iptables: removal touches only bb objects and apply brings it back" { t_remove_only_ours iptables; }

@test "nft: foreign ACCEPT at the top of raw cannot shield blocked traffic" { t_coexist_foreign_accept nft; }
@test "iptables: foreign ACCEPT at the top of raw cannot shield blocked traffic" { t_coexist_foreign_accept iptables; }

@test "nft: block --confirm arms a rollback timer; confirm and rollback work" { t_mode_confirm nft; }
@test "iptables: block --confirm arms a rollback timer; confirm and rollback work" { t_mode_confirm iptables; }

@test "nft: block --confirm without systemd-run refuses" { t_mode_confirm_needs_timer nft; }
@test "iptables: block --confirm without systemd-run refuses" { t_mode_confirm_needs_timer iptables; }

@test "nft: a failing apply keeps the running protection" { t_bad_apply_keeps_state nft; }
@test "iptables: a failing apply keeps the running protection" { t_bad_apply_keeps_state iptables; }

@test "iptables: guard puts a displaced jump back in first place" { t_guard_reorders; }
@test "nft: changed hook_priority recreates the base chains" { t_prio_change; }

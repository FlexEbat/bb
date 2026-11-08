# bb message catalog: English (default and fallback).
# printf-style placeholders; keep the same count and order in every language.
MSG[label_warning]="warning"
MSG[label_error]="error"
MSG[version]="bb %s"

MSG[err_apply_failed]="could not apply the rules; the previous state was restored"
MSG[err_bad_entry]="'%s' is not a valid IP address or network (accepted prefixes: /8-/32 for IPv4, /16-/128 for IPv6)"
MSG[err_bad_listname]="invalid list name '%s' (use a-z, 0-9, '_' and '-', up to 32 characters; 'dht' is reserved)"
MSG[err_bad_sha]="sha256 must be 64 hexadecimal characters"
MSG[err_bad_source]="the source must be an https:// URL or the path of a readable file (no spaces or quotes)"
MSG[err_bad_ttl]="invalid TTL '%s' (examples: 90s, 30m, 12h, 7d, 2w)"
MSG[err_cfg_invalid]="invalid value for %s: '%s'"
MSG[err_fw_init]="could not create firewall objects: %s"
MSG[err_https_only]="only https:// URLs are accepted for lists"
MSG[err_lang_invalid]="unsupported language '%s' (use en or ru)"
MSG[err_lock]="another bb command is running (lock wait timed out)"
MSG[err_mkdir]="cannot create directory %s"
MSG[err_need_root]="this command requires root"
MSG[err_no_list]="no such list: %s"
MSG[err_no_systemd_run]="systemd-run is required to arm the automatic rollback; mode not changed"
MSG[err_not_allowed]="%s is not in the allowlist"
MSG[err_not_banned]="%s is not in the manual ban list"
MSG[err_not_configured]="bb is not configured yet (no backend selected)"
MSG[err_rollback_arm]="could not arm the rollback timer; mode not changed"
MSG[err_rules_syntax]="the generated rules failed the syntax check; nothing was changed"
MSG[err_set_load]="could not load set %s"
MSG[err_tools_missing]="required tools are missing:%s"
MSG[err_unknown_cmd]="unknown command '%s'"
MSG[err_unknown_opt]="unknown option '%s'"
MSG[err_usage]="wrong usage; try: bb %s --help"
MSG[err_write]="cannot write %s"

MSG[warn_ban_allowed]="%s is in the allowlist, so it will never be blocked"
MSG[warn_cfg_line]="bb.conf line %s is not KEY='value'; ignored"
MSG[warn_cfg_value]="bb.conf: invalid value for %s (line %s); using the default"
MSG[warn_dht_empty]="no DHT node could be resolved; the existing set was kept"
MSG[warn_dht_line]="skipping invalid DHT node entry: %s"
MSG[warn_dht_shrunk]="DHT node list shrank sharply (%s -> %s entries); the existing set was kept"
MSG[warn_list_bad_desc]="list %s has a damaged description; skipped"
MSG[warn_list_empty]="list %s has no valid entries; the existing set was kept"
MSG[warn_list_fetch]="could not download list %s; the existing set was kept"
MSG[warn_list_sha]="list %s does not match its sha256; the existing set was kept"
MSG[warn_list_shrunk]="list %s shrank sharply (%s -> %s entries); the existing set was kept"
MSG[warn_list_too_big]="list %s exceeds the size limit; the existing set was kept"
MSG[warn_set_op]="could not update the live set for %s; it will be loaded on the next 'bb apply'"

MSG[apply_done]="Rules applied. Backend: %s, mode: %s."
MSG[guard_restored]="Rules were missing or displaced and have been restored."
MSG[config_written]="Configuration written. Backend: %s."
MSG[note_not_applied]="Rules are not active yet; the change will be loaded by 'bb apply'."
MSG[ban_done]="Banned: %s"
MSG[unban_done]="Unbanned: %s"
MSG[allow_done]="Allowed: %s"
MSG[allow_removed]="Removed from the allowlist: %s"

MSG[mode_current]="Current mode: %s"
MSG[mode_changed]="Mode changed to %s."
MSG[mode_confirm_hint]="It will revert to monitor in %s s unless confirmed. Run 'bb mode confirm' to keep it."
MSG[mode_confirm_prompt]="Keep block mode? [y/N]"
MSG[mode_confirmed]="Block mode confirmed."
MSG[mode_nothing_pending]="Nothing is waiting for confirmation."
MSG[mode_rolled_back]="Reverted to monitor mode."

MSG[lang_current]="Interface language: %s"
MSG[lang_set]="Interface language set to %s."

MSG[status_title]="bb %s"
MSG[status_backend]="Backend: %s"
MSG[status_mode]="Mode: %s"
MSG[status_lang]="Language: %s"
MSG[status_rules_present]="Rules: active"
MSG[status_rules_absent]="Rules: NOT active (run 'bb apply')"
MSG[status_sets]="Sets (entries):"
MSG[status_set_line]="  %-10s %s"
MSG[status_counters]="Counters:"
MSG[status_counter_line]="  %-8s packets %s, bytes %s"

MSG[list_none]="No lists configured. Add one with: bb list add NAME URL"
MSG[list_line]="%-16s %-5s entries: %-8s %s"
MSG[list_line_dht]="dht              nodes entries: %s"
MSG[list_added]="List %s added. Run 'bb list update' to download it."
MSG[list_removed]="List %s removed."
MSG[list_updated]="List %s updated: %s entries."
MSG[dht_updated]="DHT nodes updated: %s entries."

MSG[help_main]="bb - lightweight blocker for BitTorrent, DHT and blocklists

Usage: bb COMMAND [options]       (add --help to any command)

  install / uninstall         set bb up (wizard) or remove everything it created
  apply                       rebuild the rules from the configuration
  status                      backend, mode, set sizes, counters
  mode monitor|block          switch mode (block --confirm N reverts if not confirmed)
  ban IP|NET [--ttl 7d]       manual ban        unban IP|NET   remove a ban
  allow IP|NET [--rm]         never block this address
  list [add|update|rm]        external blocklists and DHT nodes
  notify setup|test|status    Telegram / Matrix notifications
  integrate [auto|docker|...] Docker, k3s/k8s, ufw, firewalld   doctor   diagnostics
  show flows                  flows added by traffic inspection
  log [-f]                    bb events and kernel messages from the journal
  lang [en|ru]                show or change the interface language

Global option: --lang en|ru"
MSG[help_apply]="Usage: bb apply

Rebuilds all sets and rules from the configuration. Safe to run at any time."
MSG[help_guard]="Usage: bb guard

Restores the rules if they disappeared or lost their first position. Used by the guard timer."
MSG[help_status]="Usage: bb status [--json]

Shows the backend, the mode, the size of every set and the drop counters. --json prints the same
as one JSON document with stable keys and untranslated values (needs jq)."
MSG[help_mode]="Usage: bb mode [monitor|block|confirm] [--confirm [SECONDS]]

monitor logs and counts without dropping; block drops. With --confirm the mode
reverts to monitor unless you run 'bb mode confirm' in time (default 60 s)."
MSG[help_ban]="Usage: bb ban IP|NET [--ttl DURATION]

Blocks an address or network. DURATION: 90s, 30m, 12h, 7d, 2w. Without --ttl the ban is permanent."
MSG[help_unban]="Usage: bb unban IP|NET

Removes a manual ban."
MSG[help_allow]="Usage: bb allow IP|NET [--rm]

Exempts an address or network from blocking. --rm removes the exemption."
MSG[help_lang]="Usage: bb lang [en|ru]

Shows or changes the interface language."
MSG[help_list]="Usage: bb list [add NAME URL|FILE [--sha256 HEX] | update [NAME|dht] | rm NAME]

Without arguments shows the configured lists. Only https:// sources are accepted."

MSG[err_check_failed]="the self-check failed:"
MSG[err_install_failed]="installation failed; the rules were not changed"
MSG[err_need_yes]="this is not a terminal: pass --yes to confirm"
MSG[err_no_systemd]="systemd is required (use --force to continue without units)"
MSG[err_os_unsupported]="unsupported distribution (ID=%s). Supported: Debian/Ubuntu (apt) and RHEL/Fedora (dnf). Needed: %s. Use --force to skip this check."
MSG[err_pkg_install]="package installation failed; nothing was changed"
MSG[err_pkg_still_missing]="the backend tools are still missing after installation: %s"
MSG[err_ports_required]="--ports-mode only|except requires --ports"
MSG[err_units]="could not install the systemd units"

MSG[warn_check_dht_empty]="the DHT set is empty (DNS not working?); run 'bb list update dht' later"
MSG[warn_mode_reverted]="block mode was never confirmed; reverted to monitor"
MSG[warn_units_start]="could not start some units; check 'systemctl status bb-firewall'"
MSG[inst_units_skipped]="systemd not available: units were not installed"

MSG[chk_rules_inactive]="the rules are not active"
MSG[chk_rules_missing]="no %s rules found"
MSG[chk_set_missing]="set %s is missing"
MSG[chk_stale_set]="stale temporary set %s"
MSG[chk_unit_disabled]="unit %s is not enabled"

MSG[inst_plan_pkgs]="Backend: %s. Will install: %s"
MSG[inst_plan_none]="Backend: %s. Nothing to install."
MSG[inst_pkg_installing]="Installing packages: %s"
MSG[inst_prompt_iface]="Network interface to watch [%s]:"
MSG[inst_prompt_mode]="Port mode: all, only or except [%s]:"
MSG[inst_prompt_ports]="Ports, e.g. 6881-6889,51413 [%s]:"
MSG[inst_backup]="Backup of the current state: %s"
MSG[inst_backup_kept]="The backup was kept at %s"
MSG[inst_allow_added]="Added to the allowlist: %s"
MSG[inst_units]="systemd units installed and enabled."
MSG[inst_check_ok]="Self-check passed."
MSG[inst_done]="bb is installed in monitor mode (it logs and counts, nothing is dropped). Look at 'bb status', then run 'bb mode block --confirm 60'."

MSG[uninst_confirm]="Remove bb completely (rules, sets, units, configuration, state, users and the packages bb installed)? [y/N]"
MSG[uninst_pkg_removed]="Removed the packages bb had installed: %s"
MSG[uninst_pkg_kept]="Kept the packages bb had installed (%s) because removing them would also remove: %s"
MSG[warn_pkg_remove]="could not remove the packages: %s"
MSG[uninst_aborted]="Aborted."
MSG[uninst_done]="bb has been removed completely."
MSG[uninst_resaved]="Saved rules file %s no longer mentions bb."

MSG[help_install]="Usage: bb install [--backend iptables|nft] [--iface IF] [--ports-mode all|only|except] [--ports LIST]
                  [--no-dpi] [--yes] [--force]

Checks the platform, installs missing packages, backs up the current rules, creates the sets
and rules in monitor mode, fills the allowlist (gateway, DNS, your SSH address), installs the
systemd units and verifies the result. On a terminal it asks the questions; --yes does not."
MSG[help_uninstall]="Usage: bb uninstall [--yes] [--keep-packages]

Removes everything bb installed or configured: units, rules and sets, configuration, state, backups,
users, binaries and the packages bb itself added (a package is kept if removing it would also remove
other software). Other firewall rules are left alone and saved rule files are cleaned of bb entries."

MSG[err_notify_bad_value]="invalid %s"
MSG[err_notify_chat_detect]="could not detect the chat ID (is jq installed, and did you write to the bot?)"
MSG[err_notify_event]="unknown event '%s'"
MSG[err_json_jq]="--json needs jq; install it with your package manager (apt install jq, dnf install jq)"
MSG[err_log_n]="-n needs a number from 1 to 100000"
MSG[err_log_nojournal]="journalctl is not available: bb writes its events to the systemd journal"
MSG[help_log]="Usage: bb log [-f] [-n LINES]

Shows the events bb wrote to the journal (tag bb) together with the kernel messages of its LOG
rules (prefix bb:), newest last. -f keeps following. The journal is the only log."
MSG[err_notify_jq]="jq is required for %s (install it with your package manager)"
MSG[err_notify_none]="no notification channel is configured; run 'bb notify setup telegram|matrix'"
MSG[err_notify_test_failed]="delivery to %s failed (curl exit %s); nothing was saved"
MSG[warn_notify_test_failed]="delivery to %s failed (curl exit %s)"

MSG[notify_setup_token]="Bot token:"
MSG[notify_setup_chat]="Chat ID (leave empty to detect it after you write to the bot):"
MSG[notify_setup_chat_wait]="Write any message to the bot now, then press Enter."
MSG[notify_setup_url]="Homeserver URL (https://...):"
MSG[notify_setup_mtoken]="Access token:"
MSG[notify_setup_room]="Room ID (!id:server):"
MSG[notify_testing]="Sending a test message..."
MSG[notify_test_ok]="Delivered to %s."
MSG[notify_saved]="Channel %s saved; notifications are enabled."
MSG[notify_enabled]="Notifications enabled."
MSG[notify_disabled]="Notifications disabled."

MSG[word_on]="on"
MSG[word_off]="off"
MSG[word_configured]="configured"
MSG[word_not_configured]="not configured"
MSG[ns_state]="Notifications: %s"
MSG[ns_channel]="Channel %s: %s"
MSG[ns_events]="Events: %s"
MSG[ns_queue]="Queue: %s, suppressed: %s"

MSG[ev_mode_changed]="mode is now %s"
MSG[ev_mode_reverted]="mode reverted to %s (block was not confirmed in time)"
MSG[ev_guard_restored]="the rules were missing or displaced and have been restored"
MSG[ev_list_update_failed]="download of list %s failed"
MSG[ev_list_rejected]="list %s rejected: %s"
MSG[ev_service_failed]="unit %s failed"
MSG[ev_rate_limit]="the flow addition limit was reached"
MSG[ev_integration_changed]="the integration allowlist was changed"
MSG[ev_manual_change]="manual change: %s"
MSG[ev_install]="bb installed, backend %s"
MSG[ev_uninstall]="bb removed"
MSG[ev_test]="notifications are working"
MSG[rsn_empty]="no valid entries"
MSG[rsn_shrunk]="shrank sharply"
MSG[rsn_size]="too large"
MSG[rsn_sha256]="checksum mismatch"
MSG[msg_footer]="mode: %s, backend: %s"
MSG[msg_suppressed]="suppressed notifications: %s"
MSG[dg_mode]="Mode: %s, backend: %s"
MSG[dg_sets]="Sets: %s"
MSG[dg_packets]="Packets since the previous digest: %s"
MSG[dg_lists]="Lists (entries): %s"
MSG[dg_events]="Events in 24 h: %s"

MSG[help_notify]="Usage: bb notify setup telegram|matrix | test | status | enable | disable | events [LIST]

setup asks for the secrets (they are never shown or logged) and verifies them with a test
message. Telegram needs no extra packages; Matrix needs jq and an unencrypted room.
events shows or sets the enabled events (comma-separated): mode_changed, guard_restored,
list_update_failed, list_rejected, service_failed, rate_limit, integration_changed,
manual_change, digest, install, uninstall."

MSG[err_integrate_name]="unknown integration '%s' (use docker, k8s, ufw, firewalld, auto, none or status)"
MSG[integ_updated]="Integrations: %s. Internal networks: %s, node addresses: %s."
MSG[inst_integrations]="Integrations: %s internal networks and %s node addresses added."
MSG[integ_mode]="Integrations: %s"
MSG[integ_row]="  %-10s %-12s %s"
MSG[integ_d_docker]="%s container networks in the internal set"
MSG[integ_d_k8s]="%s pod/service networks, %s node addresses"
MSG[integ_d_ufw]="ufw is %s; its rules are never changed"
MSG[integ_d_fwd]="firewalld is %s (backend %s); its rules are never changed"
MSG[st_detected]="detected"
MSG[st_absent]="not found"
MSG[st_active]="active"
MSG[st_inactive]="inactive"

MSG[doc_title]="bb doctor"
MSG[doc_lbl_ok]="  ok"
MSG[doc_lbl_warn]="warn"
MSG[doc_lbl_fail]="FAIL"
MSG[doc_summary]="Problems: %s, warnings: %s"
MSG[doc_not_configured]="bb is not configured (no backend selected)"
MSG[doc_backend_ok]="backend %s: all required tools are present"
MSG[doc_backend_missing]="backend %s: missing tools: %s"
MSG[doc_kernel_ok]="kernel support for %s is available"
MSG[doc_kernel_fail]="kernel support for %s is missing (module not loaded?)"
MSG[doc_variant]="iptables variant: %s"
MSG[doc_rules_ok]="the bb chain/table is present and the jump is in first position"
MSG[doc_rules_fail]="the bb rules are missing or displaced; 'bb guard' restores them"
MSG[doc_unit_ok]="unit %s is enabled"
MSG[doc_unit_fail]="unit %s is not enabled"
MSG[doc_timer_warn]="timer %s is not running"
MSG[doc_nosystemd]="systemd is not available; units cannot be checked"
MSG[doc_allow_ok]="the allowlist has %s entries"
MSG[doc_allow_warn]="the allowlist is empty: add the gateway, DNS and your admin addresses with 'bb allow'"
MSG[doc_nft_flush]="nftables.service is enabled and %s starts with 'flush ruleset': restarting it wipes every firewall table (bb-guard restores the bb rules)"
MSG[doc_nft_ok]="nftables.service does not flush the ruleset"
MSG[doc_others]="other firewall tools detected: %s (they use their own objects)"
MSG[doc_int_docker]="Docker: %s container networks are known"
MSG[doc_int_k8s]="k3s/k8s: %s pod/service networks are known"
MSG[doc_k8s_nocidr]="k3s/k8s detected but the pod/service networks are unknown: set k8s_pod_cidr and k8s_service_cidr in bb.conf"
MSG[doc_int_ufw]="ufw is %s; its rules are not touched"
MSG[doc_ufw_admin]="ufw is active: 'ufw allow' does not exempt anyone from bb, so keep your admin addresses in 'bb allow'"
MSG[doc_int_fwd]="firewalld is running (backend %s); its rules are not touched"
MSG[doc_selinux]="SELinux: %s"
MSG[doc_avc]="SELinux denied bb %s times recently (see: ausearch -m avc -c bb)"
MSG[doc_conf_perm]="bb.conf should have mode 0600 (found %s)"
MSG[doc_perm_ok]="notify.conf is owned by root with mode 0600"
MSG[doc_perm_fail]="notify.conf must be owned by root with mode 0600 (found %s)"
MSG[doc_queue]="the notification queue holds %s undelivered messages"
MSG[doc_catalog_ok]="language catalogs are in place (selected: %s)"
MSG[doc_catalog_fail]="language catalog %s is missing"
MSG[doc_saved_warn]="saved rules file %s mentions bb objects; boot could fail without bb-sets.service"

MSG[help_integrate]="Usage: bb integrate [status|auto|none|docker|k8s|ufw|firewalld]

bb never changes the rules of Docker, k8s, ufw or firewalld. It learns container and pod
networks (they pass only between each other), adds node addresses to the allowlist, and
reports ufw/firewalld. auto detects Docker and k3s/k8s; naming one enables just that one."
MSG[help_doctor]="Usage: bb doctor

Checks the backend, kernel support, rules and their position, units, the allowlist, known
conflicts (nftables.service, Docker, k8s, ufw, firewalld, fail2ban, ...), SELinux, file
permissions, the notification queue and the language catalogs. Exit code 1 on any FAIL. --json prints one JSON document
(checks with a stable id, a level and raw arguments, no text; needs jq)."

MSG[err_dpi_build]="building nDPId failed; the firewall was not changed. Log: %s (use --no-dpi to continue without traffic inspection)"
MSG[err_dpi_flag]="could not find the capture-filter option in the help of nDPId; use --ports-mode all or --no-dpi"
MSG[err_dpi_user]="could not create the user %s"
MSG[inst_prompt_dpi]="Enable traffic inspection with nDPId (it is built from source)? [Y/n]"
MSG[dpi_step_deps]="Installing build packages"
MSG[dpi_step_build]="Building nDPId"
MSG[dpi_present]="nDPId is already installed; skipping the build."
MSG[dpi_built]="nDPId %s built and installed: %s"
MSG[inst_dpi_on]="Traffic inspection: nDPId %s, capture filter: %s"
MSG[inst_dpi_off]="Traffic inspection is off (static mode: lists, DHT nodes and manual bans)."
MSG[word_none]="none"
MSG[chk_dpi_bin]="nDPId is not installed or does not start"
MSG[chk_dpi_user]="user %s is missing"
MSG[chk_dpi_conf]="the listener configuration is missing"

MSG[show_flows_head]="Dynamic flows (set, entry, seconds left):"
MSG[show_flows_none]="There are no dynamic flows."
MSG[show_flow_line]="  %-10s %s  %ss"

MSG[doc_dpi_bin_ok]="nDPId %s is installed and starts"
MSG[doc_dpi_bin_fail]="nDPId is missing or does not start: %s"
MSG[doc_dpi_jq_ok]="jq is installed (the listener needs it)"
MSG[doc_dpi_jq_fail]="jq is missing: the listener cannot parse events"
MSG[doc_dpi_user_fail]="user %s does not exist"
MSG[doc_dpi_notrunning]="nDPId is not running"
MSG[doc_dpi_conf_ok]="listener.conf belongs to root:bb with mode 0640"
MSG[doc_dpi_conf_fail]="listener.conf must belong to root:bb with mode 0640 (found %s)"
MSG[doc_dpi_dir_warn]="the listener's directory is missing or not owned by bb"

MSG[help_show]="Usage: bb show flows

Lists the flows that traffic inspection added (the dynamic sets) with the seconds left of each."

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
  lang [en|ru]                show or change the interface language

Global option: --lang en|ru"
MSG[help_apply]="Usage: bb apply

Rebuilds all sets and rules from the configuration. Safe to run at any time."
MSG[help_guard]="Usage: bb guard

Restores the rules if they disappeared or lost their first position. Used by the guard timer."
MSG[help_status]="Usage: bb status

Shows the backend, the mode, the size of every set and the drop counters."
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
MSG[inst_dpi_later]="Traffic inspection (nDPId) is not available in this version; using lists, DHT nodes and manual bans."
MSG[inst_units]="systemd units installed and enabled."
MSG[inst_check_ok]="Self-check passed."
MSG[inst_done]="bb is installed in monitor mode (it logs and counts, nothing is dropped). Look at 'bb status', then run 'bb mode block --confirm 60'."

MSG[uninst_confirm]="Remove all bb rules, sets and units? [y/N]"
MSG[uninst_aborted]="Aborted."
MSG[uninst_done]="bb removed. Configuration kept in %s (use --purge to delete it too)."
MSG[uninst_purged]="bb removed completely."
MSG[uninst_resaved]="Saved rules file %s no longer mentions bb."

MSG[help_install]="Usage: bb install [--backend iptables|nft] [--iface IF] [--ports-mode all|only|except] [--ports LIST]
                  [--no-dpi] [--yes] [--force]

Checks the platform, installs missing packages, backs up the current rules, creates the sets
and rules in monitor mode, fills the allowlist (gateway, DNS, your SSH address), installs the
systemd units and verifies the result. On a terminal it asks the questions; --yes does not."
MSG[help_uninstall]="Usage: bb uninstall [--yes] [--purge]

Removes bb rules, sets and units. Other firewall rules are left alone and saved rule files
are cleaned of bb entries. --purge also deletes the configuration and state."

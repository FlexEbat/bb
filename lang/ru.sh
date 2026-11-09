# Каталог сообщений bb: русский. Ключи и плейсхолдеры совпадают с en.sh.
MSG[label_warning]="предупреждение"
MSG[label_error]="ошибка"
MSG[version]="bb %s"

MSG[err_apply_failed]="не удалось применить правила; прежнее состояние восстановлено"
MSG[err_bad_entry]="«%s» не является корректным IP-адресом или сетью (допустимые префиксы: /8-/32 для IPv4, /16-/128 для IPv6)"
MSG[err_bad_listname]="недопустимое имя списка «%s» (используйте a-z, 0-9, «_» и «-», до 32 символов; имя «dht» зарезервировано)"
MSG[err_bad_sha]="sha256 должен состоять из 64 шестнадцатеричных символов"
MSG[err_bad_source]="источник должен быть URL вида https:// или путём к читаемому файлу (без пробелов и кавычек)"
MSG[err_bad_ttl]="некорректный срок «%s» (примеры: 90s, 30m, 12h, 7d, 2w)"
MSG[err_cfg_invalid]="некорректное значение параметра %s: «%s»"
MSG[err_fw_init]="не удалось создать объекты межсетевого экрана: %s"
MSG[err_https_only]="для списков допускаются только URL вида https://"
MSG[err_lang_invalid]="язык «%s» не поддерживается (доступны en и ru)"
MSG[err_lock]="выполняется другая команда bb (истекло время ожидания блокировки)"
MSG[err_mkdir]="не удалось создать каталог %s"
MSG[err_need_root]="для этой команды нужны права root"
MSG[err_no_list]="нет такого списка: %s"
MSG[err_no_systemd_run]="для автоматического отката нужен systemd-run; режим не изменён"
MSG[err_not_allowed]="%s отсутствует в списке исключений"
MSG[err_not_banned]="%s отсутствует в списке ручных блокировок"
MSG[err_not_configured]="bb ещё не настроен (бэкенд не выбран)"
MSG[err_rollback_arm]="не удалось запустить таймер отката; режим не изменён"
MSG[err_rules_syntax]="сгенерированные правила не прошли проверку синтаксиса; ничего не изменено"
MSG[err_set_load]="не удалось загрузить набор %s"
MSG[err_tools_missing]="не хватает необходимых утилит:%s"
MSG[err_unknown_cmd]="неизвестная команда «%s»"
MSG[err_unknown_opt]="неизвестный параметр «%s»"
MSG[err_usage]="неверное использование; смотрите: bb %s --help"
MSG[err_write]="не удалось записать %s"

MSG[warn_ban_allowed]="%s находится в списке исключений, поэтому блокироваться не будет"
MSG[warn_cfg_line]="строка %s в bb.conf не соответствует виду KEY='value'; пропущена"
MSG[warn_cfg_value]="bb.conf: некорректное значение параметра %s (строка %s); используется значение по умолчанию"
MSG[warn_dht_empty]="ни один DHT-узел не удалось разрешить; прежний набор сохранён"
MSG[warn_dht_line]="пропущена некорректная запись DHT-узла: %s"
MSG[warn_dht_shrunk]="список DHT-узлов резко сократился (%s -> %s записей); прежний набор сохранён"
MSG[warn_list_bad_desc]="описание списка %s повреждено; список пропущен"
MSG[warn_list_empty]="в списке %s нет корректных записей; прежний набор сохранён"
MSG[warn_list_fetch]="не удалось скачать список %s; прежний набор сохранён"
MSG[warn_list_sha]="список %s не совпадает с указанной суммой sha256; прежний набор сохранён"
MSG[warn_list_shrunk]="список %s резко сократился (%s -> %s записей); прежний набор сохранён"
MSG[warn_set_degraded]="не удалось загрузить набор %s; правила применены без него (см. журнал)"
MSG[warn_list_too_many]="в списке %s записей: %s, больше чем list_maxelem (%s); оставляю старые данные"
MSG[warn_resolve_budget]="разрешение имён прервано через %s с; неразрешённые имена пропущены"
MSG[warn_ipv6_unusable]="на этом хосте есть IPv6, но ip6tables не может использовать таблицу raw (нет модуля ip6table_raw?); обрабатывается только IPv4"
MSG[doc_ipv6_unusable]="IPv6 включён, но ip6tables не может использовать таблицу raw: трафик IPv6 не блокируется (только IPv4)"
MSG[warn_list_too_big]="список %s превышает допустимый размер; прежний набор сохранён"
MSG[warn_set_op]="не удалось обновить действующий набор для %s; он будет загружен при следующем «bb apply»"

MSG[apply_done]="Правила применены. Бэкенд: %s, режим: %s."
MSG[guard_restored]="Правила отсутствовали или сместились и были восстановлены."
MSG[config_written]="Конфигурация записана. Бэкенд: %s."
MSG[note_not_applied]="Правила ещё не активны; изменение будет загружено командой «bb apply»."
MSG[ban_done]="Заблокировано: %s"
MSG[unban_done]="Блокировка снята: %s"
MSG[allow_done]="Добавлено в исключения: %s"
MSG[allow_removed]="Удалено из исключений: %s"

MSG[mode_current]="Текущий режим: %s"
MSG[mode_changed]="Режим изменён на %s."
MSG[mode_confirm_hint]="Через %s с произойдёт возврат в monitor, если не подтвердить. Выполните «bb mode confirm», чтобы оставить block."
MSG[mode_confirm_prompt]="Оставить режим block? [y/N]"
MSG[mode_confirmed]="Режим block подтверждён."
MSG[mode_nothing_pending]="Нет режима, ожидающего подтверждения."
MSG[mode_rolled_back]="Выполнен возврат в режим monitor."

MSG[lang_current]="Язык интерфейса: %s"
MSG[lang_set]="Язык интерфейса изменён на %s."

MSG[status_title]="bb %s"
MSG[status_backend]="Бэкенд: %s"
MSG[status_mode]="Режим: %s"
MSG[status_lang]="Язык: %s"
MSG[status_rules_present]="Правила: активны"
MSG[status_rules_absent]="Правила: НЕ активны (выполните «bb apply»)"
MSG[status_sets]="Наборы (записей):"
MSG[status_set_line]="  %-10s %s"
MSG[status_counters]="Счётчики:"
MSG[status_counter_line]="  %-8s пакетов %s, байт %s"

MSG[list_none]="Списки не настроены. Добавьте: bb list add ИМЯ URL"
MSG[list_line]="%-16s %-5s записей: %-8s %s"
MSG[list_line_dht]="dht              узлов записей: %s"
MSG[list_added]="Список %s добавлен. Выполните «bb list update», чтобы скачать его."
MSG[list_removed]="Список %s удалён."
MSG[list_updated]="Список %s обновлён: записей %s."
MSG[dht_updated]="DHT-узлы обновлены: записей %s."

MSG[help_main]="bb - лёгкий блокировщик BitTorrent, DHT и чёрных списков

Использование: bb КОМАНДА [параметры]       (у каждой команды есть --help)

  install / uninstall         установить bb (мастер) или удалить всё, что он создал
  apply                       пересобрать правила из конфигурации
  status                      бэкенд, режим, размеры наборов, счётчики
  mode monitor|block          сменить режим (block --confirm N откатится без подтверждения)
  ban IP|СЕТЬ [--ttl 7d]      ручная блокировка   unban IP|СЕТЬ   снять блокировку
  allow IP|СЕТЬ [--rm]        никогда не блокировать этот адрес
  list [add|update|rm]        внешние чёрные списки и DHT-узлы
  notify setup|test|status    уведомления в Telegram / Matrix
  integrate [auto|docker|...] Docker, k3s/k8s, ufw, firewalld   doctor   диагностика
  show flows                  потоки, добавленные анализом трафика
  log [-f]                    события bb и сообщения ядра из журнала
  lang [en|ru]                показать или сменить язык интерфейса

Глобальный параметр: --lang en|ru"
MSG[help_apply]="Использование: bb apply

Пересобирает все наборы и правила из конфигурации. Можно запускать в любой момент."
MSG[help_guard]="Использование: bb guard

Восстанавливает правила, если они пропали или потеряли первое место. Вызывается таймером guard."
MSG[help_status]="Использование: bb status [--json]

Показывает бэкенд, режим, размер каждого набора и счётчики отброшенных пакетов. --json печатает то же
одним JSON-документом со стабильными ключами и непереведёнными значениями (нужен jq)."
MSG[help_mode]="Использование: bb mode [monitor|block|confirm] [--confirm [СЕКУНДЫ]]

monitor пишет в журнал и считает, но не отбрасывает; block отбрасывает. С --confirm режим
вернётся в monitor, если вы не выполните «bb mode confirm» вовремя (по умолчанию 60 с)."
MSG[help_ban]="Использование: bb ban IP|СЕТЬ [--ttl СРОК]

Блокирует адрес или сеть. СРОК: 90s, 30m, 12h, 7d, 2w. Без --ttl блокировка бессрочная."
MSG[help_unban]="Использование: bb unban IP|СЕТЬ

Снимает ручную блокировку."
MSG[help_allow]="Использование: bb allow IP|СЕТЬ [--rm]

Исключает адрес или сеть из блокировки. --rm убирает исключение."
MSG[help_lang]="Использование: bb lang [en|ru]

Показывает или меняет язык интерфейса."
MSG[help_list]="Использование: bb list [add ИМЯ URL|ФАЙЛ [--sha256 HEX] | update [ИМЯ|dht] | rm ИМЯ]

Без аргументов показывает настроенные списки. Принимаются только источники https://."

MSG[err_check_failed]="самопроверка не пройдена:"
MSG[err_install_failed]="установка не удалась; правила не изменены"
MSG[err_need_yes]="это не терминал: подтвердите параметром --yes"
MSG[err_no_systemd]="требуется systemd (с параметром --force можно продолжить без юнитов)"
MSG[err_os_unsupported]="дистрибутив не поддерживается (ID=%s). Поддерживаются Debian/Ubuntu (apt) и RHEL/Fedora (dnf). Нужно: %s. Параметр --force пропускает эту проверку."
MSG[err_pkg_install]="не удалось установить пакеты; ничего не изменено"
MSG[err_pkg_still_missing]="после установки утилиты бэкенда всё ещё отсутствуют: %s"
MSG[err_ports_required]="для --ports-mode only|except нужен параметр --ports"
MSG[err_units]="не удалось установить юниты systemd"

MSG[warn_check_dht_empty]="набор DHT пуст (не работает DNS?); позже выполните «bb list update dht»"
MSG[warn_mode_reverted]="режим block не был подтверждён; выполнен возврат в monitor"
MSG[warn_units_start]="не удалось запустить часть юнитов; смотрите «systemctl status bb-firewall»"
MSG[inst_units_skipped]="systemd недоступен: юниты не установлены"

MSG[chk_rules_inactive]="правила не активны"
MSG[chk_rules_missing]="не найдены правила %s"
MSG[chk_set_missing]="набор %s отсутствует"
MSG[chk_stale_set]="остался временный набор %s"
MSG[chk_unit_disabled]="юнит %s не включён"

MSG[inst_plan_pkgs]="Бэкенд: %s. Будут установлены: %s"
MSG[inst_plan_none]="Бэкенд: %s. Устанавливать нечего."
MSG[inst_pkg_installing]="Установка пакетов: %s"
MSG[inst_prompt_iface]="Сетевой интерфейс для наблюдения [%s]:"
MSG[inst_prompt_mode]="Режим портов: all, only или except [%s]:"
MSG[inst_prompt_ports]="Порты, например 6881-6889,51413 [%s]:"
MSG[inst_backup]="Резервная копия текущего состояния: %s"
MSG[inst_backup_kept]="Резервная копия сохранена: %s"
MSG[inst_allow_added]="Добавлено в список исключений: %s"
MSG[inst_units]="Юниты systemd установлены и включены."
MSG[inst_check_ok]="Самопроверка пройдена."
MSG[inst_done]="bb установлен в режиме monitor (пишет в журнал и считает, ничего не отбрасывает). Посмотрите «bb status», затем выполните «bb mode block --confirm 60»."

MSG[uninst_confirm]="Удалить bb полностью (правила, наборы, юниты, конфигурацию, состояние, пользователей и пакеты, которые поставил bb)? [y/N]"
MSG[uninst_pkg_removed]="Удалены пакеты, которые поставил bb: %s"
MSG[uninst_pkg_kept]="Пакеты, которые поставил bb (%s), оставлены: их удаление затронуло бы и другие пакеты: %s"
MSG[warn_pkg_remove]="не удалось удалить пакеты: %s"
MSG[uninst_aborted]="Отменено."
MSG[uninst_done]="bb полностью удалён."
MSG[uninst_resaved]="Файл сохранённых правил %s больше не упоминает bb."

MSG[help_install]="Использование: bb install [--backend iptables|nft] [--iface ИНТЕРФЕЙС[,ИНТЕРФЕЙС...]] [--ports-mode all|only|except] [--ports СПИСОК]
                       [--no-dpi] [--yes] [--force]

Проверяет платформу, ставит недостающие пакеты, делает резервную копию текущих правил, создаёт наборы
и правила в режиме monitor, заполняет список исключений (шлюз, DNS, ваш SSH-адрес), устанавливает
юниты systemd и проверяет результат. В терминале задаёт вопросы; с --yes не спрашивает."
MSG[help_uninstall]="Использование: bb uninstall [--yes] [--keep-packages]

Удаляет всё, что bb установил или настроил: юниты, правила и наборы, конфигурацию, состояние, резервные
копии, пользователей, бинарные файлы и пакеты, которые поставил сам bb (пакет остаётся, если его удаление
затронуло бы другое ПО). Остальные правила межсетевого экрана не трогаются, из сохранённых файлов правил
убираются записи bb."

MSG[err_notify_bad_value]="некорректное значение: %s"
MSG[err_notify_chat_detect]="не удалось определить ID чата (установлен ли jq и писали ли вы боту?)"
MSG[err_notify_event]="неизвестное событие «%s»"
MSG[err_json_jq]="для --json нужен jq; установите его менеджером пакетов (apt install jq, dnf install jq)"
MSG[err_log_n]="для -n нужно число от 1 до 100000"
MSG[err_log_nojournal]="journalctl недоступен: bb пишет события в журнал systemd"
MSG[help_log]="Использование: bb log [-f] [-n СТРОК]

Показывает события, которые bb записал в журнал (тег bb), вместе с сообщениями ядра от его правил
LOG (префикс bb:), новые внизу. -f продолжает следить. Журнал — единственный лог."
MSG[err_notify_jq]="для %s нужен jq (установите его менеджером пакетов)"
MSG[err_notify_none]="канал уведомлений не настроен; выполните «bb notify setup telegram|matrix»"
MSG[err_notify_test_failed]="доставка в %s не удалась (код curl %s); ничего не сохранено"
MSG[warn_notify_test_failed]="доставка в %s не удалась (код curl %s)"

MSG[notify_setup_token]="Токен бота:"
MSG[notify_setup_chat]="ID чата (оставьте пустым, чтобы определить его после сообщения боту):"
MSG[notify_setup_chat_wait]="Напишите боту любое сообщение, затем нажмите Enter."
MSG[notify_setup_url]="Адрес homeserver (https://...):"
MSG[notify_setup_mtoken]="Токен доступа:"
MSG[notify_setup_room]="ID комнаты (!id:server):"
MSG[notify_testing]="Отправка тестового сообщения..."
MSG[notify_test_ok]="Доставлено: %s."
MSG[notify_saved]="Канал %s сохранён; уведомления включены."
MSG[notify_enabled]="Уведомления включены."
MSG[notify_disabled]="Уведомления выключены."

MSG[word_on]="включены"
MSG[word_off]="выключены"
MSG[word_configured]="настроен"
MSG[word_not_configured]="не настроен"
MSG[ns_state]="Уведомления: %s"
MSG[ns_channel]="Канал %s: %s"
MSG[ns_events]="События: %s"
MSG[ns_queue]="Очередь: %s, подавлено: %s"

MSG[ev_mode_changed]="теперь режим %s"
MSG[ev_mode_reverted]="выполнен возврат в режим %s (block не подтверждён вовремя)"
MSG[ev_guard_restored]="правила пропали или сместились и были восстановлены"
MSG[ev_list_update_failed]="не удалось скачать список %s"
MSG[ev_list_rejected]="список %s отклонён: %s"
MSG[ev_service_failed]="сбой юнита %s"
MSG[ev_rate_limit]="достигнут предел добавления потоков"
MSG[ev_integration_changed]="изменён список исключений интеграций"
MSG[ev_manual_change]="ручное изменение: %s"
MSG[ev_install]="bb установлен, бэкенд %s"
MSG[ev_uninstall]="bb удалён"
MSG[ev_test]="уведомления работают"
MSG[rsn_empty]="нет корректных записей"
MSG[rsn_shrunk]="резко сократился"
MSG[rsn_size]="слишком большой"
MSG[rsn_sha256]="не совпала контрольная сумма"
MSG[msg_footer]="режим: %s, бэкенд: %s"
MSG[msg_suppressed]="подавлено уведомлений: %s"
MSG[dg_mode]="Режим: %s, бэкенд: %s"
MSG[dg_sets]="Наборы: %s"
MSG[dg_packets]="Пакетов с прошлой сводки: %s"
MSG[dg_lists]="Списки (записей): %s"
MSG[dg_events]="События за 24 ч: %s"

MSG[help_notify]="Использование: bb notify setup telegram|matrix | test | status | enable | disable | events [СПИСОК]

setup запрашивает секреты (они не показываются и не попадают в журнал) и проверяет их тестовым
сообщением. Для Telegram дополнительные пакеты не нужны; для Matrix нужны jq и незашифрованная комната.
events показывает или задаёт включённые события (через запятую): mode_changed, guard_restored,
list_update_failed, list_rejected, service_failed, rate_limit, integration_changed,
manual_change, digest, install, uninstall."

MSG[err_integrate_name]="неизвестная интеграция «%s» (docker, k8s, ufw, firewalld, auto, none или status)"
MSG[integ_updated]="Интеграции: %s. Внутренних сетей: %s, адресов узлов: %s."
MSG[inst_integrations]="Интеграции: добавлено внутренних сетей %s и адресов узлов %s."
MSG[integ_mode]="Интеграции: %s"
MSG[integ_row]="  %-10s %-12s %s"
MSG[integ_d_docker]="сетей контейнеров во внутреннем наборе: %s"
MSG[integ_d_k8s]="сетей подов и сервисов: %s, адресов узлов: %s"
MSG[integ_d_ufw]="ufw: %s; его правила никогда не меняются"
MSG[integ_d_fwd]="firewalld: %s (бэкенд %s); его правила никогда не меняются"
MSG[st_detected]="обнаружен"
MSG[st_absent]="не найден"
MSG[st_active]="активен"
MSG[st_inactive]="не активен"

MSG[doc_title]="bb doctor"
MSG[doc_lbl_ok]="  ok"
MSG[doc_lbl_warn]="вним"
MSG[doc_lbl_fail]="СБОЙ"
MSG[doc_summary]="Проблем: %s, предупреждений: %s"
MSG[doc_not_configured]="bb не настроен (бэкенд не выбран)"
MSG[doc_backend_ok]="бэкенд %s: все необходимые утилиты на месте"
MSG[doc_backend_missing]="бэкенд %s: не хватает утилит: %s"
MSG[doc_kernel_ok]="поддержка %s в ядре доступна"
MSG[doc_kernel_fail]="поддержки %s в ядре нет (модуль не загружен?)"
MSG[doc_variant]="вариант iptables: %s"
MSG[doc_rules_ok]="цепочка/таблица bb на месте, переход стоит первым"
MSG[doc_rules_fail]="правила bb отсутствуют или сместились; «bb guard» восстановит их"
MSG[doc_unit_ok]="юнит %s включён"
MSG[doc_unit_fail]="юнит %s не включён"
MSG[doc_timer_warn]="таймер %s не запущен"
MSG[doc_nosystemd]="systemd недоступен; юниты проверить нельзя"
MSG[doc_allow_ok]="в списке исключений записей: %s"
MSG[doc_allow_warn]="список исключений пуст: добавьте шлюз, DNS и свои административные адреса командой «bb allow»"
MSG[doc_nft_flush]="nftables.service включён, а %s начинается с «flush ruleset»: его перезапуск сотрёт все таблицы межсетевого экрана (bb-guard восстановит правила bb)"
MSG[doc_nft_ok]="nftables.service не сбрасывает набор правил"
MSG[doc_others]="обнаружены другие средства межсетевого экрана: %s (они используют свои объекты)"
MSG[doc_int_docker]="Docker: известных сетей контейнеров: %s"
MSG[doc_int_k8s]="k3s/k8s: известных сетей подов и сервисов: %s"
MSG[doc_k8s_nocidr]="k3s/k8s обнаружен, но сети подов и сервисов неизвестны: задайте k8s_pod_cidr и k8s_service_cidr в bb.conf"
MSG[doc_int_ufw]="ufw: %s; его правила не затрагиваются"
MSG[doc_ufw_admin]="ufw активен: «ufw allow» не освобождает от блокировки bb, поэтому держите административные адреса в «bb allow»"
MSG[doc_int_fwd]="firewalld работает (бэкенд %s); его правила не затрагиваются"
MSG[doc_selinux]="SELinux: %s"
MSG[doc_avc]="SELinux недавно запретил действия bb: %s раз (смотрите: ausearch -m avc -c bb)"
MSG[doc_conf_perm]="у bb.conf должен быть режим 0600 (сейчас %s)"
MSG[doc_perm_ok]="notify.conf принадлежит root, режим 0600"
MSG[doc_perm_fail]="notify.conf должен принадлежать root с режимом 0600 (сейчас %s)"
MSG[doc_queue]="в очереди уведомлений недоставленных сообщений: %s"
MSG[doc_catalog_ok]="каталоги языков на месте (выбран: %s)"
MSG[doc_catalog_fail]="отсутствует каталог языка %s"
MSG[doc_saved_warn]="файл сохранённых правил %s упоминает объекты bb; без bb-sets.service загрузка может не удаться"

MSG[help_integrate]="Использование: bb integrate [status|auto|none|docker|k8s|ufw|firewalld]

bb никогда не меняет правила Docker, k8s, ufw и firewalld. Он узнаёт сети контейнеров и подов
(между собой они проходят свободно), добавляет адреса узлов в список исключений и показывает
состояние ufw/firewalld. auto находит Docker и k3s/k8s; если назвать одну интеграцию, включится только она."
MSG[help_doctor]="Использование: bb doctor

Проверяет бэкенд, поддержку в ядре, правила и их положение, юниты, список исключений, известные
конфликты (nftables.service, Docker, k8s, ufw, firewalld, fail2ban и др.), SELinux, права файлов,
очередь уведомлений и каталоги языков. При любом СБОЕ код возврата 1. --json печатает один JSON-документ
(проверки со стабильным id, уровнем и исходными аргументами, без текста; нужен jq)."

MSG[err_dpi_build]="не удалось собрать nDPId; межсетевой экран не изменён. Журнал: %s (с параметром --no-dpi можно продолжить без анализа трафика)"
MSG[err_dpi_flag]="в справке nDPId не найден параметр фильтра захвата; используйте --ports-mode all или --no-dpi"
MSG[err_dpi_user]="не удалось создать пользователя %s"
MSG[inst_prompt_dpi]="Включить анализ трафика через nDPId (он собирается из исходников)? [Y/n]"
MSG[dpi_step_deps]="Установка пакетов для сборки"
MSG[dpi_step_build]="Сборка nDPId"
MSG[dpi_present]="nDPId уже установлен; сборка пропущена."
MSG[dpi_built]="nDPId %s собран и установлен: %s"
MSG[inst_dpi_on]="Анализ трафика: nDPId %s, фильтр захвата: %s"
MSG[inst_dpi_off]="Анализ трафика выключен (статический режим: списки, DHT-узлы и ручные блокировки)."
MSG[word_none]="нет"
MSG[chk_dpi_bin]="nDPId не установлен или не запускается"
MSG[chk_dpi_user]="пользователь %s отсутствует"
MSG[chk_dpi_conf]="отсутствует конфигурация слушателя"

MSG[show_flows_head]="Динамические потоки (набор, запись, осталось секунд):"
MSG[show_flows_more]="... и ещё %s (bb show flows --all покажет всё)"
MSG[doc_flows_full]="набор потоков %s заполнен: %s из %s записей (flow_maxelem); новые потоки не добавятся, когда он заполнится"
MSG[show_flows_none]="Динамических потоков нет."
MSG[show_flow_line]="  %-10s %s  %s с"

MSG[doc_dpi_bin_ok]="nDPId %s установлен и запускается"
MSG[doc_dpi_bin_fail]="nDPId отсутствует или не запускается: %s"
MSG[doc_dpi_iface_stopped]="экземпляр nDPId для интерфейса %s не запущен"
MSG[doc_dpi_iface_ok]="nDPId анализирует интерфейс %s"
MSG[doc_dpi_iface_empty]="для nDPId не задан интерфейс (он анализировал бы lo); задайте его: bb install --iface ИМЯ"
MSG[doc_dpi_iface_missing]="интерфейса %s, который использует nDPId, нет на этом хосте"
MSG[err_dpi_no_iface]="маршрут по умолчанию не найден, интерфейс для анализа неизвестен; укажите --iface ИМЯ (или --no-dpi)"
MSG[doc_dpi_jq_ok]="jq установлен (он нужен слушателю)"
MSG[doc_dpi_jq_fail]="jq отсутствует: слушатель не может разбирать события"
MSG[doc_dpi_user_fail]="пользователь %s не существует"
MSG[doc_dpi_notrunning]="nDPId не запущен"
MSG[doc_dpi_conf_ok]="listener.conf принадлежит root:bb, режим 0640"
MSG[doc_dpi_conf_fail]="listener.conf должен принадлежать root:bb с режимом 0640 (сейчас %s)"
MSG[doc_dpi_dir_warn]="каталог слушателя отсутствует или принадлежит не bb"

MSG[help_show]="Использование: bb show flows [--limit N | --all]

Показывает потоки, которые добавил анализ трафика (динамические наборы), и сколько секунд осталось у каждого.
По умолчанию показаны первые 1000."

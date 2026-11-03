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
  lang [en|ru]                показать или сменить язык интерфейса

Глобальный параметр: --lang en|ru"
MSG[help_apply]="Использование: bb apply

Пересобирает все наборы и правила из конфигурации. Можно запускать в любой момент."
MSG[help_guard]="Использование: bb guard

Восстанавливает правила, если они пропали или потеряли первое место. Вызывается таймером guard."
MSG[help_status]="Использование: bb status

Показывает бэкенд, режим, размер каждого набора и счётчики отброшенных пакетов."
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
MSG[inst_dpi_later]="Анализ трафика (nDPId) в этой версии недоступен; используются списки, DHT-узлы и ручные блокировки."
MSG[inst_units]="Юниты systemd установлены и включены."
MSG[inst_check_ok]="Самопроверка пройдена."
MSG[inst_done]="bb установлен в режиме monitor (пишет в журнал и считает, ничего не отбрасывает). Посмотрите «bb status», затем выполните «bb mode block --confirm 60»."

MSG[uninst_confirm]="Удалить все правила, наборы и юниты bb? [y/N]"
MSG[uninst_aborted]="Отменено."
MSG[uninst_done]="bb удалён. Конфигурация сохранена в %s (чтобы удалить и её, используйте --purge)."
MSG[uninst_purged]="bb удалён полностью."
MSG[uninst_resaved]="Файл сохранённых правил %s больше не упоминает bb."

MSG[help_install]="Использование: bb install [--backend iptables|nft] [--iface ИНТЕРФЕЙС] [--ports-mode all|only|except] [--ports СПИСОК]
                       [--no-dpi] [--yes] [--force]

Проверяет платформу, ставит недостающие пакеты, делает резервную копию текущих правил, создаёт наборы
и правила в режиме monitor, заполняет список исключений (шлюз, DNS, ваш SSH-адрес), устанавливает
юниты systemd и проверяет результат. В терминале задаёт вопросы; с --yes не спрашивает."
MSG[help_uninstall]="Использование: bb uninstall [--yes] [--purge]

Удаляет правила, наборы и юниты bb. Остальные правила межсетевого экрана не затрагиваются,
из файлов сохранённых правил убираются записи bb. С --purge удаляются также конфигурация и состояние."

extends Node3D

@export var player_scene: PackedScene = preload("res://player.tscn")
const SAVE_PATH := "user://rp_save.cfg"
const SERVER_SESSION_ID := "my_rp_server_main_1"
const CREATOR_SECRET_NAME := "Admin"
const MAX_PLAYERS := 7 # Максимум игроков (включая хоста)
const COURIER_REWARD := 150
const COURIER_COOLDOWN := 3.0 # Защита от спама доставками (в секундах)

@onready var tube_client: TubeClient = $TubeClient
@onready var login_panel: Panel = $CanvasLayer/LoginPanel
@onready var first_name_input: LineEdit = $CanvasLayer/LoginPanel/FirstNameInput
@onready var last_name_input: LineEdit = $CanvasLayer/LoginPanel/LastNameInput
@onready var host_button: Button = $CanvasLayer/LoginPanel/HostButton
@onready var join_button: Button = $CanvasLayer/LoginPanel/JoinButton
@onready var status_label: Label = $CanvasLayer/LoginPanel/StatusLabel
@onready var code_input: LineEdit = $CanvasLayer/LoginPanel/CodeInput
@onready var money_label: Label = $CanvasLayer/MoneyLabel
@onready var chat_history: RichTextLabel = $CanvasLayer/ChatHistory
@onready var chat_input: LineEdit = $CanvasLayer/ChatInput
@onready var job_marker: Area3D = $JobMarker

var player_names: Dictionary = {}
var player_money: Dictionary = {}
var last_delivery_time: Dictionary = {} # Античит-таймер для курьеров
var admin_ids: Array[int] = [1]
var my_saved_money: int = 0
var is_working_courier: bool = false

func _ready() -> void:
	load_game_data()
	
	# Отключаем маркер работы при старте
	job_marker.visible = false
	job_marker.monitoring = false
	
	# Подключаем сетевые события
	multiplayer.peer_connected.connect(_add_player)
	multiplayer.peer_disconnected.connect(_remove_player)
	tube_client.session_created.connect(_on_session_created)
	tube_client.session_joined.connect(_on_session_joined)
	
	# Подключаем UI и сигналы
	first_name_input.text_changed.connect(_on_first_name_changed)
	host_button.pressed.connect(_on_host_button_pressed)
	join_button.pressed.connect(_on_join_button_pressed)
	$CanvasLayer/SendButton.pressed.connect(_on_send_button_pressed)
	$CanvasLayer/CourierButton.pressed.connect(_on_courier_button_pressed)
	job_marker.body_entered.connect(_on_job_marker_body_entered)
	chat_input.text_submitted.connect(func(_text): _on_send_button_pressed())
	
	_on_first_name_changed(first_name_input.text)

# --- Сохранение и загрузка ---

func load_game_data() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		first_name_input.text = config.get_value("Player", "first_name", "")
		last_name_input.text = config.get_value("Player", "last_name", "")
		my_saved_money = config.get_value("Player", "money", 0)
	money_label.text = "Баланс: $" + str(my_saved_money)

func save_game_data() -> void:
	var config := ConfigFile.new()
	config.set_value("Player", "first_name", first_name_input.text.strip_edges())
	config.set_value("Player", "last_name", last_name_input.text.strip_edges())
	config.set_value("Player", "money", my_saved_money)
	config.save(SAVE_PATH)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		save_game_data()

# --- Меню входа и сеть Tube ---

func _on_first_name_changed(new_text: String) -> void:
	host_button.visible = (new_text.strip_edges() == CREATOR_SECRET_NAME)

func get_my_rp_name() -> String:
	var f_name := first_name_input.text.strip_edges()
	var l_name := last_name_input.text.strip_edges()
	if f_name == "":
		f_name = "Player"
	if l_name == "":
		l_name = str(multiplayer.get_unique_id())
	return f_name + "_" + l_name

func _on_host_button_pressed() -> void:
	host_button.disabled = true
	join_button.disabled = true
	status_label.text = "Запуск сервера..."
	tube_client.create_session()

func _on_join_button_pressed() -> void:
	host_button.disabled = true
	join_button.disabled = true
	status_label.text = "Подключение к серверу..."
	tube_client.join_session(code_input.text.strip_edges())

func _on_session_created() -> void:
	login_panel.visible = false
	_add_player(1)
	register_player_name.rpc(get_my_rp_name())
	sync_saved_progress.rpc_id(1, my_saved_money)
	chat_history.append_text("[color=green]Сервер запущен! Введите /help или /ahelp для команд.[/color]\n")

func _on_session_joined() -> void:
	login_panel.visible = false
	register_player_name.rpc(get_my_rp_name())
	sync_saved_progress.rpc_id(1, my_saved_money)
	chat_history.append_text("[color=cyan]Вы вошли на сервер! Введите /help для списка команд.[/color]\n")

func _add_player(id: int) -> void:
	if not multiplayer.is_server():
		return
	# get_peers() не считает хоста, поэтому >= MAX_PLAYERS - 1
	if id != 1 and multiplayer.get_peers().size() > MAX_PLAYERS - 1:
		multiplayer.disconnect_peer(id)
		return
		
	var player := player_scene.instantiate()
	player.name = str(id)
	var points := $SpawnPoints.get_children()
	if points.size() > 0:
		player.global_position = points.pick_random().global_position
	add_child(player)
	
	# Отправляем новичку список всех текущих ников
	if id != 1:
		sync_all_names.rpc_id(id, player_names)

func _remove_player(id: int) -> void:
	if not multiplayer.is_server():
		return
	var player := get_node_or_null(str(id))
	if player:
		player.queue_free()
	player_names.erase(id)
	player_money.erase(id)
	last_delivery_time.erase(id)

@rpc("any_peer", "call_local", "reliable")
func register_player_name(rp_name: String) -> void:
	var sender_id := _get_real_sender_id()
	var clean_name := rp_name.strip_edges().substr(0, 24).replace("[", "")
	if clean_name == "":
		clean_name = "Игрок_" + str(sender_id)
		
	player_names[sender_id] = clean_name
	_apply_name_to_node(sender_id, clean_name)

@rpc("authority", "call_remote", "reliable")
func sync_all_names(all_names: Dictionary) -> void:
	for id in all_names:
		player_names[id] = all_names[id]
		_apply_name_to_node(id, all_names[id])

func _apply_name_to_node(id: int, rp_name: String) -> void:
	var player_node := get_node_or_null(str(id))
	if player_node and player_node.has_node("NameLabel"):
		player_node.get_node("NameLabel").text = rp_name

@rpc("any_peer", "call_local", "reliable")
func sync_saved_progress(saved_money: int) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := _get_real_sender_id()
	var safe_money := clampi(saved_money, 0, 10000000) # Ограничение от читерских чисел
	player_money[sender_id] = safe_money
	update_money_ui.rpc_id(sender_id, safe_money)

@rpc("authority", "call_local", "reliable")
func update_money_ui(new_balance: int) -> void:
	my_saved_money = new_balance
	money_label.text = "Баланс: $" + str(new_balance)
	save_game_data()

# --- Работа курьером ---

func _on_courier_button_pressed() -> void:
	is_working_courier = !is_working_courier
	if is_working_courier:
		job_marker.visible = true
		job_marker.set_deferred("monitoring", true)
		_pick_next_delivery_point()
	else:
		job_marker.visible = false
		job_marker.set_deferred("monitoring", false)
		chat_history.append_text("[color=orange]Смена курьера окончена.[/color]\n")

func _pick_next_delivery_point() -> void:
	var points := $DeliveryPoints.get_children()
	if points.size() > 0:
		job_marker.global_position = points.pick_random().global_position

func _on_job_marker_body_entered(body: Node3D) -> void:
	if not is_working_courier or not job_marker.visible:
		return
	if body is CharacterBody3D and body.is_multiplayer_authority():
		request_add_money.rpc_id(1, 150)
		_pick_next_delivery_point()

@rpc("any_peer", "call_local", "reliable")
func request_add_money(amount: int) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = 1
	player_money[sender_id] = player_money.get(sender_id, 0) + amount
	update_money_ui.rpc_id(sender_id, player_money[sender_id])

func _on_send_button_pressed() -> void:
	var text := chat_input.text.strip_edges()
	if text == "":
		return
	chat_input.clear()
	chat_input.release_focus()
	if text.begins_with("/"):
		handle_chat_command(text)
	else:
		receive_message.rpc(multiplayer.get_unique_id(), text)

@rpc("any_peer", "call_local", "reliable")
func receive_message(sender_id: int, text: String) -> void:
	var sender_name: String = player_names.get(sender_id, "Игрок_" + str(sender_id))
	var safe_text := text.replace("[", "[lb]")
	chat_history.append_text("[color=yellow]%s:[/color] %s\n" % [sender_name, safe_text])

func handle_chat_command(cmd_text: String) -> void:
	var my_id := multiplayer.get_unique_id()
	var parts := cmd_text.split(" ", false)
	if parts.is_empty():
		return
	var command := parts.get(0).to_lower()

	match command:
		"/help":
			chat_history.append_text("[color=cyan]Команды: /me, /do, /try, /pay [ID] [сумма], /report [текст], /id[/color]\n")
		"/ahelp":
			if admin_ids.has(my_id):
				chat_history.append_text("[color=gold]Админ: /ans [ID] [текст], /tp [ID], /gethere [ID], /givemoney [ID] [сумма], /kick [ID], /makehelper [ID][/color]\n")
		"/id":
			var list_text := "Онлайн: "
			for id in player_names.keys():
				list_text += "%s (ID: %d), " % [player_names[id], id]
			chat_history.append_text("[color=cyan]" + list_text + "[/color]\n")
		"/me":
			if parts.size() >= 2:
				receive_rp_action.rpc(my_id, "me", cmd_text.substr(4))
		"/do":
			if parts.size() >= 2:
				receive_rp_action.rpc(my_id, "do", cmd_text.substr(4))
		"/try":
			if parts.size() >= 2:
				receive_rp_action.rpc(my_id, "try_ok" if randf() > 0.5 else "try_fail", cmd_text.substr(5))
		"/pay":
			if parts.size() >= 3 and parts.get(1).is_valid_int() and parts.get(2).is_valid_int():
				request_pay_player.rpc_id(1, parts.get(1).to_int(), parts.get(2).to_int())
		"/report":
			if parts.size() >= 2:
				send_report_to_server.rpc_id(1, cmd_text.substr(8))
				chat_history.append_text("[color=lime]Репорт отправлен администрации![/color]\n")
		"/ans":
			if admin_ids.has(my_id) and parts.size() >= 3 and parts.get(1).is_valid_int():
				var prefix_len := 5 + parts.get(1).length() + 1
				send_admin_answer.rpc_id(1, parts.get(1).to_int(), cmd_text.substr(prefix_len))
		"/tp":
			if admin_ids.has(my_id) and parts.size() >= 2 and parts.get(1).is_valid_int():
				admin_teleport.rpc_id(1, my_id, parts.get(1).to_int(), false)
		"/gethere":
			if admin_ids.has(my_id) and parts.size() >= 2 and parts.get(1).is_valid_int():
				admin_teleport.rpc_id(1, my_id, parts.get(1).to_int(), true)
		"/givemoney":
			if admin_ids.has(my_id) and parts.size() >= 3 and parts.get(1).is_valid_int() and parts.get(2).is_valid_int():
				admin_give_money.rpc_id(1, parts.get(1).to_int(), parts.get(2).to_int())
		"/kick":
			if admin_ids.has(my_id) and parts.size() >= 2 and parts.get(1).is_valid_int():
				admin_kick_player.rpc_id(1, parts.get(1).to_int())
		"/makehelper":
			if my_id == 1 and parts.size() >= 2 and parts.get(1).is_valid_int():
				admin_make_helper(parts.get(1).to_int())
		_:
			chat_history.append_text("[color=red]Неизвестная команда. Введите /help[/color]\n")



# 1. RP-действия теперь лучше принимать на сервере, проверять реального отправителя
# и уже от имени сервера (authority) рассылать всем в чат.
@rpc("any_peer", "call_local", "reliable")
func request_rp_action(type: String, text: String) -> void:
	if not multiplayer.is_server():
		return
	var real_sender_id := _get_real_sender_id()
	var clean_text := text.strip_edges()
	if clean_text.is_empty():
		return
	receive_rp_action.rpc(real_sender_id, type, clean_text)


@rpc("authority", "call_local", "reliable")
func receive_rp_action(sender_id: int, type: String, text: String) -> void:
	var sender_name: String = player_names.get(sender_id, "Игрок_" + str(sender_id))
	var safe_text := text.replace("[", "[lb]")
	match type:
		"me":
			chat_history.append_text("[color=violet]* %s %s[/color]\n" % [sender_name, safe_text])
		"do":
			chat_history.append_text("[color=cornflower_blue]%s (( %s ))[/color]\n" % [safe_text, sender_name])
		"try_ok":
			chat_history.append_text("[color=violet]* %s %s — [/color][color=green]Удачно[/color]\n" % [sender_name, safe_text])
		"try_fail":
			chat_history.append_text("[color=violet]* %s %s — [/color][color=red]Неудачно[/color]\n" % [sender_name, safe_text])


# 2. Передача денег
@rpc("any_peer", "call_local", "reliable")
func request_pay_player(target_id: int, amount: int) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := _get_real_sender_id()
	if amount <= 0 or sender_id == target_id or not player_money.has(target_id):
		return
	if player_money.get(sender_id, 0) < amount:
		send_sys_msg.rpc_id(sender_id, "[color=red]Недостаточно денег![/color]\n")
		return
	
	player_money[sender_id] -= amount
	player_money[target_id] += amount
	
	update_money_ui.rpc_id(sender_id, player_money[sender_id])
	update_money_ui.rpc_id(target_id, player_money[target_id])
	send_sys_msg.rpc_id(sender_id, "[color=green]Вы передали $%d игроку ID %d[/color]\n" % [amount, target_id])
	send_sys_msg.rpc_id(target_id, "[color=green]Вам передали $%d[/color]\n" % amount)


# 3. Репорты
@rpc("any_peer", "call_local", "reliable")
func send_report_to_server(report_text: String) -> void:
	if not multiplayer.is_server():
		return
	var clean_text := report_text.strip_edges()
	if clean_text.is_empty():
		return
		
	var sender_id := _get_real_sender_id()
	var sender_name: String = player_names.get(sender_id, "Игрок_" + str(sender_id))
	var safe_text := clean_text.replace("[", "[lb]")
	
	for admin_id in admin_ids:
		# Проверяем, онлайн ли админ (есть ли он в списке игроков), чтобы избежать ошибок RPC
		if player_names.has(admin_id):
			send_sys_msg.rpc_id(admin_id, "[color=tomato][РЕПОРТ] %s (ID: %d):[/color] %s\n" % [sender_name, sender_id, safe_text])


# 4. Ответ администратора
@rpc("any_peer", "call_local", "reliable")
func send_admin_answer(target_id: int, answer_text: String) -> void:
	if not multiplayer.is_server():
		return
	var admin_id := _get_real_sender_id()
	if not admin_ids.has(admin_id) or not player_names.has(target_id):
		return
		
	var admin_name: String = player_names.get(admin_id, "Администратор")
	var safe_text := answer_text.strip_edges().replace("[", "[lb]")
	if safe_text.is_empty():
		return
		
	send_sys_msg.rpc_id(target_id, "[color=gold][Ответ от %s]:[/color] %s\n" % [admin_name, safe_text])
	send_sys_msg.rpc_id(admin_id, "[color=lime]Ответ отправлен игроку ID %d[/color]\n" % target_id)


# 5. Телепорт (убран аргумент admin_id из RPC, теперь берётся реальный отправитель)
@rpc("any_peer", "call_local", "reliable")
func admin_teleport(target_id: int, pull_to_admin: bool) -> void:
	if not multiplayer.is_server():
		return
	var admin_id := _get_real_sender_id()
	if not admin_ids.has(admin_id):
		return
		
	var admin_node := get_node_or_null(str(admin_id))
	var target_node := get_node_or_null(str(target_id))
	if admin_node and target_node:
		if pull_to_admin:
			sync_player_position.rpc(target_id, admin_node.global_position + Vector3(2, 0, 0))
		else:
			sync_player_position.rpc(admin_id, target_node.global_position + Vector3(2, 0, 0))


@rpc("authority", "call_local", "reliable")
func sync_player_position(player_id: int, new_pos: Vector3) -> void:
	var p := get_node_or_null(str(player_id))
	if p:
		p.global_position = new_pos


# 6. Выдача денег
@rpc("any_peer", "call_local", "reliable")
func admin_give_money(target_id: int, amount: int) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := _get_real_sender_id()
	if admin_ids.has(sender_id) and player_money.has(target_id) and amount != 0:
		# max(0, ...) не даст балансу игрока уйти в минус, если админ введёт отрицательное число
		player_money[target_id] = max(0, player_money[target_id] + amount)
		update_money_ui.rpc_id(target_id, player_money[target_id])

@rpc("any_peer", "call_local", "reliable")
func admin_kick_player(target_id: int) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = 1
	if admin_ids.has(sender_id) and target_id != 1 and multiplayer.get_peers().has(target_id):
		multiplayer.disconnect_peer(target_id)

func admin_make_helper(target_id: int) -> void:
	if player_names.has(target_id) and not admin_ids.has(target_id):
		admin_ids.append(target_id)
		sync_admin_list.rpc(admin_ids)
		send_sys_msg.rpc_id(target_id, "[color=gold]Вы назначены игровым помощником! Введите /ahelp[/color]\n")

@rpc("authority", "call_local", "reliable")
func sync_admin_list(updated_admins: Array[int]) -> void:
	admin_ids = updated_admins

@rpc("authority", "call_local", "reliable")
func send_sys_msg(bbcode_text: String) -> void:
	chat_history.append_text(bbcode_text)
func _get_real_sender_id() -> int:
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		# Возвращает реальный уникальный ID текущего пира (для хоста это всегда 1)
		return multiplayer.get_unique_id()
	return id

extends Area3D

@export var job_btn: Button # Лучше назначить кнопку прямо в инспекторе, если она в одной сцене

func _ready() -> void:
	# Если кнопку не назначили в инспекторе, ищем её в дереве
	if not job_btn:
		await get_tree().process_frame
		_find_job_button()
	
	if job_btn:
		job_btn.visible = false
	else:
		push_warning("Кнопка курьера не найдена!")

	# Подключаем сигналы ТОЛЬКО после того, как нашли кнопку
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	# Проверяем, не стоит ли игрок уже внутри зоны при старте
	for body in get_overlapping_bodies():
		_on_body_entered(body)

func _find_job_button() -> void:
	# Совет: лучше добавить кнопке группу (например, "courier_btn") и искать через get_first_node_in_group()
	for node in get_tree().root.find_children("*", "Button", true, false):
		var btn := node as Button
		if "курьер" in btn.text.to_lower() or "courier" in btn.name.to_lower():
			job_btn = btn
			break

func _is_local_player(body: Node3D) -> bool:
	if not body is CharacterBody3D:
		return false
	# Проверяем, что игра в сети и это именно локальный игрок (наш peer_id)
	if multiplayer.has_multiplayer_peer():
		return body.get_multiplayer_authority() == multiplayer.get_unique_id()
	return true

func _on_body_entered(body: Node3D) -> void:
	if _is_local_player(body) and job_btn:
		job_btn.visible = true

func _on_body_exited(body: Node3D) -> void:
	if _is_local_player(body) and job_btn:
		if not "завершить" in job_btn.text.to_lower():
			job_btn.visible = false

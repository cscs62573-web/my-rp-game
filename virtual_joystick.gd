extends Control

@export var max_radius: float = 65.0
@export var deadzone: float = 0.15

var touch_idx: int = -1
var touch_start: Vector2 = Vector2.ZERO
var knob_pos: Vector2 = Vector2.ZERO

func _draw() -> void:
	var c := size * 0.5
	draw_circle(c, max_radius + 12.0, Color(0.1, 0.12, 0.16, 0.45))
	draw_arc(c, max_radius + 12.0, 0, TAU, 48, Color(1, 1, 1, 0.35), 2.5)
	draw_circle(c + knob_pos, 26.0, Color(1, 1, 1, 0.85))

# Начало касания ловим только внутри области джойстика
func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed and touch_idx == -1:
		touch_idx = event.index
		# Запоминаем место, куда лег палец (чтобы персонаж не дергался при касании)
		touch_start = event.position
		accept_event()

# Ведение и отпускание пальца ловим глобально, чтобы стик не залипал за краем экрана
func _input(event: InputEvent) -> void:
	if touch_idx == -1:
		return
		
	if event is InputEventScreenDrag and event.index == touch_idx:
		# Переводим глобальные координаты экрана в локальные координаты Control
		var local_pos : Vector2 = make_input_local(event).position
		_update_knob(local_pos)
	elif event is InputEventScreenTouch and not event.pressed and event.index == touch_idx:
		_reset_knob()

func _update_knob(pos: Vector2) -> void:
	if max_radius <= 0.0:
		return
	var delta := pos - touch_start
	knob_pos = delta.limit_length(max_radius)
	var dir := knob_pos / max_radius
	
	_set_action("ui_left", -dir.x)
	_set_action("ui_right", dir.x)
	_set_action("ui_up", -dir.y)
	_set_action("ui_down", dir.y)
	queue_redraw()

func _reset_knob() -> void:
	touch_idx = -1
	knob_pos = Vector2.ZERO
	for a in ["ui_left", "ui_right", "ui_up", "ui_down"]:
		if Input.is_action_pressed(a):
			Input.action_release(a)
	queue_redraw()

func _set_action(action: String, val: float) -> void:
	if val > deadzone:
		Input.action_press(action, clampf(val, 0.0, 1.0))
	elif Input.is_action_pressed(action):
		Input.action_release(action)

# Сбрасываем ввод, если джойстик скрыли или удалили во время игры
func _exit_tree() -> void:
	_reset_knob()

extends CharacterBody3D

const SPEED := 6.0
const JUMP_VELOCITY := 4.5
const MOUSE_SENSITIVITY := 0.005

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var touch_look_index: int = -1
var last_pos: Vector3 = Vector3.ZERO
@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
# Укажите здесь путь к вашей 3D-модели/скелету, чтобы поворачивать только её, а не камеру
@onready var visual_model: Node3D = $Visuals
@onready var left_leg: Node3D = $Visuals/LeftLeg
@onready var right_leg: Node3D = $Visuals/RightLeg
@onready var left_arm: Node3D = $Visuals/LeftArm
@onready var right_arm: Node3D = $Visuals/RightArm
var walk_time: float = 0.0

func _ready() -> void:
	# Упрощенная запись включения камеры для владельца
	camera.current = is_multiplayer_authority()

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
		
	if event is InputEventScreenTouch:
		if event.pressed and event.position.x > get_viewport().get_visible_rect().size.x * 0.45:
			touch_look_index = event.index
		elif not event.pressed and event.index == touch_look_index:
			touch_look_index = -1
			
	elif event is InputEventScreenDrag and event.index == touch_look_index:
		camera_pivot.rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x - event.relative.y * MOUSE_SENSITIVITY, -0.8, 0.6)

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	# Гравитация
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Добавлен прыжок (убедитесь, что действие "jump" настроено в Input Map)
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Движение
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	
	# Сначала вычисляем вектор, обнуляем Y и только ПОТОМ нормализуем
	var direction := camera_pivot.global_transform.basis * Vector3(input_dir.x, 0, input_dir.y)
	direction.y = 0
	direction = direction.normalized()

	if direction.length() > 0.01:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
		
		# Поворачиваем только модель, чтобы не сбивать угол обзора камеры
		var target_angle := atan2(direction.x, direction.z)
		visual_model.rotation.y = lerp_angle(visual_model.rotation.y, target_angle, 10.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()
		# Вычисляем реальную горизонтальную скорость по смещению позиции (работает и в мультиплеере)
	var current_pos := global_position
	var horizontal_displacement := Vector2(current_pos.x - last_pos.x, current_pos.z - last_pos.z).length()
	var speed := horizontal_displacement / delta if delta > 0.0 else 0.0
	last_pos = current_pos

	var smooth := clampf(12.0 * delta, 0.0, 1.0)

	# Анимируем ходьбу только на земле (если персонаж CharacterBody3D)
	if speed > 0.2 and is_on_floor():
		# Частота шагов зависит от скорости движения
		walk_time += delta * clampf(speed * 2.0, 6.0, 14.0)
		var swing := sin(walk_time)
		
		left_leg.rotation.x = lerp(left_leg.rotation.x, swing * 0.6, smooth)
		right_leg.rotation.x = lerp(right_leg.rotation.x, -swing * 0.6, smooth)
		left_arm.rotation.x = lerp(left_arm.rotation.x, -swing * 0.5, smooth)
		right_arm.rotation.x = lerp(right_arm.rotation.x, swing * 0.5, smooth)
	else:
		walk_time = 0.0
		left_leg.rotation.x = lerp(left_leg.rotation.x, 0.0, smooth)
		right_leg.rotation.x = lerp(right_leg.rotation.x, 0.0, smooth)
		left_arm.rotation.x = lerp(left_arm.rotation.x, 0.0, smooth)
		right_arm.rotation.x = lerp(right_arm.rotation.x, 0.0, smooth)

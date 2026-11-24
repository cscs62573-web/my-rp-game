extends Label3D

func _process(_delta: float) -> void:
	var p := get_parent()
	if not p:
		visible = false
		return
		
	var raw_lvl = p.get("admin_level")
	var lvl: int = raw_lvl if raw_lvl != null else 0
	
	# Проверка на имя "1" (ID хоста в мультиплеере) или уровень админа >= 2
	if str(p.name) == "1" or lvl >= 2:
		text = "[ADMIN]"
		modulate = Color(1.0, 0.25, 0.25)
		visible = true
	elif lvl == 1:
		text = "[HELPER]"
		modulate = Color(0.2, 0.95, 0.45)
		visible = true
	else:
		visible = false

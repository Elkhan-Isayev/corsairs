## Day/night cycle: drives the sun, sky, and fog of any 3D scene from the
## global clock (Game.time_of_day, 0..24). `look` carries the local weather
## preset (colors, fog, overcast) so every island keeps its own character
## while the light wheels overhead.
extends RefCounted


static func apply(sun: DirectionalLight3D, env: Environment, hour: float, look: Dictionary = {}) -> void:
	if sun == null or env == null:
		return
	# 0 at night, 1 at noon.
	var day_k := clampf(sin((hour - 6.0) / 12.0 * PI), 0.0, 1.0)
	var overcast: float = look.get("overcast", 0.0)
	var base_energy: float = look.get("sun_energy", 1.4)

	if day_k > 0.02:
		# The sun sweeps east to west, low and red near dawn and dusk.
		var az := lerpf(95.0, -95.0, clampf((hour - 6.0) / 12.0, 0.0, 1.0))
		sun.rotation_degrees = Vector3(-lerpf(8.0, 62.0, day_k), az, 0)
		var warm := 1.0 - day_k
		sun.light_color = Color(look.get("sun_color", "fff2d8")).lerp(Color(1.0, 0.62, 0.38), warm * 0.7)
		sun.light_energy = base_energy * (0.25 + 0.75 * day_k) * (1.0 - overcast * 0.55)
	else:
		# Moonlight: dim, cold, from the other quarter.
		sun.rotation_degrees = Vector3(-38, -60, 0)
		sun.light_color = Color(0.62, 0.72, 0.95)
		sun.light_energy = 0.14

	var sky_mat := env.sky.sky_material as ProceduralSkyMaterial
	if sky_mat == null:
		return
	var top_day := Color(look.get("sky_top", "2f6698"))
	var hor_day := Color(look.get("horizon", "e8d8b8"))
	if overcast > 0.0:
		top_day = top_day.lerp(Color("6a7480"), overcast)
		hor_day = hor_day.lerp(Color("9aa2a8"), overcast)
	# A burning horizon right around sunrise and sunset.
	var edge := clampf(1.0 - absf(day_k - 0.18) * 6.0, 0.0, 1.0)
	hor_day = hor_day.lerp(Color("f2a05c"), edge * (1.0 - overcast))
	sky_mat.sky_top_color = Color("0a1226").lerp(top_day, day_k)
	sky_mat.sky_horizon_color = Color("1c2740").lerp(hor_day, day_k)
	sky_mat.ground_horizon_color = sky_mat.sky_horizon_color
	env.fog_light_color = Color("10141f").lerp(Color(look.get("fog_color", "dcc9a6")), day_k)
	env.fog_density = float(look.get("fog", 0.0012)) * (1.0 + (1.0 - day_k) * 0.6)

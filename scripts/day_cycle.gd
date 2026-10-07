## Day/night cycle: drives the sun, sky, and fog of any 3D scene from the
## global clock (Game.time_of_day, 0..24). `look` carries the local weather
## preset (colors, fog, overcast) so every island keeps its own character
## while the light wheels overhead.
extends RefCounted

const SKY_CLEAR := "res://assets/sky/kloofendal_48d_partly_cloudy_puresky.hdr"
const SKY_OVERCAST := "res://assets/sky/kloofendal_overcast_puresky.hdr"


## Photographic sky (Poly Haven HDRI) by day, the procedural sky at night,
## plus the desktop-renderer extras: SSAO, sky-lit ambient and reflections.
## Call once right after a scene builds its Environment.
static func upgrade(env: Environment, look: Dictionary = {}) -> void:
	var night := env.sky.sky_material
	var pano := PanoramaSkyMaterial.new()
	pano.panorama = load(SKY_OVERCAST if float(look.get("overcast", 0.0)) > 0.4 else SKY_CLEAR)
	env.set_meta("night_sky", night)
	env.set_meta("day_sky", pano)
	env.fog_sky_affect = 0.12
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.ssil_enabled = true
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.04
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.06
	env.adjustment_contrast = 1.05


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

	# By day the photographed sky, brightening with the sun.
	if env.has_meta("day_sky"):
		var pano: PanoramaSkyMaterial = env.get_meta("day_sky")
		if day_k > 0.12:
			env.sky.sky_material = pano
			pano.energy_multiplier = lerpf(0.35, 1.0, day_k) * (1.0 - overcast * 0.2)
			env.fog_light_color = Color(look.get("fog_color", "dcc9a6")).lerp(Color("b8c8d8"), 0.5)
			env.fog_density = float(look.get("fog", 0.0012)) * 0.6
			return
		env.sky.sky_material = env.get_meta("night_sky")
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

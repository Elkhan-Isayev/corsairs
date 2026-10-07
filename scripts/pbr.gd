## Photo-scanned PBR materials (Poly Haven, CC0) for the procedural town:
## colour, normal and AO/roughness/metal maps projected in world space, so
## boxes of any size tile at real scale. Materials are cached per look.
extends RefCounted

const DIR := "res://assets/textures/%s/%s_%s.jpg"

static var _cache := {}


## `meters`: how many metres one texture tile covers; `tint` multiplies the colour.
static func mat(id: String, meters := 2.0, tint := Color.WHITE) -> ORMMaterial3D:
	var key := "%s|%s|%s" % [id, meters, tint.to_html()]
	if _cache.has(key):
		return _cache[key]
	var m := ORMMaterial3D.new()
	m.albedo_texture = load(DIR % [id, id, "diff"])
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load(DIR % [id, id, "nor_gl"])
	m.orm_texture = load(DIR % [id, id, "arm"])
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / meters
	m.uv1_triplanar_sharpness = 4.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_cache[key] = m
	return m

## Open sea: geometry of the sailable world map (the "globe" view).
## Pure math over World's chart — positions, docking, day pacing.
extends RefCounted

const World := preload("res://core/world.gd")

## World units per nautical mile of the 1000x800 chart.
const SCALE := 2.0
## Sailing this many units advances the calendar by one day
## (keeps the pace of the old instant voyages: 120 miles a day).
const DAY_DISTANCE := 120.0 * SCALE
## Docking becomes available this close to an island's anchorage.
const ARRIVAL_RADIUS := 90.0
## Chance a new sail appears on the horizon with each day at sea.
const ENCOUNTER_CHANCE_PER_DAY := 0.45
## Sailable rectangle (chart plus a margin of open water).
const BOUNDS := Rect2(-150.0, -150.0, 1000.0 * SCALE + 300.0, 800.0 * SCALE + 300.0)


static func island_pos(id: String) -> Vector3:
	var p: Array = World.island(id)["pos"]
	return Vector3(float(p[0]) * SCALE, 0.0, float(p[1]) * SCALE)


static func map_center() -> Vector3:
	return Vector3(500.0 * SCALE, 0.0, 400.0 * SCALE)


static func nearest_island(pos: Vector3) -> String:
	var best := ""
	var best_d := INF
	for id in World.island_ids():
		var d := island_pos(id).distance_to(pos)
		if d < best_d:
			best_d = d
			best = id
	return best


## Island the ship could dock at right now, or "" if none is close enough.
static func dockable_island(pos: Vector3) -> String:
	var id := nearest_island(pos)
	if id != "" and island_pos(id).distance_to(pos) <= ARRIVAL_RADIUS:
		return id
	return ""


## Solid footprint of an island (beach included) — ships cannot enter it.
## Always smaller than ARRIVAL_RADIUS, so the docking prompt appears
## before the hull ever touches the sand.
static func island_radius(id: String) -> float:
	return 62.0 + float(World.island(id)["tier"]) * 6.0


## Keep a ship out of every island: push the point back to open water.
static func push_out_of_islands(pos: Vector3) -> Vector3:
	for id in World.island_ids():
		var isl := island_pos(id)
		var away := pos - isl
		away.y = 0.0
		var r := island_radius(id)
		if away.length() < r:
			if away.length() < 0.01:
				away = Vector3(1, 0, 0)
			var fixed := isl + away.normalized() * r
			pos = Vector3(fixed.x, pos.y, fixed.z)
	return pos


static func clamp_to_bounds(pos: Vector3) -> Vector3:
	return Vector3(
		clampf(pos.x, BOUNDS.position.x, BOUNDS.end.x),
		pos.y,
		clampf(pos.z, BOUNDS.position.y, BOUNDS.end.y))


## Where a ship leaving `island_id` appears: just outside the dock radius,
## on the side facing the middle of the map (always open water).
static func departure_pos(island_id: String) -> Vector3:
	var isl := island_pos(island_id)
	var dir := (map_center() - isl)
	dir.y = 0.0
	if dir.length() < 1.0:
		dir = Vector3(1, 0, 0)
	return clamp_to_bounds(isl + dir.normalized() * (ARRIVAL_RADIUS + 35.0))


## Heading (degrees, 0 = north/-Z) that points a departing ship away from its island.
static func departure_heading(island_id: String) -> float:
	var isl := island_pos(island_id)
	var d := departure_pos(island_id) - isl
	return wrapf(rad_to_deg(atan2(d.x, -d.z)), 0.0, 360.0)

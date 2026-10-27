extends Node
## The level's helpers (the autoload `Level`): data/interact.json read once, not by every script that wants it; and
## moving things without costing a frame. Anything moved, or a material touched, and every light with shadows that
## sees it draws them again: a door eased toward shut for ever, a stool's seat set to the angle it's already at, did
## that every frame. From JellyVault's level.gd.

var _data := {}


func data() -> Dictionary:  # data/interact.json (once: it's 12,000 lines)
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string("res://data/interact.json"))
	return _data


static func ease_to(at: float, to: float, k: float) -> float:  # a step of an ease toward to that lands on it, rather than creeping at it for ever
	return at + (to - at) * minf(1.0, k) if absf(to - at) > 0.001 else to


static func put(n: Node3D, path: NodePath, v: float) -> void:  # n's rotation:y (say) set to v, only if that moves it
	if n.get_indexed(path) != v:
		n.set_indexed(path, v)


static func texture_of(m: MeshInstance3D) -> String:  # its first surface's picture's file name ("" if none): whether or not room.gd has made it over yet
	var mat := m.mesh.surface_get_material(0) if m.mesh and m.mesh.get_surface_count() else null
	var tex: Texture2D = mat.albedo_texture if mat is BaseMaterial3D else mat.get_shader_parameter("tex") if mat is ShaderMaterial else null
	return tex.resource_path.get_file() if tex != null else ""

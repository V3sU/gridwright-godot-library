@tool
extends EditorPlugin
## Gridwright Library: adds the "Gridwright" dock.

const DockScene := preload("dock.tscn")
const DockScript := preload("dock.gd")

var dock: DockScript


func _enter_tree() -> void:
	dock = DockScene.instantiate() as DockScript
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)
	if has_method("set_dock_tab_icon"):
		call("set_dock_tab_icon", dock, DockScript.make_icon(int(16 * EditorInterface.get_editor_scale())))
	dock.start.call_deferred()


func _exit_tree() -> void:
	if is_instance_valid(dock):
		dock.shutdown()
		remove_control_from_docks(dock)
		dock.queue_free()
	dock = null

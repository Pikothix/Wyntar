extends SceneTree
## Byte-level comparison of the Phase 1F captures against the matching Phase
## 1E fixtures. Geometry equivalence is validated separately from animated or
## renderer-sensitive raster differences.

const OUTPUT_PATH := "res://screenshots/phase1f_visual_comparison.json"


func _initialize() -> void:
	var directory := DirAccess.open("res://screenshots")
	var results: Array[Dictionary] = []
	var exact_matches: int = 0
	for file_name in directory.get_files():
		if not file_name.begins_with("phase1f_") or not file_name.ends_with(".png"):
			continue
		var baseline_name: String = file_name.replace("phase1f_", "phase1e_")
		if not FileAccess.file_exists("res://screenshots/%s" % baseline_name):
			continue
		var current := Image.load_from_file("res://screenshots/%s" % file_name)
		var baseline := Image.load_from_file("res://screenshots/%s" % baseline_name)
		var current_bytes: PackedByteArray = current.get_data()
		var baseline_bytes: PackedByteArray = baseline.get_data()
		var different_bytes: int = 0
		var maximum_channel_delta: int = 0
		for index in range(mini(current_bytes.size(), baseline_bytes.size())):
			var delta: int = absi(int(current_bytes[index]) - int(baseline_bytes[index]))
			if delta > 0:
				different_bytes += 1
				maximum_channel_delta = maxi(maximum_channel_delta, delta)
		var exact: bool = (
			current.get_size() == baseline.get_size()
			and current.get_format() == baseline.get_format()
			and different_bytes == 0)
		if exact:
			exact_matches += 1
		results.append({
			"phase1f": file_name,
			"phase1e": baseline_name,
			"exact": exact,
			"different_channel_bytes": different_bytes,
			"maximum_channel_delta": maximum_channel_delta,
		})
	var output := {
		"pair_count": results.size(),
		"exact_matches": exact_matches,
		"non_exact_matches": results.size() - exact_matches,
		"pairs": results,
	}
	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "\t"))
	file.close()
	print("PHASE1F_VISUAL_COMPARE: %s" % JSON.stringify(output))
	quit(0)

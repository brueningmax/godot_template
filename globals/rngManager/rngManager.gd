extends Node
class_name RNGManager

# Human-readable seed (e.g. "1700000000-123456")
var seed_string: String = ""

# 64-bit seed derived from seed_string (stable across platforms)
var seed_u64: int = 0

# Cached RNG streams: key -> RandomNumberGenerator
var _streams: Dictionary = {}


func _ready() -> void:
	# If nobody seeded us explicitly, seed randomly at startup.
	if seed_string == "":
		randomize_seed()


# --- Public API -------------------------------------------------------------

func randomize_seed() -> void:
	set_seed(_generate_random_seed())


func set_seed(custom_seed: String) -> void:
	seed_string = custom_seed
	seed_u64 = keyed_u32(seed_string)
	_streams.clear()


func get_seed() -> String:
	return seed_string


func get_stream(key: String) -> RngStream:
	if _streams.has(key):
		return _streams[key]

	var custom_seed := _derive_seed(key)
	var stream := RngStream.new(custom_seed)
	_streams[key] = stream
	return stream

func get_unstable_stream_for(call_owner: Object, stream_name: String = "") -> RngStream:
	## Unique per instance *within a run*
	## NOTE: not stable across runs → good for "independent randomness per copy",
	## not good for replays/ghost determinism unless you use the stable version below.
	var base := _owner_label(call_owner)
	var key := base
	if stream_name != "":
		key += "|" + stream_name
	return get_stream(key)


func get_seeded_stream_for(call_owner: Object, stable_id: String, stream_name: String = "") -> RngStream:
	## Deterministic across runs if stable_id is deterministic.
	## Example stable_id: "chunk:42:enemy:3" or saved UUID.
	var base := _owner_label(call_owner)
	var key := base + "|stable:" + stable_id
	if stream_name != "":
		key += "|" + stream_name
	return get_stream(key)


func _owner_label(call_owner: Object) -> String:
	# Try to build a readable key component.
	# Works for Nodes and plain Objects. Includes class + instance_id.
	var cls := call_owner.get_class()

	# If it's a script with class_name, this will often be more descriptive
	var script : Script = call_owner.get_script()
	if script != null:
		# Resource path is stable-ish and helps debugging
		cls = "%s@%s" % [cls, str(script.resource_path)]

	var id := str(call_owner.get_instance_id())
	return "%s#%s" % [cls, id]
	
func reset_all_streams() -> void:
	_streams.clear()

# --- Order-independent randomness (keyed) ----------------------------------
# Same seed + same key => same result, regardless of when/how often called.

func keyed_u32(key: String) -> int:
	return _fnv1a_32(seed_string + "|" + key)


func keyed_float_01(key: String) -> float:
	# Map to [0, 1) using 53 bits (safe precision for float mantissa)
	var x: int = keyed_u32(key)
	var mantissa: int = x & ((1 << 53) - 1)
	return float(mantissa) / float(1 << 53)


func keyed_int_range(key: String, min_val: int, max_val: int) -> int:
	if max_val < min_val:
		var t = min_val
		min_val = max_val
		max_val = t

	var span := max_val - min_val + 1
	var x := keyed_u32(key)
	# Modulo bias is usually fine for gameplay randomness; if you want,
	# we can implement rejection sampling later.
	return min_val + int(posmod(x, span))


# --- Internals --------------------------------------------------------------

func _generate_random_seed() -> String:
	return str(Time.get_unix_time_from_system()) + "-" + str(Time.get_ticks_usec())


func _fnv1a_32(s: String) -> int:
	var data: PackedByteArray = s.to_utf8_buffer()
	var hash_int: int = 2166136261 # 0x811C9DC5
	var prime: int = 16777619  # 0x01000193

	for b in data:
		hash_int = hash_int ^ int(b)
		# Keep it in 32-bit range
		hash_int = int((hash_int * prime) & 0x7FFFFFFF) # keep positive signed int

	return hash_int


func _derive_seed(key: String) -> int:
	# Deterministic per key, based on current seed_string
	return _fnv1a_32(seed_string + "|" + key)

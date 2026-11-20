extends GutTest
## RngManager: seeding, keyed values, streams.


func before_each() -> void:
	RngManager.set_seed("abc")


func test_empty_seed_picks_random_seed() -> void:
	RngManager.set_seed("")
	var a := RngManager.get_seed()
	RngManager.set_seed("   ")
	var b := RngManager.get_seed()
	assert_ne(a, "", "empty seed is replaced")
	assert_ne(b, "", "whitespace seed is replaced")
	assert_ne(a, b, "two random seeds differ")


func test_generated_seed_is_8_hex_chars() -> void:
	RngManager.randomize_seed()
	var s := RngManager.get_seed()
	assert_eq(s.length(), 8)
	assert_true(s.is_valid_hex_number(), "seed '%s' is hex" % s)


func test_text_seed_is_kept() -> void:
	RngManager.set_seed("my run")
	assert_eq(RngManager.get_seed(), "my run")


func test_keyed_values_are_deterministic() -> void:
	var f := RngManager.keyed_float_01("x")
	var i := RngManager.keyed_int_range("chest:3", 1, 6)
	RngManager.set_seed("other")
	RngManager.set_seed("abc")
	assert_eq(RngManager.keyed_float_01("x"), f)
	assert_eq(RngManager.keyed_int_range("chest:3", 1, 6), i)


func test_keyed_values_depend_on_seed() -> void:
	var a := RngManager.keyed_u32("x")
	RngManager.set_seed("abd")
	assert_ne(RngManager.keyed_u32("x"), a)


func test_keyed_float_is_uniform_in_unit_interval() -> void:
	var buckets := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	var total := 0.0
	var out_of_range := 0
	for i in 10000:
		var f := RngManager.keyed_float_01("k%d" % i)
		if f < 0.0 or f >= 1.0:
			out_of_range += 1
			continue
		buckets[int(f * 10.0)] += 1
		total += f
	assert_eq(out_of_range, 0, "all values in [0, 1)")
	assert_almost_eq(total / 10000.0, 0.5, 0.02, "mean")
	for count in buckets:
		assert_between(count, 850, 1150, "bucket count")


func test_keyed_int_range_covers_range_evenly() -> void:
	var counts := {}
	for i in 6000:
		var v := RngManager.keyed_int_range("d%d" % i, 1, 6)
		counts[v] = counts.get(v, 0) + 1
	assert_eq(counts.keys().size(), 6, "all of 1..6 appear")
	for v in counts:
		assert_between(v, 1, 6)
		assert_between(counts[v], 850, 1150, "count for %d" % v)


func test_keyed_int_range_swaps_reversed_bounds() -> void:
	assert_between(RngManager.keyed_int_range("r", 6, 1), 1, 6)


func test_streams_reproduce_after_reseed() -> void:
	var first := _draw("loot", 5)
	RngManager.set_seed("abc")
	assert_eq(_draw("loot", 5), first)


func test_streams_are_independent_per_key() -> void:
	var loot_alone := _draw("loot", 5)
	RngManager.set_seed("abc")
	_draw("map", 20)  # drawing from another stream must not shift "loot"
	assert_eq(_draw("loot", 5), loot_alone)


func test_seeded_stream_ignores_instance_id() -> void:
	var a: Node = autofree(Node.new())
	var b: Node = autofree(Node.new())
	var va := RngManager.get_seeded_stream_for(a, "enemy:3").rand_int(0, 1 << 30)
	RngManager.reset_all_streams()
	var vb := RngManager.get_seeded_stream_for(b, "enemy:3").rand_int(0, 1 << 30)
	assert_eq(va, vb)


func test_unstable_streams_differ_per_instance() -> void:
	var a: Node = autofree(Node.new())
	var b: Node = autofree(Node.new())
	assert_ne(RngManager.get_unstable_stream_for(a), RngManager.get_unstable_stream_for(b))


func test_known_value_is_stable_across_versions() -> void:
	# Pins the hash. If this fails, every saved seed produces different results.
	RngManager.set_seed("cross-run")
	assert_eq(RngManager.keyed_u32("a"), 4287114852)


func _draw(stream: String, n: int) -> Array:
	var out := []
	for i in n:
		out.append(RngManager.get_stream(stream).rand_int(0, 1000))
	return out

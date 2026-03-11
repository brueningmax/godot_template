class_name RngStream

var _rng: RandomNumberGenerator

func _init(custom_seed: int) -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = custom_seed


func rand_int(min_val: int, max_val: int) -> int:
	return _rng.randi_range(min_val, max_val)

func rand_float() -> float:
	return _rng.randf()


func get_random_element(array: Array):
	if array.is_empty():
		return null
	return array[_rng.randi_range(0, array.size() - 1)]


func shuffle_in_place(array: Array) -> void:
	for i in range(array.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		if i != j:
			var tmp = array[i]
			array[i] = array[j]
			array[j] = tmp

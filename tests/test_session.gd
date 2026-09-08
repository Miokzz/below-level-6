extends SceneTree

var game: Node
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)
	print(("PASS " if condition else "FAIL ") + description)

func frames(count: int) -> void:
	for _index in range(count): await process_frame

func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.saves.path = "user://test_session_checkpoint.json"
	game.return_to_menu()
	check(paused and game.hud.view == "main", "Main menu opens and suspends the world")
	game.start_new_game()
	await frames(180)
	check(game.stage == 0 and game.player.global_position.y > 1.0, "Introduction physically descends inside the shaft")
	game._pause()
	var paused_y: float = game.player.global_position.y
	await frames(20)
	check(is_equal_approx(paused_y, game.player.global_position.y), "Pause freezes cabin and passenger")
	game._resume()
	await frames(1100)
	check(game.stage == 1 and not game.player.look_only, "Introduction completes, doors open and movement unlocks")
	check(game.saves.can_continue(), "First arrival writes a resumable checkpoint")
	game._pause()
	game.hud.show_settings()
	check(game.hud.handle_back() and game.hud.view == "pause", "Settings escape returns to pause")
	game._resume()
	game.player.teleport(game.level.markers.operations)
	await frames(3)
	game.player.camera.look_at(game.level.interactables.operations.global_position)
	game.player._refresh_interaction_target()
	check(game.player.interaction_target == game.level.interactables.operations, "Operations is reachable by the controller ray")
	game.player.interacted.emit(game.player.interaction_target)
	check(game.stage == 2 and game.modal and paused, "Operations opens actual work order and starts repair progression")
	game.hud.dismiss_modal()
	check(not paused and not game.modal and not game.player.locked, "Closing a document restores controls")
	game.return_to_menu()
	game.continue_game()
	check(game.stage == 2 and game.playing and not paused, "Continue reloads the saved work order at a safe landing")
	game.start_new_game()
	await frames(90)
	game.return_to_menu()
	await frames(5)
	game.start_new_game()
	await frames(1300)
	check(game.stage == 1 and game.player.is_physics_processing(), "Restart cancels old elevator coroutine and restores passenger physics")
	check(not game.level.is_elevator_moving(), "No orphaned elevator journey remains after restart")
	game.return_to_menu()
	paused = false
	root.remove_child(game)
	game.free()
	await frames(3)
	for suffix in ["", ".backup", ".tmp"]:
		var path: String = "user://test_session_checkpoint.json" + suffix
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	print("SESSION_VALIDATION: %s / %d assertions" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(1 if failures else 0)

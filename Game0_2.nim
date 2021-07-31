import Engine0_2
import tables, arraymancer, strformat
import raylib, rayutils

type
    
    Visual_settings = object
        game_field_offset_left: float
        game_field_offset_top: float
        game_field_units_wide: int
        game_field_board_padding_left: int
        window_height: int
        window_width: int
    Control_settings = object
        keybinds: Table[KeyboardKey, Action]
    Game_Play_settings = object
        ghost: bool  # no purpose tbh. Could just ask for a ghost version
    Settings = object
        visuals: Visual_settings
        controls: Control_settings
        play: Game_Play_settings

var ui*: Settings

proc set_ui_settings() =
    # Todo check for file later. I'll just use defaults for now.
    ui.visuals.game_field_offset_left = 0.1
    ui.visuals.game_field_offset_top = 0.1
    ui.visuals.game_field_units_wide = 10 + rules.width  # todo change the order of calling settings and game to allow loading later
    ui.visuals.game_field_board_padding_left = 5
    ui.visuals.window_height = 900
    ui.visuals.window_width = 800
    # only debug hard_left, hard_right, and lock left in
    ui.controls.keybinds = {KEY_J: Action.left, KEY_K: Action.down, KEY_L: Action.right, 
    KEY_D: Action.counter_clockwise, KEY_F: Action.clockwise, KEY_A: Action.hold, KEY_SPACE: Action.hard_drop,
    KEY_RIGHT: Action.hard_right, KEY_LEFT: Action.hard_left, KEY_ENTER: Action.lock, KEY_R: Action.reset,
    KEY_S: Action.oneeighty}.toTable()


proc draw_game() =
    # We assume were in drawing mode
    let v = ui.visuals
    let size = toInt((1 - v.game_field_offset_left * 2) * v.window_width / v.game_field_units_wide)
    let x_offset = toInt(v.game_field_offset_left * v.window_width)
    let y_offset = toInt(v.game_field_offset_top * v.window_height)
    let grid_lines = 1
    
    proc draw_square(x: int, y: int, col: Color) =
        # This assumes drawing in the game field with a finness of the min size
        DrawRectangle(x * (size + grid_lines) + x_offset, y * (size + grid_lines) + y_offset, size, size, col)

    var ghost_board: Tensor[int]
    if settings.play.ghost:
        let movement = get_new_location(Action.hard_drop)
        let new_loc = test_location_custom(movement[0], movement[1], movement[2], game.state.active, game.board)
        ghost_board = new_loc[0] - game.board
        

    # Draw the game board
    let loc = test_current_location()[0]
    var val: int
    var col: Color
    for a in 0 ..< rules.height:
        for b in 0 ..< rules.width:
            val = loc[a, b]
            if val == 1:
                col = makecolor(200, 0, 0)
            elif settings.play.ghost and ghost_board[a, b] == 1:
                col = makecolor(100, 0, 0)
            else:
                col = makecolor(50, 50, 50)
            # echo fmt"Drawing {a}, {b} with {col}, {makerect(b * size + x_offset, a * size + y_offset, size, size)}"
            draw_square(b + v.game_field_board_padding_left, a, col)

    # Draw the queue
    var off_y = 0
    var mino: Mino
    for a in 0 ..< rules.visible_queue_len:
        mino = get_mino($game.state.queue[a])
        for y in 0 ..< mino.rotation_shapes[0].shape.shape[0]:
            for x in 0 ..< mino.rotation_shapes[0].shape.shape[1]:
                if mino.rotation_shapes[0].shape[y, x] == 1:
                    col = makecolor(200, 0, 0)
                else:
                    col = makecolor(50, 50, 50)
                draw_square(ui.visuals.game_field_board_padding_left + rules.width + 1 + x, a * 5 + y, col)
    
    if game.state.hold != "-":
        mino = get_mino(game.state.hold)
        for y in 0 ..< mino.rotation_shapes[0].shape.shape[0]:
            for x in 0 ..< mino.rotation_shapes[0].shape.shape[1]:
                if mino.rotation_shapes[0].shape[y, x] == 1:
                    col = makecolor(200, 0, 0)
                else:
                    col = makecolor(50, 50, 50)
                draw_square(x, y, col)
        


proc gameLoop* =
    
    InitWindow(ui.visuals.window_width, ui.visuals.window_height, "Hydris")
    SetTargetFPS(60)

    const restart_on_death = true
    # var pressed: seq[Key_event]
    # var done = false
    # var key_buffer: int
    # var del_count: int
    # var new_key: Key_event
    
    frame_step(@[])
    while game.state.game_active and not WindowShouldClose():
        DrawFPS(10, 10)

        # Check for game over
        var current = test_current_location()
        if not current[1] or current[2]:
            if restart_on_death:
                # echo fmt"{game.state.active_x} {current[1]} {current[2]}"
                newGame()
                startGame()
                fix_queue()
                echo "COLLISION == DEATH -> RESTART"
            else:
                game.state.game_active = false
                continue
            
        var pressed: seq[Action]
        # get keybinds
        for a in ui.controls.keybinds.keys():
            if IsKeyDown(a):
                pressed.add(ui.controls.keybinds[a])
        

        # Update game
        frame_step(pressed)


        ClearBackground(makecolor(0, 0, 30))
        BeginDrawing()
        
        draw_game()

        EndDrawing()

    
    CloseWindow()


proc main =
    
    newGame()
    set_settings()
    set_ui_settings()
    startGame()
    gameLoop()


if isMainModule:
    main()

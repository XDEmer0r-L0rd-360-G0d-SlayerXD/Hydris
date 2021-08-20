import sim, Board0_3
import tables, arraymancer, strformat, strutils, std/monotimes
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
        restart_on_death: bool
    Settings = object
        visuals: Visual_settings
        controls: Control_settings
        play: Game_Play_settings

var ui*: Settings

# Helpers

proc `*`*(x: float, y: int): float =
    return x * toFloat(y)

proc `/`*(x: float, y: int): float =
    return x / toFloat(y)

proc set_ui_settings() =
    # Todo check for file later. I'll just use defaults for now.
    ui.visuals.game_field_offset_left = 0.1
    ui.visuals.game_field_offset_top = 0.1
    ui.visuals.game_field_units_wide = 10 + 10  # todo change the order of calling settings and game to allow loading later
    ui.visuals.game_field_board_padding_left = 5
    ui.visuals.window_height = 900
    ui.visuals.window_width = 800
    # only debug hard_left, hard_right, and lock left in
    ui.controls.keybinds = {KEY_J: Action.left, KEY_K: Action.down, KEY_L: Action.right, 
    KEY_D: Action.counter_clockwise, KEY_F: Action.clockwise, KEY_A: Action.hold, KEY_SPACE: Action.hard_drop,
    KEY_RIGHT: Action.hard_right, KEY_LEFT: Action.hard_left, KEY_ENTER: Action.lock, KEY_R: Action.reset,
    KEY_S: Action.oneeighty, KEY_Z: Action.undo}.toTable()
    ui.play.restart_on_death = true


proc draw_game(sim: Sim) =
    # We assume were in drawing mode
    template v: Visual_settings = ui.visuals
    let size = toInt((1 - v.game_field_offset_left * 2) * v.window_width / v.game_field_units_wide)
    let x_offset = toInt(v.game_field_offset_left * v.window_width)
    let y_offset = toInt(v.game_field_offset_top * v.window_height)
    let grid_lines = 1

    proc draw_square(x: int, y: int, col: Color) =
        # This assumes drawing in the game field with a finness of the min size
        DrawRectangle(x * (size + grid_lines) + x_offset, y * (size + grid_lines) + y_offset, size, size, col)

    var ghost_board: Board
    if sim.settings.play.ghost:
        let movement = get_new_location(sim.board, sim.state, Action.hard_drop)
        let new_loc = test_location(sim.board, sim.state.active, movement[0], movement[1], movement[2])
        ghost_board = new_loc[2]
        

    # Draw the game board
    let loc = test_location(sim.board, sim.state.active, sim.state.active_x, sim.state.active_y, sim.state.active_r)[2]
    var val: Block
    var col: Color
    for a in 0 ..< sim.config.height:
        for b in 0 ..< sim.config.width:
            case loc[a, b]:
            of T, I, O, L, J, S, Z:
                col = makecolor(200, 0, 0)
            else:
                if sim.settings.play.ghost and (ghost_board[a, b] != Block.empty):
                    col = makecolor(100, 0, 0)
                else:
                    col = makecolor(50, 50, 50)
            # echo fmt"Drawing {a}, {b} with {col}, {makerect(b * size + x_offset, a * size + y_offset, size, size)}"
            draw_square(b + v.game_field_board_padding_left, a, col)

    # Draw the queue
    var mino: Mino
    for a in 0 ..< sim.settings.rules.visible_queue_len:
        mino = mino_from_str(sim.config, $sim.state.queue[a])
        for y in 0 ..< mino.rotation_shapes[0].shape.shape[0]:
            for x in 0 ..< mino.rotation_shapes[0].shape.shape[1]:
                if mino.rotation_shapes[0].shape[y, x] == 1:
                    col = makecolor(200, 0, 0)
                else:
                    col = makecolor(50, 50, 50)
                draw_square(ui.visuals.game_field_board_padding_left + sim.config.width + 1 + x, a * 5 + y, col)
    
    if sim.state.holding != "-":
        mino = mino_from_str(sim.config, sim.state.holding)
        for y in 0 ..< mino.rotation_shapes[0].shape.shape[0]:
            for x in 0 ..< mino.rotation_shapes[0].shape.shape[1]:
                if mino.rotation_shapes[0].shape[y, x] == 1:
                    col = makecolor(200, 0, 0)
                else:
                    col = makecolor(50, 50, 50)
                draw_square(x, y, col)
        


proc gameLoop*(sim: var Sim) =
    
    InitWindow(ui.visuals.window_width, ui.visuals.window_height, "Hydris")
    SetTargetFPS(60)
    
    var preview = true
    frame_step(sim, @[])
    while ui.play.restart_on_death and not WindowShouldClose():
        DrawFPS(10, 10)

        # if game.state.phase == Game_phase.dead:
        #     newGame()
        #     startGame()
        #     fix_queue()
        #     invalidate_all_actions()
        #     preview = true
        #     echo "RESTARTING"
        
        # if not preview:
        var pressed: seq[Action]
        # get keybinds
        for a in ui.controls.keybinds.keys():
            if IsKeyDown(a):
                pressed.add(ui.controls.keybinds[a])
        

        # Update game
        sim.frame_step(pressed)


        ClearBackground(makecolor(0, 0, 30))
        BeginDrawing()
        
        draw_game(sim)

        EndDrawing()

        # # lines cleared
        # var count = 0
        # for a in game.state.event_log:
        #     case a[1]:
        #     of "1", "2", "3", "4":
        #         count.inc(parseInt(a[1]))
        # DrawText(fmt"{count}/40", 30, 500, 30, WHITE)

        # if count >= 40:
        #     var time = game.state.event_log[^1][0] - game.state.event_log[0][0]
        #     echo fmt"Done in {time}s"
        #     game.state.phase = Game_phase.dead

    
    CloseWindow()


proc main =
    
    var preset = getPresetRules("MAIN")
    var sim = initSim(preset[0], preset[1])
    reboot_all(sim)
    echo sim
    # newGame()
    # set_settings()
    set_ui_settings()
    # startGame()
    # fix_queue()
    gameLoop(sim)


if isMainModule:
    main()

import sim, Board0_3
import counter
import raylib, rayutils
import tables, arraymancer, std/monotimes, strutils, random, streams, yaml/serialization


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
    Saved_controls = object
        das: float
        keybinds: Table[KeyboardKey, Action]

var ui*: Settings

let mino_col = {T: makecolor(127, 0, 127), I: makecolor(0, 255, 255), O: makecolor(255, 255, 0), 
    L: makecolor(255, 127, 0), J: makecolor(0, 0, 255), S: makecolor(0, 255, 0), Z: makecolor(255, 0, 0),
    empty: makecolor(10, 10, 10), ghost: makecolor(50, 50, 50), garbage: makecolor(120, 120, 120)}.toTable

# Info copied from from the harddrop wiki
# FIXME We assume we always do 180s here
# TODO check for similarites between different Blocks
const finess_order* = {O: @[@[hard_left], @[hard_left, right], @[left, left], @[left], @[right], @[right, right], @[hard_right, left], @[hard_right]],
                        T: @[@[hard_left], @[left, left], @[left], @[], @[right], @[right, right], @[hard_right, left], @[hard_right],
                            @[clockwise, hard_left], @[hard_left, clockwise], @[clockwise, left, left], @[clockwise, left], @[clockwise], @[clockwise, right], @[clockwise, right, right], @[clockwise, hard_right, left], @[clockwise, hard_right],
                            @[counter_clockwise, hard_left], @[counter_clockwise, left, left], @[counter_clockwise, left], @[counter_clockwise], @[counter_clockwise, right], @[counter_clockwise, right, right], @[hard_right, left, counter_clockwise], @[hard_right, counter_clockwise], @[counter_clockwise, hard_right],
                            @[hard_left, oneeighty], @[left, left, oneeighty], @[left, oneeighty], @[oneeighty], @[right, oneeighty], @[right, right, oneeighty], @[hard_right, left, oneeighty], @[hard_right, oneeighty],],
                        L: @[@[hard_left], @[left, left], @[left], @[], @[right], @[right, right], @[hard_right, left], @[hard_right],
                            @[clockwise, hard_left], @[hard_left, clockwise], @[clockwise, left, left], @[clockwise, left], @[clockwise], @[clockwise, right], @[clockwise, right, right], @[clockwise, hard_right, left], @[hard_right, clockwise],
                            @[counter_clockwise, hard_left], @[counter_clockwise, left, left], @[counter_clockwise, left], @[counter_clockwise], @[counter_clockwise, right], @[counter_clockwise, right, right], @[hard_right, left, counter_clockwise], @[hard_right, counter_clockwise], @[counter_clockwise, hard_right],
                            @[hard_left, oneeighty], @[left, left, oneeighty], @[left, oneeighty], @[oneeighty], @[right, oneeighty], @[right, right, oneeighty], @[hard_right, left, oneeighty], @[hard_right, oneeighty],],
                        J: @[@[hard_left], @[left, left], @[left], @[], @[right], @[right, right], @[hard_right, left], @[hard_right],
                            @[clockwise, hard_left], @[hard_left, clockwise], @[clockwise, left, left], @[clockwise, left], @[clockwise], @[clockwise, right], @[clockwise, right, right], @[clockwise, hard_right, left], @[hard_right, clockwise],
                            @[counter_clockwise, hard_left], @[counter_clockwise, left, left], @[counter_clockwise, left], @[counter_clockwise], @[counter_clockwise, right], @[counter_clockwise, right, right], @[hard_right, left, counter_clockwise], @[hard_right, counter_clockwise], @[counter_clockwise, hard_right],
                            @[hard_left, oneeighty], @[left, left, oneeighty], @[left, oneeighty], @[oneeighty], @[right, oneeighty], @[right, right, oneeighty], @[hard_right, left, oneeighty], @[hard_right, oneeighty],],
                        S: @[@[hard_left], @[left, left], @[left], @[], @[right], @[right, right], @[hard_right, left], @[hard_right],
                            @[counter_clockwise, hard_left], @[hard_left, clockwise], @[counter_clockwise, left], @[counter_clockwise], @[clockwise], @[clockwise, right], @[clockwise, right, right], @[hard_right, counter_clockwise], @[clockwise, hard_right],],
                        Z: @[@[hard_left], @[left, left], @[left], @[], @[right], @[right, right], @[hard_right, left], @[hard_right],
                            @[counter_clockwise, hard_left], @[hard_left, clockwise], @[counter_clockwise, left], @[counter_clockwise], @[clockwise], @[clockwise, right], @[clockwise, right, right], @[hard_right, counter_clockwise], @[clockwise, hard_right],],
                        I: @[@[hard_left], @[left, left], @[left], @[], @[right], @[right, right], @[hard_right],
                            @[counter_clockwise, hard_left], @[hard_left, counter_clockwise], @[hard_left, clockwise], @[left, counter_clockwise], @[counter_clockwise], @[clockwise], @[right, clockwise], @[hard_right, counter_clockwise], @[hard_right, clockwise], @[clockwise, hard_right]]}.toTable


# Helpers

proc `*`*(x: float, y: int): float =
    return x * toFloat(y)

proc `/`*(x: float, y: int): float =
    return x / toFloat(y)

proc `==`(x: Board, y: Board): bool =
    if not (x.shape.data == y.shape.data):
        return false
    elif not (x.storage.raw_buffer == y.storage.raw_buffer):
        return false
    return true


proc set_default_ui_settings() =
    # Todo check for file later. I'll just use defaults for now.
    ui.visuals.game_field_offset_left = 0.1
    ui.visuals.game_field_offset_top = 0.1
    ui.visuals.game_field_units_wide = 10 + 10  # todo change the order of calling settings and game to allow loading later
    ui.visuals.game_field_board_padding_left = 5
    ui.visuals.window_height = 900
    ui.visuals.window_width = 800
    # only debug hard_left, hard_right, and lock left in
    ui.controls.keybinds = {KEY_J: Action.left, KEY_K: Action.down, KEY_L: Action.right, 
    KEY_D: Action.counter_clockwise, KEY_F: Action.clockwise, KEY_SPACE: Action.hard_drop, KEY_S: Action.oneeighty}.toTable()
    ui.play.restart_on_death = true


proc load_custom_settings(sim: var Sim) =
    if not FileExists("settings.dat"):
        var filest = newFileStream("settings.dat", fmWrite)
        var temp = Saved_controls()
        temp.das = 70
        temp.keybinds = {KEY_J: Action.left, KEY_K: Action.down, KEY_L: Action.right, 
            KEY_D: Action.counter_clockwise, KEY_F: Action.clockwise, KEY_SPACE: Action.hard_drop, KEY_S: Action.oneeighty}.toTable()
        dump(temp, filest)
        filest.close()
    
    var file_read = newFileStream("settings.dat", fmRead)
    var loaded: Saved_controls
    load(file_read, loaded)
    file_read.close()
    sim.settings.controls.das = loaded.das
    ui.controls.keybinds = loaded.keybinds
    echo "loaded settings"


proc draw_game(sim: Sim, shadow: Board) =
    # We assume were in drawing mode
    template v: Visual_settings = ui.visuals
    let size = toInt((1 - v.game_field_offset_left * 2) * v.window_width / v.game_field_units_wide)
    let x_offset = toInt(v.game_field_offset_left * v.window_width)
    let y_offset = toInt(v.game_field_offset_top * v.window_height)
    let grid_lines = 1

    let mino_col = {T: makecolor(127, 0, 127), I: makecolor(0, 255, 255), O: makecolor(255, 255, 0), 
    L: makecolor(255, 127, 0), J: makecolor(0, 0, 255), S: makecolor(0, 255, 0), Z: makecolor(255, 0, 0),
    empty: makecolor(10, 10, 10), ghost: makecolor(50, 50, 50), garbage: makecolor(120, 120, 120)}.toTable

    proc draw_square(x: int, y: int, col: Color) =
        # This assumes drawing in the game field with a finness of the min size
        DrawRectangle(x * (size + grid_lines) + x_offset, y * (size + grid_lines) + y_offset, size, size, col)
        

    # Draw the game board
    let loc = test_location(sim.board, sim.state.active, sim.state.active_x, sim.state.active_y, sim.state.active_r)[2]
    var col: Color
    for a in 0 ..< sim.config.height:
        for b in 0 ..< sim.config.width:
            case loc[a, b]:
            of T, I, O, L, J, S, Z, garbage:
                col = mino_col[loc[a, b]]
            else:
                if shadow[a, b] != Block.empty:
                    col = mino_col[ghost]
                else:
                    col = mino_col[empty]
            # echo fmt"Drawing {a}, {b} with {col}, {makerect(b * size + x_offset, a * size + y_offset, size, size)}"
            draw_square(b + v.game_field_board_padding_left, a, col)

    # Draw the queue
    var mino: Mino
    for a in 0 ..< sim.settings.rules.visible_queue_len:
        mino = mino_from_str(sim.config, $sim.state.queue[a])
        for y in 0 ..< mino.rotation_shapes[0].shape.shape[0]:
            for x in 0 ..< mino.rotation_shapes[0].shape.shape[1]:
                if mino.rotation_shapes[0].shape[y, x] == 1:
                    col = mino_col[mino.pattern]
                else:
                    col = mino_col[empty]
                draw_square(ui.visuals.game_field_board_padding_left + sim.config.width + 1 + x, a * 5 + y, col)
    
    # Draw hold
    if sim.state.holding != "-":
        mino = mino_from_str(sim.config, sim.state.holding)
        for y in 0 ..< mino.rotation_shapes[0].shape.shape[0]:
            for x in 0 ..< mino.rotation_shapes[0].shape.shape[1]:
                if mino.rotation_shapes[0].shape[y, x] == 1:
                    if sim.state.hold_available:
                        col = mino_col[mino.pattern]
                    else:
                        col = mino_col[garbage]
                else:
                    col = mino_col[empty]
                draw_square(x, y, col)
        


proc main() =
    var preset = getPresetRules("MAIN")
    set_default_ui_settings()
    var sim = initSim(preset[0], preset[1])
    sim.load_custom_settings()
    sim.settings.rules.visible_queue_len = 1
    sim.settings.rules.hist_logging = {time, state, compression}
    # sim.state.set_mino(sim.config, "L")
    var shadow_board = initBoard(sim.config)
    var target_path: seq[int]  # active_x found via history
    var target_path_double: seq[int]  # For double right/left instead of 180
    var final_rotation: int  # active_r 
    var chosen_pattern: string = "L12"
    var movement_order: seq[Action]
    var background = DARKGREEN


    InitWindow(ui.visuals.window_width, ui.visuals.window_height, "Hydris - Finesse Trainer")
    SetTargetFPS(60)

    while not WindowShouldClose():

        var pressed: seq[Action]
        # get keybinds
        for a in ui.controls.keybinds.keys():
            if IsKeyDown(a):
                pressed.add(ui.controls.keybinds[a])
        
        # Jump right into play phase
        if not counter_single.check("init phase"):
            counter_single.inc("init phase")
            sim.events.add(Phase_event(start_time: getMonoTime(), phase_type: Phase_type.stopwatch, phase: Game_phase.play))
            sim.phase = Game_phase.play

        if len(sim.state.queue) == 0:
            extend_queue(sim.state, sim.config, 1)
        sim.frame_step(pressed)

        # FIXME remove temp history checks
        if sim.history_info.len() > counter_multi.check("info"):
            counter.counter_multi.inc("info")
            echo sim.history_info
        # if sim.history_state.len() > counter_multi.check("state"):
        #     counter_multi.inc("state")
        #     echo sim.history_state.len()
        
        if sim.stats.key_presses > counter_multi.check("key counter"):
            echo sim.stats.key_presses
            counter_multi.inc("key counter")

        # Find pattern to test against
        if not counter_single.check("chose pattern"):
            counter_single.inc("chose pattern")
            var block_name = sim.state.active.pattern
            chosen_pattern = block_name.str_from_block & $rand(0 .. finess_order[block_name].high)
            # echo chose0n_pattern
            

        if not counter_single.check("calc shadow"):
            counter_single.inc("calc shadow")
            shadow_board = sim.board.clone()
            var temp_state = initState()
            temp_state.set_mino(sim.config, $chosen_pattern[0])

            # add fix for das movement
            for a in finess_order[mino_from_str(sim.config, $chosen_pattern[0]).pattern][parseInt($chosen_pattern[1 .. chosen_pattern.high])]:
                if a == Action.hard_left:
                    movement_order.add(left)
                    movement_order.add(hard_left)
                elif a == Action.hard_right:
                    movement_order.add(right)
                    movement_order.add(hard_right)
                else:
                    movement_order.add(a)
            echo movement_order

            for a in movement_order:
                target_path.add(temp_state.active_x)
                target_path_double.add(temp_state.active_x)
                if a == oneeighty:
                    target_path_double.add(temp_state.active_x)
                discard do_action(temp_state, shadow_board, sim.config, a)
            target_path.add(temp_state.active_x)
            target_path_double.add(temp_state.active_x)
            final_rotation = temp_state.active_r
            discard do_action(temp_state, shadow_board, sim.config, Action.hard_drop)            
            discard do_action(temp_state, shadow_board, sim.config, Action.lock)


        if sim.history_state.len >= 2 and sim.history_state[^2].board != sim.board and not counter_single.check("board change"):
            
            block:  # TODO check if we still need this now that the start history mark has been removed
                if sim.history_state.len() == 1 and sim.history_state[0].state.active_x == 0:
                    sim.history_state.delete(0)
                    break
                counter_single.inc("board change")
                var comparison: seq[int]
                for a in sim.history_state:
                    comparison.add(a.state.active_x)
                var our_path: seq[string]
                for a in 1 .. sim.history_info.high - 1:
                    our_path.add(sim.history_info[a].info)
                let movement_final: seq[string] = block:
                    var temp2: seq[string]
                    for a in movement_order:
                        temp2.add($a)
                    temp2
                
                echo our_path & " -> " & movement_final

                var temp: seq[string]
                for a in sim.history_info:
                    temp.add(a.info)
                if (comparison == target_path or comparison == target_path_double) and sim.history_state[^1].state.active_r == final_rotation:
                    background = DARKGREEN
                    counter_single.clear()
                else:
                    background = DARKBROWN
                    sim.board = sim.history_state[0].board.clone()
                    sim.state = sim.history_state[0].state.clone(sim.config)
                    sim.spawn_mino($sim.state.active.pattern)
                    counter_single.clear()
                    counter_single.inc("chose pattern")
                target_path = @[]
                target_path_double = @[]
                sim.history_state = @[]
                sim.history_info = @[]
                sim.stats = Stats()
                counter_multi.clear()
                movement_order.setlen(0)


        if not counter_single.check("lower board"):
            counter_single.inc("lower board")
            for a in sim.board[^10, _]:
                if a != Block.empty:
                    counter_single.inc("too high")
            
            if counter_single.check("too high"):
                sim.board.drain_board(1)

            
        
        if counter_multi.check("hist len") < sim.history_state.len():
            # This is more of a debug thing
            var output: seq[int]
            for a in sim.history_state:
                output.add(a.state.active_x)
            # echo output 
            counter_multi.inc("hist len")
        
        ClearBackground(background)
        
        BeginDrawing()
        DrawFPS(10, 10)
        draw_game(sim, shadow_board)
        EndDrawing()

    CloseWindow()


if isMainModule:
    randomize(11)
    main()


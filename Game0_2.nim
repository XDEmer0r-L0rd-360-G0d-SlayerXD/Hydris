import sim, board0_3
import tables, arraymancer, strformat, strutils, std/monotimes
import raylib, rayutils
import random

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

    let mino_col = {T: makecolor(127, 0, 127), I: makecolor(0, 255, 255), O: makecolor(255, 255, 0), 
    L: makecolor(255, 127, 0), J: makecolor(0, 0, 255), S: makecolor(0, 255, 0), Z: makecolor(255, 0, 0),
    empty: makecolor(10, 10, 10), ghost: makecolor(50, 50, 50), garbage: makecolor(120, 120, 120)}.toTable

    proc draw_square(x: int, y: int, col: Color) =
        # This assumes drawing in the game field with a finness of the min size
        DrawRectangle(x * (size + grid_lines) + x_offset, y * (size + grid_lines) + y_offset, size, size, col)

    var ghost_board: Board
    if sim.settings.play.ghost:
        let movement = get_new_location(sim.board, sim.state, Action.hard_drop)
        let new_loc = test_location(initBoard(sim.config), sim.state.active, movement[0], movement[1], movement[2])
        ghost_board = new_loc[2]
        

    # Draw the game board
    let loc = test_location(sim.board, sim.state.active, sim.state.active_x, sim.state.active_y, sim.state.active_r)[2]
    var col: Color
    for a in 0 ..< sim.config.height:
        for b in 0 ..< sim.config.width:
            case loc[a, b]:
            of T, I, O, L, J, S, Z, garbage:
                col = mino_col[loc[a, b]]
            else:
                if sim.settings.play.ghost and (ghost_board[a, b] != Block.empty):
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
        



proc gameLoop_Survival(sim: var Sim) =

    InitWindow(ui.visuals.window_width, ui.visuals.window_height, "Hydris - Survival")
    SetTargetFPS(0)

    sim.settings.rules.hist_logging = Logging_type.time_on_lock
    
    var past: (float, int, float)  # TODO change this to usefull survival stats
    var hist_len = len(sim.history)
    var pause_overwritten = false
    while not WindowShouldClose():
        DrawFPS(10, 10)
        
        # if not preview:
        var pressed: seq[Action]
        # get keybinds
        for a in ui.controls.keybinds.keys():
            if IsKeyDown(a):
                if ui.controls.keybinds[a] == Action.undo:
                    continue
                pressed.add(ui.controls.keybinds[a])
        

        # Update game
        sim.frame_step(pressed)


        ClearBackground(makecolor(0, 0, 0))
        BeginDrawing()
        
        case sim.phase:
        of Game_phase.play:
            pause_overwritten = false
            past = (sim.events.get_info(Game_phase.game_time)/1000, sim.stats.pieces_placed, float(sim.stats.pieces_placed) / (sim.events.get_info(Game_phase.game_time) / 1000))
            draw_game(sim)
            let time = sim.events.get_info(Game_phase.play) / 1000
            DrawText(formatFloat(time, precision = 3) & "s", 100, 250, 50, WHITE)
            DrawText($sim.stats.pieces_placed, 100, 300, 50, WHITE)
            DrawText(formatFloat(float(sim.stats.pieces_placed) / time, precision = 3) & " pps", 50, 350, 50, WHITE)
            if sim.events.get_info("garbage") == 0:
                sim.events.add(Custom_event(start_time: getMonoTime(), phase_type: Phase_type.repeating, tag: "garbage", duration: 1000))
            
            let customs = sim.events.tick_custom()
            if len(customs) > 0:
                for a in customs:
                    case a:
                    of "garbage":
                        sim.board.insert_random_garbage(1)
                        let info = test_location(sim.board, sim.state)
                        if not (info[0] and info[1]):
                            sim.state.active_y += 1
                    else:
                        discard
            
            if len(sim.history) > hist_len:
                hist_len = len(sim.history)
                sim.events.del("latest clear")
                sim.events.add(Custom_event(start_time: getMonoTime(), phase_type: timer, tag: "latest clear", duration: 1000))
            
            if sim.events.get_info("latest clear") > 0:
                DrawText(sim.history[^1].info, 100, 600, 50, WHITE)
        
        of Game_phase.preview:
            draw_game(sim)
            let time = sim.events.get_info(Game_phase.play) / 1000
            if time > 0:
                DrawText(formatFloat(time, precision = 3) & "s", 100, 100, 50, WHITE)

        of Game_phase.delay:
            draw_game(sim)
            DrawText("Clear Delay", 100, 100, 50, WHITE)

        of Game_phase.dead:
            sim.events.del("garbage")
            let death_data = sim.events.get_info(Game_phase.preview)
            if death_data > 0:
                DrawText(formatFloat(death_data / 1000, ffDecimal, 3) & "s Until respawn", 100, 100, 50, WHITE)
            
            if not pause_overwritten and sim.history.len() > 1:
                pause_overwritten = true
                sim.events.del(Game_phase.preview)  # Override default death timer to extend it
                sim.events.add(Phase_event(start_time: getMonoTime(), phase_type: Phase_type.timer, phase: Game_phase.preview, duration: 10000))
            
            if past[0] > 0:
                DrawText("Survived for " & formatFloat(past[0], precision = 3) & "s", 100, 250, 50, WHITE)
                DrawText($past[1] & "p", 100, 300, 50, WHITE)
                DrawText(formatFloat(past[2], precision = 3) & " pps", 50, 350, 50, WHITE)
        
        else:
            discard
        

        EndDrawing()


    CloseWindow()


proc gameLoop_Sprint(sim: var Sim) =
    
    InitWindow(ui.visuals.window_width, ui.visuals.window_height, "Hydris - Sprint")
    SetTargetFPS(0)
    
    var past: (float, int, float)
    var hist_len = len(sim.history)
    # frame_step(sim, @[])
    while not WindowShouldClose():
        DrawFPS(10, 10)
        
        # if not preview:
        var pressed: seq[Action]
        # get keybinds
        for a in ui.controls.keybinds.keys():
            if IsKeyDown(a):
                # if ui.controls.keybinds[a] == Action.undo:
                #     continue
                pressed.add(ui.controls.keybinds[a])
        

        # Update game
        sim.frame_step(pressed)


        ClearBackground(makecolor(0, 0, 0))
        BeginDrawing()
        
        case sim.phase:
        of Game_phase.play:
            past[0] = 0
            draw_game(sim)
            let time = sim.events.get_info(Game_phase.game_time) / 1000
            DrawText(formatFloat(time, precision = 3) & "s", 100, 250, 50, WHITE)
            DrawText($sim.stats.pieces_placed, 100, 300, 50, WHITE)
            DrawText(formatFloat(float(sim.stats.pieces_placed) / time, precision = 3) & " pps", 50, 350, 50, WHITE)
            
            let customs = sim.events.tick_custom()
            if len(customs) > 0:
                for a in customs:
                    case a:
                    of "garbage":
                        sim.board.insert_random_garbage(1)
                        let info = test_location(sim.board, sim.state)
                        if not (info[0] and info[1]):
                            sim.state.active_y += 1
                    else:
                        discard
            
            if len(sim.history) > hist_len:
                hist_len = len(sim.history)
                sim.events.del("latest clear")
                sim.events.add(Custom_event(start_time: getMonoTime(), phase_type: timer, tag: "latest clear", duration: 1000))
            
            if sim.events.get_info("latest clear") > 0:
                DrawText(sim.history[^1].info, 100, 600, 50, WHITE)
        
        of Game_phase.preview:
            draw_game(sim)
            let time = sim.events.get_info(Game_phase.play) / 1000
            if time > 0:
                DrawText(formatFloat(time, precision = 3) & "s", 100, 100, 50, WHITE)
            # echo sim.events.get_event(Game_phase.play)

        of Game_phase.delay:
            draw_game(sim)
            DrawText("Clear Delay", 100, 100, 50, WHITE)

        of Game_phase.dead:
            let death_data = sim.events.get_info(Game_phase.preview)
            if death_data > 0:
                DrawText(formatFloat(death_data / 1000, ffDecimal, 3) & "s Until respawn", 100, 100, 50, WHITE)
            
            if past[0] > 0:
                DrawText(formatFloat(past[0], precision = 3) & "s", 100, 250, 50, WHITE)
                DrawText($past[1] & "p", 100, 300, 50, WHITE)
                DrawText(formatFloat(past[2], precision = 3) & " pps", 50, 350, 50, WHITE)
        else:
            raiseError(fmt"We're in the {sim.phase} phase")
        
        

        EndDrawing()

        const lines_to_clear = 4
        DrawText(fmt"{sim.stats.lines_cleared}/{lines_to_clear}", 30, 500, 30, WHITE)

        if sim.stats.lines_cleared >= lines_to_clear:
            echo fmt"Done in {sim.events.get_info(Game_phase.play)/1000}s"
            past = (sim.events.get_info(Game_phase.game_time)/1000, sim.stats.pieces_placed, float(sim.stats.pieces_placed) / (sim.events.get_info(Game_phase.game_time) / 1000))
            echo past
            sim.events.del_all(Game_phase.play)
            sim.phase = Game_phase.dead
            sim.events.add(Phase_event(start_time: getMonoTime(), phase_type: Phase_type.timer, phase: Game_phase.preview, duration: 5000))
            sim.reboot_game()
            tick_action_invalidate_all(sim.events)

    CloseWindow()


proc gameLoop_Cheese(sim: var Sim) =
    
    InitWindow(ui.visuals.window_width, ui.visuals.window_height, "Hydris - Cheese")
    SetTargetFPS(0)
    
    var past: (float, int, float)
    const start_lines = 10
    var cheese_lines = start_lines
    # frame_step(sim, @[])
    while not WindowShouldClose():
        DrawFPS(10, 10)
        
        # if not preview:
        var pressed: seq[Action]
        # get keybinds
        for a in ui.controls.keybinds.keys():
            if IsKeyDown(a):
                # if ui.controls.keybinds[a] == Action.undo:
                #     continue
                pressed.add(ui.controls.keybinds[a])
        

        # Update game
        sim.frame_step(pressed)


        ClearBackground(makecolor(0, 0, 0))
        BeginDrawing()
        
        while cheese_lines > 0:
            cheese_lines -= 1
            sim.board.insert_random_garbage(1)
        
        case sim.phase:
        of Game_phase.play:
            past[0] = 0
            draw_game(sim)
            let time = sim.events.get_info(Game_phase.game_time) / 1000
            DrawText(formatFloat(time, precision = 3) & "s", 100, 250, 50, WHITE)
            DrawText($sim.stats.pieces_placed, 100, 300, 50, WHITE)
            DrawText(formatFloat(float(sim.stats.pieces_placed) / time, precision = 3) & " pps", 50, 350, 50, WHITE)
            
        
        of Game_phase.preview:
            draw_game(sim)
            let time = sim.events.get_info(Game_phase.play) / 1000
            if time > 0:
                DrawText(formatFloat(time, precision = 3) & "s", 100, 100, 50, WHITE)
            # echo sim.events.get_event(Game_phase.play)

        of Game_phase.delay:
            draw_game(sim)
            DrawText("Clear Delay", 100, 100, 50, WHITE)

        of Game_phase.dead:
            let death_data = sim.events.get_info(Game_phase.preview)
            if death_data > 0:
                DrawText(formatFloat(death_data / 1000, ffDecimal, 3) & "s Until respawn", 100, 100, 50, WHITE)
            
            if past[0] > 0:
                DrawText(formatFloat(past[0], precision = 3) & "s", 100, 250, 50, WHITE)
                DrawText($past[1] & "p", 100, 300, 50, WHITE)
                DrawText(formatFloat(past[2], precision = 3) & " pps", 50, 350, 50, WHITE)
        else:
            raiseError(fmt"We're in the {sim.phase} phase")
        
        

        EndDrawing()


        if sim.board[sim.config.height - 1, 0] != Block.garbage and sim.board[sim.config.height - 1, 1] != Block.garbage:
            cheese_lines = start_lines
            echo fmt"Done in {sim.events.get_info(Game_phase.play)/1000}s"
            past = (sim.events.get_info(Game_phase.game_time)/1000, sim.stats.pieces_placed, float(sim.stats.pieces_placed) / (sim.events.get_info(Game_phase.game_time) / 1000))
            echo past
            sim.events.del_all(Game_phase.play)
            sim.phase = Game_phase.dead
            sim.events.add(Phase_event(start_time: getMonoTime(), phase_type: Phase_type.timer, phase: Game_phase.preview, duration: 5000))
            sim.reboot_game()
            tick_action_invalidate_all(sim.events)

    CloseWindow()


proc gameLoop_Ultra(sim: var Sim) =
    
    InitWindow(ui.visuals.window_width, ui.visuals.window_height, "Hydris - Ultra")
    SetTargetFPS(0)
    
    var past: int
    # frame_step(sim, @[])
    while not WindowShouldClose():
        DrawFPS(10, 10)
        
        # if not preview:
        var pressed: seq[Action]
        # get keybinds
        for a in ui.controls.keybinds.keys():
            if IsKeyDown(a):
                # if ui.controls.keybinds[a] == Action.undo:
                #     continue
                pressed.add(ui.controls.keybinds[a])
        

        # Update game
        sim.frame_step(pressed)


        ClearBackground(makecolor(0, 0, 0))
        BeginDrawing()
        
        
        case sim.phase:
        of Game_phase.play:
            past = 0
            draw_game(sim)
            let time = sim.events.get_info(Game_phase.game_time) / 1000
            DrawText(formatFloat(time, precision = 3) & "s", 100, 250, 50, WHITE)
            DrawText($sim.stats.pieces_placed, 100, 300, 50, WHITE)
            DrawText(formatFloat(float(sim.stats.pieces_placed) / time, precision = 3) & " pps", 50, 350, 50, WHITE)
            DrawText($sim.stats.score, 100, 400, 50, WHITE)
            
        
        of Game_phase.preview:
            draw_game(sim)
            let time = sim.events.get_info(Game_phase.play) / 1000
            if time > 0:
                DrawText(formatFloat(time, precision = 3) & "s", 100, 100, 50, WHITE)
            # echo sim.events.get_event(Game_phase.play)

        of Game_phase.delay:
            draw_game(sim)
            DrawText("Clear Delay", 100, 100, 50, WHITE)

        of Game_phase.dead:
            let death_data = sim.events.get_info(Game_phase.preview)
            if death_data > 0:
                DrawText(formatFloat(death_data / 1000, ffDecimal, 3) & "s Until respawn", 100, 100, 50, WHITE)

            DrawText($past, 100, 250, 50, WHITE)
            
        else:
            raiseError(fmt"We're in the {sim.phase} phase")
        
        

        EndDrawing()


        if sim.events.get_info(Game_phase.game_time) > 10000:
            sim.events.del(Game_phase.game_time)
            echo fmt"Done in {sim.events.get_info(Game_phase.game_time)/1000}s"
            past = sim.stats.score
            sim.events.del_all(Game_phase.play)
            sim.phase = Game_phase.dead
            sim.events.add(Phase_event(start_time: getMonoTime(), phase_type: Phase_type.timer, phase: Game_phase.preview, duration: 5000))
            sim.reboot_game()
            tick_action_invalidate_all(sim.events)

    CloseWindow()



proc main =
    randomize()
    const mode = "ultra"
    var preset = getPresetRules("MAIN")
    var sim = initSim(preset[0], preset[1])
    set_ui_settings()
    case mode:
    of "survival":
        gameLoop_Survival(sim)
    of "sprint":
        gameLoop_Sprint(sim)
    of "cheese":
        gameLoop_Cheese(sim)
    of "ultra":
        gameLoop_Ultra(sim)


if isMainModule:
    main()

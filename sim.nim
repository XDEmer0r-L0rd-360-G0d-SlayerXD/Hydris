{.experimental: "codeReordering".}
import arraymancer, Board0_3, std/monotimes, tables

# TODO try to make spacing nicer
# Anything time related should try to stay in ms

type

    Stats* = object
        time*: float
        lines_cleared*: int
        pieces_placed*: int
        score*: int
        lines_sent*: int
        level*: int
    Sim* = object  # TODO may want to get rid of this construct as well
        stats*: Stats  # TODO consider putting stats in state object
        settings*: Settings
        board*: Board
        state*: State
        config*: Rules
        events*: Event_container
        phase*: Game_phase
        history*: seq[Hist_obj]  # TODO consider adding an extra log to be able to detect changes and create history
    Control_settings = object
        das: float  # units should be ms/square
        arr: float
        sds: float  # TODO need to chose between ms/down or down/ms. Is d/ms rn
    Game_Play_settings = object
        ghost*: bool
        history_len: int
    Other_rules = object  # TODO clean up the mess that is the settings which is spread across multiple files
        visible_height*: int
        visible_queue_len*: int
        lock_delay*: float
        clear_delay*: float
        allow_clutch_clear*: bool
        min_sds*: float  # TODO these settings may not properly interact with custom controls
        min_das*: float
        min_arr*: float
        gravity_speed*: float
        pregame_time*: float
        hist_logging*: Logging_type
        use_hold_limit: bool

    Settings* = object
        controls: Control_settings
        play*: Game_Play_settings
        rules*: Other_rules
    Hist_obj* = object
        stats*: Stats
        board*: Board
        state*: State
        time*: MonoTime
        info*: string
    Logging_type* = enum
        none, time_on_move, time_on_lock, full_on_move, full_on_lock
        

const all_minos* = [Block.T, Block.I, Block.O, Block.L, Block.J, Block.S, Block.Z]


# Use a names such as tetrio to preset rules object to have desired settings
proc getPresetRules*(name: string): (Rules, Settings) = 
    var config: Rules
    var settings: Settings

    template s: Settings = settings.other_rules  # TODO May not need this

    case name:  # FIXME Most of these are unusable due to lazyness
    # Real field height is wrong for these 
    of "TETRIO":
        config = Rules(preset_name: name, width: 10, height: 24, spawn_x: 4, spawn_y: 21, 
        bag_type: "7 bag", kick_table: "SRS+", can_hold: true, line_clearing_system: "classic",
        scoring_system: "guideline")

        settings.rules = Other_rules(visible_height: 20, lock_delay: 0.0, clear_delay: 0.0, 
        allow_clutch_clear: true, min_sds: 0, gravity_speed: 0, pregame_time: 3, visible_queue_len: 5,
        hist_logging: time_on_lock, use_hold_limit: true)

        settings.controls = Control_settings(das: 70, arr: 0, sds: 0)
    of "MAIN":
        config = Rules(preset_name: name, width: 10, height: 24, spawn_x: 4, spawn_y: 21, 
        bag_type: "7 bag", kick_table: "SRS+", can_hold: true, line_clearing_system: "classic",
        scoring_system: "guideline")

        settings.rules = Other_rules(visible_height: 20, lock_delay: 0.0, clear_delay: 0.0, 
        allow_clutch_clear: true, min_sds: 0, gravity_speed: 0, pregame_time: 3, visible_queue_len: 10,
        hist_logging: full_on_lock, use_hold_limit: false)
        
        settings.controls = Control_settings(das: 70, arr: 0, sds: 0)
    of "TEC":
        config = Rules(preset_name: name, width: 10, height: 21, spawn_x: 4, spawn_y: 20, 
        bag_type: "7 bag", kick_table: "SRS", can_hold: true, line_clearing_system: "classic",
        scoring_system: "guideline")

        settings.rules = Other_rules(visible_height: 20, lock_delay: 500, clear_delay: 250, 
        allow_clutch_clear: false, min_sds: 0.2, gravity_speed: 1, pregame_time: 3, visible_queue_len: 5,
        hist_logging: time_on_lock, use_hold_limit: true)
        
        settings.controls = Control_settings(das: 167, arr: 33, sds: 33)


    # of "MINI TESTING":
    #     config = Rules(preset_name: name, width: 6, visible_height: 6, height: 10, lock_delay: 0.0, 
    #     clear_delay: 0.0, spawn_x: 2, spawn_y: 8, allow_clutch_clear: false, min_sds: 0, 
    #     bag_piece_names: "JLZSIOT", bag_type: "7 bag", kick_table: "SRS+", can_hold: true, visible_queue_len: 10, gravity_speed: 0
    #     )
    # of "WACKY":
    #     config = Rules(preset_name: name, width: 8, visible_height: 5, height: 5, lock_delay: 0.0, 
    #     clear_delay: 0.0, spawn_x: 2, spawn_y: 3, allow_clutch_clear: false, min_sds: 0, 
    #     bag_piece_names: "TTT", bag_type: "random", kick_table: "SRS+", can_hold: true, visible_queue_len: 10, gravity_speed: 0
    #     )
    else:
        var e: ref ValueError
        new(e)
        e.msg = "name name doesn't exist"
        raise e

    initAllMinos(config)
    settings.play = Game_Play_settings(ghost: true, history_len: 3)

    return (config, settings)


proc initSim*(r: Rules, s: Settings): Sim =
    
    result = Sim(settings: s, config: r, board: initBoard(r), state: State(active: initEmptyMino()))
    result.reset_state()


proc reset_state(sim: var Sim) =
    sim.state = State(active: initEmptyMino())  # This should have the correct default values iirc
    sim.state.holding = "-"
    sim.state.queue = ""


proc reset_stats(sim: var Sim) =
    # TODO put level declaration in a better spot
    sim.stats = Stats(level: 1)


proc reboot_game*(sim: var Sim) =
    ## Wipe the board and reset the state

    sim.board = initBoard(sim.config)
    reset_state(sim)
    reset_stats(sim)


proc mark_history*(sim: var Sim) =
    # TODO add a check to make sure it saves changes
    var next: Hist_obj
    next.stats = sim.stats
    next.board = sim.board.clone
    next.state = sim.state
    if sim.history.len() > 0 and sim.history[^1].state == sim.state:  # Only care for unique states (Stops spam from continous movementy types)
        return
    sim.history.add(next)

proc mark_history*(sim: var Sim, info: string) =  # TODO Only two mark types considered. May want to change or just save everything
    var next: Hist_obj
    next.info = info
    next.time = getMonoTime()
    sim.history.add(next)


proc step_back(sim: var Sim) =
    if len(sim.history) < 1:
        return
    let change = sim.history.pop()
    echo len(sim.history)
    sim.stats = change.stats
    sim.board = change.board
    sim.state = change.state


proc frame_step*(sim: var Sim, inputs: seq[Action]) =
    ## This is the main loop of the sim
    
    # Start the game if nothing is active
    if sim.phase == Game_phase.empty:
        sim.events.add(Phase_event(start_time: getMonoTime(), phase_type: Phase_type.timer, phase: Game_phase.preview, duration: 300))
        sim.phase = Game_phase.dead
    

    let phase_changes = tick_phase(sim.events)
    if len(phase_changes) > 0:

        case sim.phase:
        of Game_phase.dead:
            if Game_phase.play in phase_changes:
                sim.events.add(Phase_event(start_time: getMonoTime(), phase_type: Phase_type.stopwatch, phase: Game_phase.play))
                sim.phase = Game_phase.play
                sim.events.del_all(Game_phase.game_time)
                sim.events.add(Phase_event(start_time: getMonoTime(), phase_type: Phase_type.stopwatch, phase: Game_phase.game_time))
            elif Game_phase.preview in phase_changes:
                sim.events.add(Phase_event(start_time: getMonoTime(), phase_type: Phase_type.timer, phase: Game_phase.play, duration: 1000))
                sim.phase = Game_phase.preview
            else:
                echo "from dead?"
        of Game_phase.preview:
            if Game_phase.play in phase_changes:
                sim.events.add(Phase_event(start_time: getMonoTime(), phase_type: Phase_type.stopwatch, phase: Game_phase.play))
                sim.events.del_all(Game_phase.game_time)
                sim.events.add(Phase_event(start_time: getMonoTime(), phase_type: Phase_type.stopwatch, phase: Game_phase.game_time))
                sim.phase = Game_phase.play
            else:
                echo "from preview?"
        of Game_phase.play:
            if Game_phase.preview in phase_changes:
                # Were assuming this means reset
                sim.events.add(Phase_event(start_time: getMonoTime(), phase_type: Phase_type.timer, phase: Game_phase.play, duration: 1000))
                sim.phase = Game_phase.preview
            elif Game_phase.dead in phase_changes:
                sim.events.add(Phase_event(start_time: getMonoTime(), phase_type: Phase_type.timer, phase: Game_phase.preview, duration: 1000))
                sim.phase = Game_phase.dead
                echo "we dead"
            elif Game_phase.delay in phase_changes:
                sim.events.add(Phase_event(start_time: getMonoTime(), phase_type: Phase_type.timer, phase: Game_phase.play, duration: sim.settings.rules.clear_delay))
                sim.phase = Game_phase.delay
                
            else:
                echo "from play?"
        of Game_phase.delay:
            if Game_phase.play in phase_changes:
                sim.events.add(Phase_event(start_time: getMonoTime(), phase_type: Phase_type.stopwatch, phase: Game_phase.play))
                sim.phase = Game_phase.play
        else:
            echo "unknown phase"
    
    case sim.phase:

    of Game_phase.play:
        let death_check = test_location(sim.board, sim.state)
        if not death_check[0] or not death_check[1]:
            sim.events.del_all(Game_phase.play)
            sim.events.add(Phase_event(start_time: getMonoTime(), phase_type: Phase_type.timer, phase: Game_phase.dead, duration: 0))
            sim.reboot_game()
            sim.frame_step(@[])
            tick_action_invalidate_all(sim.events)
            return

        while len(sim.state.queue) <= sim.settings.rules.visible_queue_len:
            # echo sim.state.queue
            sim.state.extend_queue(sim.config)
        
        # Fill active gap if there is one
        if sim.state.active.pattern == Block.empty:
            sim.state.set_mino(sim.config, $sim.state.queue[0])
            sim.state.queue = sim.state.queue[1 .. sim.state.queue.high]
        

        for a in inputs:
            if not get_info(sim.events, a):
                var movement: Move_type
                case a:
                of Action.right, Action.left:
                    movement = Move_type.das
                    sim.events.add(Action_event(start_time: getMonoTime(), arr_len: sim.settings.controls.arr, das_len: sim.settings.controls.das, movement: movement, action: a))
                of Action.down:
                    movement = Move_type.continuous
                    sim.events.add(Action_event(start_time: getMonoTime(), arr_len: sim.settings.controls.sds, das_len: sim.settings.controls.das, movement: movement, action: a))
                of Action.hard_drop, Action.hard_left, Action.hard_right, Action.clockwise, Action.counter_clockwise, Action.oneeighty, Action.reset, Action.hold, Action.undo:
                    movement = Move_type.single
                    sim.events.add(Action_event(start_time: getMonoTime(), arr_len: sim.settings.controls.arr, das_len: sim.settings.controls.das, movement: movement, action: a))
                else:
                    movement = Move_type.single
                    sim.events.add(Action_event(start_time: getMonoTime(), arr_len: sim.settings.controls.arr, das_len: sim.settings.controls.das, movement: movement, action: a))
                    echo "Action not set"

        let activations = tick_action(sim.events, inputs)

        for a in activations:
            case sim.settings.rules.hist_logging:
            of full_on_move:
                if a != Action.undo:
                    sim.mark_history()
            of time_on_move:
                sim.mark_history($a)
            else:
                discard

            case a:
            of Action.left:
                    if sim.settings.controls.arr == 0 and get_event(sim.events, a).arr_active:
                        discard do_action(sim.state, sim.board, sim.config, Action.hard_left)
                    else:
                        discard do_action(sim.state, sim.board, sim.config, Action.left)
            of Action.down:
                let change = calc_drop_score(sim.config, sim.board, sim.state, Action.down, sim.stats.level)
                if sim.settings.controls.sds == 0:
                    sim.stats.score += change * (sim.state.active_y - get_new_location(sim.board, sim.state, Action.hard_drop)[1])
                    discard do_action(sim.state, sim.board, sim.config, Action.hard_drop)
                else:
                    sim.stats.score += change
                    discard do_action(sim.state, sim.board, sim.config, Action.down)
                    
            of Action.right:
                if sim.settings.controls.arr == 0 and get_event(sim.events, a).arr_active:
                    discard do_action(sim.state, sim.board, sim.config, Action.hard_right)
                else:
                    discard do_action(sim.state, sim.board, sim.config, Action.right)
            of Action.counter_clockwise:
                discard do_action(sim.state, sim.board, sim.config, Action.counter_clockwise)
            of Action.clockwise:
                discard do_action(sim.state, sim.board, sim.config, Action.clockwise)
            of Action.oneeighty:
                discard do_action(sim.state, sim.board, sim.config, Action.oneeighty)
            of Action.hard_drop:
                # FIXME all this checking and moving of info (that is hard to reach is bad)
                if sim.settings.rules.hist_logging == full_on_lock:
                    sim.mark_history()
                let drop = calc_drop_score(sim.config, sim.board, sim.state, Action.hard_drop, sim.stats.level)  # TODO introduce level into calculation and for the line below
                discard do_action(sim.state, sim.board, sim.config, Action.hard_drop)
                let info = clear_lines(sim.board, sim.state, sim.config)  # TODO add this to the other locking
                if sim.settings.rules.hist_logging == time_on_lock:
                    sim.mark_history($info[1])  # FIXME This is a temporary work around 
                sim.stats.score += calc_score(sim.config, info[0], info[1]) + drop
                discard do_action(sim.state, sim.board, sim.config, Action.lock)
                sim.stats.pieces_placed += 1
                if info[0] > 0:
                    sim.stats.lines_cleared += info[0]
                    # echo info[1]
                    sim.board = info[2]
                    if sim.settings.rules.clear_delay > 0:
                        sim.events.add(Phase_event(start_time: getMonoTime(), phase_type: Phase_type.timer, phase: Game_phase.delay, duration: 0))


            of Action.hard_right:
                # FIXME Changed this to test the garbage

                for a in 0 ..< 4:
                    sim.board.insert_random_garbage(1)
                # echo sim.board

                # discard do_action(sim.state, sim.board, sim.config, Action.hard_right)
            of Action.hard_left:
                discard do_action(sim.state, sim.board, sim.config, Action.hard_left)
            of Action.lock:
                discard do_action(sim.state, sim.board, sim.config, Action.lock)
            of Action.hold:
                if not sim.settings.rules.use_hold_limit or sim.state.hold_available:
                    discard do_action(sim.state, sim.board, sim.config, Action.hold)
                    sim.state.hold_available = false
            of Action.reset:
                sim.reboot_game()
                sim.frame_step(@[])
                tick_action_invalidate_all(sim.events)
                sim.events.del_all(Game_phase.play)
                sim.events.add(Phase_event(start_time: getMonoTime(), phase_type: Phase_type.timer, phase: Game_phase.play, duration: 1000))
                sim.phase = Game_phase.preview
            of Action.undo:
                # discard do_action(sim.state, sim.board, sim.config, Action.undo)
                step_back(sim)
            else:
                echo "missed Action"
    
    of Game_phase.dead:
        return

    of Game_phase.preview, Game_phase.delay:
        while len(sim.state.queue) <= sim.settings.rules.visible_queue_len:
            # echo sim.state.queue
            sim.state.extend_queue(sim.config)
        if sim.state.active.pattern == Block.empty:
            sim.state.set_mino(sim.config, $sim.state.queue[0])
            sim.state.queue = sim.state.queue[1 .. sim.state.queue.high]
        
        for a in inputs:
            if not get_info(sim.events, a):
                var movement: Move_type
                case a:
                of Action.right, Action.left:
                    movement = Move_type.das
                of Action.down:
                    movement = Move_type.continuous
                of Action.hard_drop, Action.hard_left, Action.hard_right, Action.clockwise, Action.counter_clockwise, Action.oneeighty, Action.reset, Action.hold, Action.undo:
                    movement = Move_type.single
                else:
                    movement = Move_type.single
                    echo "Action not set"
                sim.events.add(Action_event(start_time: getMonoTime(), arr_len: sim.settings.controls.arr, das_len: sim.settings.controls.das, movement: movement, action: a))

        discard tick_action(sim.events, inputs)


    else:
        echo "Wierd phase things"
    



if isMainModule:
    echo "Hello World!"
    var preset = getPresetRules("TEC")
    # # echo type(preset[1])
    # quit()
    var sim = initSim(preset[0], preset[1])
    # echo preset
    reboot_game(sim)
    frame_step(sim, @[])

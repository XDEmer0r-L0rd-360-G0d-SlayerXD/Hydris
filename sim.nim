{.experimental: "codeReordering".}
import arraymancer, Board0_3, std/monotimes, tables

# Anything time related should try to stay in ms

type

    Stats* = object
        time*: float
        lines_cleared*: int
        pieces_placed*: int
        score*: int
        lines_sent*: int
    Sim* = object  # TODO may want to get rid of this construct as well
        stats*: Stats  # TODO consider putting stats in state object
        settings*: Settings
        board*: Board
        state*: State
        config*: Rules
        events*: Event_container
        phase*: Game_phase
        # history: seq[(string, Tensor[int])]
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
        min_sds*: float
        gravity_speed*: float
        pregame_time*: float
    Settings* = object
        controls: Control_settings
        play*: Game_Play_settings
        rules*: Other_rules
        

const all_minos* = [Block.T, Block.I, Block.O, Block.L, Block.J, Block.S, Block.Z]


# Use a names such as tetrio to preset rules object to have desired settings
proc getPresetRules*(name: string): (Rules, Settings) = 
    var config: Rules
    var settings: Settings

    template s: Settings = settings.other_rules  # TODO May not need this

    case name:  # FIXME Most of these are unusable due to lazyness
    of "TETRIO":
        config = Rules(preset_name: name, width: 10, height: 24, spawn_x: 4, spawn_y: 21, 
        bag_type: "7 bag", kick_table: "SRS+", can_hold: true)

        settings.rules = Other_rules(visible_height: 20, lock_delay: 0.0, clear_delay: 0.0, 
        allow_clutch_clear: true, min_sds: 0, gravity_speed: 0, pregame_time: 3, visible_queue_len: 5)
    of "MAIN":
        config = Rules(preset_name: name, width: 10, height: 24, spawn_x: 4, spawn_y: 21, 
        bag_type: "7 bag", kick_table: "SRS+", can_hold: true)

        settings.rules = Other_rules(visible_height: 20, lock_delay: 0.0, clear_delay: 0.0, 
        allow_clutch_clear: true, min_sds: 0, gravity_speed: 0, pregame_time: 3, visible_queue_len: 10)
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
    settings.controls = Control_settings(das: 70, arr: 0, sds: 0)

    return (config, settings)


proc initSim*(r: Rules, s: Settings): Sim =
    
    result = Sim(settings: s, config: r, board: initBoard(r), state: State(active: initEmptyMino()))
    # echo result.stats, result.settings, result.config, result.events, result.board, result.state
    # echo result


proc reset_state(sim: var Sim) =
    sim.state = State(active: initEmptyMino())  # This should have the correct default values iirc
    sim.state.holding = "-"
    sim.state.queue = ""


proc reset_stats(sim: var Sim) =
    sim.stats = Stats()


proc reboot_game*(sim: var Sim) =
    ## Wipe the board and reset the state

    sim.board = initBoard(sim.config)
    reset_state(sim)
    reset_stats(sim)


proc frame_step*(sim: var Sim, inputs: seq[Action]) =
    ## This is the main loop of the sim
    
    # Start the game if nothing is ready
    if len(sim.events.phases) == 0:
        sim.events.add(Phase_event(start_time: getMonoTime(), phase_type: Phase_type.stopwatch, phase: Game_phase.play))
        sim.phase = Game_phase.play
    

    let phase_changes = tick_phase(sim.events)
    if len(phase_changes) > 0:
        sim.phase = phase_changes[0]
        case phase_changes[0]:
        of Game_phase.play:
                sim.events.add(Phase_event(start_time: getMonoTime(), phase_type: Phase_type.stopwatch, phase: Game_phase.play))
        of Game_phase.dead:
                sim.events.add(Phase_event(start_time: getMonoTime(), phase_type: Phase_type.timer, phase: Game_phase.preview, duration: 1000))
        of Game_phase.preview:
                sim.events.del_all(Game_phase.play)
                sim.events.add(Phase_event(start_time: getMonoTime(), phase_type: Phase_type.timer, phase: Game_phase.play, duration: 3000))
        else:
            echo "Wierd phase things"

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

        let cleared = sim.board.clear_lines()
        if cleared > 0:
            # echo cleared, " lines cleared"
            sim.stats.lines_cleared += cleared
        # echo cleared, " lines cleared"  # TODO make this conditional

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

        let activations = tick_action(sim.events, inputs)

        for a in activations:
            case a:
            of Action.left:
                    if sim.settings.controls.arr == 0 and get_event(sim.events, a).arr_active:
                        discard do_action(sim.state, sim.board, sim.config, Action.hard_left)
                    else:
                        discard do_action(sim.state, sim.board, sim.config, Action.left)
            of Action.down:
                discard do_action(sim.state, sim.board, sim.config, Action.hard_drop)
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
                discard do_action(sim.state, sim.board, sim.config, Action.hard_drop)
                discard do_action(sim.state, sim.board, sim.config, Action.lock)
            of Action.hard_right:
                discard do_action(sim.state, sim.board, sim.config, Action.hard_right)
            of Action.hard_left:
                discard do_action(sim.state, sim.board, sim.config, Action.hard_left)
            of Action.lock:
                discard do_action(sim.state, sim.board, sim.config, Action.lock)
            of Action.hold:
                discard do_action(sim.state, sim.board, sim.config, Action.hold)
            of Action.reset:
                sim.reboot_game()
                sim.frame_step(@[])
                tick_action_invalidate_all(sim.events)
                sim.events.del_all(Game_phase.play)
                sim.events.add(Phase_event(start_time: getMonoTime(), phase_type: Phase_type.timer, phase: Game_phase.play, duration: 1000))
                sim.phase = Game_phase.preview
            of Action.undo:
                discard do_action(sim.state, sim.board, sim.config, Action.undo)
            else:
                echo "missed Action"
    
    of Game_phase.dead:
        return

    of Game_phase.preview:
        
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
    var preset = getPresetRules("MAIN")
    # # echo type(preset[1])
    # quit()
    var sim = initSim(preset[0], preset[1])
    # echo preset
    reboot_game(sim)
    frame_step(sim, @[])

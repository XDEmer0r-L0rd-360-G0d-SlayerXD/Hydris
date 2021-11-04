{.experimental: "codeReordering".}
import arraymancer, Board0_3, std/monotimes, tables, counter, sequtils, strformat, counter

# TODO try to make spacing nicer
# Anything time related should try to stay in ms
# FIXME All history stuff needs to be changed to also hold the present to avoid timing issues

type

    Stats* = object
        time*: float
        lines_cleared*: int
        pieces_placed*: int
        key_presses*: int
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
        history_state*: seq[Hist_obj_state]
        history_info*: seq[Hist_obj_info]
    Control_settings = object
        das*: float  # units should be ms/square
        arr*: float
        sds*: float  # TODO need to chose between ms/down or down/ms. Is d/ms rn
    Logging_flags* {.size: sizeof(cint).}= enum  # cannot compress when logging only time
        time, state, lock, compression  # Save timestamp, save state, only on lock or every move, attempt compression to trim unneeded moves
    Logging_settings* = set[Logging_flags]  # nim's implimentation of bit fields
    Hist_obj_state* = object
        stats*: Stats
        board*: Board
        state*: State
    Hist_obj_info* = object
        time*: MonoTime
        info*: string
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
        hist_logging*: Logging_settings
        use_hold_limit: bool

    Settings* = object
        controls*: Control_settings
        play*: Game_Play_settings
        rules*: Other_rules
        

const all_minos* = [Block.T, Block.I, Block.O, Block.L, Block.J, Block.S, Block.Z]
    
let all_actions_as_strings* = block:
    var temp: seq[string]
    for a in Action:
        temp.add($a)    
    temp


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
        hist_logging: {time, lock, compression}, use_hold_limit: true)

        settings.controls = Control_settings(das: 70, arr: 0, sds: 0)
    of "MAIN":
        config = Rules(preset_name: name, width: 10, height: 24, spawn_x: 4, spawn_y: 21, 
        bag_type: "7 bag", kick_table: "SRS+", can_hold: true, line_clearing_system: "classic",
        scoring_system: "guideline")

        settings.rules = Other_rules(visible_height: 20, lock_delay: 0.0, clear_delay: 0.0, 
        allow_clutch_clear: true, min_sds: 0, gravity_speed: 0, pregame_time: 3, visible_queue_len: 10,
        hist_logging: {time, state, lock, compression}, use_hold_limit: false)
        
        settings.controls = Control_settings(das: 70, arr: 0, sds: 0)
    of "TEC":
        config = Rules(preset_name: name, width: 10, height: 21, spawn_x: 4, spawn_y: 20, 
        bag_type: "7 bag", kick_table: "SRS", can_hold: true, line_clearing_system: "classic",
        scoring_system: "guideline")

        settings.rules = Other_rules(visible_height: 20, lock_delay: 500, clear_delay: 250, 
        allow_clutch_clear: false, min_sds: 0.2, gravity_speed: 1, pregame_time: 3, visible_queue_len: 5,
        hist_logging: {time, lock}, use_hold_limit: true)
        
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


proc mark_history_state*(sim: var Sim) =
    # TODO add a check to make sure it saves changes
    var next: Hist_obj_state
    next.stats = sim.stats
    next.board = sim.board.clone
    next.state = sim.state
    if (compression in sim.settings.rules.hist_logging) and sim.history_state.len() > 0 and sim.history_state[^1].state == sim.state:  # Only care for unique states (Stops spam from continous movementy types)
        return
    sim.history_state.add(next)

proc mark_history_info*(sim: var Sim, info: string) =  # TODO Only two mark types considered. May want to change or just save everything

    var next = Hist_obj_info(time: getMonoTime())

    template hist: set[Logging_flags] = sim.settings.rules.hist_logging

    if compression in hist:
            # TODO Make sure i'm happy with this. In theory it works, but I need be I can just used the state to generate the next hist steps instead.

        var logged_moves: int
        for a in sim.history_info:
            if (a.info in all_actions_as_strings) and (a.info != $Action.hard_right) and (a.info != $Action.hard_left) and (a.info != $Action.spawn):
                logged_moves.inc()
        
        
        if sim.history_info.len() == 0:

            next.info = info
        
        elif sim.stats.key_presses > logged_moves:  # +1 for the spawn offset

            next.info = info

        elif sim.stats.key_presses == logged_moves:
            
            if info == $Action.right and sim.history_info[^1].info == $Action.right and sim.events.get_event(Action.right).arr_active:  # We assume that there will always be a single move before hard
                next.info = $Action.hard_right
            elif info == $Action.left and sim.history_info[^1].info == $Action.left and sim.events.get_event(Action.left).arr_active:
                next.info = $Action.hard_left
            elif info == $Action.right and sim.history_info[^1].info == $Action.hard_right and sim.events.get_event(Action.right).arr_active and sim.settings.controls.arr == 0:
                return
            elif info == $Action.left and sim.history_info[^1].info == $Action.hard_left and sim.events.get_event(Action.left).arr_active and sim.settings.controls.arr == 0:
                return
            else:
                return
        else:

            return

    else:
        next.info = info


    sim.history_info.add(next)

    # Debug print the history
    # var temp: seq[string]
    # for a in sim.history_info:
    #     temp.add(a.info)
    # echo temp
    # var temp2: seq[int]
    # for a in sim.history_state:
    #     temp2.add(a.state.active_x)
    # echo temp2


proc step_back(sim: var Sim) =
    if len(sim.history_state) > 1:
        discard sim.history_state.pop()
        let change = sim.history_state[^1]
        # echo len(sim.history)
        sim.stats = change.stats
        sim.board = change.board
        sim.state = change.state
    
    # FIXME remove until only enough after counted moves like in mark
    if len(sim.history_info) > 0:
        sim.history_info.del(sim.history_info.high)


proc spawn_mino*(sim: var Sim, mino: string) =
    ## This is a history aware replacement for set_mino
    template hist_flags: set[Logging_flags] = sim.settings.rules.hist_logging
    
    sim.state.set_mino(sim.config, mino)
    if state in hist_flags:
        sim.mark_history_state()
    if time in hist_flags:
        sim.mark_history_info($Action.spawn & " " & mino)
        


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
            template hist: set[Logging_flags] = sim.settings.rules.hist_logging
            if lock notin hist:
                if state in hist:
                    sim.mark_history_state()
                if time in hist:
                    sim.mark_history_info($Action.spawn)
                    discard
        

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

            template hist_flags: set[Logging_flags] = sim.settings.rules.hist_logging

            # incriment key_presses stat
            var event = get_event_ptr(sim.events, a)
            case event.movement:
            of Move_type.single:
                sim.stats.key_presses += 1
            of Move_type.das:
                if not event.arr_active:
                    sim.stats.key_presses += 1
            of Move_type.continuous:
                if not event.arr_active:
                    sim.stats.key_presses += 1
                    event.arr_active = true

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
                let drop = calc_drop_score(sim.config, sim.board, sim.state, Action.hard_drop, sim.stats.level)  # TODO introduce level into calculation and for the line below
                discard do_action(sim.state, sim.board, sim.config, Action.hard_drop)
                let info = clear_lines(sim.board, sim.state, sim.config)  # TODO add this to the other locking
                if lock in hist_flags:
                    if state in hist_flags:
                        sim.mark_history_state()
                    if time in hist_flags:
                        sim.mark_history_info($info[0])  # TODO I probably want to have better info here
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
            
            if lock notin hist_flags:
                if state in hist_flags:
                    sim.mark_history_state()
                if time in hist_flags:
                    sim.mark_history_info($a)
                    discard
            
    
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

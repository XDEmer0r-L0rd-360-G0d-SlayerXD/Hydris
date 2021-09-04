# This file focuses on board manipulations and a stateless way
# We are NOT playing the game
# Anything with the event loops us ms timings

{.experimental: "codeReordering".}
import arraymancer, tables, strformat, random, sequtils, strutils, std/monotimes, times

# cordinates always start from the top left excep for the board which is the only thing that starts at the bottom left

type  # consider changing these to ref objects while testing
    Mino_rotation = object
        rotation_id: int
        shape*: Tensor[int]
        pivot_x: int
        pivot_y: int
        removed_top: int
        removed_right: int
        removed_bottom: int
        removed_left: int
        cleaned_shape*: Tensor[int]
        cleaned_width: int
        cleaned_height: int
        y_max, x_max, y_min, x_min: int  # location when touching walls
    Mino* = object
        rotation_shapes*: array[4, Mino_rotation]
        kick_table: Table[string, seq[(int, int)]]
        pattern*: Block  # basically enum stuff to choose color
    Rules* = object of RootObj # TODO Consider renaming these to allow use of rules elsewhere
        preset_name*: string
        width*: int
        height*: int  # its implied that anything placed fully above height will kill
        spawn_x*: int
        spawn_y*: int
        can_hold*: bool
        bag_type*: string  # how the queue is generated
        bag_minos*: Table[Block, Mino]  # TODO May not want to use key and Mino.pattern be the same
        kick_table*: string  # TODO consider changing this to enum
    State* = object
        active*: Mino  # maybe make this ref?
        active_x*: int
        active_y*: int
        active_r*: int
        holding*: string
        hold_available*: bool
        queue*: string
    Milis = float  # TODO try to propigate this more
    Action_event* = object
        start_time*: MonoTime
        arr_active*: bool
        arr_len*: float
        das_len*: float
        first_tap_done*: bool
        movement*: Move_type
        action*: Action    
    Phase_event* = object 
        start_time*: MonoTime
        # run: bool  # TODO conisder removing this and the do_action field
        # do_action: bool  # use the special functionality that comes with phase_type. Usuall gets info
        phase_type*: Phase_type  # TODO consider adding some kind of id for this, maybe both, events
        phase*: Game_phase
        duration*: float
    Move_type* = enum
        single, continuous, das
    Phase_type* = enum
        stopwatch, timer, 
    Event_container* = object
        actions*: seq[Action_event]
        phases*: seq[Phase_event]
    Action* = enum
        lock, up, right, down, left, counter_clockwise, clockwise, hard_drop, hard_right, hard_left, hold, max_down, max_right, max_left, soft_drop, reset, oneeighty, undo  # TODO do we need all of these actions
    Game_phase* {.pure.}= enum  # dead to delay are not intended to be modified randomly, things will break
        empty, dead, preview, play, paused, delay, game_over, game_time
    Block* = enum
        empty, garbage, ghost, T, I, O, L, J, Z, S
    Board* = Tensor[Block]



const kicks* = {
    "modern_kicks_all": {"0>1": @[(0,0), (-1, 0), (-1, 1), (0, -2), (-1, -2)],
                    "1>0": @[(0, 0), (1, 0), (1, -1), (0, 2), (1, 2)],
                    "1>2": @[(0, 0), (1, 0), (1, -1), (0, 2), (1, 2)],
                    "2>1": @[(0, 0), (-1, 0), (-1, 1), (0, -2), (-1, -2)],
                    "2>3": @[(0, 0), (1, 0), (1, 1), (0, -2), (1, -2)],
                    "3>2": @[(0, 0), (-1, 0), (-1, -1), (0, 2), (-1, 2)],
                    "3>0": @[(0, 0), (-1, 0), (-1, -1), (0, 2), (-1, 2)],
                    "0>3": @[(0, 0), (1, 0), (1, 1), (0, -2), (1, -2)]}.toTable,
    "modern_kicks_I": {"0>1": @[(0,0), (-2, 0), (1, 0), (-2, -1), (1, 2)],
                    "1>0": @[(0,0), (2, 0), (-1, 0), (2, 1), (-1, -2)],
                    "1>2": @[(0,0), (-1, 0), (2, 0), (-1, 2), (2, -1)],
                    "2>1": @[(0,0), (1, 0), (-2, 0), (1, -2), (-2, 1)],
                    "2>3": @[(0,0), (2, 0), (-1, 0), (2, 1), (-1, -2)],
                    "3>2": @[(0,0), (-2, 0), (1, 0), (-2, -1), (1, 2)],
                    "3>0": @[(0,0), (1, 0), (-2, 0), (1, -2), (-2, 1)],
                    "0>3": @[(0,0), (-1, 0), (2, 0), (-1, 2), (2, -1)]}.toTable,
    "tetrio_180": {"0>2": @[(0, 0), (0, 1), (1, 1), (-1, 1), (1, 0), (-1, 0)],
                "2>0": @[(0, 0), (0, -1), (-1, -1), (1, -1), (-1, 0), (1, 0)],
                "1>3": @[(0, 0), (1, 0), (1, 2), (1, 1), (0, 2), (0, 1)],
                "3>1": @[(0, 0), (-1, 0), (-1, 2), (-1, 1), (0, 2), (0, 1)]}.toTable,
    "tetrio_srsp_I": {"0>1": @[(0,0), (1, 0), (-2, 0), (-2, -1), (1, 2)],
                    "1>0": @[(0,0), (-1, 0), (2, 0), (-1, -2), (2, 1)],
                    "1>2": @[(0,0), (-1, 0), (2, 0), (-1, 2), (2, -1)],
                    "2>1": @[(0,0), (-2, 0), (1, 0), (-2, 1), (1, -2)],
                    "2>3": @[(0,0), (2, 0), (-1, 0), (2, 1), (-1, -2)],
                    "3>2": @[(0,0), (1, 0), (-2, 0), (1, 2), (-2, -1)],
                    "3>0": @[(0,0), (1, 0), (-2, 0), (-2, -1), (-2, 1)],
                    "0>3": @[(0,0), (-1, 0), (2, 0), (-2, -1), (-1, 2)]}.toTable}.toTable

let shapes* = {  # (shape that is square, all center cords based on rotation)
    Block.L: ([0, 0, 1, 1, 1, 1, 0, 0, 0].toTensor.reshape(3, 3), @[(1, 1), (1, 1), (1, 1), (1, 1)]),
    Block.J: ([1, 0, 0, 1, 1, 1, 0, 0, 0].toTensor.reshape(3, 3), @[(1, 1), (1, 1), (1, 1), (1, 1)]),
    Block.S: ([0, 1, 1, 1, 1, 0, 0, 0, 0].toTensor.reshape(3, 3), @[(1, 1), (1, 1), (1, 1), (1, 1)]),
    Block.Z: ([1, 1, 0, 0, 1, 1, 0, 0, 0].toTensor.reshape(3, 3), @[(1, 1), (1, 1), (1, 1), (1, 1)]),
    Block.I: ([0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0].toTensor.reshape(4, 4), @[(1, 1), (2, 1), (2, 2), (1, 2)]),
    Block.O: ([1, 1, 1, 1].toTensor.reshape(2, 2), @[(0, 1), (0, 0), (1, 0), (1, 1)]),
    Block.T: ([0, 1, 0, 1, 1, 1, 0, 0, 0].toTensor.reshape(3, 3), @[(1, 1), (1, 1), (1, 1), (1, 1)])
}.toTable


proc rotate_tensor(ten: var Tensor, rotations: int = 1) =
    ## Assumes square and goes clockwise

    let extra = (((rotations mod 4) + 4) mod 4) - 1
    if extra < 0:
        return
    let size = ten.shape[0]
    var temp = ten.zeros_like()
    for a in 0 ..< size:  # TODO remove dependency on square shapes
        for b in 0 ..< size:
            temp[a, b] = ten[size - 1 - b, a]
    ten = temp
    if extra > 0:
        rotate_tensor(ten, extra)  # Technically recursive but should never be more than 3


proc raiseError(msg: string) =
    ## Probably unneeded, but it works
    var e: ref ValueError
    new(e)
    e.msg = msg
    raise e


proc merge(t1: var Table, t2: Table) =
    ## Shallow copy all keys from t2 into t1
    for a in t2.keys:
        t1[a] = t2[a]


func safe_mod(val: int, modulo: int): int =
    ## This will always mod the way I want to, I feel like using the normal mod might have done wierd things and also looked worse
    ((val mod modulo) + modulo) mod modulo


func milli_from_nano(val: int64): float =
    float(val) / 1e6


func milli_from_duration(val: Duration): float =
    let temp = inNanoseconds(val)
    milli_from_nano(temp)


func keys[T, U](t: Table[T, U]): seq[T] =
    for a in t.keys():
        result.add(a)


proc fix_shape_type(t: Tensor[int], b: Block): Tensor[Block] =
    ## Fixes a tensor incompatibility with the way some blocks are stored.
    ## Tensor[int] -> Tensor[Block]
    proc change(val: int): Block =
        Block(val)
        
    var val = t * ord(b)
    val.map(change)


func mino_from_str*(r: Rules, s: string): Mino =
    ## Get the mino version of a string
    case s:
    of "T":
        return r.bag_minos[T]
    of "I":
        return r.bag_minos[I]
    of "O":
        return r.bag_minos[O]
    of "L":
        return r.bag_minos[L]
    of "J":
        return r.bag_minos[J]
    of "S":
        return r.bag_minos[S]
    of "Z":
        return r.bag_minos[Z]


func str_from_block(b: Block): string =
    case b
    of T:
        return "T"
    of I:
        return "I"
    of O:
        return "O"
    of L:
        return "L"
    of J:
        return "J"
    of S:
        return "S"
    of Z:
        return "Z"
    else:
        return "-"


func str_from_mino(m: Mino): string =
    ## Get the string version of a mino
    str_from_block(m.pattern)


proc fake_clone(t: Tensor[Block]): Tensor[Block] =
    ## TODO THIS IS BAD AND SHOULD BE REPLACED SOON
    var new_t = newTensor[Block]([t.shape[0], t.shape[1]])
    for a in 0 ..< t.shape[0]:
        for b in 0 ..< t.shape[1]:
            new_t[a, b] = t[a, b]
    return new_t


proc dev_initRules: Rules =
    ## Rules should not be generated in this file. These are defalt settings for testing
    result = Rules(preset_name: "TETRIO", width: 10, height: 24, spawn_x: 4, spawn_y: 21, can_hold: true, bag_type: "7BAG", kick_table: "SRS+")
    result.initAllMinos()


func initBoard*(rules: Rules): Board =
    newTensor[Block]([rules.height, rules.width])


proc initMino*(rules: Rules, name: Block): Mino =
    ## Use the rules to generate a correct Mino
    var piece_data: Mino = Mino()
    piece_data.pattern = name
    case rules.kick_table:
        of "SRS+":
            if name == Block.I:
                piece_data.kick_table = kicks["tetrio_srsp_I"]
                piece_data.kick_table.merge(kicks["tetrio_180"])
            else:
                piece_data.kick_table = kicks["modern_kicks_all"]
                piece_data.kick_table.merge(kicks["tetrio_180"])
        of "SRS":
            if name == Block.I:
                piece_data.kick_table = kicks["modern_kicks_I"]
            else:
                piece_data.kick_table = kicks["modern_kicks_all"]
        else:
            raiseError("Unimplimented kick table")

    var ready = clone(shapes[name][0])
    for b in 0 ..< 4:
        var rotation = Mino_rotation()
        rotation.rotation_id = b
        rotation.shape = clone(ready)
        rotation.pivot_x = shapes[name][1][b][0]
        rotation.pivot_y = shapes[name][1][b][1]
        var count = 0
        var top_set = false
        for c in 0 ..< rotation.shape.shape[0]:
            if sum(rotation.shape[c, _]) == 0:
                inc(count)
            else:
                if not top_set:
                    rotation.removed_top = count
                top_set = true
                count = 0
        rotation.removed_bottom = count

        count = 0
        var left_set = false
        for c in 0 ..< rotation.shape.shape[0]:
            if sum(rotation.shape[_, c]) == 0:
                inc(count)
            else:
                if not left_set:
                    rotation.removed_left = count
                left_set = true
                count = 0
        rotation.removed_right = count

        rotation.cleaned_shape = rotation.shape[rotation.removed_top .. rotation.shape.shape[0] - rotation.removed_bottom - 1, rotation.removed_left .. rotation.shape.shape[0] - rotation.removed_right - 1]
        rotation.cleaned_width = rotation.cleaned_shape.shape[1]
        rotation.cleaned_height = rotation.cleaned_shape.shape[0]

        rotation.y_max = rules.height - (rotation.pivot_y - rotation.removed_top) - 1
        rotation.x_max = rules.width - (rotation.shape.shape[1] - rotation.pivot_x - rotation.removed_right - 1) - 1
        rotation.y_min = rotation.shape.shape[0] - rotation.pivot_y - rotation.removed_bottom - 1
        rotation.x_min = rotation.pivot_x - rotation.removed_left

        piece_data.rotation_shapes[b] = rotation
        rotate_tensor(ready)
    return piece_data


proc initEmptyMino*: Mino =
    result.pattern = Block.empty
    var base: Mino_rotation
    base.shape = newTensor[int](1)
    base.cleaned_shape = base.shape.clone()
    result.rotation_shapes = [base, base, base, base]


proc initAllMinos*(rules: var Rules) =
    # TODO consider making the functional
    if rules.preset_name == "TETRIO" or rules.preset_name == "MAIN" or rules.preset_name == "TEC":
        for a in [Block.T, Block.I, Block.O, Block.L, Block.J, Block.S, Block.Z]:
            # echo initMino(rules, a)
            rules.bag_minos[a] = initMino(rules, a)
    # echo rules


proc set_mino*(state: var State, rules: Rules, mino: string) =
    state.active = mino_from_str(rules, mino)
    state.active_x = rules.spawn_x
    state.active_y = rules.spawn_y - 1
    state.active_r = 0


proc debug_print_board(board: Board) =
    var line: seq[int]
    for a in 0 ..< board.shape[0]:
        line.setLen(0)
        for b in 0 ..< board.shape[1]:
            if board[a, b] == Block.empty:
                line.add(0)
            else:
                line.add(1)
        echo line


proc test_location*(b: Board, m: Mino, x, y, r: int): (bool, bool, Board) =  # (In bounds, fits w/ no colisions, example output)
    template mshape: Mino_rotation = m.rotation_shapes[r.safe_mod(4)]

    if x < mshape.x_min or x > mshape.x_max or y < mshape.y_min or y > mshape.y_max:
        return (false, false, b)

    var sample = b.clone()
    var sx, sy: int
    var cleanly = true
    var block_val: Block

    let cleaned = mshape.cleaned_shape.fix_shape_type(m.pattern)

    for a in 0 ..< mshape.cleaned_height:
        for b in 0 ..< mshape.cleaned_width:
            # find out corresponding coords on the sample board
            sy = sample.shape[0] - 1 - y - (mshape.pivot_y - mshape.removed_top) + a
            sx = x - (mshape.pivot_x - mshape.removed_left) + b

            # check for collision and then set
            if (sample[sy, sx] != Block.empty) and (cleaned[a, b] != Block.empty):
                cleanly = false

            if cleaned[a, b] != Block.empty:
                sample[sy, sx] = cleaned[a, b]

    return (true, cleanly, sample)


proc test_location*(b: Board, s: State): (bool, bool, Board) =
    b.test_location(s.active, s.active_x, s.active_y, s.active_r)


# Interprates the Action enum
proc get_new_location*(b: Board, s: State, a: Action): array[3, int] =

    case a:
    of Action.lock:
        return [s.active_x, s.active_y, s.active_r]
    of Action.up:
        return [s.active_x, s.active_y + 1, s.active_r]
    of Action.right:
        return [s.active_x + 1, s.active_y, s.active_r]
    of Action.down:
        return [s.active_x, s.active_y - 1, s.active_r]
    of Action.left:
        return [s.active_x - 1, s.active_y, s.active_r]
    of Action.counter_clockwise:
        let new_r = safe_mod(s.active_r + 3, 4)
        return [s.active_x + s.active.rotation_shapes[new_r].pivot_x - s.active.rotation_shapes[s.active_r].pivot_x, s.active_y - s.active.rotation_shapes[new_r].pivot_y + s.active.rotation_shapes[s.active_r].pivot_y, new_r]
    of Action.clockwise:
        let new_r = safe_mod(s.active_r + 1, 4)
        return [s.active_x + s.active.rotation_shapes[new_r].pivot_x - s.active.rotation_shapes[s.active_r].pivot_x, s.active_y - s.active.rotation_shapes[new_r].pivot_y + s.active.rotation_shapes[s.active_r].pivot_y, new_r]
    of Action.oneeighty:
        let new_r = safe_mod(s.active_r + 2, 4)
        return [s.active_x + s.active.rotation_shapes[new_r].pivot_x - s.active.rotation_shapes[s.active_r].pivot_x, s.active_y - s.active.rotation_shapes[new_r].pivot_y + s.active.rotation_shapes[s.active_r].pivot_y, new_r]
    of Action.max_down:
        return [s.active_x, s.active.rotation_shapes[s.active_r].y_min, s.active_r]
    of Action.max_right:
        return [s.active.rotation_shapes[s.active_r].x_max, s.active_y, s.active_r]
    of Action.max_left:
        return [s.active.rotation_shapes[s.active_r].x_min, s.active_y, s.active_r]
    of Action.hard_drop:  # TODO conisder a hard_up
        var movement = get_new_location(b, s, Action.max_down)
        var offset = 0
        var new_loc: (bool, bool, Board)
        while movement[1] <= s.active_y - offset:
            new_loc = test_location(b, s.active, movement[0], s.active_y - offset, movement[2])
            if new_loc[0] and new_loc[1]:
                offset.inc()
            else:
                return [s.active_x, s.active_y - offset + 1, s.active_r]
        return [s.active_x, movement[1], s.active_r]
    of Action.hard_right:
        var movement = get_new_location(b, s, Action.max_right)
        var offset = 0
        var new_loc: (bool, bool, Board)
        while movement[0] >= s.active_x + offset:
            new_loc = test_location(b, s.active, s.active_x + offset, movement[1], movement[2])
            if new_loc[0] and new_loc[1]:
                offset.inc()
            else:
                return [s.active_x + offset - 1, s.active_y, s.active_r]
        return [movement[0], s.active_y, s.active_r]
    of Action.hard_left:
        var movement = get_new_location(b, s, Action.max_left)
        var offset = 0
        var new_loc: (bool, bool, Board)
        while movement[0] <= s.active_x + offset:
            new_loc = test_location(b, s.active, s.active_x - offset, movement[1], movement[2])
            if new_loc[0] and new_loc[1]:
                offset.inc()
            else:
                return [s.active_x - offset + 1, s.active_y, s.active_r]
        return [movement[0], s.active_y, s.active_r]

    else:
        return [s.active_x, s.active_y, s.active_r]  # this is a generic fallback


proc do_action*(s: var State, b: var Board, r: Rules, move: Action): bool =  # TODO this one breaks convention from a functional to a oop design
    # TODO This one may do wierd things. I haven't checked everything properly. Just fixed incompatible things
    case move:
    of Action.up, Action.right, Action.down, Action.left, Action.hard_drop, Action.hard_left, Action.hard_right:
        # get new pos, test, change active cords
        var movement = get_new_location(b, s, move)
        var new_loc = test_location(b, s.active, movement[0], movement[1], movement[2])
        if not new_loc[0] or not new_loc[1]:
            # this should only trigger via left and right because they don't check for bounds in their calcs
            return false
        s.active_x = movement[0]
        s.active_y = movement[1]
        s.active_r = movement[2]
    of Action.counter_clockwise, Action.clockwise, Action.oneeighty:
        var movement = get_new_location(b, s, move)
        var new_loc = test_location(b, s.active, movement[0], movement[1], movement[2])
        let kicks = s.active.kick_table[fmt"{s.active_r}>{movement[2]}"]
        var new_x: int
        var new_y: int
        for a in kicks:
            new_x = movement[0] + a[0]
            new_y = movement[1] + a[1]

            new_loc = test_location(b, s.active, new_x, new_y, movement[2])
            if new_loc[0] and new_loc[1]:
                s.active_x = new_x
                s.active_y = new_y
                s.active_r = movement[2]
                return true
        return false

    of Action.lock:
        var movement = get_new_location(b, s, move)
        var new_loc = test_location(b, s.active, movement[0], movement[1], movement[2])
        if not new_loc[0] or not new_loc[1]:
            return false
        b = new_loc[2]
        s.active = mino_from_str(r, $s.queue[0])
        s.queue = s.queue[1 .. s.queue.high]
        s.hold_available = true
        s.active_x = r.spawn_x
        s.active_y = r.spawn_y - 1
        s.active_r = 0

    of Action.hold:
        # todo limit holds and use that when to rutern true or false
        var temp = s.active.str_from_mino()
        if s.holding == "-":
            s.holding = temp
            s.active = mino_from_str(r, $s.queue[0])
            s.queue = s.queue[1 .. s.queue.high]
        else:
            s.active = mino_from_str(r, s.holding)
            s.holding = temp

        s.hold_available = false
        s.active_x = r.spawn_x
        s.active_y = r.spawn_y - 1
        s.active_r = 0

    else:
        echo "else hit"
        return false

    return true


proc extend_queue*(s: var State, r: Rules, steps: int = 1) =
    for a in 0 ..< steps:
        case r.bag_type:
        of "random":
            s.queue = s.queue & str_from_block(sample(r.bag_minos.keys()))
        of "7 bag":
            var temp: seq[string]
            for a in r.bag_minos.keys:
                temp.add(str_from_block(a))
            temp.shuffle()
            s.queue = s.queue & temp.join()
            # echo r.bag_minos.keys


proc clear_lines*(board: var Board): int =
    ## Returns the number of full lines while clearing them from the current board
    var lines: seq[int]
    for a in 0 ..< board.shape[0]:
        block row:
            for b in board[a, _]:
                if b == Block.empty:
                    break row
            lines.add(a)

    var skips = 0
    for a in countdown(board.shape[0] - 1, 0):
        if a notin lines:
            board[a + skips, _] = board[a, _]
        else:
            skips.inc()

    if len(lines) > 0:
        board[0 ..< len(lines), _] = Block.empty
    
    return skips


proc insert_garbage(board: var Board, garbage: Tensor[Block]) =
    for a in 0 ..< board.shape[0] - garbage.shape[0]:
        board[a, _] = board[a + garbage.shape[0], _]
    
    board[^garbage.shape[0]..^1, _] = garbage


proc insert_random_garbage*(board: var Board, amount: int) =
    let col = rand(board.shape[1] - 1)
    var garbage = newTensor[Block]([amount, board.shape[1]])
    garbage[_, _] = Block.garbage
    garbage[_, col] = Block.empty
    insert_garbage(board, garbage)


### Adds event loop stuff

proc add*(container: var Event_container, action: Action_event) =
    container.actions.add(action)


proc add*(container: var Event_container, phase: Phase_event) =
    container.phases.add(phase)


proc del*(container: var Event_container, action: Action) =  # TODO all things with delete will probably delete wring things if multiple found

    template act: seq[Action_event] = container.actions

    for a in 0 .. container.actions.high:
        if act[a].action == action:
            act.del(a)
            return


proc del*(container: var Event_container, phase: Game_phase) =  

    template act: seq[Phase_event] = container.phases

    for a in 0 .. act.high:
        if act[a].phase == phase:
            act.del(a)
            return


proc del_all*(container: var Event_container, phase: Game_phase) =
    
    template phases: seq[Phase_event] = container.phases

    var offset = 0
    for a in 0 .. phases.high:
        if phases[a - offset].phase == phase:
            phases.del(a - offset)
            offset += 1



proc tick_action*(container: var Event_container, actions: seq[Action]): seq[Action] =
    ## Runnig the Action loop ticks while removing unpressed keys
    
    template act: seq[Action_event] = container.actions

    # TODO I should be able to combine this in a single loop
    var offset = 0
    for a in 0 .. act.high:
        if act[a - offset].action notin actions:
            act.delete(a - offset)
            offset = offset + 1
    
    var activations: seq[Action]

    for a in 0 .. act.high:
        if not act[a].first_tap_done:
            act[a].first_tap_done = true
            activations.add(act[a].action)
        elif act[a].movement == Move_type.das and not act[a].arr_active and getMonoTime() - act[a].start_time > initDuration(milliseconds = toInt(act[a].das_len)):  # das done
            act[a].start_time = act[a].start_time + initDuration(milliseconds = toInt(act[a].das_len))  # todo consider moving these to down to when I actually press things. Also these are prob + not -
            act[a].arr_active = true
            activations.add(act[a].action)
        elif act[a].movement == Move_type.das and act[a].arr_active and getMonoTime() - act[a].start_time > initDuration(milliseconds = toInt(act[a].arr_len)):  # arr done
            act[a].start_time = act[a].start_time + initDuration(milliseconds = toInt(act[a].arr_len))
            activations.add(act[a].action)
        elif act[a].movement == Move_type.continuous:
            if act[a].action == Action.down and getMonoTime() - act[a].start_time > initDuration(milliseconds = toInt(act[a].arr_len)):
                act[a].start_time = act[a].start_time + initDuration(milliseconds = toInt(act[a].arr_len))
                activations.add(act[a].action)

    return activations


proc tick_action_invalidate_all*(container: var Event_container) =
    ## Invalidates all action inputs
    
    container.actions = @[]
    for a in Action:
        let temp = Action_event(first_tap_done: true, movement: Move_type.single, action: a)
        container.actions.add(temp)


proc tick_phase*(container: var Event_container): seq[Game_phase] =
    ## This effectively auto queries all stopwatches and removes it when triggered
    
    template phas: seq[Phase_event] = container.phases

    var triggered: seq[Game_phase]

    var offset = 0
    for a in 0 .. phas.high:
        if phas[a - offset].phase_type == Phase_type.timer and getMonoTime() - phas[a - offset].start_time > initDuration(milliseconds = toInt(phas[a - offset].duration)):
            triggered.add(phas[a - offset].phase)
            phas.delete(a - offset)  # TODO can probably be changed to del
            offset = offset + 1
    
    return triggered


proc tick_events*(container: var Event_container, actions: seq[Action]): (seq[Action], seq[Game_phase]) =
    let act = tick_action(container, actions)
    let phas = tick_phase(container)
    return (act, phas)


proc get_info*(container: Event_container, act: Action): bool =
    ## Check if an action is active
    for a in container.actions:
        if a.action == act:
            return true
    return false


proc get_info*(container: Event_container, phase: Game_phase): float =
    for a in container.phases:
        if a.phase == phase:
            if a.phase_type == Phase_type.stopwatch:
                let diff = getMonoTime() - a.start_time
                return milli_from_duration(diff)
            elif a.phase_type == Phase_type.timer:
                let diff = a.start_time + initDuration(toInt(a.duration*1e6)) - getMonoTime()
                return milli_from_duration(diff)
    return 0


proc get_event*(container: Event_container, act: Action): Action_event =
    for a in container.actions:
        if a.action == act:
            return a


proc get_event*(container: Event_container, phase: Game_phase): Phase_event =
    for a in container.phases:
        if a.phase == phase:
            return a


if isMainModule:
    # DEBUG TESTING
    var test_rules = dev_initRules()
    var test_board = initBoard(test_rules)
    echo type(test_board)
    echo test_rules.bag_minos[Block.T].rotation_shapes[3].y_max
    # var board = newTensor[Block]([24, 10])
    echo test_location(test_board, test_rules.bag_minos[L], 5, 5, 1)
    echo clear_lines(test_board)

echo "Imported Board0_3.nim"
{.experimental: "codeReordering".}
import tables, arraymancer, sequtils, strutils, strformat, rdstdin, random, os
import raylib, rayutils
# import math, random

# cordinates always start from the top left excep for the board which is the only thing that starts at the bottom left

type  # consider changing these to ref objects while testing
    Mino_rotation = object
        rotation_id: int
        shape: Tensor[int]
        pivot_x: int
        pivot_y: int
        removed_top: int
        removed_right: int
        removed_bottom: int
        removed_left: int
        cleaned_shape: Tensor[int]
        cleaned_width: int
        cleaned_height: int
        map_bounds: array[4, int]  # starts north and then goes clockwise
    Mino = object
        name: string
        rotation_shapes: seq[Mino_rotation]
        kick_table: Table[string, seq[(int, int)]]
        pattern: int  # basically enum stuff to choose color
    Rules = object
        name: string
        width: int
        visible_height: int
        height: int  # its implied that anything placed fully above height will kill
        place_delay: float
        clear_delay: float
        spawn_x: int
        spawn_y: int
        allow_clutch_clear: bool
        softdrop_duration: float
        can_hold: bool
        bag_piece_names: string
        bag_type: string
        bag_minos: seq[Mino]
        kick_table: string
        visible_queue_len: int
        gravity_speed: int
    State = object
        game_active: bool
        active: Mino  # maybe make this ref? 
        active_x: int
        active_y: int
        active_r: int
        hold: string
        hold_available: bool
        queue: string
        current_combo: int
    Stats = object
        time: float
        lines_cleared: int
        pieces_placed: int
        score: int
        lines_sent: int
    Game = object
        rules: Rules
        board: Tensor[int]
        state: State
        stats: Stats
        settings: Settings
    Action = enum
        lock, up, right, down, left, counter_clockwise, clockwise, hard_drop, hard_right, hard_left, hold, max_down, max_right, max_left, soft_drop, reset
    Move_type = enum
        single, continuous, das
    Visual_settings = object
        game_field_offset_left: float
        game_field_offset_top: float
        game_field_units_wide: int
        game_field_board_padding_left: int
        window_height: int
        window_width: int
    Control_settings = object
        das: float  # units should be ms/square
        arr: float
        sds: float  # soft drop speed
        dasable_keys: seq[KeyboardKey]
        keybinds: Table[KeyboardKey, Action]
    Game_Play_settings = object
        ghost: bool
    Settings = object
        visuals: Visual_settings
        controls: Control_settings
        play: Game_Play_settings
    Key_event = object
        name: KeyboardKey
        start_time: float
        arr_active: bool
        first_tap: bool
        movement: Move_type
        action: Action
        

var game*: Game
var rules* = addr(game.rules)
var settings* = addr(game.settings)


# Helpers

proc `*`(x: float, y: int): float =
    return x * toFloat(y)

proc `/`(x: float, y: int): float =
    return x / toFloat(y)

proc `in`(x: KeyboardKey, y: seq[Key_event]): bool =
    for a in y:
        # echo fmt"{KeyboardKey(x)}, {a.name}"
        if KeyboardKey(x) == a.name:
            return true
    return false

proc `notin`(x: KeyboardKey, y: seq[Key_event]): bool =
    return not (x in y)

# I may need this later depending on how I choose to represent board colors later
proc has_val_to_one(x: int): int =
    if x == 0:
        return 0
    return 1


# Main

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
    'L': ([0, 0, 1, 1, 1, 1, 0, 0, 0].toTensor.reshape(3, 3), @[(1, 1), (1, 1), (1, 1), (1, 1)]),
    'J': ([1, 0, 0, 1, 1, 1, 0, 0, 0].toTensor.reshape(3, 3), @[(1, 1), (1, 1), (1, 1), (1, 1)]),
    'S': ([0, 1, 1, 1, 1, 0, 0, 0, 0].toTensor.reshape(3, 3), @[(1, 1), (1, 1), (1, 1), (1, 1)]),
    'Z': ([1, 1, 0, 0, 1, 1, 0, 0, 0].toTensor.reshape(3, 3), @[(1, 1), (1, 1), (1, 1), (1, 1)]),
    'I': ([0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0].toTensor.reshape(4, 4), @[(1, 1), (2, 1), (2, 2), (1, 2)]),
    'O': ([1, 1, 1, 1].toTensor.reshape(2, 2), @[(0, 0), (1, 0), (1, 1), (0, 1)]),
    'T': ([0, 1, 0, 1, 1, 1, 0, 0, 0].toTensor.reshape(3, 3), @[(1, 1), (1, 1), (1, 1), (1, 1)])
}.toTable


proc raiseError(msg: string) =
    var e: ref ValueError
    new(e)
    e.msg = msg
    raise e


# Shallow copy all keys from t2 into t1
proc merge(t1: var Table, t2: Table) =
    for a in t2.keys:
        t1[a] = t2[a]


# Assumes square and goes clockwise
proc rotate_tensor(ten: var Tensor, rotations: int = 1) =
    let extra = (((rotations mod 4) + 4) mod 4) - 1
    if extra < 0:
        return
    let size = ten.shape[0]
    var temp = ten.zeros_like()
    for a in 0 ..< size:
        for b in 0 ..< size:
            temp[a, b] = ten[size - 1 - b, a]
    ten = temp
    if extra > 0:
        rotate_tensor(ten, extra)  # Technically recursive but should never be more than 3



# generate the rules.bag_minos based on rules
proc createMinos =
    rules.bag_minos = @[]

    for a in rules.bag_piece_names:
        var piece_data: Mino = Mino()
        piece_data.name = $a
        piece_data.pattern = 0
        case rules.kick_table:
            of "SRS+":
                if a == 'I':
                    piece_data.kick_table = kicks["tetrio_srsp_I"]
                    piece_data.kick_table.merge(kicks["tetrio_180"])
                else:
                    piece_data.kick_table = kicks["modern_kicks_all"]
                    piece_data.kick_table.merge(kicks["tetrio_180"])
            else:
                raiseError("Unimplimented kick table")
        
        var ready = clone(shapes[a][0])
        for b in 0 ..< 4:
            var rotation = Mino_rotation()
            rotation.rotation_id = b
            rotation.shape = clone(ready)
            rotation.pivot_x = shapes[a][1][b][0]
            rotation.pivot_y = shapes[a][1][b][1]
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

            rotation.map_bounds[0] = rules.height - (rotation.pivot_y - rotation.removed_top) - 1
            rotation.map_bounds[1] = rules.width - (rotation.shape.shape[1] - rotation.pivot_x - rotation.removed_right - 1) - 1
            rotation.map_bounds[2] = rotation.shape.shape[0] - rotation.pivot_y - rotation.removed_bottom - 1
            rotation.map_bounds[3] = rotation.pivot_x - rotation.removed_left

            piece_data.rotation_shapes.add(rotation)
            rotate_tensor(ready)
        rules.bag_minos.add(piece_data)


proc get_mino(name: string): Mino =
    for a in rules.bag_minos:
        if a.name == name:
            return a
    # no check done for fake mino names


# Use a names such as tetrio to preset rules object to have desired settings
proc setRules(name: string) = 
    case name:
        of "TETRIO":
            game.rules = Rules(name: name, width: 10, visible_height: 20, height: 24, place_delay: 0.0, 
            clear_delay: 0.0, spawn_x: 4, spawn_y: 21, allow_clutch_clear: true, softdrop_duration: 0, 
            bag_piece_names: "JLSZIOT", bag_type: "7 bag", kick_table: "SRS+", can_hold: true, visible_queue_len: 5, gravity_speed: 0
            )
        of "MAIN":
            game.rules = Rules(name: name, width: 10, visible_height: 20, height: 24, place_delay: 0.0, 
            clear_delay: 0.0, spawn_x: 4, spawn_y: 21, allow_clutch_clear: true, softdrop_duration: 0, 
            bag_piece_names: "JLZSIOT", bag_type: "random", kick_table: "SRS+", can_hold: true, visible_queue_len: 10, gravity_speed: 0
            )
        of "MINI TESTING":
            game.rules = Rules(name: name, width: 6, visible_height: 6, height: 10, place_delay: 0.0, 
            clear_delay: 0.0, spawn_x: 2, spawn_y: 8, allow_clutch_clear: false, softdrop_duration: 0, 
            bag_piece_names: "JLZSIOT", bag_type: "7 bag", kick_table: "SRS+", can_hold: true, visible_queue_len: 10, gravity_speed: 0
            )
        of "WACKY":
            game.rules = Rules(name: name, width: 8, visible_height: 5, height: 5, place_delay: 0.0, 
            clear_delay: 0.0, spawn_x: 2, spawn_y: 3, allow_clutch_clear: false, softdrop_duration: 0, 
            bag_piece_names: "TTT", bag_type: "random", kick_table: "SRS+", can_hold: true, visible_queue_len: 10, gravity_speed: 0
            )
        else:
            var e: ref ValueError
            new(e)
            e.msg = "name name doesn't exist"
            raise e

    createMinos()


# todo fix this to also show where the active piece is located
proc print_game =
    var temp = test_current_location()
    for a in 0 ..< rules.height:
        var line: seq[int]
        for b in 0 ..< rules.width:
            line.add(temp[0][a, b])
        echo line
    echo fmt"({game.state.hold})  {game.state.active.name}  {game.state.queue}"


# A test that can happen without messing with game state
proc test_location_custom(x: int, y: int, r_val: int, m: Mino, t: Tensor[int]): (Tensor[int], bool, bool) =  # (out map, possible location, requires colisions)
    let r = r_val mod 4
    if x < m.rotation_shapes[r].map_bounds[3] or x > m.rotation_shapes[r].map_bounds[1] or y > m.rotation_shapes[r].map_bounds[0] or y < m.rotation_shapes[r].map_bounds[2]:
        return (t, false, false)

    var colissions = false
    var base = zeros_like(t)

    let active = m.rotation_shapes[r]
    let shape = active.cleaned_shape.shape
    for a in 0..<shape[0]:
        for b in 0..<shape[1]:
            # I think this is right? todo
            base[base.shape[0]-1-y-(active.pivot_y-active.removed_top)+a, x - (active.pivot_x - active.removed_left) + b] = active.cleaned_shape[a, b]
            if t[base.shape[0]-1-y-(active.pivot_y-active.removed_top)+a, x - (active.pivot_x - active.removed_left) + b] == 1 and active.cleaned_shape[a, b] == 1:
                colissions = true
    base += t
    return (base, true, colissions)
    


# Test current location
proc test_current_location(): (Tensor[int], bool, bool) =
    return test_location_custom(game.state.active_x, game.state.active_y, game.state.active_r, game.state.active, game.board)


# A way to get user input rn
proc get_user_action(): Action =
    echo fmt"User input(0-7)>"
    var action = readline(stdin)
    # var action = "3"
    # echo action, type(action)
    case action:
    of "0":
        result = Action.lock
    of "1":
        result = Action.up
    of "2":
        result = Action.right
    of "3":
        result = Action.down
    of "4":
        result = Action.left
    of "5":
        result = Action.counter_clockwise
    of "6":
        result = Action.clockwise
    of "7":
        result = Action.hard_drop


# Interprates the Action enum
proc get_new_location(a: Action): array[3, int] =
    
    case a:
    of Action.lock:
        return [game.state.active_x, game.state.active_y, game.state.active_r]
    of Action.up:
        return [game.state.active_x, game.state.active_y + 1, game.state.active_r]
    of Action.right:
        return [game.state.active_x + 1, game.state.active_y, game.state.active_r]
    of Action.down:
        return [game.state.active_x, game.state.active_y - 1, game.state.active_r]
    of Action.left:
        return [game.state.active_x - 1, game.state.active_y, game.state.active_r]
    of Action.counter_clockwise:
        let new_r = (game.state.active_r + 3) mod 4
        return [game.state.active_x + game.state.active.rotation_shapes[new_r].pivot_x - game.state.active.rotation_shapes[game.state.active_r].pivot_x, game.state.active_y - game.state.active.rotation_shapes[new_r].pivot_y + game.state.active.rotation_shapes[game.state.active_r].pivot_y, new_r]
    of Action.clockwise:
        let new_r = (game.state.active_r + 1) mod 4
        return [game.state.active_x + game.state.active.rotation_shapes[new_r].pivot_x - game.state.active.rotation_shapes[game.state.active_r].pivot_x, game.state.active_y - game.state.active.rotation_shapes[new_r].pivot_y + game.state.active.rotation_shapes[game.state.active_r].pivot_y, new_r]
    of Action.max_down:
        return [game.state.active_x, game.state.active.rotation_shapes[game.state.active_r mod 4].map_bounds[2], game.state.active_r mod 4]
    of Action.max_right:
        return [game.state.active.rotation_shapes[game.state.active_r].map_bounds[1], game.state.active_y, game.state.active_r]
    of Action.max_left:
        return [game.state.active.rotation_shapes[game.state.active_r].map_bounds[3], game.state.active_y, game.state.active_r]
    of Action.hard_drop:
        var movement = get_new_location(Action.max_down)
        var offset = 0
        var new_loc: (Tensor[int], bool, bool)
        var hit = false
        while movement[1] <= game.state.active_y - offset:
            new_loc = test_location_custom(movement[0], game.state.active_y - offset, movement[2], game.state.active, game.board)
            if new_loc[1] and not new_loc[2]:
                offset.inc()
            else:
                return [game.state.active_x, game.state.active_y - offset + 1, game.state.active_r]
        return [game.state.active_x, movement[1], game.state.active_r]
    of Action.hard_right:
        var movement = get_new_location(Action.max_right)
        var offset = 0
        var new_loc: (Tensor[int], bool, bool)
        var hit = false
        while movement[0] >= game.state.active_x + offset:
            new_loc = test_location_custom(game.state.active_x + offset, movement[1], movement[2], game.state.active, game.board)
            if new_loc[1] and not new_loc[2]:
                offset.inc()
            else:
                echo "colision"
                return [game.state.active_x + offset - 1, game.state.active_y, game.state.active_r]
        echo "wall"
        return [movement[0], game.state.active_y, game.state.active_r]
    of Action.hard_left:
        var movement = get_new_location(Action.max_left)
        echo movement
        var offset = 0
        var new_loc: (Tensor[int], bool, bool)
        var hit = false
        while movement[0] <= game.state.active_x + offset:
            new_loc = test_location_custom(game.state.active_x - offset, movement[1], movement[2], game.state.active, game.board)
            if new_loc[1] and not new_loc[2]:
                offset.inc()
            else:
                return [game.state.active_x - offset + 1, game.state.active_y, game.state.active_r]
        return [movement[0], game.state.active_y, game.state.active_r]

    else:
        return [game.state.active_x, game.state.active_y, game.state.active_r]  # this is a generic fallback


proc evaluate_board() =
    var remove: seq[int]
    for a in 0 ..< rules.height:
        if product(game.board[a, _]) >= 1:
            remove.add(a)
            
    var temp = zeros_like(game.board)
    var skips = 0
    for a in countdown(rules.height - 1, 0):
        if a notin remove:
            temp[a + skips, _] = game.board[a, _]
        else:
            skips.inc()
    
    game.board = temp


proc newGame =
    var game_type = "TETRIO"
    setRules(game_type)
    game.board = zeros[int]([rules.height, rules.width])
    game.state = State()
    game.stats = Stats()
    

# prepare the initial state
proc startGame =
    game.state.game_active = true
    game.state.active.name = "-"
    game.state.active_x = rules.spawn_x
    game.state.active_y = rules.spawn_y
    game.state.active_r = 0
    game.state.hold = "-"
    game.state.queue = ""  # todo use random
    game.state.current_combo = 0


proc do_action(move: Action): bool =
    
    case move:
    of Action.up, Action.right, Action.down, Action.left, Action.hard_drop, Action.hard_left, Action.hard_right:
        # get new pos, test, change active cords
        var movement = get_new_location(move)
        var new_loc = test_location_custom(movement[0], movement[1], movement[2], game.state.active, game.board)
        if not new_loc[1] or new_loc[2]:
            echo "this should never trigger"
            echo new_loc[1], new_loc[2], movement
            return false
        echo 1
        game.state.active_x = movement[0]
        game.state.active_y = movement[1]
        game.state.active_r = movement[2]
    of Action.counter_clockwise, Action.clockwise:
        var movement = get_new_location(move)
        var new_loc = test_location_custom(movement[0], movement[1], movement[2], game.state.active, game.board)
        let kicks = game.state.active.kick_table[fmt"{game.state.active_r}>{movement[2]}"]
        var new_x: int
        var new_y: int
        for a in kicks:
            new_x = movement[0] + a[0]
            new_y = movement[1] + a[1]

            new_loc = test_location_custom(new_x, new_y, movement[2], game.state.active, game.board)
            if new_loc[1] and not new_loc[2]:
                game.state.active_x = new_x
                game.state.active_y = new_y
                game.state.active_r = movement[2]
                return true
        return false

    of Action.lock:
        var movement = get_new_location(move)
        var new_loc = test_location_custom(movement[0], movement[1], movement[2], game.state.active, game.board)
        if not new_loc[1] or new_loc[2]:
            return false
        game.board = new_loc[0]
        game.state.active = get_mino($game.state.queue[0])
        game.state.queue = game.state.queue[1 .. game.state.queue.high]
        game.state.hold_available = true
        game.state.active_x = game.rules.spawn_x
        game.state.active_y = game.rules.spawn_y
        game.state.active_r = 0
    
    of Action.hold:
        # todo limit holds and use that when to rutern true or false
        var temp = game.state.active.name
        if game.state.hold == "-":
            game.state.hold = temp
            game.state.active = get_mino($game.state.queue[0])
            game.state.queue = game.state.queue[1 .. game.state.queue.high]
        else:
            game.state.active = get_mino(game.state.hold)
            game.state.hold = temp

        game.state.hold_available = false
        game.state.active_x = game.rules.spawn_x
        game.state.active_y = game.rules.spawn_y
        game.state.active_r = 0
    
    else:
        echo "else hit"
        return false
    
    return true


proc fix_queue() =
    
    case rules.bag_type:
    of "random":
        while len(game.state.queue) < rules.visible_queue_len + 3:
            game.state.queue = game.state.queue & $sample(rules.bag_piece_names)
    of "7 bag":
        var temp = rules.bag_piece_names
        while len(game.state.queue) < rules.visible_queue_len + 7:
            temp.shuffle()
            game.state.queue = game.state.queue & temp
    if game.state.active.name == "-":
        game.state.active = get_mino($game.state.queue[0])
        game.state.queue = game.state.queue[1 .. game.state.queue.high]


proc draw_game() =
    # We assume were in drawing mode
    let v = settings.visuals
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
                draw_square(settings.visuals.game_field_board_padding_left + rules.width + 1 + x, a * 5 + y, col)
    
    if game.state.hold != "-":
        mino = get_mino(game.state.hold)
        for y in 0 ..< mino.rotation_shapes[0].shape.shape[0]:
            for x in 0 ..< mino.rotation_shapes[0].shape.shape[1]:
                if mino.rotation_shapes[0].shape[y, x] == 1:
                    col = makecolor(200, 0, 0)
                else:
                    col = makecolor(50, 50, 50)
                draw_square(x, y, col)
        


proc set_settings() =
    # Todo check for file later. I'll just use defaults for now.
    settings.visuals.game_field_offset_left = 0.1
    settings.visuals.game_field_offset_top = 0.1
    settings.visuals.game_field_units_wide = 10 + rules.width  # todo change the order of calling settings and game to allow loading later
    settings.visuals.game_field_board_padding_left = 5
    settings.visuals.window_height = 900
    settings.visuals.window_width = 800
    # only debug hard_left, hard_right, and lock left in
    settings.controls.keybinds = {KEY_J: Action.left, KEY_K: Action.down, KEY_L: Action.right, 
    KEY_D: Action.counter_clockwise, KEY_F: Action.clockwise, KEY_A: Action.hold, KEY_SPACE: Action.hard_drop,
    KEY_RIGHT: Action.hard_right, KEY_LEFT: Action.hard_left, KEY_ENTER: Action.lock, KEY_R: Action.reset}.toTable()
    settings.controls.das = 100
    settings.controls.arr = 0
    settings.controls.dasable_keys = @[KEY_J, KEY_L]
    settings.play.ghost = true


proc gameLoop =
    
    InitWindow(settings.visuals.window_width, settings.visuals.window_height, "Hydris")
    SetTargetFPS(0)

    const restart_on_death = true
    var pressed: seq[Key_event]
    var done = false
    var key_buffer: int
    var del_count: int
    var new_key: Key_event
    while game.state.game_active and not WindowShouldClose():
        DrawFPS(10, 10)
        # Check for game over

        # remove released keys
        del_count = 0
        for a in 0 ..< pressed.len():
            if not IsKeyDown(pressed[a - del_count].name):
                pressed.del(a - del_count)
                del_count.inc()
                
        # add newly pressed keys
        for key in settings.controls.keybinds.keys():
            if IsKeyDown(key) and (key notin pressed):
                new_key = Key_event(name: key, start_time: GetTime(), action: settings.controls.keybinds[key])
                case settings.controls.keybinds[key]:
                of Action.right, Action.left:
                    new_key.movement = Move_type.das
                of Action.down:
                    new_key.movement = Move_type.continuous
                of Action.hard_drop, Action.hard_left, Action.hard_right, Action.clockwise, Action.counter_clockwise:
                    new_key.movement = Move_type.single
                else:
                    new_key.movement = Move_type.single
                    echo fmt"{key} not set"
                pressed.add(new_key)


        fix_queue()

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
            
        # print_game()

        evaluate_board()

        ClearBackground(makecolor(0, 0, 30))
        BeginDrawing()
        
        draw_game()

        EndDrawing()

        block key_movement:
            var press: bool
            for a in 0 .. pressed.high():
                press = false
                if not pressed[a].first_tap:  # first tap
                    pressed[a].first_tap = true
                    press = true
                elif pressed[a].movement == Move_type.das and not pressed[a].arr_active and GetTime() - pressed[a].start_time > settings.controls.das / 1000:  # das done
                    pressed[a].start_time = pressed[a].start_time - settings.controls.das / 1000  # todo consider moving these to down to when I actually press things
                    pressed[a].arr_active = true
                    press = true
                elif pressed[a].movement == Move_type.das and pressed[a].arr_active and GetTime() - pressed[a].start_time > settings.controls.arr / 1000:  # arr done
                    pressed[a].start_time = pressed[a].start_time - settings.controls.arr / 1000
                    press = true
                elif pressed[a].movement == Move_type.continuous:
                    press = true
                
                if press:
                    case pressed[a].action:  # what we call it to how we implement
                    of Action.left:
                        discard do_action(Action.left)
                    of Action.down:
                        discard do_action(Action.hard_drop)
                    of Action.right:
                        discard do_action(Action.right)
                    of Action.counter_clockwise:
                        discard do_action(Action.counter_clockwise)
                    of Action.clockwise:
                        discard do_action(Action.clockwise)
                    of Action.hard_drop:
                        discard do_action(Action.hard_drop)
                        discard do_action(Action.lock)
                    of Action.hard_right:
                        discard do_action(Action.hard_right)
                    of Action.hard_left:
                        discard do_action(Action.hard_left)
                    of Action.lock:
                        discard do_action(Action.lock)
                    of Action.hold:
                        discard do_action(Action.hold)
                    of Action.reset:
                        newGame()
                        startGame()
                        pressed = @[]
                        os.sleep(300)  # todo make this a setting
                    else:
                        continue 


    
    CloseWindow()


newGame()
set_settings()
startGame()
gameLoop()
# # print_game()
# # game.board[2, 3] = 1
# # echo test_location_custom(1, 3, 3, rules.bag_minos[6], game.board)
# echo test_location()

echo "Done"

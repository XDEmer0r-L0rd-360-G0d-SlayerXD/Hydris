{.experimental: "codeReordering".}
import tables, arraymancer, sequtils, strutils, strformat, rdstdin
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
        bag_order: string
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
    Action {.pure.} = enum
        lock, up, right, down, left, counter_clockwise, clockwise, hard_drop

var game*: Game
var rules* = addr(game.rules)

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
            bag_piece_names: "JLSZIOT", bag_order: "random", kick_table: "SRS+", can_hold: true, visible_queue_len: 5, gravity_speed: 0
            )
        of "MAIN":
            game.rules = Rules(name: name, width: 10, visible_height: 20, height: 24, place_delay: 0.0, 
            clear_delay: 0.0, spawn_x: 4, spawn_y: 21, allow_clutch_clear: true, softdrop_duration: 0, 
            bag_piece_names: "JLZSIOT", bag_order: "random", kick_table: "SRS+", can_hold: true, visible_queue_len: 10, gravity_speed: 0
            )
        of "MINI TESTING":
            game.rules = Rules(name: name, width: 6, visible_height: 6, height: 6, place_delay: 0.0, 
            clear_delay: 0.0, spawn_x: 2, spawn_y: 4, allow_clutch_clear: false, softdrop_duration: 0, 
            bag_piece_names: "JLZSIOT", bag_order: "random", kick_table: "SRS+", can_hold: true, visible_queue_len: 10, gravity_speed: 0
            )
        of "WACKY":
            game.rules = Rules(name: name, width: 8, visible_height: 5, height: 5, place_delay: 0.0, 
            clear_delay: 0.0, spawn_x: 2, spawn_y: 3, allow_clutch_clear: false, softdrop_duration: 0, 
            bag_piece_names: "TTT", bag_order: "random", kick_table: "SRS+", can_hold: true, visible_queue_len: 10, gravity_speed: 0
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
        return [game.state.active_x, game.state.active_y, game.state.active_r + 3 mod 4]
    of Action.clockwise:
        return [game.state.active_x, game.state.active_y, game.state.active_r + 1 mod 4]
    of Action.hard_drop:
        return [game.state.active_x, game.state.active.rotation_shapes[game.state.active_r mod 4].map_bounds[2], game.state.active_r mod 4]



proc newGame =
    var game_type = "MINI TESTING"
    setRules(game_type)
    game.board = zeros[int]([rules.height, rules.width])
    game.state = State()
    game.stats = Stats()
    

# prepare the initial state
proc startGame =
    game.state.game_active = true
    game.state.active = rules.bag_minos[6]  # todo use random
    game.state.active_x = rules.spawn_x
    game.state.active_y = rules.spawn_y
    game.state.active_r = 0
    game.state.hold = "-"
    game.state.queue = "LSIOZS"  # todo use random
    game.state.current_combo = 0


proc do_action(move: Action): bool =
    
    # var valid = false
    # var action: Action
    # var movement: array[3, int]
    # var test: (Tensor[int], bool, bool)
    # while not valid:
    #     action = get_user_action()
    #     movement = get_new_location(action)  # todo Impliment the kick table
    #     var test = test_location_custom(movement[0], movement[1], movement[2], game.state.active, game.board)
    #     if test[1] and not test[2]:
    #         valid = true
    #         continue
    
    case move:
    of Action.up, Action.right, Action.down, Action.left, Action.counter_clockwise, Action.clockwise, Action.hard_drop:
        var movement = get_new_location(move)
        var new_loc = test_location_custom(movement[0], movement[1], movement[2], game.state.active, game.board)
        if not new_loc[1] or new_loc[2]:
            return false
        game.state.active_x = movement[0]
        game.state.active_y = movement[1]
        game.state.active_r = movement[2]
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
    
    return true


proc draw_game() =
    # We assume were in drawing mode
    let x_offset = 50
    let y_offset = 50
    let size = 50

    let loc = test_current_location()[0]
    var val: int
    var col: Color
    for a in 0 ..< rules.height:
        for b in 0 ..< rules.width:
            val = loc[a, b]
            if val == 1:
                col = makecolor(200, 0, 0)
                col = GREEN
            else:
                col = makecolor(50, 50, 50)
                col = RED
            # echo fmt"Drawing {a}, {b} with {col}, {makerect(b * size + x_offset, a * size + y_offset, size, size)}"
            DrawRectangle(b * size + x_offset, a * size + y_offset, size, size, col)



proc gameLoop =
    
    InitWindow(800, 800, "Hydris")
    SetTargetFPS(60)

    while game.state.game_active and not WindowShouldClose():
        
        # Check for game over
        var current = test_current_location()
        if not current[1] or current[2]:
            game.state.game_active = false
            continue
        # print_game()

        ClearBackground(makecolor(0, 0, 30))
        BeginDrawing()
        
        draw_game()

        EndDrawing()

        block key_detection:
            var action: Action
            var pressed = true
            if IsKeyPressed(KEY_J):
                action = Action.left
            elif IsKeyPressed(KEY_K):
                action = Action.down
            elif IsKeyPressed(KEY_L):
                action = Action.right
            elif IsKeyPressed(KEY_D):
                action = Action.counter_clockwise
            elif IsKeyPressed(KEY_F):
                action = Action.clockwise
            elif IsKeyPressed(KEY_SPACE):
                action = Action.hard_drop
            elif IsKeyPressed(KEY_SEMICOLON):
                action = Action.up
            elif IsKeyPressed(KEY_ENTER):
                action = Action.lock
            else:
                pressed = false
            
            # wierd and buggy
            # if pressed:
            #     if do_action(action):
            #         ClearBackground(GRAY)
            #     else:
            #         ClearBackground(DARKGRAY)
            if pressed:
                discard do_action(action)

            if IsKeyPressed(KEY_R):
                newGame()
                startGame()

    
    CloseWindow()


newGame()
startGame()
gameLoop()
# # print_game()
# # game.board[2, 3] = 1
# # echo test_location_custom(1, 3, 3, rules.bag_minos[6], game.board)
# echo test_location()

echo "Done"

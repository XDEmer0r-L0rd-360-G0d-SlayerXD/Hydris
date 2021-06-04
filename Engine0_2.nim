import tables, arraymancer, strutils, math, sequtils, random

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


proc merge(t1: var Table, t2: Table) =
    for a in t2.keys:
        t1[a] = t2[a]


proc rotate_tensor(ten: var Tensor) =
    let size = ten.shape[0]
    var temp = ten.zeros_like()
    for a in 0 ..< size:
        for b in 0 ..< size:
            temp[a, b] = ten[size - 1 - b, a]
    ten = temp


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




proc newGame =
    var game_type = "MINI TESTING"
    setRules(game_type)
    game.board = zeros[int]([rules.height, rules.width])
    


newGame()
echo rules.bag_minos[0]

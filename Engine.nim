import tables, arraymancer, strutils, math, sequtils, random

# cordinates always start from the top left excep for the board which is the only thing that starts at the bottom left

type  # consider changing these to ref objects while testing
    Mino_state = object
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
    Mino = object
        name: string
        rotation_shapes: seq[Mino_state]
        kick_table: Table[string, seq[(int, int)]]
    Rules = object
        game: string
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
    # Board = object
    #     state: Tensor[int]
    # CompactBoard = object
    #     state: array[int, seq[int]]
    State = object
        game_active: bool
        active: Mino
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




# This should rotate a square tensor 90 degrees clockwise
proc rotate_tensor(data: Tensor[int]): Tensor[int] =
    let size = data.shape[0]
    var temp = data.zeros_like
    for a in 0..<size:
        for b in 0..<size:
            temp[a, b] = data[size-b-1, a]
    return temp


# Couldn't find a good way to merge two different tables so I made my own method for
# this specific situation.
proc merge(var_1: Table[string, seq[(int, int)]], var_2: Table[string, seq[(int, int)]]): Table[string, seq[(int, int)]] =
    var outval: Table[string, seq[(int, int)]]
    for k, v in var_1:
        outval[k] = v
    for k, v in var_2:
        outval[k] = v
    return outval


# because parseInt doesn't accept chars
proc parse_char_to_int(val: char): int =
    return parseInt($val)


# takes in the shape to be analyzed in tensor[int] form, center cordinates
# from the top left, and the state id to generate all extra data in mino_shape
# and return the finished shape with all data filled in.
proc gen_mino_state(data: Tensor[int], center: (int, int), id: int): Mino_state =
    var state = Mino_state(rotation_id: id, shape: data, pivot_x: center[0], pivot_y: center[1])
    var temp = 0
    
    while sum(data[temp..temp]) == 0:
        inc(temp)
    state.removed_top = temp

    temp = 0
    while sum(data[^(temp + 1)..^(temp + 1)]) == 0:
        inc(temp)
    state.removed_bottom = temp

    temp = 0
    while sum(data[_, temp..temp]) == 0:
        inc(temp)
    state.removed_left = temp

    temp = 0
    while sum(data[_, ^(temp + 1)..^(temp + 1)]) == 0:
        inc(temp)
    state.removed_right = temp

    state.cleaned_shape = data[state.removed_top..^state.removed_bottom+1, state.removed_left..^state.removed_right+1]
    # echo data
    # echo state.cleaned_shape
    state.cleaned_height = state.cleaned_shape.shape[0]
    state.cleaned_width = state.cleaned_shape.shape[1]
    
    return state


# this takes a string version of a mino and returns all possible states by rotating based on how
# many centers there are that it accounts for and then generates all the state objcets in a sequence
proc gen_mino_states(mino_data: string, center: seq[(int, int)]): seq[Mino_state] =
    # output: seq[mino_state]
    # mino shape goes in (must be a square), all states + data come out
    # 010
    # 111
    # 000

    # Might be able to remove this part and just do for a in mino_data directly todo
    let lines = toSeq(mino_data)
    
    var thing: seq[int]
    for a in lines:
        if a == '0':
            thing.add(0)
        else:
            thing.add(1)

    let dim = int(sqrt(float(len(mino_data))))
    var ten = thing.toTensor.reshape(dim, dim)

    var output: seq[Mino_state]
    for a in 0..<len(center):
        output.add(gen_mino_state(ten, center[a], a))
        ten = ten.rotate_tensor()
    
    return output


# Mino shapes and kick tables get defined here
# By using pieces letter and the rules, the shape and kick table gets applied here
proc newMino(name: string, rules: Rules): Mino =
    # This holds the kick table types that need to be applied
    const 
        modern_kicks_all = {"0>1": @[(0,0), (-1, 0), (-1, 1), (0, -2), (-1, -2)],
                        "1>0": @[(0, 0), (1, 0), (1, -1), (0, 2), (1, 2)],
                        "1>2": @[(0, 0), (1, 0), (1, -1), (0, 2), (1, 2)],
                        "2>1": @[(0, 0), (-1, 0), (-1, 1), (0, -2), (-1, -2)],
                        "2>3": @[(0, 0), (1, 0), (1, 1), (0, -2), (1, -2)],
                        "3>2": @[(0, 0), (-1, 0), (-1, -1), (0, 2), (-1, 2)],
                        "3>0": @[(0, 0), (-1, 0), (-1, -1), (0, 2), (-1, 2)],
                        "0>3": @[(0, 0), (1, 0), (1, 1), (0, -2), (1, -2)]}.toTable
        modern_kicks_I = {"0>1": @[(0,0), (-2, 0), (1, 0), (-2, -1), (1, 2)],
                        "1>0": @[(0,0), (2, 0), (-1, 0), (2, 1), (-1, -2)],
                        "1>2": @[(0,0), (-1, 0), (2, 0), (-1, 2), (2, -1)],
                        "2>1": @[(0,0), (1, 0), (-2, 0), (1, -2), (-2, 1)],
                        "2>3": @[(0,0), (2, 0), (-1, 0), (2, 1), (-1, -2)],
                        "3>2": @[(0,0), (-2, 0), (1, 0), (-2, -1), (1, 2)],
                        "3>0": @[(0,0), (1, 0), (-2, 0), (1, -2), (-2, 1)],
                        "0>3": @[(0,0), (-1, 0), (2, 0), (-1, 2), (2, -1)]}.toTable
        tetrio_180 = {"0>2": @[(0, 0), (0, 1), (1, 1), (-1, 1), (1, 0), (-1, 0)],
                    "2>0": @[(0, 0), (0, -1), (-1, -1), (1, -1), (-1, 0), (1, 0)],
                    "1>3": @[(0, 0), (1, 0), (1, 2), (1, 1), (0, 2), (0, 1)],
                    "3>1": @[(0, 0), (-1, 0), (-1, 2), (-1, 1), (0, 2), (0, 1)]}.toTable
        tetrio_srsp_I = {"0>1": @[(0,0), (1, 0), (-2, 0), (-2, -1), (1, 2)],
                        "1>0": @[(0,0), (-1, 0), (2, 0), (-1, -2), (2, 1)],
                        "1>2": @[(0,0), (-1, 0), (2, 0), (-1, 2), (2, -1)],
                        "2>1": @[(0,0), (-2, 0), (1, 0), (-2, 1), (1, -2)],
                        "2>3": @[(0,0), (2, 0), (-1, 0), (2, 1), (-1, -2)],
                        "3>2": @[(0,0), (1, 0), (-2, 0), (1, 2), (-2, -1)],
                        "3>0": @[(0,0), (1, 0), (-2, 0), (-2, -1), (-2, 1)],
                        "0>3": @[(0,0), (-1, 0), (2, 0), (-2, -1), (-1, 2)]}.toTable
    
    result = Mino(name: name)

    # Here goes the Letter to map conversion which currently assumes all tetris games have the same names for shapes
    case name:
        of "L":
            result.rotation_shapes = gen_mino_states("001111000", @[(1, 1), (1, 1), (1, 1), (1, 1)])
        of "J":
            result.rotation_shapes = gen_mino_states("100111000", @[(1, 1), (1, 1), (1, 1), (1, 1)])
        of "S":
            result.rotation_shapes = gen_mino_states("011110000", @[(1, 1), (1, 1), (1, 1), (1, 1)])
        of "Z":
            result.rotation_shapes = gen_mino_states("110011000", @[(1, 1), (1, 1), (1, 1), (1, 1)])
        of "I":
            result.rotation_shapes = gen_mino_states("0000111100000000", @[(1, 1), (2, 1), (2, 2), (1, 2)])
        of "O":
            result.rotation_shapes = gen_mino_states("1111", @[(0, 0), (1, 0), (1, 1), (0, 1)])
        of "T":
            result.rotation_shapes = gen_mino_states("010111000", @[(1, 1), (1, 1), (1, 1), (1, 1)])
    
    if rules.kick_table == "SRS+":
        if name == "I":
            result.kick_table = result.kick_table.merge(tetrio_srsp_I)
        else:
            result.kick_table = result.kick_table.merge(modern_kicks_all)
        result.kick_table = result.kick_table.merge(tetrio_180)

    return result

# Convets the string version of the bag and makes the minos with the piece names
# This takes each pieces type in the bag and fetches the mino object for it.
proc generate_minos(rules: Rules): seq[Mino] =
    result = @[]
    for a in rules.bag_piece_names:
        result.add(newMino($a, rules))
    return result


# Based on the bag_piece_names in the rules, it will generate all usable pieces for the type.
# This is where custom bags get deffined such as pentominos, or 1bags
proc newBag(rules: Rules): seq[Mino] =
    return generate_minos(rules)



# Use a names such as tetrio to preset rules object to have desired settings
proc newRules(game: string): Rules = 
    if game.toUpperAscii() == "TETRIO":
        result = Rules(game: game.toUpperAscii(), width: 10, visible_height: 20, height: 23, place_delay: 0.0, 
        clear_delay: 0.0, spawn_x: 4, spawn_y: 21, allow_clutch_clear: true, softdrop_duration: 0, 
        bag_piece_names: "JLSZIOT", bag_order: "random", kick_table: "SRS+", can_hold: true, visible_queue_len: 5, gravity_speed: 0
        )
        result.bag_minos = newBag(result)
        return result
    elif game.toUpperAscii() == "MAIN":
        result = Rules(game: game.toUpperAscii(), width: 10, visible_height: 20, height: 23, place_delay: 0.0, 
        clear_delay: 0.0, spawn_x: 4, spawn_y: 21, allow_clutch_clear: true, softdrop_duration: 0, 
        bag_piece_names: "JLZSIOT", bag_order: "random", kick_table: "SRS+", can_hold: true, visible_queue_len: 10, gravity_speed: 0
        )
        result.bag_minos = newBag(result)
    elif game.toUpperAscii() == "MINI TESTING":
        result = Rules(game: game.toUpperAscii(), width: 6, visible_height: 6, height: 6, place_delay: 0.0, 
        clear_delay: 0.0, spawn_x: 2, spawn_y: 4, allow_clutch_clear: false, softdrop_duration: 0, 
        bag_piece_names: "JLZSIOT", bag_order: "random", kick_table: "SRS+", can_hold: true, visible_queue_len: 10, gravity_speed: 0
        )
        result.bag_minos = newBag(result)
    else:
        var e: ref ValueError
        new(e)
        e.msg = "Game name doesn't exist"
        raise e


# Generates a new empty board for use
proc newBoard(rules: Rules): Tensor[int] =
    return zeros[int]([rules.height, rules.width])


# Builds from top to bottom
proc str_to_board(str: string): Tensor[int] =

    result = toSeq(str).toTensor().reshape([int(len(str)/10), 10]).map(parse_char_to_int)
    return result

# Am overloading because I wanted to make rules an optional argument and wanted to try this method out
proc str_to_board(str: string, rules: Rules): Tensor[int] =

    result = toSeq(str).toTensor().reshape([rules.height, rules.width]).map(parse_char_to_int)
    return result


# Converts the board tensor to a more compact string
proc board_to_str(ten: Tensor[int]): string =
    result = ""
    for a in ten:
        result.add($a)
    return result


# Creates a new Stats object. Usefull for current ones
proc newStats(): Stats =
    return Stats(time: 0.0, lines_cleared: 0, pieces_placed: 0, score: 0, lines_sent: 0)


# Used for playing nothing but single player
# Inits the game with default values, nothing instance specific
proc newGame(game_name: string): Game =
    let rules = newRules(game_name)
    result = Game(rules: rules, board: newBoard(rules), state: State(game_active: false), stats: newStats())


proc gen_bag(rules: Rules): string =
    var bag = rules.bag_piece_names
    if rules.bag_order == "random":
        shuffle(bag)
        return bag
    elif rules.bag_order == "ordered":
        return bag
    elif rules.bag_order == "clasic":
        for a in 0..<len(rules.bag_piece_names):
            bag.add(sample(rules.bag_piece_names))
        return bag



# The point of this is to initalize the game state like its a real game. This is only for my game
# This only assumes modern rule set
proc startGame(game: var Game): Game  =
    game.state.game_active = true

    # populate enough of the queue
    while game.rules.visible_queue_len > len(game.state.queue):
        game.state.queue.add(gen_bag(game.rules))
    game.state.active = newMino($game.state.queue[0], game.rules)
    game.state.queue = game.state.queue[1 .. high(game.state.queue)]

    # if piece set to active shortens the queue too much
    if game.rules.visible_queue_len > len(game.state.queue):
        game.state.queue.add(gen_bag(game.rules))
    
    # set active mino char via rules
    game.state.active_r = 0
    game.state.active_x = game.rules.spawn_x
    game.state.active_y = game.rules.spawn_y

    # set other needed values
    game.state.hold_available = true
    game.state.hold = "empty"
    game.state.current_combo = 0

    return game


# Changes the current active piece, Will reset position to spawn
proc set_active(state: var State, rules: Rules, change: string): State =
    let index = rules.bag_piece_names.find(change)
    state.active = rules.bag_minos[index]
    state.active_r = 0
    state.active_x = rules.spawn_x
    state.active_y = rules.spawn_y
    return state


# for when I just want to thow the game into this proc. Also working with overloading
proc set_active(game: var Game, change: string): Game =
    game.state = set_active(game.state, game.rules, change)
    return game


proc lock_piece(board: var Tensor[int], state: State, rules: Rules): Tensor[int] =
    echo board
    echo state.active_x, " ", state.active_y
    # echo state.active.rotation_shapes[state.active_r]
    let active = state.active.rotation_shapes[state.active_r]
    let shape = active.cleaned_shape.shape
    for a in 0..<shape[0]:
        for b in 0..<shape[1]:
            # I think this is right? todo
            board[rules.height-1-state.active_y-(active.pivot_y-active.removed_top)+a, state.active_x - (active.pivot_x - active.removed_left) + b] = active.cleaned_shape[a, b]
    return board

# this is testing right now

# generate a mino and return its states. Prints every cleaned state.
# let thing = gen_mino_states("010111000", @[(1, 1), (1, 1), (1, 1), (1, 1)])
# for a in thing:
#     echo a.cleaned_shape


# generate the tetrio rules and print the last cleaned T piece it has
# let thing = newRules("tetrio")
# echo thing.game_bag.available_pieces[6].rotation_shapes[3].cleaned_shape


# generate a lot of rule data objects to stress test a little
# var bench: seq[Rules]
# for a in 0..<10000:
#     bench.add(newRules("tetrio"))
# echo len(bench)
# echo "end>"

# When generating and storing 10000 of newRules("tetrio") it takes a while and uses
# ~500 mb to store

# Test board storage types conversions to ensure they work both ways correctly
# let test_rules = newRules("tetrio")
# var board = newBoard(test_rules)
# echo board
# var str = board.board_to_str()
# echo len(str), ": ", str
# board = str.str_to_board(test_rules)
# echo board

# make a random queue to care about to ensure population of queue works
# randomize()
# var game = newGame("Main")
# game.state.queue.add("T")
# game.rules.visible_queue_len = 10
# game = startGame(game)
# echo len(game.state.queue), game.rules.bag_order, game.state.queue

var test_game = newGame("mini testing")
test_game = startGame(test_game)
# discard test_game.set_active("T")
test_game.board = lock_piece(test_game.board, test_game.state, test_game.rules)
echo test_game.state
echo test_game.board


# Only use this line when output is in terminal mode 
# discard readLine(stdin)
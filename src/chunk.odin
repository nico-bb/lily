package lily

Op_Code :: enum byte {
	Op_Push,
	Op_Pop,
	Op_Const,
	Op_Module,
	Op_Prototype,

	// Operation related Op_Codes
	Op_Inc,
	Op_Dec,
	Op_Neg,
	Op_Not,
	Op_Add,
	Op_Mul,
	Op_Div,
	Op_Rem,
	Op_And,
	Op_Or,
	Op_Eq,
	Op_Greater,
	Op_Greater_Eq,
	Op_Lesser,
	Op_Lesser_Eq,

	// Scope management related Op_Codes
	Op_Begin,
	Op_End,
	Op_Call,
	Op_Call_Method,
	Op_Call_Constr,
	Op_Return,
	Op_Jump,
	Op_Cond_Jump,

	// All the access related Op_Codes
	Op_Get,
	Op_Get_Global,
	Op_Get_Elem,
	Op_Get_Field,
	Op_Bind,
	Op_Set,
	Op_Set_Global,
	Op_Set_Elem,
	Op_Set_Field,

	// Allocation related Op_Codes
	Op_Make_Array,
	Op_Make_Instance,
	Op_Append_Array,
}

instr_length := map[Op_Code]int {
	.Op_Push          = 1,
	.Op_Pop           = 1,
	.Op_Const         = 3,
	.Op_Module        = 3,
	.Op_Prototype     = 3,
	.Op_Inc           = 1,
	.Op_Dec           = 1,
	.Op_Neg           = 1,
	.Op_Not           = 1,
	.Op_Add           = 1,
	.Op_Mul           = 1,
	.Op_Div           = 1,
	.Op_Rem           = 1,
	.Op_And           = 1,
	.Op_Or            = 1,
	.Op_Eq            = 1,
	.Op_Greater       = 1,
	.Op_Greater_Eq    = 1,
	.Op_Lesser        = 1,
	.Op_Lesser_Eq     = 1,
	.Op_Begin         = 1,
	.Op_End           = 1,
	.Op_Call          = 3,
	.Op_Call_Method   = 3,
	.Op_Call_Constr   = 3,
	.Op_Return        = 3,
	.Op_Jump          = 3,
	.Op_Cond_Jump     = 3,
	.Op_Get           = 3,
	.Op_Get_Global    = 3,
	.Op_Get_Elem      = 1,
	.Op_Get_Field     = 3,
	.Op_Bind          = 5,
	.Op_Set           = 3,
	.Op_Set_Global    = 3,
	.Op_Set_Elem      = 1,
	.Op_Set_Field     = 3,
	.Op_Make_Instance = 1,
	.Op_Make_Array    = 1,
	.Op_Append_Array  = 1,
}

Const_Pool :: distinct [dynamic]Value

add_constant :: proc(p: ^Const_Pool, val: Value) -> (addr: i16) {
	for constant, i in p {
		if value_equal(constant, val) {
			return i16(i)
		}
	}
	append(p, val)
	return i16(len(p) - 1)
}

add_string_constant :: proc(p: ^Const_Pool, str: string) -> (addr: i16) {
	loop: for constant, i in p {
		if constant.kind == .Object_Ref {
			object := constant.data.(^Object)
			if object.kind == .String {
				str_object := cast(^String_Object)object
				for r, j in str {
					if r != str_object.data[j] {
						continue loop
					}
				}
				return i16(i)
			}
		}
	}
	new_str := new_string_object(str)
	append(p, new_str)
	return i16(len(p) - 1)
}

CHUNK_INIT_CAP :: 100
SELF_STACK_ADDR :: 0
METHOD_RESULT_STACK_ADDR :: 1
FN_RESULT_STACK_ADDR :: 0

Chunk :: struct {
	bytecode:  [dynamic]byte,
	constants: Const_Pool,
	variables: []Variable,
}

Variable :: struct {
	stack_id: int,
}

make_chunk :: proc(with_consts: bool, var_count: int) -> Chunk {
	c := Chunk {
		bytecode  = make([dynamic]byte),
		constants = make(Const_Pool) if with_consts else nil,
		variables = make([]Variable, var_count),
	}
	reserve(&c.bytecode, CHUNK_INIT_CAP)
	return c
}

push_byte :: proc(c: ^Chunk, b: byte) {
	append(&c.bytecode, b)
}

push_op_code :: proc(c: ^Chunk, op: Op_Code) {
	append(&c.bytecode, byte(op))
}

push_simple_instruction :: proc(c: ^Chunk, op: Op_Code, instr: i16) {
	append(&c.bytecode, byte(op))
	lower_instr := byte(instr)
	upper_instr := byte(instr >> 8)
	push_byte(c, lower_instr)
	push_byte(c, upper_instr)
}

push_double_instruction :: proc(c: ^Chunk, op: Op_Code, i1: i16, i2: i16) {
	append(&c.bytecode, byte(op))
	lower_instr := byte(i1)
	upper_instr := byte(i1 >> 8)
	append(&c.bytecode, lower_instr)
	append(&c.bytecode, upper_instr)

	lower_instr = byte(i2)
	upper_instr = byte(i2 >> 8)
	append(&c.bytecode, lower_instr)
	append(&c.bytecode, upper_instr)
}

package lily

import "core:fmt"
import "core:sort"

Compiler :: struct {
	state:           ^State,
	current_read:    ^Checked_Module,
	current_write:   ^Compiled_Module,

	// Data for the current chunk compiling
	chunk:           Chunk,
	chunk_variables: map[string]i16,
	var_count:       i16,
	constants:       ^Const_Pool,
	current_access:  Accessor_Kind,
	selected_class:  ^Symbol,
}

Compiled_Module :: struct {
	id:                 int,
	class_addr:         map[string]i16,
	class_consts:       []Const_Pool,
	class_fields:       []map[string]i16,
	class_constructors: []map[string]i16,
	class_methods:      []map[string]i16,
	protypes:           []Class_Object,
	vtables:            []Class_Vtable,
	fn_addr:            map[string]i16,
	functions:          []Fn_Object,
	var_addr:           map[string]i16,
	variables:          []Value,
	main:               Chunk,
}

// Allocate the right amount of compiled modules.
// This procedure does not compiled the input!
make_compiled_program :: proc(state: ^State) -> []^Compiled_Module {
	output := make([]^Compiled_Module, len(state.checked_modules))
	for module, i in state.checked_modules {
		current := output[i]
		current =
			new_clone(
				Compiled_Module{
					id = i,
					class_addr = make(map[string]i16),
					class_consts = make([]Const_Pool, len(module.classes)),
					class_fields = make([]map[string]i16, len(module.classes)),
					class_constructors = make([]map[string]i16, len(module.classes)),
					class_methods = make([]map[string]i16, len(module.classes)),
					protypes = make([]Class_Object, len(module.classes)),
					vtables = make([]Class_Vtable, len(module.classes)),
					fn_addr = make(map[string]i16),
					functions = make([]Fn_Object, len(module.functions)),
					variables = make([]Value, len(module.variables)),
				},
			)

		for node, j in module.classes {
			n := node.(^Checked_Class_Declaration)
			current.class_addr[n.identifier.name] = i16(j)
			current.class_consts[j] = make(Const_Pool)
			current.vtables[j] = Class_Vtable {
				constructors = make([]Fn_Object, len(n.constructors)),
				methods      = make([]Fn_Object, len(n.methods)),
			}
			current.class_fields[j] = make(map[string]i16)
			for field, h in n.fields {
				current.class_fields[j][field.name] = i16(h)
			}

			current.class_constructors[j] = make(map[string]i16)
			for constructor, h in n.constructors {
				current.class_constructors[j][constructor.identifier.name] = i16(h)
			}

			current.class_methods[j] = make(map[string]i16)
			for method, h in n.methods {
				current.class_methods[j][method.identifier.name] = i16(h)
			}
		}
		output[i] = current
	}
	return output
}

add_variable :: proc(c: ^Compiler, name: string) -> (addr: i16) {
	addr = c.var_count
	append(&c.chunk.variables, Variable{stack_addr = -1})
	c.chunk_variables[name] = addr
	c.var_count += 1
	return
}

get_class_addr :: proc(c: ^Compiled_Module, name: string) -> (addr: i16) {
	return c.class_addr[name]
}

get_field_addr :: proc(c: ^Compiled_Module, class, field: string) -> (addr: i16) {
	class_addr := c.class_addr[class]
	return c.class_fields[class_addr][field]
}

get_constructor_addr :: proc(c: ^Compiled_Module, class, name: string) -> (addr: i16) {
	class_addr := c.class_addr[class]
	return c.class_constructors[class_addr][name]
}

get_method_addr :: proc(c: ^Compiled_Module, class, name: string) -> (addr: i16) {
	class_addr := c.class_addr[class]
	return c.class_methods[class_addr][name]
}

get_fn_addr :: proc(c: ^Compiled_Module, name: string) -> (addr: i16) {
	return c.fn_addr[name]
}

// FIXME: Does not handle module level variables
get_var_addr :: proc(c: ^Compiler, name: string) -> (addr: i16) {
	return c.chunk_variables[name]
}


reset_compiler :: proc(c: ^Compiler) {
	c.var_count = 0
	clear(&c.chunk_variables)
	c.constants = nil
}

compile_module :: proc(state: ^State, index: int) {
	c := Compiler {
		state           = state,
		current_read    = state.checked_modules[index],
		current_write   = state.compiled_modules[index],
		chunk_variables = make(map[string]i16),
	}

	for node, i in c.current_read.classes {
		n := node.(^Checked_Class_Declaration)
		enter_class_scope(c.current_read, Token{text = n.identifier.name})
		defer pop_scope(c.current_read)

		vtable := &c.current_write.vtables[i]
		c.constants = &c.current_write.class_consts[i]
		for constructor, j in n.constructors {
			fn_info := constructor.identifier.info.(Fn_Symbol_Info)
			enter_child_scope_by_id(c.current_read, fn_info.sub_scope_id)
			defer pop_scope(c.current_read)

			c.chunk = make_chunk(false)

			push_op_code(&c.chunk, .Op_Make_Instance)
			push_simple_instruction(&c.chunk, .Op_Move, SELF_STACK_ADDR)
			self_var_addr := add_variable(&c, "self")
			push_double_instruction(&c.chunk, .Op_Bind, self_var_addr, SELF_STACK_ADDR)

			compile_fn_parameters(&c, constructor.params, 1)
			compile_node(&c, constructor.body)
			push_simple_instruction(&c.chunk, .Op_Return, SELF_STACK_ADDR)

			c.chunk.constants = c.current_write.class_consts[i]
			vtable.constructors[j] = Fn_Object {
				base = Object{kind = .Fn},
				chunk = c.chunk,
			}
			reset_compiler(&c)
		}

		for method, j in n.methods {
			fn_info := method.identifier.info.(Fn_Symbol_Info)
			enter_child_scope_by_id(c.current_read, fn_info.sub_scope_id)
			defer pop_scope(c.current_read)

			c.chunk = make_chunk(false)

			self_addr := add_variable(&c, "self")
			push_double_instruction(&c.chunk, .Op_Bind, self_addr, SELF_STACK_ADDR)
			if fn_info.has_return {
				result_addr := add_variable(&c, "result")
				push_double_instruction(&c.chunk, .Op_Bind, result_addr, METHOD_RESULT_STACK_ADDR)
			}

			compile_fn_parameters(&c, method.params, 2 if fn_info.has_return else 1)
			compile_node(&c, method.body)

			if fn_info.has_return {
				push_simple_instruction(&c.chunk, .Op_Return, METHOD_RESULT_STACK_ADDR)
			} else {
				push_simple_instruction(&c.chunk, .Op_Return, -1)
			}

			c.chunk.constants = c.current_write.class_consts[i]
			vtable.methods[j] = Fn_Object {
				base = Object{kind = .Fn},
				chunk = c.chunk,
			}
			reset_compiler(&c)
		}


		c.current_write.protypes[i] = Class_Object {
			base = Object{kind = .Class},
			fields = make([]Value, len(n.fields)),
			vtable = vtable,
		}
	}

	for node, i in c.current_read.functions {
		n := node.(^Checked_Fn_Declaration)
		#partial switch n.kind {
		case .Foreign:
			c.current_write.functions[i] = Fn_Object {
				base = Object{kind = .Fn},
				foreign_fn = c.state->internal_bind_fn(n),
			}

		case .Function:
			fn_info := n.identifier.info.(Fn_Symbol_Info)
			enter_child_scope_by_id(c.current_read, fn_info.sub_scope_id)
			defer pop_scope(c.current_read)

			c.chunk = make_chunk(true)
			c.constants = &c.chunk.constants

			if fn_info.has_return {
				result_addr := add_variable(&c, "result")
				push_double_instruction(&c.chunk, .Op_Bind, result_addr, FN_RESULT_STACK_ADDR)
			}

			compile_fn_parameters(&c, n.params, 1 if fn_info.has_return else 0)
			compile_node(&c, n.body)

			if fn_info.has_return {
				push_simple_instruction(&c.chunk, .Op_Return, FN_RESULT_STACK_ADDR)
			} else {
				push_simple_instruction(&c.chunk, .Op_Return, -1)
			}

			c.current_write.functions[i] = Fn_Object {
				base = Object{kind = .Fn},
				chunk = c.chunk,
			}
		}
		reset_compiler(&c)
	}

	c.chunk = make_chunk(true)
	c.constants = &c.chunk.constants
	module_body :=
		make([]Checked_Node, len(c.current_read.variables) + len(c.current_read.nodes), context.temp_allocator)
	copy(module_body[:len(c.current_read.variables)], c.current_read.variables[:])
	copy(module_body[len(c.current_read.variables):], c.current_read.nodes[:])

	//odinfmt: disable
	sort.sort(sort.Interface{
		len = proc(it: sort.Interface) -> int {
			buf := cast(^[]Checked_Node)it.collection
			return len(buf)
		}, 
		less = proc(it: sort.Interface, i, j: int) -> bool {
			buf := cast(^[]Checked_Node)it.collection
			i_token, j_token := checked_node_token(buf[i]), checked_node_token(buf[j])
			return i_token.line < j_token.line
		},
		swap = proc(it: sort.Interface, i, j: int) {
			buf := cast(^[]Checked_Node)it.collection
			buf[i], buf[j] = buf[j], buf[i]
		},
		collection = &module_body,
	})
	//odinfmt: enable

	for node in module_body {
		compile_node(&c, node)
	}
	c.current_write.main = c.chunk
	delete(c.chunk_variables)
}

compile_fn_parameters :: proc(c: ^Compiler, params: []^Symbol, offset: i16) {
	for param, i in params {
		param_addr := add_variable(c, param.name)
		push_double_instruction(&c.chunk, .Op_Bind, param_addr, i16(i) + offset)
	}
}

compile_node :: proc(c: ^Compiler, node: Checked_Node) {
	switch n in node {
	case ^Checked_Expression_Statement:
		compile_expr(c, n.expr)

	case ^Checked_Block_Statement:
		for inner_node in n.nodes {
			compile_node(c, inner_node)
		}

	case ^Checked_Assigment_Statement:
		compile_expr(c, n.right)
		#partial switch left in n.left {
		case ^Checked_Identifier_Expression:
			var_addr := get_var_addr(c, left.symbol.name)
			push_simple_instruction(&c.chunk, .Op_Set, var_addr)
		case ^Checked_Index_Expression:
			compile_expr(c, left.index)
			compile_expr(c, left.left)
			push_op_code(&c.chunk, .Op_Set_Elem)
		case ^Checked_Dot_Expression:
			c.current_access = .None
			c.selected_class = nil
			compile_dot_expr(c, left, true)
		}

	case ^Checked_If_Statement:
		push_op_code(&c.chunk, .Op_Begin)
		compile_expr(c, n.condition)
		jmp_start := reserve_bytes(&c.chunk, instr_length[.Op_Cond_Jump])
		compile_node(c, n.body)

		jmp_addr := i16(len(c.chunk.bytecode))
		c.chunk.bytecode[jmp_start] = byte(Op_Code.Op_Cond_Jump)
		c.chunk.bytecode[jmp_start + 1] = byte(jmp_addr)
		c.chunk.bytecode[jmp_start + 2] = byte(jmp_addr >> 8)
		if n.next_branch != nil {
			compile_node(c, n.next_branch)
		}
		push_op_code(&c.chunk, .Op_End)

	case ^Checked_Range_Statement:
		push_op_code(&c.chunk, .Op_Begin)
		iterator_addr := add_variable(c, n.iterator.name)
		compile_expr(c, n.low)
		compile_expr(c, n.high)
		push_double_instruction(&c.chunk, .Op_Bind, iterator_addr, 0)

		loop_addr := i16(len(c.chunk.bytecode))
		push_simple_instruction(&c.chunk, .Op_Get, iterator_addr)
		push_simple_instruction(&c.chunk, .Op_Copy, 1)
		switch n.op {
		case .Exclusive:
			push_op_code(&c.chunk, .Op_Lesser)
		case .Inclusive:
			push_op_code(&c.chunk, .Op_Lesser_Eq)
		}
		jmp_start := reserve_bytes(&c.chunk, instr_length[.Op_Cond_Jump])

		compile_node(c, n.body)

		push_simple_instruction(&c.chunk, .Op_Copy, 0)
		push_op_code(&c.chunk, .Op_Inc)
		push_simple_instruction(&c.chunk, .Op_Move, 0)
		push_simple_instruction(&c.chunk, .Op_Jump, loop_addr)
		jmp_addr := i16(len(c.chunk.bytecode))
		c.chunk.bytecode[jmp_start] = byte(Op_Code.Op_Cond_Jump)
		c.chunk.bytecode[jmp_start + 1] = byte(jmp_addr)
		c.chunk.bytecode[jmp_start + 2] = byte(jmp_addr >> 8)

		push_op_code(&c.chunk, .Op_End)


	case ^Checked_Var_Declaration:
		var_addr := add_variable(c, n.identifier.name)
		compile_expr(c, n.expr)
		push_simple_instruction(&c.chunk, .Op_Set, var_addr)

	case ^Checked_Fn_Declaration:

	case ^Checked_Type_Declaration:

	case ^Checked_Class_Declaration:

	}
}

compile_expr :: proc(c: ^Compiler, expr: Checked_Expression) {
	switch e in expr {
	case ^Checked_Literal_Expression:
		const_addr := add_constant(c.constants, e.value)
		push_simple_instruction(&c.chunk, .Op_Const, const_addr)

	case ^Checked_String_Literal_Expression:
		const_addr := add_string_constant(c.constants, e.value)
		push_simple_instruction(&c.chunk, .Op_Const, const_addr)

	case ^Checked_Array_Literal_Expression:
		for i := len(e.values) - 1; i >= 0; i -= 1 {
			value_expr := e.values[i]
			compile_expr(c, value_expr)
		}
		push_op_code(&c.chunk, .Op_Make_Array)

		for i in 0 ..< len(e.values) {
			push_op_code(&c.chunk, .Op_Append_Array)
		}

	case ^Checked_Unary_Expression:
		compile_expr(c, e.expr)
		#partial switch e.op {
		case .Minus_Op:
			push_op_code(&c.chunk, .Op_Neg)
		case .Not_Op:
			push_op_code(&c.chunk, .Op_Not)
		}

	case ^Checked_Binary_Expression:
		compile_expr(c, e.left)
		compile_expr(c, e.right)
		#partial switch e.op {
		case .Plus_Op:
			push_op_code(&c.chunk, .Op_Add)
		case .Minus_Op:
			push_op_code(&c.chunk, .Op_Neg)
			push_op_code(&c.chunk, .Op_Add)
		case .Mult_Op:
			push_op_code(&c.chunk, .Op_Mul)
		case .Div_Op:
			push_op_code(&c.chunk, .Op_Div)
		case .Rem_Op:
			push_op_code(&c.chunk, .Op_Rem)
		case .Or_Op:
			push_op_code(&c.chunk, .Op_Or)
		case .And_Op:
			push_op_code(&c.chunk, .Op_And)
		case .Equal_Op:
			push_op_code(&c.chunk, .Op_Eq)
		case .Greater_Op:
			push_op_code(&c.chunk, .Op_Greater)
		case .Greater_Eq_Op:
			push_op_code(&c.chunk, .Op_Greater_Eq)
		case .Lesser_Op:
			push_op_code(&c.chunk, .Op_Lesser)
		case .Lesser_Eq_Op:
			push_op_code(&c.chunk, .Op_Lesser_Eq)
		}

	case ^Checked_Identifier_Expression:
		#partial switch e.symbol.kind {
		case .Var_Symbol:
			var_addr := get_var_addr(c, e.symbol.name)
			push_simple_instruction(&c.chunk, .Op_Get, var_addr)

		case:
			fmt.println(e.symbol, c.current_read.name)
			assert(false)
		}

	case ^Checked_Index_Expression:
		#partial switch left in e.left {
		case ^Checked_Identifier_Expression:
			compile_expr(c, e.index)
			compile_expr(c, e.left)
			push_op_code(&c.chunk, .Op_Get_Elem)
		case:
			assert(false)
		}

	case ^Checked_Dot_Expression:
		c.current_access = .None
		c.selected_class = nil
		compile_dot_expr(c, e, false)

	case ^Checked_Call_Expression:
		symbol := checked_expr_symbol(e.func)
		fn_info := symbol.info.(Fn_Symbol_Info)
		push_op_code(&c.chunk, .Op_Begin)
		if fn_info.has_return {
			push_op_code(&c.chunk, .Op_Push)
		}
		for arg_expr in e.args {
			compile_expr(c, arg_expr)
		}
		fn_addr := get_fn_addr(c.current_write, symbol.name)
		#partial switch fn_info.kind {
		case .Foreign:
			push_simple_instruction(&c.chunk, .Op_Call_Foreign, fn_addr)
		case .Function:
			push_simple_instruction(&c.chunk, .Op_Call, fn_addr)
		}
	}
}

compile_dot_expr :: proc(c: ^Compiler, expr: ^Checked_Dot_Expression, lhs: bool) {
	current_id := c.current_write.id
	#partial switch left in expr.left {
	case ^Checked_Identifier_Expression:
		#partial switch left.symbol.kind {
		case .Var_Symbol:
			var_info := left.symbol.info.(Var_Symbol_Info)
			if var_info.symbol.kind == .Class_Symbol {
				var_addr := get_var_addr(c, left.symbol.name)
				push_simple_instruction(&c.chunk, .Op_Get, var_addr)
				c.selected_class = var_info.symbol
			}
			c.current_access = .Instance_Access

		case .Class_Symbol:
			class_addr := get_var_addr(c, left.symbol.name)
			push_simple_instruction(&c.chunk, .Op_Prototype, class_addr)
			c.current_access = .Class_Access
			c.selected_class = left.symbol

		case .Module_Symbol:
			module_info := left.symbol.info.(Module_Symbol_Info)
			module_addr := module_info.ref_mod_id
			push_simple_instruction(&c.chunk, .Op_Module, i16(module_addr))
			c.current_write = c.state.compiled_modules[module_addr]
			c.current_access = .Module_Access
		}

	case ^Checked_Index_Expression:
		symbol := checked_expr_symbol(left.left)
		var_addr := get_var_addr(c, symbol.name)
		compile_expr(c, left.index)
		compile_expr(c, left.left)
		push_op_code(&c.chunk, .Op_Get_Elem)
		c.current_access = .Instance_Access
		c.selected_class = left.symbol

	case ^Checked_Call_Expression:
		switch c.current_access {
		case .None, .Module_Access:
			compile_expr(c, left)
		case .Class_Access:
			compile_constructor_call_expr(c, left)
		case .Instance_Access:
			compile_method_call_expr(c, left)
		}
		c.selected_class = left.symbol
		c.current_access = .Instance_Access
	}

	inner_symbol := checked_expr_symbol(expr.selector)
	op: Op_Code
	#partial switch selector in expr.selector {
	case ^Checked_Identifier_Expression:
		#partial switch c.current_access {
		case .Instance_Access:
			op = .Op_Set_Field if lhs else .Op_Get_Field
			class_module := c.state.compiled_modules[c.selected_class.module_id]
			field_addr := get_field_addr(class_module, c.selected_class.name, selector.symbol.name)
			push_simple_instruction(&c.chunk, op, field_addr)

		case .Module_Access:
			op = .Op_Set if lhs else .Op_Get
			var_addr := get_var_addr(c, selector.symbol.name)
			push_simple_instruction(&c.chunk, op, var_addr)
		}
	case ^Checked_Index_Expression:
		#partial switch c.current_access {
		case .Instance_Access:
			op = .Op_Set_Elem if lhs else .Op_Get_Elem
			compile_expr(c, selector.index)
			class_module := c.state.compiled_modules[c.selected_class.module_id]
			field_addr := get_field_addr(class_module, c.selected_class.name, inner_symbol.name)
			push_simple_instruction(&c.chunk, .Op_Get_Field, field_addr)
			push_op_code(&c.chunk, op)

		case .Module_Access:
			op = .Op_Set_Elem if lhs else .Op_Get_Elem
			compile_expr(c, selector.index)
			compile_expr(c, selector.left)
			push_op_code(&c.chunk, op)
		}
	case ^Checked_Call_Expression:
		#partial switch c.current_access {
		case .Instance_Access:
			symbol := checked_expr_symbol(selector.func)
			if symbol.module_id == BUILTIN_MODULE_ID {
				switch symbol.name {
				case "append":
					left_symbol := checked_expr_symbol(expr.left)
					var_addr := get_var_addr(c, left_symbol.name)
					for i := len(selector.args) - 1; i >= 0; i -= 1 {
						compile_expr(c, selector.args[i])
					}
					push_simple_instruction(&c.chunk, .Op_Get, var_addr)
					for i in 0 ..< len(selector.args) {
						push_op_code(&c.chunk, .Op_Append_Array)
					}
					push_op_code(&c.chunk, .Op_Pop)
				case "length":
					left_symbol := checked_expr_symbol(expr.left)
					var_addr := get_var_addr(c, left_symbol.name)
					push_simple_instruction(&c.chunk, .Op_Get, var_addr)
					push_op_code(&c.chunk, .Op_Length)
				}
			} else {
				compile_method_call_expr(c, selector)
			}

		case .Class_Access:
			compile_constructor_call_expr(c, selector)

		case .Module_Access:
			compile_expr(c, selector)
		}
	case ^Checked_Dot_Expression:
		compile_dot_expr(c, selector, lhs)
	}
	if c.current_write.id != current_id {
		c.current_write = c.state.compiled_modules[current_id]
		push_simple_instruction(&c.chunk, .Op_Module, i16(current_id))
	}
}

compile_method_call_expr :: proc(c: ^Compiler, expr: ^Checked_Call_Expression) {
	symbol := checked_expr_symbol(expr.func)
	fn_info := symbol.info.(Fn_Symbol_Info)
	push_op_code(&c.chunk, .Op_Begin)
	push_op_code(&c.chunk, .Op_Push)
	if fn_info.has_return {
		push_op_code(&c.chunk, .Op_Push)
	}
	for arg_expr in expr.args {
		compile_expr(c, arg_expr)
	}
	class_module := c.state.compiled_modules[c.selected_class.module_id]
	method_addr := get_method_addr(class_module, c.selected_class.name, symbol.name)
	push_simple_instruction(&c.chunk, .Op_Call_Method, method_addr)
	if fn_info.has_return {
		push_op_code(&c.chunk, .Op_Push_Back)
	} else {
		push_op_code(&c.chunk, .Op_Pop)
	}

}

compile_constructor_call_expr :: proc(c: ^Compiler, expr: ^Checked_Call_Expression) {
	symbol := checked_expr_symbol(expr.func)
	push_op_code(&c.chunk, .Op_Begin)
	push_op_code(&c.chunk, .Op_Push)
	for arg_expr in expr.args {
		compile_expr(c, arg_expr)
	}
	class_module := c.state.compiled_modules[c.selected_class.module_id]
	constructor_addr := get_constructor_addr(class_module, c.selected_class.name, symbol.name)
	push_simple_instruction(&c.chunk, .Op_Call_Constr, constructor_addr)
	push_op_code(&c.chunk, .Op_Push_Back)
}

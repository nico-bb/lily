package lily

Typed_Identifier :: struct {
	name:      Token,
	type_expr: Expression,
}

Expression :: union {
	// Value Expressions
	^Literal_Expression,
	^String_Literal_Expression,
	^Array_Literal_Expression,
	^Unary_Expression,
	^Binary_Expression,
	^Identifier_Expression,
	^Index_Expression,
	^Call_Expression,

	// Type Expressions
	^Array_Type,
}

Literal_Expression :: struct {
	value: Value,
}

// We separate this from the other fixed sized native value types
// to avoid having to allocate a Object_Ref during parsing and let
// the vm/interpreter do that at runtime
String_Literal_Expression :: struct {
	value: string,
}

Array_Literal_Expression :: struct {
	token:     Token, // the "array" token
	// This is either a Identifier (for builtin types and user defined types) 
	// or another composite type (array or map)
	type_expr: Expression,
	values:    [dynamic]Expression,
}

Unary_Expression :: struct {
	token: Token,
	expr:  Expression,
	op:    Operator,
}

Binary_Expression :: struct {
	token: Token,
	left:  Expression,
	right: Expression,
	op:    Operator,
}

Identifier_Expression :: struct {
	name: Token,
}
unresolved_identifier := Identifier_Expression {
	name = Token{text = "untyped"},
}

Index_Expression :: struct {
	token: Token, // the '[' token
	left:  Expression,
	index: Expression,
}

Call_Expression :: struct {
	token:     Token, // the '(' token
	func:      Expression,
	args:      [5]Expression,
	arg_count: int,
}

Array_Type :: struct {
	token:     Token, // The "array" token
	of_token:  Token, //The "of" token
	elem_type: Expression, // Either Identifier or another Type Expression. Allows for multi-arrays
}

//////

Node :: union {
	// Statements
	^Expression_Statement,
	^Block_Statement,
	^Assignment_Statement,
	^If_Statement,
	^Range_Statement,

	// Declarations
	^Var_Declaration,
	^Fn_Declaration,
	^Type_Declaration,
}

Expression_Statement :: struct {
	expr: Expression,
}

Block_Statement :: struct {
	nodes: [dynamic]Node,
}

Assignment_Statement :: struct {
	token: Token, // the '=' token
	left:  Expression,
	right: Expression,
}

If_Statement :: struct {
	token:       Token, // the "if" token
	condition:   Expression,
	body:        ^Block_Statement,
	next_branch: ^If_Statement,
}

Range_Statement :: struct {
	token:         Token, // the "for" token
	iterator_name: Token,
	low:           Expression,
	high:          Expression,
	reverse:       bool,
	op:            Range_Operator,
	body:          ^Block_Statement,
}

Var_Declaration :: struct {
	token:       Token, // the "var" token
	identifier:  Token,
	type_expr:   Expression,
	expr:        Expression,
	initialized: bool,
}

Fn_Declaration :: struct {
	identifier:       Token,
	parameters:       [dynamic]Typed_Identifier,
	body:             ^Block_Statement,
	return_type_expr: Expression,
}

Type_Declaration :: struct {
	token:      Token, // the "type" token
	is_token:   Token,
	identifier: Token,
	type_expr:  Expression,
	is_alias:   bool,
	fields:     [dynamic]Typed_Identifier,
	// methods:    [dynamic]^Fn_Declaration,
}

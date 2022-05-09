package test

import "core:fmt"
import lily "../src"

vm: ^lily.Vm

main :: proc() {
	vm = lily.new_vm()
	defer lily.delete_vm(vm)

	test_lexer()

	fmt.println("=====")
	fmt.println("=====")
	playground()
}

playground :: proc() {
	using lily
	input: string = `
       var arr = array of number[10, 1, 2]
	`
	program := make_program()
	defer delete_program(program)

	err := append_to_program(input, program)

	assert(err == nil, fmt.tprint("Failed, Error raised ->", err))


	checker := new_checker()
	check_err := check_program(checker, program.nodes[:])
	assert(check_err == nil, fmt.tprint("Failed, Error raised ->", check_err))

	print_ast(program)
	run_program(vm, program.nodes[:])
	fmt.println(vm.names)
	fmt.println(vm.functions)
	// fmt.println(vm.stack)
	fmt.println(get_stack_value(vm, "str"))
}

test_lexer :: proc() {
	using lily
	inputs := [?]string{
		"= == < <= > >=",
		". .. ... ,",
		"+ - * / %",
		"var fn return and or true false",
		`10 1.2 "hello" --comment`,
	}
	counts := [?]int{6, 4, 5, 7, 4}
	expects := [?][]Token_Kind{
		{.Assign, .Equal, .Lesser, .Lesser_Equal, .Greater, .Greater_Equal},
		{.Dot, .Double_Dot, .Triple_Dot, .Comma},
		{.Plus, .Minus, .Star, .Slash, .Percent},
		{.Var, .Fn, .Return, .And, .Or, .True, .False},
		{.Number_Literal, .Number_Literal, .String_Literal, .Comment},
	}

	lexer := Lexer{}
	for input, i in inputs {
		count := 0
		set_lexer_input(&lexer, input)
		for {
			t := scan_token(&lexer)
			if t.kind == .EOF {
				break
			}
			assert(
				t.kind == expects[i][count],
				fmt.tprint("Failed, Expected", expects[i][count], "Got", t.kind),
			)
			count += 1
		}
		assert(
			count == counts[i],
			fmt.tprintf(
				"Failed, Too many tokens for input number %i; Got %i, but expected %i",
				i,
				count,
				counts[i],
			),
		)
	}

	fmt.println("Lexer: OK")
}

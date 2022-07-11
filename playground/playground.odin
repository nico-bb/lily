package playground

import "core:fmt"
import "core:mem"
import lily "../src"

main :: proc() {
	track := mem.Tracking_Allocator{}
	mem.tracking_allocator_init(&track, context.allocator)
	context.allocator = mem.tracking_allocator(&track)
	playground()

	// fmt.println()
	// if len(track.allocation_map) > 0 {
	// 	fmt.printf("Leaks:")
	// 	for _, v in track.allocation_map {
	// 		fmt.printf("\t%v\n\n", v)
	// 	}
	// }
	// fmt.printf("Leak count: %d\n", len(track.allocation_map))
	// if len(track.bad_free_array) > 0 {
	// 	fmt.printf("Bad Frees:")
	// 	for v in track.bad_free_array {
	// 		fmt.printf("\t%v\n\n", v)
	// 	}
	// }
}

playground :: proc() {using lily
	PRINT_AST :: true
	PRINT_SYMBOL_TABLE :: false
	PRINT_COMPILE :: true
	PRINT_VM_STATE :: true

	RUN_PARSER :: true
	RUN_CHECKER :: true
	RUN_COMPILER :: true
	RUN_VM :: true

	// input: string = `
	// 	type Foo is class
	// 		x: number

	// 		constructor new(_x: number):
	// 			self.x = _x
	// 		end

	// 		fn add(n: number):
	// 			self.x = self.x + n
	// 		end
	// 	end

	//     var a = Foo.new(1)
	// 	a.add(13)
	// `
	input := `
		import std
        
		var a = false
		var res = 11
		for i in 0..10:
			if not a:
				a = true
				res = res + 1
				break
			end
		end

		std.print(res)
	`

	state := new_state(Config{})
	err := compile_source(state, "main", input)
	assert(err == nil, fmt.tprint(err))

	run_module(state, "main")
	free_state(state)
	fmt.println("finished")
}

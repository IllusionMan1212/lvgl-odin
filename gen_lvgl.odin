package lvgl

import os "core:os/os2"
import "core:encoding/json"
import "core:fmt"
import "core:io"
import "core:c"
import "core:strings"

LVGL_VERSION :: "9.5"

// TODO: Improvements
/*
	Needed to just have the thing compile
	- [x] ^void -> rawptr
	- [x] -> void -> nothing
	- [x] void arguments -> nothing
	- [x] any argument named `context` needs to be `_context` or `ctx`
	- [ ] private forward decls? gltf stuff + some lv structs
		- the lv_image_dsc_t struct is just not found in the json file, even tho its defined in the header
		  we only get its typedef.
		  idk
	- [x] duplicate procs. resolve by skipping and printing warning when gen'ing
	- [ ] usage of enum members as array dimensions. not sure how to solve this.
		 can hardcode the only place this is used but I don't like hardcoding stuff.

	Nice to haves
	- ^u8 -> cstring
	- ^^ -> [^]^ ?? not super sure about this tbh. maybe manually on a case by case basis
*/

/*
	TODO: Are these needed? Can we do without them.
	- Macros ??
	- Variables ??
*/

get_primitive_type :: proc(type_name: string, options: ResolveOptions = {}) -> string {
	switch type_name {
	case "char":
		return "u8"
	case "bool":
		return "bool"
	case "int":
		return "i32"
	case "float":
		return "f32"
	case "void":
		if .PointerType not_in options && (.FunctionArgument in options || .ReturnType in options) {
			return ""
		}

		return "void"
	case "struct":
		return ""
	case:
		fmt.panicf("unknown primitive type: %v", type_name)
	}
}

ResolveOption :: enum {
	FunctionArgument,
	ReturnType,
	PointerType,
}

ResolveOptions :: bit_set[ResolveOption]

resolve_type :: proc(type: json.Object, nest_level: int, options: ResolveOptions = {}) -> string {
	tabs := strings.repeat("\t", nest_level)

	sb := strings.builder_make_len_cap(0, 8)

	json_type := type["json_type"].(json.String)

	switch json_type {
	case "primitive_type":
		name := type["name"].(json.String)
		strings.write_string(&sb, get_primitive_type(name, options))
	case "stdlib_type":
		name := type["name"].(json.String)
		strings.write_string(&sb, get_stdlib_type(name))
	case "lvgl_type":
		name := type["name"].(json.String)
		strings.write_string(&sb, name)
	case "struct":
		nested_type := type["type"].(json.Object)
		tabs = strings.repeat("\t", nest_level + 1)

		strings.write_string(&sb, fmt.tprintf("struct {{\n"))

		fields := type["fields"].(json.Array)

		for field in fields {
			f_tabs := strings.repeat("\t", nest_level + 2)
			f := field.(json.Object)
			f_name := f["name"].(json.String)
			f_type := f["type"].(json.Object)

			strings.write_string(&sb, fmt.tprintf("%s%s: %s,\n", f_tabs, f_name, resolve_type(f_type, nest_level + 2)))
		}

		strings.write_string(&sb, fmt.tprintf("%s}", tabs))
	case "pointer":
		nested_type := type["type"].(json.Object)
		resolved_type := resolve_type(nested_type, nest_level + 1, options + {.PointerType})

		if resolved_type == "void" {
			strings.write_string(&sb, "rawptr")
		} else {
			strings.write_string(&sb, fmt.tprintf("^%s", resolved_type))
		}

	case "union":
		nested_type := type["type"].(json.Object)

		strings.write_string(&sb, fmt.tprintf("struct #raw_union {{\n"))

		fields := type["fields"].(json.Array)

		for field in fields {
			f_tabs := strings.repeat("\t", nest_level + 1)
			f := field.(json.Object)
			f_name := f["name"].(json.String)
			f_type := f["type"].(json.Object)

			strings.write_string(&sb, fmt.tprintf("%s%s: %s,\n", f_tabs, f_name, resolve_type(f_type, nest_level + 1)))
		}

		strings.write_string(&sb, fmt.tprintf("%s}", tabs))
	case "function_pointer":
		strings.write_string(&sb, fmt.tprintf("#type proc \"c\" ("))

		fp_type := type["type"].(json.Object)
		args := type["args"].(json.Array)

		i := 0
		for arg in args {
			if i != 0 {
				strings.write_string(&sb, ", ")
			}

			a := arg.(json.Object)
			a_name := a["name"]

			arg_name := ""
			#partial switch v in a_name {
			case json.Null:
				arg_name = fmt.tprintf("arg%v", i)
			case json.String:
				arg_name = v
				if arg_name == "context" {
					arg_name = "ctx"
				}
			}

			a_docstring := a["docstring"].(json.String)
			a_type := a["type"].(json.Object)
			arg_type := resolve_type(a_type, nest_level + 1, options + {.FunctionArgument})

			if a_docstring != "" {
				strings.write_string(&sb, fmt.tprintf("/* %s */", a_docstring))
			}

			if arg_type != "" {
				strings.write_string(&sb, fmt.tprintf("%s: %s", arg_name, arg_type))
			}

			i += 1
		}

		strings.write_string(&sb, ")")
		strings.write_string(&sb, fmt.tprintf("%s", resolve_type(fp_type, nest_level + 1)))
	case "ret_type":
		nested_type := type["type"].(json.Object)
		ret_type := resolve_type(nested_type, nest_level + 1, options + {.ReturnType})

		if ret_type != "" {
			strings.write_string(&sb, fmt.tprintf(" -> %s", ret_type))
		}
	case "array":
		name := type["name"]
		dim := ""
		if d, ok := type["dim"].(json.String); ok {
			dim = d
		}

		#partial switch n in name {
		case nil:
			nested_type := type["type"].(json.Object)

			strings.write_string(&sb, fmt.tprintf("[%s]%s", dim, resolve_type(nested_type, nest_level + 1)))
		case json.String:
			// NOTE: array types don't have a nested type when a name is present.
			// The name could be a primitive type or a custom type.
			switch n {
			case "char", "uint8_t":
				strings.write_string(&sb, fmt.tprintf("[%s]u8", dim))
			case "short":
				strings.write_string(&sb, fmt.tprintf("[%s]i16", dim))
			case "int", "int32_t":
				strings.write_string(&sb, fmt.tprintf("[%s]i32", dim))
			case "float":
				strings.write_string(&sb, fmt.tprintf("[%s]f32", dim))
			case "double":
				strings.write_string(&sb, fmt.tprintf("[%s]f64", dim))
			case:
				strings.write_string(&sb, fmt.tprintf("[%s]%s", dim, n))
			}
		case:
			fmt.panicf("unhandled array name type: %s", n)
		}
	case "forward_decl":
		name := type["name"].(json.String)
		type := type["type"].(json.Object)

		strings.write_string(&sb, fmt.tprintf("%s %s", name, resolve_type(type, nest_level + 1)))
	case "typedef":
		name := type["name"].(json.String)
		type := type["type"].(json.Object)

		strings.write_string(&sb, fmt.tprintf("%s", resolve_type(type, nest_level + 1)))
	case "special_type":
		name := type["name"].(json.String)

		switch name {
		case "ellipsis":
			strings.write_string(&sb, "..any")
		case:
			fmt.panicf("unhandled special type: %s", name)
		}
	case:
		fmt.panicf("unhandled json_type: %v", json_type)
	}

	return strings.to_string(sb)
}

generate_enums :: proc(value: json.Array, file: ^os.File) {
	os.write_string(file, `
/*
    ----------------
     ENUMS
    ----------------
*/

`)

	for e in value {
		e := e.(json.Object)
		e_name := e["name"].(json.String)
		e_docstring := e["docstring"].(json.String)
		e_type := e["type"].(json.Object)
		e_members := e["members"].(json.Array)

		if e_docstring != "" {
			os.write_string(file, fmt.tprintf("/* %s */\n", e_docstring))
		}

		// if type["json_type"].(json.String) != "primitive_type" {
		// 	fmt.panicf("Got enum with non-primitive type: %v", type)
		// }

		os.write_string(file, fmt.tprintf("%s :: enum %s {{\n", e_name, resolve_type(e_type, 0)))

		for member in e_members {
			m := member.(json.Object)
			m_name := m["name"].(json.String)
			m_docstring := m["docstring"].(json.String)
			m_value := m["value"].(json.String)

			if m_docstring != "" {
				os.write_string(file, fmt.tprintf("\t/* %s */\n", m_docstring))
			}

			os.write_string(file, fmt.tprintf("\t%s = %v,\n", m_name, m_value))
		}

		os.write_string(file, "}\n\n")
	}
}

get_stdlib_type :: proc(type: string) -> string {
	switch type {
	case "int8_t":
		return "i8"
	case "uint8_t":
		return "u8"
	case "int16_t":
		return "i16"
	case "uint16_t":
		return "u16"
	case "int32_t":
		return "i32"
	case "uint32_t":
		return "u32"
	case "int64_t":
		return "i64"
	case "uint64_t":
		return "u64"
	case "intptr_t":
		return "int"
	case "uintptr_t":
		return "uintptr"
	case "size_t":
		return "uint"
	case "ssize_t":
		return "int"
	case "va_list":
		return "c.va_list"
	case:
		fmt.panicf("unknown stdlib type: %v", type)
	}
}

generate_structs :: proc(value: json.Array, file: ^os.File) {
	os.write_string(file, `
/*
	-----------------
	 STRUCTURES
	-----------------
*/

`)

	for s in value {
		s := s.(json.Object)
		s_name := s["name"].(json.String)
		s_docstring := s["docstring"].(json.String)
		s_type := s["type"].(json.Object)
		s_fields := s["fields"].(json.Array)

		if s_docstring != "" {
			os.write_string(file, fmt.tprintf("/* %s */\n", s_docstring))
		}

		os.write_string(file, fmt.tprintf("%s :: struct {{\n", s_name))

		for field in s_fields {
			f := field.(json.Object)
			f_name := f["name"].(json.String)
			f_docstring := f["docstring"].(json.String)
			f_type := f["type"].(json.Object)

			if f_docstring != "" {
				os.write_string(file, fmt.tprintf("\t/* %s */\n", f_docstring))
			}

			os.write_string(file, fmt.tprintf("\t%s: %s,\n", f_name, resolve_type(f_type, 1)))
		}

		os.write_string(file, "}\n\n")
	}
}

generate_field :: proc(file: ^os.File, field: json.Value, nest_level: int) {
	tabs := strings.repeat("\t", nest_level)

	f := field.(json.Object)
	f_name := f["name"].(json.String)
	f_docsring := f["docstring"].(json.String)
	f_bitsize := f["bitsize"]
	f_type := f["type"].(json.Object)

	#partial switch b in f_bitsize {
	case json.Null:
		os.write_string(file, fmt.tprintf("%s%s: %s,\n", tabs, f_name, resolve_type(f_type, 0)))
	case json.String:
		fmt.panicf("Unhandled bitfield")
	}
}

generate_unions :: proc(value: json.Array, file: ^os.File) {
	os.write_string(file, `
/*
	----------------
	 UNIONS
	----------------
*/

`)

	for u in value {
		u := u.(json.Object)
		u_name := u["name"].(json.String)
		u_docstring := u["docstring"].(json.String)
		u_fields := u["fields"].(json.Array)

		if u_docstring != "" {
			os.write_string(file, fmt.tprintf("/* %s */\n", u_docstring))
		}

		os.write_string(file, fmt.tprintf("%s :: struct #raw_union {{\n", u_name))

		for field in u_fields {
			generate_field(file, field, 1)
		}

		os.write_string(file, "}\n\n")
	}
}

generate_proc_pointers :: proc(value: json.Array, file: ^os.File) {
	os.write_string(file, `
/*
	---------------------
	 PROCEDURE POINTERS
	---------------------
*/

`)

	for fp in value {
		fp := fp.(json.Object)
		fp_name := fp["name"].(json.String)
		fp_docstring := fp["docstring"].(json.String)

		if fp_docstring != "" {
			os.write_string(file, fmt.tprintf("/* %s */\n", fp_docstring))
		}

		os.write_string(file, fmt.tprintf("%s :: %s\n", fp_name, resolve_type(fp, 0)))
	}
}

generate_typedefs :: proc(value: json.Array, file: ^os.File) {
	commented_out_typedefs := [?]string{"lv_gltf_environment_t", "lv_gltf_ibl_sampler_t"}

	os.write_string(file,`
/*
	-------------------
	 TYPEDEFS
	-------------------
*/

`)

	for t in value {
		t := t.(json.Object)
		t_name := t["name"].(json.String)
		t_docstring := t["docstring"].(json.String)

		if t_docstring != "" {
			os.write_string(file, fmt.tprintf("/* %s */\n", t_docstring))
		}

		for ct in commented_out_typedefs {
			if t_name == ct {
				os.write_string(file, "// ")
			}
		}

		os.write_string(file, fmt.tprintf("%s :: distinct %s\n", t_name, resolve_type(t, 0)))
	}
}

generate_forward_decls :: proc(value: json.Array, file: ^os.File) {
	os.write_string(file, `
/*
	---------------------
	 FORWARD DECLERATIONS
	---------------------
*/

`)

	for fd in value {
		fd := fd.(json.Object)
		fd_name := fd["name"].(json.String)
		fd_type := fd["type"].(json.Object)
		fd_docstring := fd["docstring"].(json.String)

		if fd_docstring != "" {
			os.write_string(file, fmt.tprintf("/* %s */\n", fd_docstring))
		}

		os.write_string(file, fmt.tprintf("%s :: struct {{}\n", fd_name))
	}
}

generate_procs :: proc(value: json.Array, file: ^os.File) {
	seen_procs := make(map[string]struct{})

	os.write_string(file, `
/*
	--------------------
	 PROCEDURES
	--------------------
*/

foreign lvgl {
`)

	for p in value {
		p := p.(json.Object)
		p_name := p["name"].(json.String)
		p_docstring := p["docstring"].(json.String)
		p_args := p["args"].(json.Array)
		p_type := p["type"].(json.Object)

		if _, seen := seen_procs[p_name]; seen {
			fmt.printfln("WARN: procedure \"%s\" was already seen before. Skipping", p_name)
			continue
		}

		if p_docstring != "" {
			os.write_string(file, fmt.tprintf("\t/* %s */\n", p_docstring))
		}

		seen_procs[p_name] = {}

		os.write_string(file, fmt.tprintf("\t%s :: proc(", p_name))

		i := 0
		for arg in p_args {
			if i != 0 {
				os.write_string(file, ", ")
			}

			a := arg.(json.Object)
			a_name := a["name"]

			arg_name := ""
			#partial switch v in a_name {
			case json.Null:
				arg_name = fmt.tprintf("arg%v", i)
			case json.String:
				arg_name = v
				if arg_name == "context" {
					arg_name = "ctx"
				}
				if arg_name == "matrix" {
					arg_name = "mtx"
				}
				if arg_name == "map" {
					arg_name = "map_"
				}
				if arg_name == "..." {
					arg_name = "args"
				}
			}

			a_docstring := a["docstring"].(json.String)
			a_type := a["type"].(json.Object)
			arg_type := resolve_type(a_type, 0, {.FunctionArgument})

			if a_docstring != "" {
				os.write_string(file, fmt.tprintf("/* %s */", a_docstring))
			}

			if arg_type != "" {
				if arg_type == "..any" {
					os.write_string(file, fmt.tprintf("#c_vararg %s: %s", arg_name, arg_type))
				} else {
					os.write_string(file, fmt.tprintf("%s: %s", arg_name, arg_type))
				}
			}

			i += 1
		}

		os.write_string(file, ")")
		resolved_type := resolve_type(p_type, 0, {.ReturnType})
		if resolved_type != "" {
			os.write_string(file, fmt.tprintf("%s", resolved_type))
		}
		os.write_string(file, " ---\n")
	}

	os.write_string(file, "}")
}

main :: proc() {
	data, err := os.read_entire_file_from_path("lvgl_api.json", context.temp_allocator)
	if err != nil {
		fmt.panicf("Error reading api file: %v", err)
	}

	// api: API
	// unmarshal_err := json.unmarshal(data, &api)
	// if unmarshal_err != nil {
	// 	fmt.panicf("Error while unmarshalling: %v", unmarshal_err)
	// }

	file, open_err := os.open("lvgl.odin", {.Write, .Create, .Trunc})
	if open_err != nil {
		fmt.panicf("Error opening lvgl.odin file: %v", open_err)
	}
	defer os.close(file)

	os.write_string(file, "/*\n")
	os.write_string(file, "\tTHIS FILE WAS GENERATED BY gen_lvgl.odin. DO NOT MODIFY\n")
	os.write_string(file, "\tTHIS FILE WAS GENERATED BY gen_lvgl.odin. DO NOT MODIFY\n")
	os.write_string(file, "\tTHIS FILE WAS GENERATED BY gen_lvgl.odin. DO NOT MODIFY\n")
	os.write_string(file, "\n")
	os.write_string(file, fmt.tprintf("\tGENERATED FROM LVGL VERSION %s\n", LVGL_VERSION))
	os.write_string(file, "*/")

	os.write_string(file, `
package lvgl

import "core:c"

when ODIN_OS == .Linux {
foreign import lvgl {
	"lib/liblvgl.a",
}
} else when ODIN_OS == .Windows {
foreign import lvgl {
	"lib/lvgl.lib",
}
} else when ODIN_OS == .Darwin {
	// TODO: implement me
}
`)

	value, parse_err := json.parse(data)
	if parse_err != nil {
		fmt.panicf("Failed to parse json: %v", parse_err)
	}
	defer json.destroy_value(value)

	generate_enums(value.(json.Object)["enums"].(json.Array), file)
	generate_proc_pointers(value.(json.Object)["function_pointers"].(json.Array), file)
	generate_forward_decls(value.(json.Object)["forward_decls"].(json.Array), file)
	generate_typedefs(value.(json.Object)["typedefs"].(json.Array), file)
	generate_structs(value.(json.Object)["structures"].(json.Array), file)
	generate_unions(value.(json.Object)["unions"].(json.Array), file)
	generate_procs(value.(json.Object)["functions"].(json.Array), file)

	fmt.println("Successfully generated bindings")
}

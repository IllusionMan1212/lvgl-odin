package lvgl

import os "core:os/os2"
import "core:encoding/json"
import "core:fmt"
import "core:io"
import "core:c"
import "core:strings"

LVGL_VERSION :: "9.5"

/*
            "name": "lv_result_t",
            "type": {
                "name": "int",
                "json_type": "primitive_type"
            },
            "json_type": "enum",
            "docstring": "",
            "members": [
                {
                    "name": "LV_RESULT_INVALID",
                    "type": {
                        "name": "lv_result_t",
                        "json_type": "lvgl_type"
                    },
                    "json_type": "enum_member",
                    "docstring": "",
                    "value": "0x0"
                },
                {
                    "name": "LV_RESULT_OK",
                    "type": {
                        "name": "lv_result_t",
                        "json_type": "lvgl_type"
                    },
                    "json_type": "enum_member",
                    "docstring": "",
                    "value": "0x1"
                }
            ],
            "quals": []
*/

EnumMember :: struct {
	name: string `json:"name"`,
	/* type */
	/* json_type */
	docstring: string `json:"docstring"`,
	value: string `json:"value"`,
}

Qual :: distinct string

Enum :: struct {
	name: string `json:"name"`,
	/* type */
	/* json_type */
	docstring: string `json:"docstring"`,
	members: []EnumMember `json:"members"`,
	quals: []Qual `json:"quals"`
}

Function :: struct {
}

Argument :: struct {
	name: Maybe(string) `json:"name"`,
	// type: Type,
	/* json_type. always arg */
	docstring: string `json:"docstring"`,
	quals: []Qual `json:"quals"`,
}

FunctionPointer :: struct {
	name: string `json:"name"`,
	/* type */
	/* json_type. always function_pointer */
	docstring: string `json:"docstring"`,
	args: []Argument `json:"args"`,
}

Structure :: struct {
	name: string `json:"name"`,
	/* type. usually just primitive_type of struct which we already know */
	/* json_type */
	docstring: string `json:"docstring"`,
	fields: []Field `json:"fields"`,
	quals: []Qual `json:"quals"`,
}

Field :: struct {
	name: string `json:"name"`,
	type: struct {
		name: string `json:"name"`,
		json_type: string `json:"json_type"`,
		docstring: string `json:"docstring"`,
		type: struct {
			name: string `json:"name"`,
			json_type: string `json:"json_type"`,
			type: struct { // There's no way we're gonna have more than 2 pointers right?
				name: string `json:"name"`,
				json_type: string `json:"json_type"`,
			},
		} `json:"type"`,
		fields: []Field `json:"fields"`,
	},
	/* json_type */
	docstring: string `json:"docstring"`,
}

Union :: struct {
	name: string `json:"name"`,
	/* type */
	/* json_type */
	docstring: string `json:"docstring"`,
	fields: []Field `json:"fields"`,
	quals: []Qual `json:"quals"`,
}

Variable :: struct {

}

Typedef :: struct {

}

ForwardDecl :: struct {
}

Macro :: struct {
}

API :: struct {
	enums: []Enum `json:"enums"`,
	functions: []Function `json:"functions"`,
	function_pointers: []FunctionPointer `json:"function_pointers"`,
	structures: []Structure `json:"structures"`,
	unions: []Union `json:"unions"`,
	variables: []Variable `json:"variables"`,
	typedefs: []Typedef `json:"typedefs"`,
	forward_decls: []ForwardDecl `json:"forward_decls"`,
	macros: []Macro `json:"macros"`,
}

resolve_type :: proc(type: json.Object) -> string {
	sb := strings.builder_make_len_cap(0, 8)

	name := type["name"].(json.String)
	json_type := type["json_type"].(json.String)

	switch json_type {
	case "primitive_type":
		strings.write_string(&sb, get_primitive_type(name))
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

		os.write_string(file, fmt.tprintf("%s :: enum %s {{\n", e_name, resolve_type(e_type)))

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

get_primitive_type :: proc(type_name: string) -> string {
	switch type_name {
	case "int":
		return "i32"
	case:
		fmt.panicf("unknown primitive type: %v", type_name)
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
	case "size_t":
		return "uint"
	case "ssize_t":
		return "int"
	case:
		fmt.panicf("unknown stdlib type: %v", type)
	}
}

generate_field :: proc(file: ^os.File, field: Field, nest_level: int) {
	tabs := strings.repeat("\t", nest_level)
	if field.docstring != "" {
		os.write_string(file, fmt.tprintf("%s/* %s */\n", tabs, field.docstring))
	}

	switch field.type.json_type {
	case "struct":
		os.write_string(file, fmt.tprintf("%s%s: struct {{\n", tabs, field.name))
		for subfield in field.type.fields {
			generate_field(file, subfield, nest_level + 1)
		}
		os.write_string(file, fmt.tprintf("%s},\n", tabs))
	case "pointer":
		switch field.type.type.json_type {
		case "primitive_type":
			switch field.type.type.name {
			case "void":
				os.write_string(file, fmt.tprintf("%s%s: rawptr,\n", tabs, field.name))
			case "char":
				os.write_string(file, fmt.tprintf("%s%s: cstring,\n", tabs, field.name))
			case:
				fmt.panicf("unimplemented primitive pointer: %v", field)
			}
		case "stdlib_type":
			os.write_string(file, fmt.tprintf("%s%s: ^%s,\n", tabs, field.name, get_stdlib_type(field.type.type.name)))
		case "lvgl_type":
			os.write_string(file, fmt.tprintf("%s%s: ^%s,\n", tabs, field.name, field.type.type.name))
		case "pointer":
			switch field.type.type.type.json_type {
			case "primitive_type":
				switch field.type.type.type.name {
				case "void":
					os.write_string(file, fmt.tprintf("%s%s: ^rawptr,\n", tabs, field.name))
				case:
					fmt.panicf("unimplemented primitive pointer: %v", field)
				}
			case "stdlib_type":
				os.write_string(file, fmt.tprintf("%s%s: ^^%s,\n", tabs, field.name, get_stdlib_type(field.type.type.type.name)))
			case "lvgl_type":
				os.write_string(file, fmt.tprintf("%s%s: ^^%s,\n", tabs, field.name, field.type.type.type.name))
			case:
				fmt.panicf("unimplemented pointer: %v", field)
			}
		case:
			fmt.panicf("unimplemented pointer: %v", field)
		}
	case "stdlib_type":
		os.write_string(file, fmt.tprintf("%s%s: %s,\n", tabs, field.name, get_stdlib_type(field.type.name)))
	case "primitive_type":
		switch field.type.name {
		case "float":
			os.write_string(file, fmt.tprintf("%s%s: f32,\n", tabs, field.name))
		case "bool":
			os.write_string(file, fmt.tprintf("%s%s: bool,\n", tabs, field.name))
		case "char":
			os.write_string(file, fmt.tprintf("%s%s: u8,\n", tabs, field.name))
		case:
			fmt.panicf("unimplemented primitive type: %v", field)
		}
	case:
		os.write_string(file, fmt.tprintf("%s%s: %s,\n", tabs, field.name, field.type.name))
	}
}

generate_structs :: proc(api: API, file: ^os.File) {
	os.write_string(file, `
/*
	-----------------
	 STRUCTURES
	-----------------
*/

`)

	for s in api.structures {
		if s.docstring != "" {
			os.write_string(file, fmt.tprintf("/* %s */\n", s.docstring))
		}

		os.write_string(file, fmt.tprintf("%s :: struct {{\n", s.name))

		for field in s.fields {
			generate_field(file, field, 1)
		}

		os.write_string(file, "}\n\n")
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
			f := field.(json.Object)
			f_name := f["name"].(json.String)
			f_docsring := f["docstring"].(json.String)

			// TODO: CONTINUE FROM HERE
		}

		os.write_string(file, "}\n\n")
	}

	// for u in api.unions {
	// 	if u.docstring != "" {
	// 		os.write_string(file, fmt.tprintf("/* %s */\n", u.docstring))
	// 	}

	// 	os.write_string(file, fmt.tprintf("%s :: struct #raw_union {{\n", u.name))

	// 	for field in u.fields {
	// 		generate_field(file, field, 1)
	// 	}

	// 	os.write_string(file, "}\n\n")
	// }
}

generate_proc_pointers :: proc(api: API, file: ^os.File) {
	os.write_string(file, `
/*
	---------------------
	 PROCEDURE POINTERS
	---------------------
*/

`)

	for fp in api.function_pointers {
	}
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

	// fmt.println(api)

	value, parse_err := json.parse(data)
	if parse_err != nil {
		fmt.panicf("Failed to parse json: %v", parse_err)
	}
	defer json.destroy_value(value)

	// fmt.println(value)

	generate_enums(value.(json.Object)["enums"].(json.Array), file)
	// generate_structs(api, file)
	generate_unions(value.(json.Object)["unions"].(json.Array), file)
	// generate_proc_pointers(api, file)
	// generate_procs(api, file)
}

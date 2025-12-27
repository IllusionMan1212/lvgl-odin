package lvgl

import os "core:os/os2"
import "core:encoding/json"
import "core:fmt"
import "core:io"

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

FunctionPointer :: struct {

}

Structure :: struct {
}

UnionField :: struct {
	name: string `json:"name"`,
	type: struct {
		name: string `json:"name"`,
		json_type: string `json:"json_type"`,
		docstring: string `json:"docstring"`,
		fields: []UnionField `json:"fields"`,
	},
	/* json_type */
	docstring: string `json:"docstring"`,
}

Union :: struct {
	name: string `json:"name"`,
	/* type */
	/* json_type */
	docstring: string `json:"docstring"`,
	fields: []UnionField `json:"fields"`,
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

generate_enums :: proc(api: API, file: ^os.File) {
	os.write_string(file, `
/*
    ----------------
     ENUMS
    ----------------
*/

`)
	for e in api.enums {
		if e.docstring != "" {
			os.write_string(file, fmt.tprintf("/* %s */\n", e.docstring))
		}

		os.write_string(file, fmt.tprintf("%s :: enum {{\n", e.name))

		for member in e.members {
			if member.docstring != "" {
				os.write_string(file, fmt.tprintf("\t/* %s */\n", member.docstring))
			}

			os.write_string(file, fmt.tprintf("\t%s = %v,\n", member.name, member.value))
		}

		// TODO: quals?

		os.write_string(file, "}\n\n")
	}
}

generate_structs :: proc(api: API, file: ^os.File) {
}

generate_unions :: proc(api: API, file: ^os.File) {
	os.write_string(file, `
/*
	----------------
	 UNIONS
	----------------
*/

`)

	for u in api.unions {
		if u.docstring != "" {
			os.write_string(file, fmt.tprintf("/* %s */\n", u.docstring))
		}

		os.write_string(file, fmt.tprintf("%s :: struct #raw_union {{\n", u.name))

		for field in u.fields {
			if field.docstring != "" {
				os.write_string(file, fmt.tprintf("\t/* %s */\n", field.docstring))
			}

			switch field.type.json_type {
			case "struct":
				// os.write_string(file, "\t//TODO: this is a struct\n")
				os.write_string(file, "\t")
				for subfield in field.type.fields {
					// TODO: make this recursive

					os.write_string(file, fmt.tprintf("\t\t %s: %s", subfield.name, subfield.type))
				}
				fmt.panicf("unimplemented struct: %v", field)
			case "pointer":
				fmt.panicf("unimplemented pointer: %v", field)
				// os.write_string(file, fmt.tprintf("\t%s: %s,\n", field.name, field.type.name))
			case "stdlib_type":
				fmt.panicf("unimplemented stdlib type: %v", field)
			case:
				os.write_string(file, fmt.tprintf("\t%s: %s,\n", field.name, field.type.name))
			}
			if field.type.json_type == "struct" {
			} else {
			}
		}

		os.write_string(file, "}\n\n")
	}
}

main :: proc() {
	data, err := os.read_entire_file_from_path("lvgl_api.json", context.temp_allocator)
	if err != nil {
		fmt.panicf("Error reading api file: %v", err)
	}

	api: API
	unmarshal_err := json.unmarshal(data, &api)
	if unmarshal_err != nil {
		fmt.panicf("Error while unmarshalling: %v", unmarshal_err)
	}

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

	generate_enums(api, file)
	generate_unions(api, file)
	// generate_structs(api, file)
	// generate_procs(api, file)
}

; Module docstring (first stmt if it's a string)
(module
  (expression_statement (string) @module.docstring)) @module

; Imports
(import_statement) @module.import
(import_from_statement) @module.import_from

; Top-level defs (direct children of module)
(module (function_definition) @toplevel.func)
(module (class_definition) @toplevel.class)

; Useful top-level statements
; (module (assignment) @toplevel.assign)
(module (expression_statement) @toplevel.stmt)

; if __name__ == "__main__": entrypoint
; (if_statement
;   condition: (comparison_operator
;     left: (identifier) @name (#eq? @name "__name__")
;     right: (string) @main_str (#match? @main_str "^['\"]__main__['\"]")))
; @toplevel.main


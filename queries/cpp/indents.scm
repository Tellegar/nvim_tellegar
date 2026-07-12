
; (_) @indent.zero
; (_) @indent.ignore

(concatenated_string) @indent.auto
(preproc_directive) @indent.zero
(access_specifier) @indent.branch

; fuck this shit, any person who doesn't make his own IDE is insane
;   simply because when you make it you will understand it and to tweak anything
;   will be so much easier then to tweak non-functioning shit like this

; ((_) @indent.begin (field_initializer_list) @indent.end)

; (function_definition
;   .
;   ")" @indent.begin
;   "{" @indent.end
; )

; (field_initializer_list) @indent.begin       ; indent children when matching this node
; (field_initializer_list) @indent.end         ; marks the end of indented block
; (field_initializer_list) @indent.align       ; behaves like python aligned/hanging indent
; (field_initializer_list) @indent.dedent      ; dedent children when matching this node
; (field_initializer_list) @indent.branch      ; dedent itself when matching this node
; (field_initializer_list) @indent.ignore      ; do not indent in this node
; (field_initializer_list) @indent.auto        ; behaves like 'autoindent' buffer option
; (field_initializer_list) @indent.zero        ; sets this node at position 0 (no indent)

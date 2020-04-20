
        AREA    |Test$$Code|, CODE

        GET     hdr.swis

hello_world     ROUT
        ADR     r0, hello
        MOV     r1, #0
        ADR     r2, world
        SWI     OS_PrettyPrint
        SWI     OS_NewLine
        MOV     pc, lr
hello
        = "Hello ", 27, 0, 0
world
        = "world", 0

        END

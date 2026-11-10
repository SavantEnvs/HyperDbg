/*
 * libFuzzer harness for HyperDbg's script engine front end (scanner + LL(1) parser + code generator).
 * ScriptEngineParse() is the entry point the debugger calls for every script, "?" expression and
 * event condition a user types.
 */
#include "pch.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

/* Identifiers declared by one script stay visible to the next one in a real session. */
extern PSCRIPT_ENGINE_TOKEN_LIST GlobalIdTable;

static void
ResetGlobalIdTable(void)
{
    if (GlobalIdTable == NULL)
    {
        return;
    }
    for (uintptr_t i = 0; i < GlobalIdTable->Pointer; i++)
    {
        PSCRIPT_ENGINE_TOKEN Token = GlobalIdTable->Head[i];
        RemoveToken(&Token);
    }
    GlobalIdTable->Pointer = 0;
}

int
LLVMFuzzerTestOneInput(const uint8_t * Data, size_t Size)
{
    char * Script = (char *)malloc(Size + 1);
    if (Script == NULL)
    {
        return 0;
    }
    memcpy(Script, Data, Size);
    Script[Size] = '\0';

    PSYMBOL_BUFFER CodeBuffer = (PSYMBOL_BUFFER)ScriptEngineParse(Script);
    int            Rc         = (CodeBuffer != NULL && CodeBuffer->Message != NULL) ? -1 : 0;

    if (CodeBuffer != NULL)
    {
        RemoveSymbolBuffer(CodeBuffer);
    }
    ResetGlobalIdTable();
    free(Script);
    return Rc;
}

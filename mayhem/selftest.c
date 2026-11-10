/*
 * Known-answer probe for the script engine: parses each script given on the command line and prints
 * the generated symbol buffer in a stable text form (or the parser's error message). mayhem/test.sh
 * diffs that output against mayhem/tests/<name>.expected.
 */
#include "pch.h"

#include <stdio.h>
#include <stdlib.h>

extern PSCRIPT_ENGINE_TOKEN_LIST GlobalIdTable;

static char *
ReadAll(const char * Path)
{
    FILE * F = fopen(Path, "rb");
    if (!F)
    {
        fprintf(stderr, "cannot open %s\n", Path);
        exit(2);
    }
    fseek(F, 0, SEEK_END);
    long N = ftell(F);
    fseek(F, 0, SEEK_SET);
    char * Buf = malloc(N + 1);
    if (fread(Buf, 1, N, F) != (size_t)N)
    {
        exit(2);
    }
    Buf[N] = 0;
    fclose(F);
    return Buf;
}

int
main(int argc, char ** argv)
{
    for (int i = 1; i < argc; i++)
    {
        char *         Script = ReadAll(argv[i]);
        PSYMBOL_BUFFER Buf    = (PSYMBOL_BUFFER)ScriptEngineParse(Script);

        if (Buf->Message != NULL)
        {
            printf("ERROR: %s\n", Buf->Message);
        }
        else
        {
            printf("SYMBOLS: %u\n", Buf->Pointer);
            for (unsigned int j = 0; j < Buf->Pointer; j++)
            {
                printf("%llu %llu\n", Buf->Head[j].Type, Buf->Head[j].Value);
            }
        }
        RemoveSymbolBuffer(Buf);
        for (uintptr_t j = 0; GlobalIdTable && j < GlobalIdTable->Pointer; j++)
        {
            PSCRIPT_ENGINE_TOKEN T = GlobalIdTable->Head[j];
            RemoveToken(&T);
        }
        if (GlobalIdTable)
        {
            GlobalIdTable->Pointer = 0;
        }
        free(Script);
    }
    return 0;
}

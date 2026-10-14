#ifndef __miva_pcre2_h
#define __miva_pcre2_h

#include "../include/mivapi.h"


#ifdef WIN32
  #define IMPORT __declspec(dllimport)
  #define EXPORT __declspec(dllexport)
#else
  #define IMPORT
  #define EXPORT
#endif

#ifdef __cplusplus
extern "C" {
#endif

/**
* Forward Declarations
*/

void miva_pcre2_regexp(mvProgram program, mvVariableHash parameters, mvVariable returnvalue, void **unknown);
void miva_pcre2_last_error(mvProgram program, mvVariableHash parameters, mvVariable returnvalue, void **unknown);
EXPORT MV_EL_Function_List *miva_function_table();

#ifdef __cplusplus
}
#endif

#endif

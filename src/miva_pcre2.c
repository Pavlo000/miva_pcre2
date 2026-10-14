#include <string.h>
#include "miva_pcre2.h"

#define PCRE2_CODE_UNIT_WIDTH 8

#include "../include/pcre2/build/interface/pcre2.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
* Function Parameter Data Structures
*/
MV_EL_FunctionParameter miva_pcre2_regexp_parameters[] = {
  { "pattern",  7, EPF_NORMAL },
  { "string",   8, EPF_NORMAL },
  { "options",  8, EPF_NORMAL },
  { "output",   6, EPF_REFERENCE },
};

MV_EL_FunctionParameter miva_pcre2_last_error_parameters[] = {

};

/**
* miva_pcre2_regexp
*
* Perform a regular expression match. Returns 0 on no match and 1-indexed
* offset of the first match.
*
* Options:
*   i - case-insensitive
*   g - find all matches
*   m - multiline (^/$ match line boundaries)
*   s - dotall (. matches newlines)
*   x - extended (ignore unescaped whitespace / # comments)
*   u - UTF-8 + Unicode character properties
*
* On success, output is populated as:
*   output:matches[n][c]  - capture c (1-based; 1 = full match) of match n
*   output:groups:name    - named captures from the first match
*
* Example:
*
* <MvASSIGN NAME="g.match" VALUE="{ pcre2_regexp('^Hello', 'Hello World', '', l.out) }" />  - Returns 1
* <MvASSIGN NAME="g.match" VALUE="{ pcre2_regexp('^hello', 'Hello World', 'i', l.out) }" /> - Returns 1
* <MvASSIGN NAME="g.match" VALUE="{ pcre2_regexp('^hello', 'Hello World', '', l.out) }" />  - Returns 0
*/

static char last_error[256];
static int  last_error_length = 0;

static void miva_pcre2_set_last_error_msg(const char *msg) {
  size_t len = strlen(msg);

  if (len >= sizeof(last_error)) {
    len = sizeof(last_error) - 1;
  }

  memcpy(last_error, msg, len);
  last_error[len] = '\0';
  last_error_length = (int)len;
}

static void miva_pcre2_set_last_error_pcre(int errorcode) {
  int len = pcre2_get_error_message(errorcode, (PCRE2_UCHAR *)last_error, sizeof(last_error));

  if (len < 0) {
    last_error[0] = '\0';
    last_error_length = 0;
    return;
  }

  last_error_length = len;
}

static void miva_pcre2_fill_captures(mvVariable captures, PCRE2_SPTR subject, PCRE2_SIZE *ovector, int rc) {
  int i;

  for (i = 0; i < rc; i++) {
    PCRE2_SPTR substring_start  = subject + ovector[2 * i];
    PCRE2_SIZE substring_length = ovector[2 * i + 1] - ovector[2 * i];
    mvVariable match            = mvVariable_Array_Element(i + 1, captures, 1);

    mvVariable_SetValue(match, (char *)substring_start, (int)substring_length);
  }
}

static void miva_pcre2_fill_named_groups(mvVariable groups, PCRE2_SPTR subject, PCRE2_SIZE *ovector,
                                         PCRE2_SPTR name_table, uint32_t namecount,
                                         uint32_t name_entry_size) {
  PCRE2_SPTR tabptr = name_table;
  uint32_t i;

  for (i = 0; i < namecount; i++) {
    int n              = (tabptr[0] << 8) | tabptr[1];
    const char *name   = (const char *)(tabptr + 2);
    int name_len       = (int)strlen(name);
    PCRE2_SPTR start   = subject + ovector[2 * n];
    PCRE2_SIZE length  = ovector[2 * n + 1] - ovector[2 * n];
    mvVariable group   = mvVariable_Struct_Member(name, name_len, groups, 1);

    mvVariable_SetValue(group, (char *)start, (int)length);
    tabptr += name_entry_size;
  }
}

void miva_pcre2_regexp(mvProgram program, mvVariableHash parameters, mvVariable returnvalue, void **unknown) {
  int pattern_length = 0;
  int string_length = 0;
  int options_length = 0;
  int find_all = 0;
  uint32_t compile_options = 0;
  int errornumber = 0;
  PCRE2_SIZE erroroffset = 0;
  pcre2_code *re = NULL;
  pcre2_match_data *match_data = NULL;
  PCRE2_SIZE *ovector = NULL;
  int rc;
  int first_match_offset = 0;
  int match_index = 1;
  uint32_t namecount = 0;
  PCRE2_SPTR name_table = NULL;
  uint32_t name_entry_size = 0;
  mvVariable output;
  mvVariable matches;
  mvVariable groups;
  int i;

  last_error[0] = '\0';
  last_error_length = 0;

  const PCRE2_SPTR pattern = (PCRE2_SPTR)mvVariable_Value(mvVariableHash_Index(parameters, 0), &pattern_length);
  const PCRE2_SPTR string  = (PCRE2_SPTR)mvVariable_Value(mvVariableHash_Index(parameters, 1), &string_length);
  const char *options      = mvVariable_Value(mvVariableHash_Index(parameters, 2), &options_length);

  for (i = 0; i < options_length; i++) {
    switch (options[i]) {
      case 'g':
        find_all = 1;
        break;
      case 'i':
        compile_options |= PCRE2_CASELESS;
        break;
      case 's':
        compile_options |= PCRE2_DOTALL;
        break;
      case 'm':
        compile_options |= PCRE2_MULTILINE;
        break;
      case 'x':
        compile_options |= PCRE2_EXTENDED;
        break;
      case 'u':
        compile_options |= PCRE2_UTF | PCRE2_UCP;
        break;
    }
  }

  re = pcre2_compile(
    pattern,
    (PCRE2_SIZE)pattern_length,
    compile_options,
    &errornumber,
    &erroroffset,
    NULL
  );

  if (re == NULL) {
    miva_pcre2_set_last_error_pcre(errornumber);
    mvVariable_SetValue_Integer(returnvalue, 0);
    return;
  }

  match_data = pcre2_match_data_create_from_pattern(re, NULL);
  if (match_data == NULL) {
    miva_pcre2_set_last_error_msg("Failed to allocate match data");
    pcre2_code_free(re);
    mvVariable_SetValue_Integer(returnvalue, 0);
    return;
  }

  rc = pcre2_match(
    re,
    string,
    (PCRE2_SIZE)string_length,
    0,
    0,
    match_data,
    NULL
  );

  if (rc < 0) {
    if (rc != PCRE2_ERROR_NOMATCH) {
      miva_pcre2_set_last_error_pcre(rc);
    }

    pcre2_match_data_free(match_data);
    pcre2_code_free(re);
    mvVariable_SetValue_Integer(returnvalue, 0);
    return;
  }

  ovector = pcre2_get_ovector_pointer(match_data);

  if (ovector[0] > ovector[1]) {
    miva_pcre2_set_last_error_msg("\\K was used in an assertion to set the match start after its end.");
    pcre2_match_data_free(match_data);
    pcre2_code_free(re);
    mvVariable_SetValue_Integer(returnvalue, 0);
    return;
  }

  first_match_offset = (int)ovector[0] + 1;

  output  = mvVariableHash_Index(parameters, 3);
  matches = mvVariable_Struct_Member("matches", 7, output, 1);
  groups  = mvVariable_Struct_Member("groups", 6, output, 1);

  (void)pcre2_pattern_info(re, PCRE2_INFO_NAMECOUNT, &namecount);
  if (namecount > 0) {
    (void)pcre2_pattern_info(re, PCRE2_INFO_NAMETABLE, &name_table);
    (void)pcre2_pattern_info(re, PCRE2_INFO_NAMEENTRYSIZE, &name_entry_size);
  }

  /* First match: matches[1][c] = captures; groups:name from first match */
  {
    mvVariable match_captures = mvVariable_Array_Element(match_index, matches, 1);
    miva_pcre2_fill_captures(match_captures, string, ovector, rc);

    if (namecount > 0) {
      miva_pcre2_fill_named_groups(groups, string, ovector, name_table, namecount, name_entry_size);
    }
  }

  if (find_all) {
    PCRE2_SIZE ovector_last[2];

    ovector_last[0] = ovector[0];
    ovector_last[1] = ovector[1];

    for (;;) {
      PCRE2_SIZE start_offset;
      uint32_t match_options;
      mvVariable match_captures;

      if (!pcre2_next_match(match_data, &start_offset, &match_options)) {
        break;
      }

      rc = pcre2_match(
        re,
        string,
        (PCRE2_SIZE)string_length,
        start_offset,
        match_options,
        match_data,
        NULL
      );

      if (rc == PCRE2_ERROR_NOMATCH) {
        break;
      }

      if (rc < 0) {
        miva_pcre2_set_last_error_pcre(rc);
        pcre2_match_data_free(match_data);
        pcre2_code_free(re);
        mvVariable_SetValue_Integer(returnvalue, 0);
        return;
      }

      if (!(ovector[1] > ovector_last[1] ||
            (ovector[1] == ovector[0] && ovector_last[1] > ovector_last[0] &&
             ovector[1] == ovector_last[1]))) {
        miva_pcre2_set_last_error_msg("Match loop failed to advance");
        pcre2_match_data_free(match_data);
        pcre2_code_free(re);
        mvVariable_SetValue_Integer(returnvalue, 0);
        return;
      }

      ovector_last[0] = ovector[0];
      ovector_last[1] = ovector[1];

      if (ovector[0] > ovector[1]) {
        miva_pcre2_set_last_error_msg("\\K was used in an assertion to set the match start after its end.");
        pcre2_match_data_free(match_data);
        pcre2_code_free(re);
        mvVariable_SetValue_Integer(returnvalue, 0);
        return;
      }

      match_index++;
      match_captures = mvVariable_Array_Element(match_index, matches, 1);
      miva_pcre2_fill_captures(match_captures, string, ovector, rc);
    }
  }

  pcre2_match_data_free(match_data);
  pcre2_code_free(re);
  mvVariable_SetValue_Integer(returnvalue, first_match_offset);
}

void miva_pcre2_last_error(mvProgram program, mvVariableHash parameters, mvVariable returnvalue, void **unknown) {
  mvVariable_SetValue(returnvalue, last_error, last_error_length);
}

/**
* Hook the functions into Miva
*/
EXPORT MV_EL_Function_List *miva_function_table() {
  static MV_EL_Function exported_functions[] = {
    { "pcre2_regexp", 12, 4, miva_pcre2_regexp_parameters, miva_pcre2_regexp },
    { "pcre2_last_error", 16, 0, miva_pcre2_last_error_parameters, miva_pcre2_last_error },
    { 0, 0, 0, 0, 0 },
  };

  static MV_EL_Function_List list = { MV_EL_FUNCTION_VERSION, exported_functions };

  return &list;
}

#ifdef __cplusplus
}
#endif

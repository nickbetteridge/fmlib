Release 0.5.4
================================================================================


- `Fmlib_browser`:

    - Added `debug` functions
    - Fix: Set `value` property and not `value` attribute. Reason: The browser
      updates only the property and not the attribute.
    - Added `sandbox_plus` (a sandbox with subscriptions) and
      `basic_application`(an application without javascript communication).
    - Added namespace elements and `svg` elements.
    - Added `Subscription.on_keyup`.
    - Added `Command.map`.
    - Added `Command.just_do` which does not send a message back to the
      application.
    - Added examples from the 7 Guis.



Release 0.5.3
============================================================

- First release of `Fmlib_browser`


Release 0.5.2
============================================================

- Stream module is deprecated in ocaml stdlib. Therefore all usages of the
  Stream module are removed from `Fmlib`.

- `Fmlib_parse`:

    - Some fixes in error reporting
    - Fix: Error in `<?>` operator with layout parsing


Release 0.5.1
============================================================



## `Fmlib_parse`

- Rework of lookahead access. Main function now `fold_lookahead`.

- Added interfaces `MINIMAL_PARSER`, `NORMAL_PARSER`, `FULL_PARSER`, `LEXER`.

- Added `Token_parser` and `Parse_with_lex` to support the separation of parsing
  and lexing.



Release 0.5.0
============================================================

## `Fmlib_std`

- Performance improvement 'Array.replace'

## `Fmlib_pretty`

- Added function 'write_to_channel'

## `Fmlib_parse`

- Changed signature of repetition combinators (e.g. 'one_or_more' and
  'zero_or_more').

- Added a generic parsing combinator for parsing of operator expressions.

- Complete rework of layout parsing.

- Added functions to pretty print error messages and code snippets containing an
  error.

- Documentation for parsing improved and augmented significantly.

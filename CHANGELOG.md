## async.fnl v0.0.3 (2022-07-01)

- Change from single-file library to a multi-module with `init.fnl` and `init-macros.fnl`.
  The library now can be required via `(require :async)` and `(require-macros :async)` where `async` is the name of the directory of the library.
- Add `take-all` function.
- Add TCP REPL support for remote code evaluation.

## async.fnl v0.0.2 (2022-06-13)

- Add basic "non-blocking" disk IO module.
- Add (experimental) asynchronous TCP module.

## async.fnl v0.0.1 (2022-01-09)

Initial release of the async.fnl library.

<!--  LocalWords:  destructuring metamethod multi
 -->

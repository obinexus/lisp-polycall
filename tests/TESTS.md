# Common Lisp tests

`npm test` runs the native forwarding test, source audit, ASDF metadata check,
and npm package test. `npm run test:lisp` additionally loads the ASDF test
system through SBCL and calls the mock shared library through CFFI.

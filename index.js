'use strict';

// Build-tool entry point for the npm distribution of lisp-polycall: absolute
// paths of the packaged ASDF system and sources. The binding itself is
// Common Lisp (CFFI onto libpolycall), loaded through ASDF.

const path = require('node:path');

const fromPackageRoot = (...parts) => path.join(__dirname, ...parts);

module.exports = Object.freeze({
  packageName: '@obinexusltd/lisp-polycall',
  asdfSystem: fromPackageRoot('lisp-polycall.asd'),
  packageSource: fromPackageRoot('src', 'package.lisp'),
  lispSource: fromPackageRoot('src', 'lisp-polycall.lisp'),
  tests: fromPackageRoot('tests', 'real-core.lisp'),
  config: fromPackageRoot('lisp-polycallrc'),
  manifest: fromPackageRoot('polycall-binding.json'),
  makefile: fromPackageRoot('Makefile')
});

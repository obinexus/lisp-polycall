'use strict';

const path = require('node:path');

const fromPackageRoot = (...parts) => path.join(__dirname, ...parts);

module.exports = Object.freeze({
  packageName: '@obinexusltd/lisp-polycall',
  asdfSystem: fromPackageRoot('lisp-polycall.asd'),
  packageSource: fromPackageRoot('src', 'package.lisp'),
  lispSource: fromPackageRoot('src', 'lisp-polycall.lisp'),
  nativeSource: fromPackageRoot('src', 'lisp_polycall.c'),
  windowsExports: fromPackageRoot('src', 'lisp_polycall.def'),
  nativeHeader: fromPackageRoot('include', 'lisp_polycall.h'),
  ffiHeader: fromPackageRoot('generated', 'polycall', 'polycall_ffi.h'),
  config: fromPackageRoot('lisp-polycallrc'),
  manifest: fromPackageRoot('polycall-binding.json'),
  makefile: fromPackageRoot('Makefile')
});

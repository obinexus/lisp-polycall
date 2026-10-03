'use strict';

// Package-metadata test (no Lisp needed): npm, ASDF and binding manifest are
// consistent and every exported path exists. The binding itself is tested
// against the real core by tests/run-real-core.sh.

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const binding = require('..');
const metadata = require('../package.json');
const manifest = require('../polycall-binding.json');

const repo = 'https://github.com/obinexus/lisp-polycall';

assert.equal(metadata.name, 'lisp-polycall');
assert.equal(metadata.license, 'MIT');
assert.equal(metadata.publishConfig.access, 'public');
assert.equal(metadata.repository.url, `git+${repo}.git`);
assert.equal(metadata.bugs.url, `${repo}/issues`);
assert.equal(metadata.homepage, `${repo}#readme`);
assert.equal(manifest.version, metadata.version);
assert.equal(manifest.core, 'polycall >= 1.1.0 (binding ABI 1)');
assert.equal(manifest.core_repository, 'https://github.com/obinexus/polycall');
for (const key of ['config', 'asdf_system']) {
  assert.ok(fs.existsSync(path.join(__dirname, '..', manifest[key])), `manifest ${key} exists`);
}

const author = typeof metadata.author === 'string'
  ? metadata.author
  : `${metadata.author?.name} <${metadata.author?.email}>`;
assert.equal(author, 'Nnamdi Michael Okpala <okpalan@protonmail.com>');

for (const [name, file] of Object.entries(binding)) {
  if (name === 'packageName') continue;
  assert.equal(fs.existsSync(file), true, `missing ${name}: ${file}`);
}

const asdf = fs.readFileSync(binding.asdfSystem, 'utf8');
assert.match(asdf, /asdf:defsystem "lisp-polycall"/);
assert.match(asdf, /:depends-on \("cffi" "babel" "uiop"\)/);
assert.match(asdf, new RegExp(`:version "${metadata.version}"`));
assert.match(asdf, new RegExp(`:homepage "${repo}"`));

const lisp = fs.readFileSync(binding.lispSource, 'utf8');
assert.match(lisp, /\(%run-config config-path \(if strict 1 0\)\)/);
assert.match(lisp, /"polycall_ffi_abi_version"/);
assert.doesNotMatch(lisp, /lisp_polycall_run_config/, 'no C shim: CFFI calls libpolycall directly');

console.log('lisp-polycall package metadata test: PASS');

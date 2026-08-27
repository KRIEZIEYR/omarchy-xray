#!/usr/bin/env node
/*
 * Runs model tests without a QML engine: loads model/V2rayA.js as a plain
 * script (the .pragma library line is stripped), then evaluates the test
 * suite against it.
 */
'use strict'

const fs = require('fs')
const path = require('path')
const vm = require('vm')

const root = path.resolve(__dirname, '..')

function loadModel() {
  let src = fs.readFileSync(path.join(root, 'model', 'V2rayA.js'), 'utf8')
  src = src.replace(/^\.pragma library\s*/m, '')
  const api = ['shellQuote', 'curlScript', 'parseResponse', 'whichKey', 'serverKey',
    'whichFor', 'toNode', 'parseTouch', 'applyLatencies', 'mergeLatencies',
    'latencyLabel', 'latencyGood', 'latencyBad', 'buildLatencyQuery',
    'filterNodes', 'findNodeByKey', 'pickConnectTarget', 'heroLine', 'formatSpeed', 'formatBytes'].join(', ')
  const sandbox = { module: { exports: {} }, exports: {}, JSON, encodeURIComponent }
  vm.createContext(sandbox)
  vm.runInContext(src + '\nmodule.exports = { ' + api + ' }', sandbox, { filename: 'V2rayA.js' })
  return sandbox.module.exports
}

const V2rayA = loadModel()
let passed = 0
let failed = 0

function assert(name, cond) {
  if (cond) { passed++ } else { failed++; console.error('FAIL: ' + name) }
}

function eq(name, actual, expected) {
  const a = JSON.stringify(actual)
  const e = JSON.stringify(expected)
  if (a === e) { passed++ } else { failed++; console.error('FAIL: ' + name + '\n  expected: ' + e + '\n  actual:   ' + a) }
}

require(path.join(__dirname, 'model', 'v2raya.test.js'))({ V2rayA, assert, eq })

console.log(passed + ' passed, ' + failed + ' failed')
process.exit(failed > 0 ? 1 : 0)

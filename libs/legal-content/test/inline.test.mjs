import { test } from 'node:test'
import assert from 'node:assert/strict'
import { parseInline } from '../src/inline.mjs'

test('plain text is one text token', () => {
  assert.deepEqual(parseInline('hello world'), [{ type: 'text', text: 'hello world' }])
})

test('bold in the middle splits into three tokens', () => {
  assert.deepEqual(parseInline('a **b** c'), [
    { type: 'text', text: 'a ' },
    { type: 'bold', text: 'b' },
    { type: 'text', text: ' c' },
  ])
})

test('a link keeps its label and url', () => {
  assert.deepEqual(parseInline('see [the policy](privacy.html) now'), [
    { type: 'text', text: 'see ' },
    { type: 'link', text: 'the policy', url: 'privacy.html' },
    { type: 'text', text: ' now' },
  ])
})

test('bold and link coexist', () => {
  assert.deepEqual(parseInline('**Note:** mail [us](mailto:a@b.c)'), [
    { type: 'bold', text: 'Note:' },
    { type: 'text', text: ' mail ' },
    { type: 'link', text: 'us', url: 'mailto:a@b.c' },
  ])
})

test('an unmatched asterisk pair stays literal', () => {
  assert.deepEqual(parseInline('2 ** 3'), [{ type: 'text', text: '2 ** 3' }])
})

test('empty string yields no tokens', () => {
  assert.deepEqual(parseInline(''), [])
})

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { utf8Decode, utf8Encode } from '../.gen/protocol/Utf8';

test('utf8 round-trips ascii, CJK and emoji', () => {
  for (const s of ['', 'abc', '测试 图片(1).png', 'emoji 😀.jpg']) assert.equal(utf8Decode(utf8Encode(s)), s);
});
test('utf8 encodes CJK as 3 bytes and emoji as 4', () => {
  assert.deepEqual(Array.from(utf8Encode('测')), [0xE6, 0xB5, 0x8B]);
  assert.deepEqual(Array.from(utf8Encode('😀')), [0xF0, 0x9F, 0x98, 0x80]);
  assert.equal(utf8Decode(new Uint8Array([0xF0, 0x9F, 0x98, 0x80])), '😀');
});

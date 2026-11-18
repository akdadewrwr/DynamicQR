import { test } from 'node:test';
import assert from 'node:assert/strict';
import { crc16, crc32 } from '../.gen/protocol/Crc';
import { utf8Encode } from '../.gen/protocol/Utf8';

test('crc32 IEEE check value', () => {
  const t = utf8Encode('123456789');
  assert.equal(crc32(t, 0, t.length), 0xCBF43926);
});
test('crc16 CCITT-FALSE check value', () => {
  const t = utf8Encode('123456789');
  assert.equal(crc16(t, 0, t.length), 0x29B1);
});
test('crc32 respects the range', () => {
  const t = utf8Encode('123456789');
  const s = utf8Encode('23');
  assert.equal(crc32(t, 1, 3), crc32(s, 0, 2));
});

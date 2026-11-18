import { test } from 'node:test';
import assert from 'node:assert/strict';
import { base45Decode, base45Encode } from '../.gen/protocol/Base45';
import { utf8Decode, utf8Encode } from '../.gen/protocol/Utf8';
import { randomBytes } from './helpers/random';

test('base45 encodes RFC 9285 examples', () => {
  assert.equal(base45Encode(utf8Encode('AB')), 'BB8');
  assert.equal(base45Encode(utf8Encode('Hello!!')), '%69 VD92EX0');
  assert.equal(base45Encode(utf8Encode('base-45')), 'UJCLQE7W581');
});

test('base45 decodes RFC 9285 example', () => {
  const d = base45Decode('QED8WEX0');
  assert.ok(d !== null);
  assert.equal(utf8Decode(d), 'ietf!');
});

test('base45 round-trips all byte values including odd tails', () => {
  for (const n of [0, 1, 2, 3, 20, 1001]) {
    const b = randomBytes(n);
    assert.deepEqual(base45Decode(base45Encode(b)), b);
  }
  const all = new Uint8Array(256); for (let i = 0; i < 256; i++) all[i] = i;
  assert.deepEqual(base45Decode(base45Encode(all)), all);
});

test('base45 rejects invalid input', () => {
  assert.equal(base45Decode('GGW'), null);       // 65536 overflow
  assert.equal(base45Decode('A'), null);         // length % 3 == 1
  assert.equal(base45Decode('https://x'), null); // not in alphabet
  assert.equal(base45Decode('U8'), null);        // pair value 30+8*45=390 > 255
});

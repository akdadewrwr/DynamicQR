import { test } from 'node:test';
import assert from 'node:assert/strict';
import { ReceiverSession, SessionState } from '../.gen/protocol/ReceiverSession';
import { BundleFile, packBundle } from '../.gen/protocol/Bundle';
import { TestEncoder } from './helpers/TestEncoder';
import { randomBytes } from './helpers/random';

function bf(name: string, data: Uint8Array): BundleFile { const f = new BundleFile(); f.name = name; f.data = data; return f; }
function clock(): { now: () => number; t: number } { const c = { t: 1000, now: () => c.t }; return c; }

test('session completes and exposes files and timing', () => {
  const files = [bf('a.jpg', randomBytes(5000)), bf('b.jpg', randomBytes(7000))];
  const bundle = packBundle(files);
  const enc = new TestEncoder(bundle, 500, 77);
  const c = clock();
  const s = new ReceiverSession(c.now);
  let id = 3;
  while (s.state() !== SessionState.COMPLETE) { c.t += 100; s.onScan(enc.frame(id)); id += 2; assert.ok(id < 2000); }
  assert.deepEqual(s.files(), files);
  const p = s.progress();
  assert.equal(p.transferId, 77); assert.equal(p.k, enc.k); assert.equal(p.resolved, enc.k);
  assert.equal(p.bundleLen, bundle.length);
  assert.equal(p.elapsedMs, c.t - 1100);
  assert.equal(p.scans, p.uniqueFrames);
});

test('foreign QR codes are ignored', () => {
  const s = new ReceiverSession(() => 0);
  const foreign = ['HTTPS://X', '', 'WIFI:S:x;;', 'hello'];
  for (const t of foreign) assert.equal(s.onScan(t), false);
  assert.equal(s.state(), SessionState.IDLE);
  assert.equal(s.progress().scans, 4);
  assert.equal(s.progress().uniqueFrames, 0);
});

test('duplicate frames are counted as scans but not accepted', () => {
  const enc = new TestEncoder(packBundle([bf('a.jpg', randomBytes(3000))]), 500, 1);
  const s = new ReceiverSession(() => 0);
  assert.equal(s.onScan(enc.frame(0)), true);
  assert.equal(s.onScan(enc.frame(0)), false);
  assert.equal(s.progress().scans, 2);
  assert.equal(s.progress().uniqueFrames, 1);
  assert.equal(s.state(), SessionState.RECEIVING);
});

test('a restarted sender (new transferId) replaces the old transfer', () => {
  const a = new TestEncoder(packBundle([bf('a.jpg', randomBytes(20000))]), 500, 111);
  const filesB = [bf('b.jpg', randomBytes(9000))];
  const b = new TestEncoder(packBundle(filesB), 500, 222);
  const s = new ReceiverSession(() => 0);
  for (let i = 0; i < Math.floor(a.k * 0.6); i++) s.onScan(a.frame(i));
  let id = 0;
  while (s.state() !== SessionState.COMPLETE) { s.onScan(b.frame(id++)); assert.ok(id < 1000); }
  assert.equal(s.progress().transferId, 222);
  assert.deepEqual(s.files(), filesB);
});

test('bundle CRC mismatch fails without exposing files, then restarts', () => {
  const enc = new TestEncoder(packBundle([bf('a.jpg', randomBytes(3000))]), 500, 5, 0x12345678);
  const s = new ReceiverSession(() => 0);
  for (let i = 0; i < enc.k; i++) s.onScan(enc.frame(i));
  assert.equal(s.state(), SessionState.FAILED);
  assert.deepEqual(s.files(), []);
  assert.ok(s.error().length > 0);
  s.onScan(enc.frame(0));
  assert.equal(s.state(), SessionState.RECEIVING);
});

test('the failure message stays visible after the automatic restart until reset or success', () => {
  const bad = new TestEncoder(packBundle([bf('a.jpg', randomBytes(3000))]), 500, 5, 0x12345678);
  const s = new ReceiverSession(() => 0);
  for (let i = 0; i < bad.k; i++) s.onScan(bad.frame(i));
  const message = s.error();
  assert.ok(message.length > 0);
  for (let i = 0; i < 3; i++) s.onScan(bad.frame(100 + i));   // scanning continues after the failure
  assert.equal(s.state(), SessionState.RECEIVING);
  assert.equal(s.error(), message);
  s.reset();
  assert.equal(s.error(), '');

  const files = [bf('ok.jpg', randomBytes(2000))];
  const good = new TestEncoder(packBundle(files), 500, 6);
  for (let i = 0; i < bad.k; i++) s.onScan(bad.frame(i));
  assert.ok(s.error().length > 0);
  for (let i = 0; s.state() !== SessionState.COMPLETE; i++) s.onScan(good.frame(i));
  assert.equal(s.error(), '');
});

test('K = 1 completes after a single frame', () => {
  const files = [bf('tiny.jpg', randomBytes(20))];
  const enc = new TestEncoder(packBundle(files), 800, 9);
  assert.equal(enc.k, 1);
  const s = new ReceiverSession(() => 0);
  s.onScan(enc.frame(12345));
  assert.equal(s.state(), SessionState.COMPLETE);
  assert.deepEqual(s.files(), files);
});

test('reset returns to idle', () => {
  const enc = new TestEncoder(packBundle([bf('a.jpg', randomBytes(3000))]), 500, 1);
  const s = new ReceiverSession(() => 0);
  s.onScan(enc.frame(0));
  s.reset();
  assert.equal(s.state(), SessionState.IDLE);
  assert.equal(s.progress().uniqueFrames, 0);
  assert.equal(s.progress().scans, 0);
});

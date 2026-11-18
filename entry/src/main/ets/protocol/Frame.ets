// Wire frame (spec §5.4): 21-byte little-endian header, payload, CRC-16 trailer; carried as Base45 text.
import { base45Decode, base45Encode } from './Base45';
import { crc16 } from './Crc';

export const FRAME_HEADER_LEN: number = 21;
export const FRAME_OVERHEAD: number = 23;
export const FRAME_VERSION: number = 1;

export class Frame {
  version: number = FRAME_VERSION;
  transferId: number = 0;
  bundleLen: number = 0;
  blockSize: number = 0;
  bundleCrc32: number = 0;
  blockId: number = 0;
  degree: number = 0;
  payload: Uint8Array = new Uint8Array(0);
}

function readU16(b: Uint8Array, o: number): number {
  return b[o] | (b[o + 1] << 8);
}

function readU32(b: Uint8Array, o: number): number {
  return (b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24)) >>> 0;
}

function writeU16(b: Uint8Array, o: number, v: number): void {
  b[o] = v & 0xff;
  b[o + 1] = (v >>> 8) & 0xff;
}

function writeU32(b: Uint8Array, o: number, v: number): void {
  b[o] = v & 0xff;
  b[o + 1] = (v >>> 8) & 0xff;
  b[o + 2] = (v >>> 16) & 0xff;
  b[o + 3] = (v >>> 24) & 0xff;
}

export function encodeFrame(f: Frame): string {
  const n = FRAME_HEADER_LEN + f.payload.length;
  const b = new Uint8Array(n + 2);
  b[0] = f.version;
  writeU32(b, 1, f.transferId);
  writeU32(b, 5, f.bundleLen);
  writeU16(b, 9, f.blockSize);
  writeU32(b, 11, f.bundleCrc32);
  writeU32(b, 15, f.blockId);
  writeU16(b, 19, f.degree);
  b.set(f.payload, FRAME_HEADER_LEN);
  writeU16(b, n, crc16(b, 0, n));
  return base45Encode(b);
}

// Returns null for anything that is not a valid frame of this protocol.
export function parseFrame(text: string): Frame | null {
  const b = base45Decode(text);
  if (b === null || b.length < FRAME_OVERHEAD + 1) {
    return null;
  }
  const blockSize = readU16(b, 9);
  if (blockSize < 1 || b.length !== FRAME_OVERHEAD + blockSize || b[0] !== FRAME_VERSION) {
    return null;
  }
  const n = FRAME_HEADER_LEN + blockSize;
  if (crc16(b, 0, n) !== readU16(b, n)) {
    return null;
  }
  const f = new Frame();
  f.version = b[0];
  f.transferId = readU32(b, 1);
  f.bundleLen = readU32(b, 5);
  f.blockSize = blockSize;
  f.bundleCrc32 = readU32(b, 11);
  f.blockId = readU32(b, 15);
  f.degree = readU16(b, 19);
  if (f.bundleLen < 1) {
    return null;
  }
  const k = Math.ceil(f.bundleLen / blockSize);
  if (f.degree < 1 || f.degree > k || (f.blockId < k && f.degree !== 1)) {
    return null;
  }
  f.payload = b.slice(FRAME_HEADER_LEN, n);
  return f;
}

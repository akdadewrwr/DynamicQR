// Deterministic test randomness (xorshift32) so failures are reproducible.
export class TestRng {
  s: number;
  constructor(seed: number) { this.s = (seed | 0) || 1; }
  next(): number { let x = this.s; x ^= x << 13; x ^= x >>> 17; x ^= x << 5; this.s = x; return x >>> 0; }
  float(): number { return this.next() / 4294967296; }
  bytes(n: number): Uint8Array { const b = new Uint8Array(n); for (let i = 0; i < n; i++) b[i] = this.next() & 0xff; return b; }
}
export function randomBytes(n: number, seed = 12345): Uint8Array { return new TestRng(seed + n).bytes(n); }

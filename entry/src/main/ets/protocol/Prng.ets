// Deterministic 32-bit PRNG shared bit-for-bit with the PC sender (tools/pc-sender/src/Protocol.cs).

export function mix32(a: number, b: number): number {
  let h = (a ^ Math.imul((b + 0x9E3779B9) | 0, 0x85EBCA6B)) | 0;
  h ^= h >>> 16;
  h = Math.imul(h, 0x85EBCA6B);
  h ^= h >>> 13;
  h = Math.imul(h, 0xC2B2AE35);
  h ^= h >>> 16;
  return h >>> 0;
}

export class Mulberry32 {
  private s: number;

  constructor(seed: number) {
    this.s = seed | 0;
  }

  next(): number {
    this.s = (this.s + 0x6D2B79F5) | 0;
    let t = Math.imul(this.s ^ (this.s >>> 15), 1 | this.s);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return (t ^ (t >>> 14)) >>> 0;
  }
}

// Source-block indices combined into block `blockId`. Blocks below k are systematic (the source block itself).
export function ltNeighbors(transferId: number, blockId: number, degree: number, k: number): number[] {
  if (blockId < k) {
    return [blockId];
  }
  const rng = new Mulberry32(mix32(transferId, blockId));
  const out: number[] = [];
  while (out.length < degree) {
    const i = rng.next() % k;
    if (out.indexOf(i) < 0) {
      out.push(i);
    }
  }
  return out;
}

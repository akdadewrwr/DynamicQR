// Reference LT encoder for tests: mirrors the PC sender's frame production.
import { encodeFrame, Frame } from '../../.gen/protocol/Frame';
import { crc32 } from '../../.gen/protocol/Crc';
import { ltNeighbors, mix32, Mulberry32 } from '../../.gen/protocol/Prng';

function robustSolitonCdf(k: number): number[] {
  if (k === 1) return [0, 1];
  const c = 0.1, delta = 0.5;
  const R = c * Math.log(k / delta) * Math.sqrt(k);
  const pivot = Math.min(k, Math.max(1, Math.floor(k / R)));
  const mu: number[] = new Array(k + 1).fill(0);
  for (let d = 1; d <= k; d++) {
    const rho = d === 1 ? 1 / k : 1 / (d * (d - 1));
    let tau = 0;
    if (d < pivot) tau = R / (d * k);
    else if (d === pivot) tau = (R * Math.log(R / delta)) / k;
    mu[d] = rho + Math.max(0, tau);
  }
  const z = mu.reduce((a, b) => a + b, 0);
  const cdf: number[] = [0];
  let acc = 0;
  for (let d = 1; d <= k; d++) { acc += mu[d] / z; cdf.push(acc); }
  cdf[k] = 1;
  return cdf;
}

export class TestEncoder {
  readonly k: number;
  readonly blocks: Uint8Array[] = [];
  private cdf: number[];
  readonly bundle: Uint8Array;
  readonly blockSize: number;
  readonly transferId: number;
  readonly crcOverride: number | undefined;
  constructor(bundle: Uint8Array, blockSize: number, transferId: number, crcOverride?: number) {
    this.bundle = bundle; this.blockSize = blockSize; this.transferId = transferId; this.crcOverride = crcOverride;
    this.k = Math.ceil(bundle.length / blockSize);
    for (let i = 0; i < this.k; i++) {
      const b = new Uint8Array(blockSize);
      b.set(bundle.subarray(i * blockSize, Math.min(bundle.length, (i + 1) * blockSize)));
      this.blocks.push(b);
    }
    this.cdf = robustSolitonCdf(this.k);
  }
  degree(blockId: number): number {
    if (blockId < this.k) return 1;
    const r = new Mulberry32((mix32(this.transferId, blockId) ^ 0xA5A5A5A5) >>> 0).next() / 4294967296;
    let d = 1;
    while (d < this.k && this.cdf[d] <= r) d++;
    return d;
  }
  frame(blockId: number): string {
    const degree = this.degree(blockId);
    const data = new Uint8Array(this.blockSize);
    for (const i of ltNeighbors(this.transferId, blockId, degree, this.k)) {
      const s = this.blocks[i];
      for (let j = 0; j < this.blockSize; j++) data[j] ^= s[j];
    }
    const f = new Frame();
    f.transferId = this.transferId; f.bundleLen = this.bundle.length; f.blockSize = this.blockSize;
    f.bundleCrc32 = this.crcOverride ?? crc32(this.bundle, 0, this.bundle.length);
    f.blockId = blockId; f.degree = degree; f.payload = data;
    return encodeFrame(f);
  }
}

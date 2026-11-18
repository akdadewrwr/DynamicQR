// LT fountain-code peeling (belief-propagation) decoder.

class PendingBlock {
  data: Uint8Array;
  remaining: Set<number>;
  done: boolean = false;

  constructor(data: Uint8Array, remaining: Set<number>) {
    this.data = data;
    this.remaining = remaining;
  }
}

class Resolution {
  index: number;
  data: Uint8Array;

  constructor(index: number, data: Uint8Array) {
    this.index = index;
    this.data = data;
  }
}

function xorInto(target: Uint8Array, src: Uint8Array): void {
  for (let i = 0; i < target.length; i++) {
    target[i] ^= src[i];
  }
}

export class LtDecoder {
  private k: number;
  private blockSize: number;
  private sources: Array<Uint8Array | null> = [];
  private resolved: number = 0;
  private pendingBySource: Map<number, PendingBlock[]> = new Map<number, PendingBlock[]>();

  constructor(k: number, blockSize: number) {
    this.k = k;
    this.blockSize = blockSize;
    for (let i = 0; i < k; i++) {
      this.sources.push(null);
    }
  }

  addBlock(neighbors: number[], data: Uint8Array): void {
    if (this.isComplete()) {
      return;
    }
    const copy = new Uint8Array(this.blockSize);
    copy.set(data.subarray(0, this.blockSize));
    const remaining = new Set<number>();
    for (let i = 0; i < neighbors.length; i++) {
      const idx = neighbors[i];
      const known = this.sources[idx];
      if (known !== null) {
        xorInto(copy, known);
      } else {
        remaining.add(idx);
      }
    }
    if (remaining.size === 0) {
      return;
    }
    if (remaining.size === 1) {
      this.cascade(new Resolution(Array.from(remaining)[0], copy));
      return;
    }
    const pending = new PendingBlock(copy, remaining);
    remaining.forEach((idx: number) => {
      const list = this.pendingBySource.get(idx);
      if (list === undefined) {
        this.pendingBySource.set(idx, [pending]);
      } else {
        list.push(pending);
      }
    });
  }

  private cascade(first: Resolution): void {
    const queue: Resolution[] = [first];
    while (queue.length > 0) {
      const r = queue.pop() as Resolution;
      if (this.sources[r.index] !== null) {
        continue;
      }
      this.sources[r.index] = r.data;
      this.resolved++;
      const list = this.pendingBySource.get(r.index);
      if (list === undefined) {
        continue;
      }
      this.pendingBySource.delete(r.index);
      for (let i = 0; i < list.length; i++) {
        const p = list[i];
        if (p.done) {
          continue;
        }
        xorInto(p.data, r.data);
        p.remaining.delete(r.index);
        if (p.remaining.size <= 1) {
          p.done = true;
          if (p.remaining.size === 1) {
            queue.push(new Resolution(Array.from(p.remaining)[0], p.data));
          }
        }
      }
    }
  }

  resolvedCount(): number {
    return this.resolved;
  }

  isComplete(): boolean {
    return this.resolved === this.k;
  }

  // Concatenated source blocks truncated to totalLen. Only valid once complete.
  assemble(totalLen: number): Uint8Array {
    const out = new Uint8Array(totalLen);
    for (let i = 0; i < this.k; i++) {
      const s = this.sources[i];
      if (s === null) {
        throw new Error('LtDecoder.assemble called before completion');
      }
      const start = i * this.blockSize;
      out.set(s.subarray(0, Math.min(this.blockSize, totalLen - start)), start);
    }
    return out;
  }
}

// Receiver state machine: feeds scanned QR text into the LT decoder and verifies the result.
import { BundleFile, unpackBundle } from './Bundle';
import { crc32 } from './Crc';
import { Frame, parseFrame } from './Frame';
import { LtDecoder } from './LtDecoder';
import { ltNeighbors } from './Prng';

export class SessionState {
  static readonly IDLE: number = 0;
  static readonly RECEIVING: number = 1;
  static readonly COMPLETE: number = 2;
  static readonly FAILED: number = 3;
}

export class SessionProgress {
  transferId: number = 0;
  k: number = 0;
  resolved: number = 0;
  uniqueFrames: number = 0;
  scans: number = 0;
  bundleLen: number = 0;
  blockSize: number = 0;
  elapsedMs: number = 0;
}

export class ReceiverSession {
  private now: () => number;
  private st: number = SessionState.IDLE;
  private decoder: LtDecoder | null = null;
  private transferId: number = 0;
  private bundleLen: number = 0;
  private blockSize: number = 0;
  private bundleCrc32: number = 0;
  private k: number = 0;
  private seen: Set<number> = new Set<number>();
  private scans: number = 0;
  private unique: number = 0;
  private startMs: number = 0;
  private endMs: number = 0;
  private err: string = '';
  private result: BundleFile[] = [];

  constructor(now: () => number) {
    this.now = now;
  }

  // Returns true only when the text was a new, accepted block of the current transfer.
  onScan(text: string): boolean {
    this.scans++;
    if (this.st === SessionState.FAILED) {
      this.clearTransfer();
    }
    const f = parseFrame(text);
    if (f === null || this.st === SessionState.COMPLETE) {
      return false;
    }
    if (this.decoder === null || !this.sameTransfer(f)) {
      this.startTransfer(f);
    }
    if (this.seen.has(f.blockId)) {
      return false;
    }
    this.seen.add(f.blockId);
    this.unique++;
    const decoder = this.decoder as LtDecoder;
    decoder.addBlock(ltNeighbors(f.transferId, f.blockId, f.degree, this.k), f.payload);
    if (decoder.isComplete()) {
      this.finish(decoder);
    }
    return true;
  }

  state(): number {
    return this.st;
  }

  progress(): SessionProgress {
    const p = new SessionProgress();
    p.transferId = this.transferId;
    p.k = this.k;
    p.resolved = this.decoder === null ? 0 : this.decoder.resolvedCount();
    p.uniqueFrames = this.unique;
    p.scans = this.scans;
    p.bundleLen = this.bundleLen;
    p.blockSize = this.blockSize;
    if (this.st === SessionState.RECEIVING) {
      p.elapsedMs = this.now() - this.startMs;
    } else if (this.st === SessionState.COMPLETE || this.st === SessionState.FAILED) {
      p.elapsedMs = this.endMs - this.startMs;
    }
    return p;
  }

  // Verified files; empty unless the session is COMPLETE.
  files(): BundleFile[] {
    return this.st === SessionState.COMPLETE ? this.result : [];
  }

  error(): string {
    return this.err;
  }

  reset(): void {
    this.clearTransfer();
    this.scans = 0;
  }

  private sameTransfer(f: Frame): boolean {
    return f.transferId === this.transferId && f.bundleLen === this.bundleLen &&
      f.blockSize === this.blockSize && f.bundleCrc32 === this.bundleCrc32;
  }

  private startTransfer(f: Frame): void {
    this.clearTransfer();
    this.transferId = f.transferId;
    this.bundleLen = f.bundleLen;
    this.blockSize = f.blockSize;
    this.bundleCrc32 = f.bundleCrc32;
    this.k = Math.ceil(f.bundleLen / f.blockSize);
    this.decoder = new LtDecoder(this.k, f.blockSize);
    this.startMs = this.now();
    this.st = SessionState.RECEIVING;
  }

  private finish(decoder: LtDecoder): void {
    this.endMs = this.now();
    const bundle = decoder.assemble(this.bundleLen);
    if (crc32(bundle, 0, bundle.length) !== this.bundleCrc32) {
      this.fail('Checksum mismatch: the received data is corrupted. Scanning again.');
      return;
    }
    try {
      this.result = unpackBundle(bundle);
      this.st = SessionState.COMPLETE;
    } catch (e) {
      this.fail('Invalid bundle: ' + (e as Error).message);
    }
  }

  private fail(message: string): void {
    this.err = message;
    this.result = [];
    this.st = SessionState.FAILED;
  }

  private clearTransfer(): void {
    this.st = SessionState.IDLE;
    this.decoder = null;
    this.transferId = 0;
    this.bundleLen = 0;
    this.blockSize = 0;
    this.bundleCrc32 = 0;
    this.k = 0;
    this.seen = new Set<number>();
    this.unique = 0;
    this.startMs = 0;
    this.endMs = 0;
    this.err = '';
    this.result = [];
  }
}

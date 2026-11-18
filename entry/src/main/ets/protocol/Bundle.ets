// Multi-file bundle (spec §5.2): "DQB1", u16 count, then per file u16 nameLen, UTF-8 name, u32 dataLen, data.
import { utf8Decode, utf8Encode } from './Utf8';

export class BundleFile {
  name: string = '';
  data: Uint8Array = new Uint8Array(0);
}

const MAGIC: number[] = [0x44, 0x51, 0x42, 0x31];

export function packBundle(files: BundleFile[]): Uint8Array {
  const names: Uint8Array[] = [];
  let size = 6;
  for (let i = 0; i < files.length; i++) {
    const n = utf8Encode(files[i].name);
    names.push(n);
    size += 6 + n.length + files[i].data.length;
  }
  const out = new Uint8Array(size);
  const view = new DataView(out.buffer);
  out.set(MAGIC, 0);
  view.setUint16(4, files.length, true);
  let o = 6;
  for (let i = 0; i < files.length; i++) {
    view.setUint16(o, names[i].length, true);
    out.set(names[i], o + 2);
    o += 2 + names[i].length;
    view.setUint32(o, files[i].data.length, true);
    out.set(files[i].data, o + 4);
    o += 4 + files[i].data.length;
  }
  return out;
}

// Throws Error on bad magic, truncation or trailing bytes.
export function unpackBundle(bytes: Uint8Array): BundleFile[] {
  if (bytes.length < 6) {
    throw new Error('Bundle too short');
  }
  for (let i = 0; i < 4; i++) {
    if (bytes[i] !== MAGIC[i]) {
      throw new Error('Not a DynamicQr bundle');
    }
  }
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const count = view.getUint16(4, true);
  const files: BundleFile[] = [];
  let o = 6;
  for (let i = 0; i < count; i++) {
    if (o + 2 > bytes.length) {
      throw new Error('Bundle truncated');
    }
    const nameLen = view.getUint16(o, true);
    o += 2;
    if (o + nameLen + 4 > bytes.length) {
      throw new Error('Bundle truncated');
    }
    const name = utf8Decode(bytes.slice(o, o + nameLen));
    o += nameLen;
    const dataLen = view.getUint32(o, true);
    o += 4;
    if (o + dataLen > bytes.length) {
      throw new Error('Bundle truncated');
    }
    const f = new BundleFile();
    f.name = name;
    f.data = bytes.slice(o, o + dataLen);
    o += dataLen;
    files.push(f);
  }
  if (o !== bytes.length) {
    throw new Error('Bundle has trailing bytes');
  }
  return files;
}

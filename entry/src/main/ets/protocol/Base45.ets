// Base45 (RFC 9285). Output uses only QR alphanumeric-mode characters.

const ALPHABET: string = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:';

export function base45Encode(data: Uint8Array): string {
  const out: string[] = [];
  let i = 0;
  for (; i + 1 < data.length; i += 2) {
    let n = data[i] * 256 + data[i + 1];
    const c = n % 45;
    n = (n - c) / 45;
    const d = n % 45;
    const e = (n - d) / 45;
    out.push(ALPHABET.charAt(c), ALPHABET.charAt(d), ALPHABET.charAt(e));
  }
  if (i < data.length) {
    const n = data[i];
    const c = n % 45;
    out.push(ALPHABET.charAt(c), ALPHABET.charAt((n - c) / 45));
  }
  return out.join('');
}

// Returns null on any invalid character, invalid length, or out-of-range group.
export function base45Decode(text: string): Uint8Array | null {
  const len = text.length;
  if (len % 3 === 1) {
    return null;
  }
  const out = new Uint8Array(Math.floor(len / 3) * 2 + (len % 3 === 2 ? 1 : 0));
  let o = 0;
  for (let i = 0; i < len; i += 3) {
    const c = ALPHABET.indexOf(text.charAt(i));
    const d = ALPHABET.indexOf(text.charAt(i + 1));
    if (c < 0 || d < 0) {
      return null;
    }
    if (i + 2 < len) {
      const e = ALPHABET.indexOf(text.charAt(i + 2));
      if (e < 0) {
        return null;
      }
      const n = c + d * 45 + e * 2025;
      if (n > 65535) {
        return null;
      }
      out[o++] = n >> 8;
      out[o++] = n & 0xff;
    } else {
      const n = c + d * 45;
      if (n > 255) {
        return null;
      }
      out[o++] = n;
    }
  }
  return out;
}

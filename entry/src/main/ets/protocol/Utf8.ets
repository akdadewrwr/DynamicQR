// Dependency-free UTF-8 encode/decode (so protocol code runs both on device and under Node).

export function utf8Encode(s: string): Uint8Array {
  const out: number[] = [];
  for (let i = 0; i < s.length; i++) {
    let cp = s.charCodeAt(i);
    if (cp >= 0xD800 && cp <= 0xDBFF && i + 1 < s.length) {
      const lo = s.charCodeAt(i + 1);
      if (lo >= 0xDC00 && lo <= 0xDFFF) {
        cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
        i++;
      }
    }
    if (cp < 0x80) {
      out.push(cp);
    } else if (cp < 0x800) {
      out.push(0xC0 | (cp >> 6), 0x80 | (cp & 0x3F));
    } else if (cp < 0x10000) {
      out.push(0xE0 | (cp >> 12), 0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F));
    } else {
      out.push(0xF0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3F), 0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F));
    }
  }
  return new Uint8Array(out);
}

// Invalid sequences decode to U+FFFD.
export function utf8Decode(b: Uint8Array): string {
  const parts: string[] = [];
  let i = 0;
  while (i < b.length) {
    const x = b[i];
    let cp = 0xFFFD;
    let need = 0;
    if (x < 0x80) {
      cp = x;
    } else if ((x & 0xE0) === 0xC0) {
      cp = x & 0x1F;
      need = 1;
    } else if ((x & 0xF0) === 0xE0) {
      cp = x & 0x0F;
      need = 2;
    } else if ((x & 0xF8) === 0xF0) {
      cp = x & 0x07;
      need = 3;
    }
    i++;
    let ok = true;
    for (let k = 0; k < need; k++) {
      if (i >= b.length || (b[i] & 0xC0) !== 0x80) {
        ok = false;
        break;
      }
      cp = (cp << 6) | (b[i] & 0x3F);
      i++;
    }
    parts.push(String.fromCodePoint(ok ? cp : 0xFFFD));
  }
  return parts.join('');
}

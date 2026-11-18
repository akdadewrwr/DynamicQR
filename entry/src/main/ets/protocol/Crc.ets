// CRC-32/IEEE (zlib) and CRC-16/CCITT-FALSE over data[start, end).

export function crc32(data: Uint8Array, start: number, end: number): number {
  let c = 0xFFFFFFFF;
  for (let i = start; i < end; i++) {
    c ^= data[i];
    for (let k = 0; k < 8; k++) {
      c = (c >>> 1) ^ (0xEDB88320 & -(c & 1));
    }
  }
  return (~c) >>> 0;
}

export function crc16(data: Uint8Array, start: number, end: number): number {
  let c = 0xFFFF;
  for (let i = start; i < end; i++) {
    c ^= data[i] << 8;
    for (let k = 0; k < 8; k++) {
      c = (c & 0x8000) !== 0 ? ((c << 1) ^ 0x1021) & 0xFFFF : (c << 1) & 0xFFFF;
    }
  }
  return c;
}

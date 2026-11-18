// Gallery title for a received file: the name without extension, with every character that
// photoAccessHelper.createAsset rejects (. \ / : * ? " ' ` < > | { } [ ]) replaced by '_'.

const MAX_TITLE_LENGTH: number = 250;

export function galleryTitle(name: string): string {
  const dot = name.lastIndexOf('.');
  const stem = dot >= 0 ? name.substring(0, dot) : name;
  let clean = stem.replace(/[.\\/:*?"'`<>|{}\[\]]/g, '_').trim();
  if (clean.length > MAX_TITLE_LENGTH) {
    clean = clean.substring(0, MAX_TITLE_LENGTH);
  }
  return clean.length > 0 ? clean : 'DynamicQr';
}

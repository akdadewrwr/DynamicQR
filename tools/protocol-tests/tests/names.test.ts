import { test } from 'node:test';
import assert from 'node:assert/strict';
import { galleryTitle } from '../.gen/protocol/Names';

test('gallery title drops the extension', () => {
  assert.equal(galleryTitle('a.jpg'), 'a');
  assert.equal(galleryTitle('测试 图片(1).jpg'), '测试 图片(1)');
});

test('gallery title replaces every character the media library rejects', () => {
  // photoAccessHelper.createAsset: invalid  .. \ / : * ? " ' ` < > | { } [ ]
  assert.equal(galleryTitle('photo[1].jpg'), 'photo_1_');
  assert.equal(galleryTitle("Mum's.jpg"), 'Mum_s');
  assert.equal(galleryTitle('{x}`y`.jpg'), '_x__y_');
  assert.equal(galleryTitle('a:b*c?d"e<f>g|h\\i/j.jpg'), 'a_b_c_d_e_f_g_h_i_j');
  assert.equal(galleryTitle('v1..2.final.jpg'), 'v1__2_final');
});

test('gallery title falls back when nothing usable is left', () => {
  assert.equal(galleryTitle('.jpg'), 'DynamicQr');
  assert.equal(galleryTitle('   .jpg'), 'DynamicQr');
});

test('gallery title is capped so title + extension stays within 255 characters', () => {
  const t = galleryTitle('x'.repeat(400) + '.jpg');
  assert.ok(t.length <= 250, `length ${t.length}`);
});

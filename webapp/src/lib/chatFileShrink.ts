/**
 * チャットに添付するファイルを、アップロードの前に端末で縮める(chatFiles.tsから使う)。
 * ログイン・APIに依存しないので、ここだけをブラウザで単体に動かして確かめられる。
 *
 * 画像は長辺2048pxのJPEGに(透明な部分を残す必要があるものはPNG)。docx・pptxは中の画像を同じように
 * 縮めて、開ける正しいファイルのまま作り直す(2026-10-06の検証で、37枚のスクショのpptxが32MB → 5.4MB、
 * 読み取りの精度は変わらなかった)。作り直すとEXIF(撮影場所など)は消える。
 */

export class ChatFileError extends Error {
  constructor(
    public code: string,
    public detail: Record<string, unknown> = {}
  ) {
    super(code);
    this.name = 'ChatFileError';
  }
}

/** 画像・docx/pptxの中の画像を縮める長辺と、JPEGの画質。 */
const IMAGE_LONG_SIDE = 2048;
const JPEG_QUALITY = 0.85;

// ---------------------------------------------------------------------------
// 画像を縮める
// ---------------------------------------------------------------------------

async function decodeImage(blob: Blob): Promise<ImageBitmap | HTMLImageElement> {
  try {
    // 向き(EXIF)を反映して読む
    return await createImageBitmap(blob, { imageOrientation: 'from-image' });
  } catch {
    // createImageBitmapが読めない形式でも、<img>なら読めることがある(SafariのHEICなど)
    const url = URL.createObjectURL(blob);
    try {
      const img = new Image();
      img.src = url;
      await img.decode();
      return img;
    } catch {
      throw new ChatFileError('IMAGE_DECODE_FAILED');
    } finally {
      URL.revokeObjectURL(url);
    }
  }
}

function canvasToBlob(canvas: HTMLCanvasElement, type: string, quality?: number): Promise<Blob> {
  return new Promise((resolve, reject) => {
    canvas.toBlob((blob) => (blob ? resolve(blob) : reject(new ChatFileError('IMAGE_DECODE_FAILED'))), type, quality);
  });
}

/** 透明な部分があるか(縮めた後の絵で、間引いて調べる)。 */
function hasTransparency(ctx: CanvasRenderingContext2D, width: number, height: number): boolean {
  const data = ctx.getImageData(0, 0, width, height).data;
  const step = Math.max(1, Math.floor((width * height) / 250_000)) * 4;
  for (let i = 3; i < data.length; i += step) {
    if (data[i] < 250) return true;
  }
  return false;
}

/**
 * 画像を長辺IMAGE_LONG_SIDEに縮める。keepTransparencyなら、透明な部分がある画像はPNGのまま
 * (docx・pptxの中のロゴや図をJPEGにすると、透明な部分が白い四角になるため)。それ以外はJPEG
 * (白い背景に描く)。EXIF(撮影場所など)は作り直しで消える。
 */
export async function shrinkImage(blob: Blob, keepTransparency: boolean): Promise<{ blob: Blob; type: 'jpeg' | 'png' }> {
  const source = await decodeImage(blob);
  const w0 = 'naturalWidth' in source ? source.naturalWidth : source.width;
  const h0 = 'naturalHeight' in source ? source.naturalHeight : source.height;
  const scale = Math.min(1, IMAGE_LONG_SIDE / Math.max(w0, h0));
  const width = Math.max(1, Math.round(w0 * scale));
  const height = Math.max(1, Math.round(h0 * scale));
  const canvas = document.createElement('canvas');
  canvas.width = width;
  canvas.height = height;
  const ctx = canvas.getContext('2d', { willReadFrequently: keepTransparency });
  if (!ctx) throw new ChatFileError('IMAGE_DECODE_FAILED');
  ctx.drawImage(source, 0, 0, width, height);
  if ('close' in source) source.close();
  if (keepTransparency && hasTransparency(ctx, width, height)) {
    return { blob: await canvasToBlob(canvas, 'image/png'), type: 'png' };
  }
  // JPEGは透明を黒で塗るので、後ろに白を敷く
  ctx.globalCompositeOperation = 'destination-over';
  ctx.fillStyle = '#ffffff';
  ctx.fillRect(0, 0, width, height);
  return { blob: await canvasToBlob(canvas, 'image/jpeg', JPEG_QUALITY), type: 'jpeg' };
}

// ---------------------------------------------------------------------------
// docx・pptxの中の画像を縮める
// ---------------------------------------------------------------------------

const OFFICE_MEDIA_DIR: Record<'docx' | 'pptx', string> = { docx: 'word/media/', pptx: 'ppt/media/' };
const SHRINKABLE = /\.(png|jpe?g|bmp)$/i;

/**
 * docx・pptxの中の画像を縮めて作り直す(開ける正しいファイルのまま)。PNGをJPEGにしたときは、
 * 参照(.relsのTarget・[Content_Types].xml)も書き換える。小さくならなければ元のファイルを返す。
 */
export async function shrinkOfficeFile(
  file: File,
  kind: 'docx' | 'pptx',
  onProgress?: (ratio: number) => void
): Promise<Blob> {
  // チャットの画面を重くしないよう、docx・pptxを縮めるときに初めて読み込む
  const { default: JSZip } = await import('jszip');
  let zip: InstanceType<typeof JSZip>;
  try {
    zip = await JSZip.loadAsync(file);
  } catch {
    throw new ChatFileError('FILE_CORRUPT');
  }
  const media = Object.keys(zip.files).filter(
    (name) => name.startsWith(OFFICE_MEDIA_DIR[kind]) && SHRINKABLE.test(name) && !zip.files[name].dir
  );
  if (media.length === 0) return file;

  const renames: Array<[string, string]> = [];
  let changed = false;
  for (let i = 0; i < media.length; i++) {
    const name = media[i];
    onProgress?.(i / media.length);
    const original = await zip.files[name].async('blob');
    let shrunk: { blob: Blob; type: 'jpeg' | 'png' };
    try {
      shrunk = await shrinkImage(original, true);
    } catch {
      continue; // 読めない画像はそのまま
    }
    if (shrunk.blob.size >= original.size * 0.9) continue;
    const isPng = /\.png$/i.test(name);
    if (shrunk.type === 'jpeg' && isPng) {
      let next = name.replace(/\.png$/i, '.jpg');
      if (zip.files[next]) next = name.replace(/\.png$/i, '_c.jpg');
      zip.remove(name);
      zip.file(next, shrunk.blob);
      renames.push([name, next]);
    } else if (shrunk.type === 'png' || !isPng) {
      zip.file(name, shrunk.blob);
    }
    changed = true;
  }
  onProgress?.(1);
  if (!changed) return file;

  if (renames.length > 0) {
    const base = (path: string) => path.slice(path.lastIndexOf('/') + 1);
    const relFiles = Object.keys(zip.files).filter((n) => n.endsWith('.rels'));
    for (const rel of relFiles) {
      let xml = await zip.files[rel].async('string');
      let touched = false;
      for (const [from, to] of renames) {
        const needle = `/${base(from)}"`;
        if (xml.includes(needle)) {
          xml = xml.split(needle).join(`/${base(to)}"`);
          touched = true;
        }
      }
      if (touched) zip.file(rel, xml);
    }
    const ctPath = '[Content_Types].xml';
    if (zip.files[ctPath]) {
      let ct = await zip.files[ctPath].async('string');
      for (const [from, to] of renames) {
        ct = ct.replace(
          new RegExp(`(<Override[^>]*PartName="/${from.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}"[^>]*>)`, 'g'),
          (tag) => tag.replace(`/${from}"`, `/${to}"`).replace(/ContentType="[^"]*"/, 'ContentType="image/jpeg"')
        );
      }
      if (!/Extension="jpg"/i.test(ct)) {
        ct = ct.replace('</Types>', '<Default Extension="jpg" ContentType="image/jpeg"/></Types>');
      }
      zip.file(ctPath, ct);
    }
  }
  const out = await zip.generateAsync({ type: 'blob', compression: 'DEFLATE', compressionOptions: { level: 1 } });
  return out.size < file.size ? out : file;
}

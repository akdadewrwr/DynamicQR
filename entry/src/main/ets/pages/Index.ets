// DynamicQr receiver: scans the PC's animated QR code continuously and rebuilds the images.
import { abilityAccessCtrl, common, PermissionRequestResult, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { display, window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { customScan, scanBarcode, scanCore } from '@kit.ScanKit';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { BundleFile } from '../protocol/Bundle';
import { ReceiverSession, SessionProgress, SessionState } from '../protocol/ReceiverSession';

const DOMAIN: number = 0xD0;
const TAG: string = 'DynamicQr';
const CAMERA: Permissions = 'ohos.permission.CAMERA';
const RATE_WINDOW_MS: number = 2000;

function formatClock(ms: number): string {
  const s = Math.floor(ms / 1000);
  const mm = Math.floor(s / 60);
  const ss = s % 60;
  return (mm < 10 ? '0' : '') + mm + ':' + (ss < 10 ? '0' : '') + ss;
}

function formatKb(bytes: number): string {
  return (bytes / 1024).toFixed(bytes < 10240 ? 1 : 0) + ' KB';
}

// Gallery title: file name without extension and without characters the media library rejects.
function galleryTitle(name: string): string {
  const dot = name.lastIndexOf('.');
  const stem = dot > 0 ? name.substring(0, dot) : name;
  const clean = stem.replace(/[\\/:*?"<>|.]/g, '_').trim();
  return clean.length > 0 ? clean : 'DynamicQr';
}

class Thumb {
  name: string;
  pixelMap: image.PixelMap | null;

  constructor(name: string, pixelMap: image.PixelMap | null) {
    this.name = name;
    this.pixelMap = pixelMap;
  }
}

@Entry
@Component
struct Index {
  @State permissionGranted: boolean = false;
  @State permissionDenied: boolean = false;
  @State sessionState: number = SessionState.IDLE;
  @State progress: SessionProgress = new SessionProgress();
  @State scanRate: number = 0;
  @State errorText: string = '';
  @State previewWidth: number = 360;
  @State previewHeight: number = 640;
  @State thumbs: Thumb[] = [];
  @State viewerIndex: number = -1;
  private session: ReceiverSession = new ReceiverSession(() => Date.now());
  private xController: XComponentController = new XComponentController();
  private surfaceId: string = '';
  private scanning: boolean = false;
  private scanTimes: number[] = [];
  private ticker: number = -1;

  aboutToAppear(): void {
    try {
      const d = display.getDefaultDisplaySync();
      this.previewWidth = this.getUIContext().px2vp(d.width);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'display size unavailable, using default preview size');
    }
    this.previewHeight = this.previewWidth * 16 / 9;
    this.keepScreenOn();
    this.requestCamera();
    this.ticker = setInterval(() => this.refresh(), 500);
  }

  aboutToDisappear(): void {
    clearInterval(this.ticker);
    this.stopScan();
  }

  onPageShow(): void {
    this.startScan();
  }

  onPageHide(): void {
    this.stopScan();
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private keepScreenOn(): void {
    window.getLastWindow(this.context()).then((w: window.Window) => {
      return w.setWindowKeepScreenOn(true);
    }).catch((e: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'keep screen on failed: %{public}s', e.message);
    });
  }

  private requestCamera(): void {
    const atManager = abilityAccessCtrl.createAtManager();
    atManager.requestPermissionsFromUser(this.context(), [CAMERA])
      .then((r: PermissionRequestResult) => {
        this.permissionGranted = r.authResults.length > 0 && r.authResults[0] === 0;
        this.permissionDenied = !this.permissionGranted;
        this.startScan();
      })
      .catch((e: BusinessError) => {
        hilog.error(DOMAIN, TAG, 'permission request failed: %{public}s', e.message);
        this.permissionDenied = true;
      });
  }

  private startScan(): void {
    if (this.scanning || !this.permissionGranted || this.surfaceId === '' ||
      this.sessionState === SessionState.COMPLETE) {
      return;
    }
    try {
      const options: scanBarcode.ScanOptions = {
        scanTypes: [scanCore.ScanType.QR_CODE],
        enableMultiMode: false,
        enableAlbum: false
      };
      customScan.init(options);
      const viewControl: customScan.ViewControl = {
        width: this.previewWidth,
        height: this.previewHeight,
        surfaceId: this.surfaceId
      };
      customScan.start(viewControl, (err: BusinessError, results: Array<scanBarcode.ScanResult>) => {
        this.onScanResult(err, results);
      });
      this.scanning = true;
      try {
        customScan.setAutoZoomEnabled(false);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'auto zoom setting not applied');
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'start scan failed: %{public}s', (e as BusinessError).message);
    }
  }

  private stopScan(): void {
    if (!this.scanning) {
      return;
    }
    this.scanning = false;
    customScan.stop()
      .then(() => customScan.release())
      .catch((e: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'stop scan failed: %{public}s', e.message);
      });
  }

  private onScanResult(err: BusinessError, results: Array<scanBarcode.ScanResult>): void {
    if (!this.scanning) {
      return;
    }
    if (err) {
      hilog.warn(DOMAIN, TAG, 'scan error %{public}d: %{public}s', err.code, err.message);
    } else {
      const now = Date.now();
      for (let i = 0; i < results.length; i++) {
        this.scanTimes.push(now);
        this.session.onScan(results[i].originalValue);
      }
      this.refresh();
    }
    if (this.session.state() === SessionState.COMPLETE) {
      this.stopScan();
      return;
    }
    try {
      customScan.rescan();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'rescan failed: %{public}s', (e as BusinessError).message);
    }
  }

  private refresh(): void {
    const now = Date.now();
    while (this.scanTimes.length > 0 && this.scanTimes[0] < now - RATE_WINDOW_MS) {
      this.scanTimes.shift();
    }
    this.scanRate = this.scanTimes.length * 1000 / RATE_WINDOW_MS;
    this.progress = this.session.progress();
    const previous = this.sessionState;
    this.sessionState = this.session.state();
    this.errorText = this.session.error();
    if (previous !== SessionState.COMPLETE && this.sessionState === SessionState.COMPLETE) {
      this.loadThumbs(this.session.files());
    }
  }

  private async loadThumbs(files: BundleFile[]): Promise<void> {
    const result: Thumb[] = [];
    for (let i = 0; i < files.length; i++) {
      let pm: image.PixelMap | null = null;
      try {
        const buf = files[i].data.buffer.slice(files[i].data.byteOffset, files[i].data.byteOffset + files[i].data.byteLength);
        const source = image.createImageSource(buf as ArrayBuffer);
        pm = await source.createPixelMap();
        await source.release();
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'cannot decode %{public}s', files[i].name);
      }
      result.push(new Thumb(files[i].name, pm));
    }
    this.thumbs = result;
  }

  private releaseThumbs(): void {
    for (let i = 0; i < this.thumbs.length; i++) {
      const pm = this.thumbs[i].pixelMap;
      if (pm !== null) {
        pm.release();
      }
    }
    this.thumbs = [];
    this.viewerIndex = -1;
  }

  private async saveAll(): Promise<void> {
    const files = this.session.files();
    const helper = photoAccessHelper.getPhotoAccessHelper(this.context());
    let saved = 0;
    let lastError = '';
    for (let i = 0; i < files.length; i++) {
      try {
        const options: photoAccessHelper.CreateOptions = { title: galleryTitle(files[i].name) };
        const uri = await helper.createAsset(photoAccessHelper.PhotoType.IMAGE, 'jpg', options);
        const file = fileIo.openSync(uri, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
        try {
          const d = files[i].data;
          fileIo.writeSync(file.fd, d.buffer.slice(d.byteOffset, d.byteOffset + d.byteLength) as ArrayBuffer);
        } finally {
          fileIo.closeSync(file);
        }
        saved++;
      } catch (e) {
        lastError = (e as BusinessError).message;
        hilog.error(DOMAIN, TAG, 'save %{public}s failed: %{public}s', files[i].name, lastError);
      }
    }
    const message = lastError === '' ? 'Saved ' + saved + ' images to the gallery' :
      'Saved ' + saved + ' of ' + files.length + ' images. Error: ' + lastError;
    this.toast(message);
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 3000 });
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'toast failed: %{public}s', message);
    }
  }

  private resetSession(): void {
    if (this.sessionState === SessionState.COMPLETE) {
      // The preview XComponent is rebuilt when the results view closes; its onLoad starts scanning.
      this.surfaceId = '';
    }
    this.releaseThumbs();
    this.session.reset();
    this.scanTimes = [];
    this.refresh();
    this.startScan();
  }

  private bytesReceived(): number {
    return Math.min(this.progress.resolved * this.progress.blockSize, this.progress.bundleLen);
  }

  private speedText(): string {
    const s = this.progress.elapsedMs / 1000;
    const kbps = s > 0 ? this.bytesReceived() / 1024 / s : 0;
    return formatClock(this.progress.elapsedMs) + ' · ' + kbps.toFixed(1) + ' KB/s · ' +
      this.scanRate.toFixed(1) + ' fr/s';
  }

  @Builder
  ProgressPanel() {
    Column({ space: 8 }) {
      if (this.sessionState === SessionState.IDLE) {
        Text('Point the camera at the QR animation on your PC')
          .fontSize(16)
      } else {
        Text('Receiving · ' + formatKb(this.progress.bundleLen))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
        Progress({ value: this.progress.resolved, total: Math.max(1, this.progress.k), type: ProgressType.Linear })
          .width('100%')
        Text(this.progress.resolved + ' / ' + this.progress.k + ' blocks (' +
          Math.floor(this.progress.resolved * 100 / Math.max(1, this.progress.k)) + '%)')
          .fontSize(14)
        Text(this.speedText())
          .fontSize(14)
        Text('unique frames: ' + this.progress.uniqueFrames + ' · scans: ' + this.progress.scans)
          .fontSize(12)
          .fontColor(Color.Gray)
      }
      if (this.errorText !== '') {
        Text(this.errorText)
          .fontSize(14)
          .fontColor(Color.Red)
      }
      Button('Reset')
        .onClick(() => this.resetSession())
    }
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .width('100%')
  }

  @Builder
  ResultsPanel() {
    Stack() {
      Column({ space: 12 }) {
        Text('✓ ' + this.session.files().length + ' images · ' + formatKb(this.progress.bundleLen) + ' · ' +
          (this.progress.elapsedMs / 1000).toFixed(1) + ' s')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
        Grid() {
          ForEach(this.thumbs, (t: Thumb, i: number) => {
            GridItem() {
              Column({ space: 4 }) {
                if (t.pixelMap !== null) {
                  Image(t.pixelMap)
                    .width('100%')
                    .aspectRatio(1)
                    .objectFit(ImageFit.Cover)
                    .borderRadius(6)
                } else {
                  Text('can\'t display')
                    .width('100%')
                    .aspectRatio(1)
                    .textAlign(TextAlign.Center)
                    .fontSize(12)
                    .backgroundColor(Color.Gray)
                    .borderRadius(6)
                }
                Text(t.name)
                  .fontSize(11)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .onClick(() => {
                if (t.pixelMap !== null) {
                  this.viewerIndex = i;
                }
              })
            }
          }, (t: Thumb, i: number) => i + ':' + t.name)
        }
        .columnsTemplate('1fr 1fr 1fr')
        .columnsGap(8)
        .rowsGap(8)
        .layoutWeight(1)
        Row({ space: 12 }) {
          SaveButton({ icon: SaveIconStyle.FULL_FILLED, text: SaveDescription.SAVE_TO_GALLERY,
            buttonType: ButtonType.Capsule })
            .onClick((event: ClickEvent, result: SaveButtonOnClickResult) => {
              if (result === SaveButtonOnClickResult.SUCCESS) {
                this.saveAll();
              } else {
                this.toast('Saving was not allowed');
              }
            })
          Button('Scan again')
            .onClick(() => this.resetSession())
        }
      }
      .padding(16)
      .width('100%')
      .height('100%')

      if (this.viewerIndex >= 0 && this.viewerIndex < this.thumbs.length) {
        Image(this.thumbs[this.viewerIndex].pixelMap)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Contain)
          .backgroundColor(Color.Black)
          .onClick(() => {
            this.viewerIndex = -1;
          })
      }
    }
    .width('100%')
    .height('100%')
  }

  build() {
    Column() {
      if (this.permissionDenied) {
        Column({ space: 12 }) {
          Text('Camera permission is needed to receive images')
            .fontSize(16)
          Button('Allow camera')
            .onClick(() => this.requestCamera())
        }
        .padding(24)
      } else if (this.sessionState === SessionState.COMPLETE) {
        this.ResultsPanel()
      } else {
        Stack() {
          XComponent({ type: XComponentType.SURFACE, controller: this.xController })
            .width(this.previewWidth)
            .height(this.previewHeight)
            .onLoad(() => {
              this.surfaceId = this.xController.getXComponentSurfaceId();
              this.startScan();
            })
        }
        .width('100%')
        .layoutWeight(1)
        .clip(true)

        this.ProgressPanel()
      }
    }
    .width('100%')
    .height('100%')
  }
}

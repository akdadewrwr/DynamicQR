import { base45Encode } from '../protocol/Base45';
import { crc32 } from '../protocol/Crc';
import { utf8Encode } from '../protocol/Utf8';

// Temporary: references protocol modules so the ArkTS build type-checks them (replaced in Task 8).
const PROTOCOL_CHECK: string = base45Encode(utf8Encode('x')) + crc32(new Uint8Array(1), 0, 1);

@Entry
@Component
struct Index {
  @State message: string = 'Hello World';

  build() {
    RelativeContainer() {
      Text(this.message)
        .id('HelloWorld')
        .fontSize($r('app.float.page_text_font_size'))
        .fontWeight(FontWeight.Bold)
        .alignRules({
          center: { anchor: '__container__', align: VerticalAlign.Center },
          middle: { anchor: '__container__', align: HorizontalAlign.Center }
        })
        .onClick(() => {
          this.message = 'Welcome';
        })
    }
    .height('100%')
    .width('100%')
  }
}
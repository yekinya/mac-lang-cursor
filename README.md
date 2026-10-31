# LangCursor

마우스 커서 오른쪽에 현재 입력 언어(`한` / `A`)를 반투명 배지로 보여 주는 macOS 메뉴바 앱입니다.

- 마우스를 움직이거나 타자를 치는 동안 표시되고, 아무 입력이 없으면 5초 뒤 사라집니다.
- 한영 전환 키를 누르는 즉시 표시합니다. 전환이 씹히면 언어가 그대로이니 바로 알 수 있습니다.
- 메뉴바의 `항상 켜져 있기`를 켜면 사라지지 않습니다.

## 빌드와 실행

```sh
./scripts/build-app.sh
open dist/LangCursor.app
```

macOS 13 이상이 필요합니다.

## 권한

타자 감지와 전환 키 즉시 표시에는 **입력 모니터링** 권한이 필요합니다.
시스템 설정 > 개인정보 보호 및 보안 > 입력 모니터링에서 LangCursor를 켜 주세요.
권한이 없어도 언어 변경과 마우스 이동에 따른 표시는 동작합니다.

앱은 키 코드만 확인하며, 입력한 내용을 읽거나 저장하지 않습니다.

앱을 ad-hoc 서명하므로 다시 빌드하면 macOS가 다른 앱으로 인식합니다.
재빌드 후 권한이 듣지 않으면 목록에서 LangCursor를 지우고 다시 추가하세요.

## 테스트

Xcode가 있으면 `swift test`로 실행합니다. Command Line Tools만 쓴다면 매크로 경로를 지정합니다.

```sh
swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
```

# Android（包名 / 构建 / 签名 / 电视）

## 包名

| 项 | 值 |
| --- | --- |
| `applicationId` | `dev.khinsider.khinsider` |
| `namespace`（Kotlin 包名） | `dev.khinsider.khinsider` |
| 应用显示名 | `KHInsider` |
| FileProvider authority | `dev.khinsider.khinsider.fileprovider`（Manifest 里写的是 `${applicationId}.fileprovider`） |
| 通知频道 id / 平台通道前缀 | 见 `MainActivity.kt` 与 `lib/platform/`（通道统一用 `dev.khinsider/...`） |

定义位置：

- `app/android/app/build.gradle.kts` —— `namespace` / `applicationId`
- `app/android/app/src/main/AndroidManifest.xml` —— `android:label`、权限、FileProvider
- `app/android/app/src/main/kotlin/dev/khinsider/khinsider/MainActivity.kt` —— 平台通道（电视检测、MediaStore 导出、存储权限）

**这个包名不要改。** `applicationId` 就是 Android 认应用身份的东西，改了以后新 APK 会被当成另一个应用：

- 已安装的旧版本**无法覆盖升级**（用户必须先卸载，缓存和设置全丢）；
- 签名密钥带来的「同一应用」关系、Android 13+ 的通知权限都要重新申请一遍；
- 电视/盒子的启动器里会**多出一个图标**，而不是替换原来的。

## 产物

CI（`.github/workflows/ci.yml`）出三个 APK：

- `khinsider-<版本>-armv7.apk` —— Chromecast / Google TV / 老电视盒子（armv7a，32 位）
- `khinsider-<版本>-arm64.apk`
- `khinsider-<版本>-universal.apk`

本地构建：

```sh
cd app
flutter build apk --release --target-platform android-arm,android-arm64
```

## 签名

Android 不允许用不同的密钥签名去升级已安装的应用，所以 CI 从一个固定的 release keystore 取密钥，仓库 secrets 里需要这几个：

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_TYPE`（`JKS` 或 `PKCS12`）
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

生成一次，然后备份好（丢了就再也发不出能覆盖安装的包）：

```bash
keytool -genkeypair -v \
  -keystore upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload

base64 -w0 upload-keystore.jks   # Linux；macOS 用 base64 -i upload-keystore.jks
```

把 base64 的内容填进 `ANDROID_KEYSTORE_BASE64`。CI 会把它解码成
`app/android/app/upload-keystore.<type>`，并在构建前写好 `app/android/key.properties`；
没配 secrets 时退回 debug key（**只能本地开发用，不能发版**）。

`key.properties`、`*.jks`、`*.p12`、`keystore.b64` 都在 `.gitignore` 里，**永远不要提交**。

如果 macOS 上的 `keytool` 崩在 `CodeHeap::allocate` (SIGBUS)，改用 OpenSSL 生成 PKCS12：

```bash
openssl req -newkey rsa:2048 -nodes -keyout key.pem -x509 -days 10000 \
  -out cert.pem -subj "/CN=KHInsider/OU=Mobile/O=trdthg/C=CN"
openssl pkcs12 -export -out upload-keystore.p12 \
  -inkey key.pem -in cert.pem -name upload -passout pass:YOUR_PASSWORD
base64 -i upload-keystore.p12 | tr -d '\n' > keystore.b64
```

然后把 `ANDROID_KEYSTORE_TYPE` 设成 `PKCS12`。

## 电视 / 手机两用

Manifest 里同时注册了 `LAUNCHER` 和 `LEANBACK_LAUNCHER`，并声明：

- `android.software.leanback`（`required="false"`）
- `android.hardware.touchscreen`（`required="false"`）
- `android.hardware.gamepad`（`required="false"`）

所以手机和电视（盒子）的启动器里都能看到，遥控器的方向键/确定键由应用自己的焦点系统处理
（详见 `ARCHITECTURE.md` 和 `TODO.md` 的 K 节）。

播放期间应用会通过 `dev.khinsider/platform` 的 `setKeepScreenOn` 给窗口加
`FLAG_KEEP_SCREEN_ON`：电视屏幕一旦超时就会进 ambient / 待机，待机会掐掉音频输出
（Chromecast 上表现为「放着放着就停了」）。暂停或播放结束就放开，退到后台时该 flag
自动失效。电视自己的「无操作 N 小时自动关机」是固件/用户设置，应用管不了。

权限：

- `INTERNET`、`WAKE_LOCK`、`FOREGROUND_SERVICE`、`FOREGROUND_SERVICE_MEDIA_PLAYBACK` —— 播放与通知栏控制
- `POST_NOTIFICATIONS` —— Android 13+ 的通知栏控制
- `REQUEST_INSTALL_PACKAGES` —— 应用内更新下载完之后的安装
- `MANAGE_EXTERNAL_STORAGE`（11+）/ `WRITE_EXTERNAL_STORAGE`（`maxSdkVersion="29"`）—— **可选**，只有用户要把缓存放进 `Music/KHInsider` 时才需要
- 免权限的「导出到 Music」走 MediaStore（`RELATIVE_PATH` + `IS_PENDING`），不需要上面这两个存储权限

## 通知栏图标

`app/android/app/src/main/res/drawable/khinsider_{play,pause,skip_next,skip_previous,stop}.xml`
是**按名字**在运行时引用的，所以 `build.gradle.kts` 里关掉了资源压缩
（`isShrinkResources = false`）——否则 R8/资源压缩会把只被字符串引用的 drawable 删掉，
通知栏就变成空白方块。加图标时记得同步这几个名字。

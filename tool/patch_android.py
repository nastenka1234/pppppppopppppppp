"""بعد از `flutter create` اجرا می‌شود: مجوزها، سرویس پخش، AudioServiceActivity و desugaring."""
import pathlib, re, sys

root = pathlib.Path(sys.argv[1])
man = root / 'android/app/src/main/AndroidManifest.xml'
s = man.read_text(encoding='utf8')

perms = ['INTERNET', 'FOREGROUND_SERVICE', 'FOREGROUND_SERVICE_MEDIA_PLAYBACK',
         'WAKE_LOCK', 'POST_NOTIFICATIONS', 'RECEIVE_BOOT_COMPLETED', 'ACCESS_NETWORK_STATE', 'RECORD_AUDIO']
add = ''.join(f'    <uses-permission android:name="android.permission.{p}"/>\n'
              for p in perms if f'android.permission.{p}"' not in s)
s = re.sub(r'(<manifest[^>]*>\n)', lambda m: m.group(1) + add, s, count=1)
if 'xmlns:tools' not in s:
    s = s.replace('<manifest ', '<manifest xmlns:tools="http://schemas.android.com/tools" ', 1)
s = re.sub(r'android:label="[^"]*"', 'android:label="امید"', s, count=1)
# امنیت: بدون بکاپ ابری/adb (توکن و صف ارسال داخل بکاپ نمی‌رود) و فقط HTTPS.
# (آپدیت اپ از روی نسخه‌ی قبلی داده را نگه می‌دارد؛ این‌ها به آپدیت ربطی ندارند.)
if 'android:allowBackup' not in s:
    s = s.replace('<application', '<application android:allowBackup="false" android:usesCleartextTraffic="false"', 1)

extra = '''
        <service android:name="com.ryanheise.audioservice.AudioService"
            android:foregroundServiceType="mediaPlayback"
            android:exported="true" tools:ignore="Instantiatable">
            <intent-filter><action android:name="android.media.browse.MediaBrowserService"/></intent-filter>
        </service>
        <receiver android:name="com.ryanheise.audioservice.MediaButtonReceiver"
            android:exported="true" tools:ignore="Instantiatable">
            <intent-filter><action android:name="android.intent.action.MEDIA_BUTTON"/></intent-filter>
        </receiver>
        <receiver android:exported="false"
            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"/>
        <receiver android:exported="false"
            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON"/>
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
'''
s = s.replace('</application>', extra + '    </application>', 1)
man.write_text(s, encoding='utf8')

for f in (root / 'android/app/src/main').rglob('MainActivity.*'):
    t = f.read_text(encoding='utf8')
    t = t.replace('io.flutter.embedding.android.FlutterActivity',
                  'com.ryanheise.audioservice.AudioServiceActivity')
    t = t.replace('FlutterActivity', 'AudioServiceActivity')
    f.write_text(t, encoding='utf8')

app = root / 'android/app'
kts, groovy = app / 'build.gradle.kts', app / 'build.gradle'

# ---- قوانین R8: بدون این‌ها اعلان‌ها و پخش‌کننده بعد از کوچک‌سازی می‌شکنند ----
(app / 'proguard-rules.pro').write_text("""-keepattributes Signature
-keepattributes *Annotation*
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class com.ryanheise.audioservice.** { *; }
-keep class com.ryanheise.just_audio.** { *; }
-keep class com.google.gson.** { *; }
-keep class androidx.work.** { *; }
-keep class dev.fluttercommunity.workmanager.** { *; }
-keep class be.tramckrijte.workmanager.** { *; }
-dontwarn com.google.android.play.core.**
""", encoding='utf8')

if kts.exists():
    g = kts.read_text(encoding='utf8')
    # record_android (ضبط ویس) به Android API 23 نیاز دارد.
    if re.search(r'minSdk\s*=\s*flutter\.minSdkVersion', g):
        g = re.sub(r'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 23', g, count=1)
    elif re.search(r'minSdk\s*=\s*\d+', g):
        g = re.sub(r'minSdk\s*=\s*\d+', 'minSdk = 23', g, count=1)
    elif re.search(r'defaultConfig\s*\{', g):
        g = re.sub(r'(defaultConfig\s*\{)', r'\1\n        minSdk = 23', g, count=1)
    g = re.sub(r'(compileOptions\s*\{)', r'\1\n        isCoreLibraryDesugaringEnabled = true', g, count=1)
    # امضا: key.properties
    g = 'import java.util.Properties\nimport java.io.FileInputStream\n' + g
    g = re.sub(r'^android\s*\{', """val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }
""", g, count=1, flags=re.M)
    g, n = re.subn(r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)', """signingConfig = if (keystorePropertiesFile.exists()) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")""", g, count=1)
    if n != 1 or 'signingConfigs.getByName("release")' not in g:
        sys.exit('patch_android: بلوک release در build.gradle.kts پیدا نشد؛ امضا اعمال نشد')
    g += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
    kts.write_text(g, encoding='utf8')
else:
    g = groovy.read_text(encoding='utf8')
    if re.search(r'minSdkVersion\s+flutter\.minSdkVersion', g):
        g = re.sub(r'minSdkVersion\s+flutter\.minSdkVersion', 'minSdkVersion 23', g, count=1)
    elif re.search(r'minSdkVersion\s+\d+', g):
        g = re.sub(r'minSdkVersion\s+\d+', 'minSdkVersion 23', g, count=1)
    elif re.search(r'defaultConfig\s*\{', g):
        g = re.sub(r'(defaultConfig\s*\{)', r'\1\n        minSdkVersion 23', g, count=1)
    g = re.sub(r'(compileOptions\s*\{)', r'\1\n        coreLibraryDesugaringEnabled true', g, count=1)
    g = re.sub(r'^android\s*\{', """def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}

android {
    signingConfigs {
        release {
            if (keystorePropertiesFile.exists()) {
                keyAlias keystoreProperties['keyAlias']
                keyPassword keystoreProperties['keyPassword']
                storeFile file(keystoreProperties['storeFile'])
                storePassword keystoreProperties['storePassword']
            }
        }
    }
""", g, count=1, flags=re.M)
    g, n = re.subn(r'signingConfig\s*=?\s*signingConfigs\.debug', """signingConfig = keystorePropertiesFile.exists() ? signingConfigs.release : signingConfigs.debug
            minifyEnabled true
            shrinkResources true
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'""", g, count=1)
    if n != 1 or 'signingConfigs.release' not in g:
        sys.exit('patch_android: بلوک release در build.gradle پیدا نشد؛ امضا اعمال نشد')
    g += "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n"
    groovy.write_text(g, encoding='utf8')
print('android patched')

exec((pathlib.Path(__file__).with_name('blocker_patch.py')).read_text(encoding='utf8'))

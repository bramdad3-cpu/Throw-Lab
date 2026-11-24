"""Adjust the Android project that `flutter create` generates on every CI build:
microphone permission, text-to-speech visibility, minimum Android version, app name."""
import pathlib, re

app = pathlib.Path("android/app")
manifest = app / "src/main/AndroidManifest.xml"
m = manifest.read_text()

perms = [
    '<uses-permission android:name="android.permission.RECORD_AUDIO"/>',
    '<uses-permission android:name="android.permission.WAKE_LOCK"/>',
]
for p in perms:
    if p not in m:
        m = m.replace("<application", p + "\n    <application", 1)

tts = '<intent><action android:name="android.intent.action.TTS_SERVICE"/></intent>'
if "TTS_SERVICE" not in m:
    if "<queries>" in m:
        m = m.replace("<queries>", "<queries>\n        " + tts, 1)
    else:
        m = m.replace("</manifest>", "    <queries>\n        " + tts + "\n    </queries>\n</manifest>", 1)

m = re.sub(r'android:label="[^"]*"', 'android:label="Throw Lab"', m, count=1)
manifest.write_text(m)

for name in ("build.gradle.kts", "build.gradle"):
    g = app / name
    if g.exists():
        t = g.read_text()
        t = t.replace("minSdk = flutter.minSdkVersion", "minSdk = 24")
        t = t.replace("minSdkVersion flutter.minSdkVersion", "minSdkVersion 24")
        g.write_text(t)
        print("patched", g)

print(manifest.read_text())

# Publishing the app to the Google Play Store

A complete guide, from zero to a live app. Written for someone who has
never published anything to the Play Store before.

> **Timing notice:** Play Store rules change a few times a year. This
> guide is up to date as of **August 2026**. Always check the
> corresponding official page before each submission — the links are at
> the end.

---

## Overview: how long this actually takes

| Stage | Time | Cost |
|---|---|---|
| Setting up the environment and building | 1 to 3 hours | free |
| Creating the developer account | 15 min + **1 to 3 days** of verification | **US$25**, once for life |
| Filling in the store listing (text and images) | 2 to 4 hours | free |
| **Mandatory closed testing (12 people, 14 days)** | **at least 14 days** | free |
| Production review | 1 to 7 days | free |

**From zero to a published app: 3 to 5 weeks in practice.** The
bottleneck is closed testing, which can't be skipped or sped up. Start it
as early as possible.

---

## Stage 0 — What you need on hand

- A computer running **Windows, macOS or Linux** (Android Studio runs on
  all three).
- A **Google account** that will own the app forever. Use one you won't
  lose — changing it later is bureaucratic.
- **US$25** on an internationally-enabled card.
- A **government ID** and a proof of address: Google verifies the
  identity of every individual developer.
- **12 people** willing to install your app and open it over 14 days.
  Start inviting them now — it's the hardest item to line up.

---

## Stage 1 — Set up your computer

1. Install **Flutter** (version 3.44 or newer):
   <https://docs.flutter.dev/get-started/install>
2. Install **Android Studio** — it brings along the Android SDK, the NDK
   and the build tools.
3. In Android Studio, under *SDK Manager → SDK Platforms*, check
   **Android 16 (API 36)**. Under *SDK Tools*, check
   **NDK (Side by side)** and **Android SDK Command-line Tools**.
4. Check that everything's in order:

   ```bash
   flutter doctor
   ```

   Fix anything marked with a ✗ before moving on. The
   *"Android license status unknown"* item is fixed with
   `flutter doctor --android-licenses`.

---

## Stage 2 — Run the project for the first time

```bash
git clone https://github.com/lianeheidemann/aplicativo-video-to-gif-1.git
cd aplicativo-video-to-gif-1

flutter pub get
flutter test   # the size-estimator tests should pass
flutter run    # with the phone connected and USB debugging on
```

> `gradlew` and `android/local.properties` are not version-controlled
> (Flutter convention) — the tool itself creates them on the first build,
> pointing at the SDK installed on your machine.

If you get an NDK error, open `android/app/build.gradle.kts` and set
`ndkVersion` to whichever version you installed (the error message tells
you which one).

---

## Stage 3 — Define the app's identity

Three things need to be decided **before** the first submission, because
they can no longer change afterward:

### 3.1 The `applicationId`

This is the app's permanent address in the store. In this project it's
`br.com.lianeheidemann.videotogif`, defined in two places:

- `android/app/build.gradle.kts` → `namespace` and `applicationId`
- the folder `android/app/src/main/kotlin/br/com/lianeheidemann/videotogif/`

If you want to change it, change it in both places and rename the folder.

### 3.2 The visible name

It's in `android/app/src/main/AndroidManifest.xml`, in the
`android:label` attribute. On the store, the name can be at most **30
characters**.

### 3.3 The icon

**Already done.** The repository ships with its own icon (not Flutter's
default) at every density, plus the adaptive-icon version for Android 8+:

```
android/app/src/main/res/mipmap-*/ic_launcher.png
android/app/src/main/res/mipmap-*/ic_launcher_foreground.png
android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml
assets/icone.png                                 (1024×1024 master)
```

If you want to change the design or colors, edit `tool/gerar_icones.py`
and run:

```bash
pip install Pillow
python3 tool/gerar_icones.py
```

The script regenerates the icon at every density **and** the two store
listing images (`loja/icone_512.png` and
`loja/grafico_destaque_1024x500.png`), which keeps everything consistent.

---

## Stage 4 — Create the signing key

Every APK/AAB needs to be signed. **This key is forever**: if you lose it,
you can no longer publish updates to the same app — you'd have to start a
brand-new app from scratch, without the existing users.

> ⚠️ **Generate the key on your own machine.** Never create the production
> keystore in a disposable environment — a container, CI, a cloud
> machine, an agent session. Either you lose the key when the environment
> is destroyed, or you have to transfer it over an insecure path. This is
> the one part of the process that can't be outsourced or automated.

`keytool` ships with Java. If you don't have Java installed, it's inside
Android Studio, at `<android-studio-folder>/jbr/bin/keytool`. Android
Studio can also do this through its UI, under
*Build → Generate Signed App Bundle → Create new…*.

**Interactive mode** (asks for the password and details one at a time):

```bash
keytool -genkeypair -v \
  -keystore ~/videotogif-upload-key.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload
```

**Direct mode** (no prompts — swap in your own name and password):

```bash
keytool -genkeypair -v \
  -keystore ~/videotogif-upload-key.jks \
  -storepass YOUR_STRONG_PASSWORD -keypass YOUR_STRONG_PASSWORD \
  -alias upload -keyalg RSA -keysize 2048 -validity 10000 \
  -dname "CN=Your Name, O=, L=Your City, ST=State, C=BR"
```

The `-dname` details aren't shown to anyone on the store: the certificate
is self-signed and only serves to prove that the releases came from the
same person. What actually matters is the file and the password.

Check that it worked:

```bash
keytool -list -v -keystore ~/videotogif-upload-key.jks
```

You should see `Alias name: upload`, the validity period (about 27 years,
with `-validity 10000`) and the SHA1 and SHA256 fingerprints.

> The 10,000-day validity isn't overkill: the Play Store requires a
> certificate valid until at least October 22, 2033.

Now create the file `android/key.properties` (copy it from
`android/key.properties.example`):

```properties
storePassword=the-password-you-chose
keyPassword=the-same-password
keyAlias=upload
storeFile=/full/path/to/videotogif-upload-key.jks
```

> ⚠️ **Never** put the `.jks` or `key.properties` into Git. This
> project's `.gitignore` already blocks both. Keep a copy of the `.jks`
> and the passwords in a password manager **and** in a separate backup
> (a USB drive, a private Drive). This is the single most critical item
> in the entire process.

**Play App Signing:** Google keeps the final distribution key for you.
Your `.jks` is the *upload key* — if it leaks or gets lost, you can ask
support for a replacement, as long as Play App Signing is enabled (it's
the default for new apps). Even so, treat it as if there were no second
chance.

---

## Stage 5 — Build the package for the store

The Play Store **no longer accepts APKs** for new apps. The format is the
**AAB** (Android App Bundle):

```bash
flutter build appbundle --release
```

The file comes out at:

```
build/app/outputs/bundle/release/app-release.aab
```

Before submitting, test the release build on your phone — release mode
uses R8 (which strips unused code), and that's where ProGuard bugs show
up:

```bash
flutter build apk --release
flutter install --release
```

If the app opens and converts a GIF without crashing, the AAB will work
too.

> If the app works in debug but crashes in release while converting, it's
> almost always R8 stripping FFmpeg classes. The rules that prevent this
> are already in `android/app/proguard-rules.pro`.

---

## Stage 5b — Let GitHub build it for you (optional, but recommended)

If your machine doesn't have the Android environment ready — or if you
want to send the app to testers without passing a file over WhatsApp —
the repository already has a workflow that builds and publishes
everything to a GitHub Release: `.github/workflows/release.yml`.

### How to trigger it

```bash
git tag v1.0.0
git push origin v1.0.0
```

Or, without touching tags: the **Actions → Release → Run workflow** tab,
typing in the version.

Within a few minutes a Release appears with:

| File | What it's for |
|---|---|
| `...-arm64-v8a.apk` | install on a modern phone (the one you send to testers) |
| `...-armeabi-v7a.apk` | older, 32-bit devices |
| `...-universal.apk` | works on any device, but larger |
| `....aab` | **the file that goes to the Play Console** (only produced if signing is configured) |

### Setting up signing (so the AAB comes out publishable)

Without the secrets below, the workflow still works, but signs with the
debug key: the APKs install and run for testing, and the `.aab` isn't
generated, since it wouldn't be usable.

To enable real signing, turn your keystore into text:

```bash
base64 -w0 ~/videotogif-upload-key.jks > key-base64.txt
# on macOS, without the -w0 option:
# base64 -i ~/videotogif-upload-key.jks -o key-base64.txt
```

Under **Settings → Secrets and variables → Actions → New repository
secret**, create four secrets:

| Name | Content |
|---|---|
| `KEYSTORE_BASE64` | the entire content of `key-base64.txt` |
| `KEYSTORE_PASSWORD` | the keystore password |
| `KEY_PASSWORD` | the key password (the same one, if you used a single password) |
| `KEY_ALIAS` | `upload` |

Afterward, **delete `key-base64.txt`** from your machine — it's the
entire keystore in text form.

> ⚠️ This puts a copy of your signing key on GitHub. Actions secrets are
> encrypted and don't show up in logs, and the workflow deletes the file
> from the runner at the end. Even so, anyone with admin access to the
> repository can extract the key by modifying a workflow — keep the
> repository private and the collaborator list short. If you'd rather not
> take that risk, don't configure the secrets: generate the `.aab` on
> your own machine and use the Release only to distribute test APKs.

### The versionCode

The workflow uses the Actions run number as the `versionCode`, which
climbs on its own with every run. That solves the most annoying
submission error ("versionCode already exists") without you having to
remember anything. The `versionName` comes from the tag: `v1.0.0` becomes
`1.0.0`.

---

## Stage 6 — Create the Google Play Console account

1. Go to <https://play.google.com/console/signup>.
2. Choose a **personal account** (simpler; a company account requires a
   D-U-N-S number and takes weeks).
3. Pay the **US$25** (a one-time payment, good for every app you'll ever
   publish).
4. **Identity verification:** submit a photo of your ID and your address.
   Takes 1 to 3 days. The address you provide shows up publicly on the
   app's listing — if you don't want to expose your home address,
   consider using a business address or a PO box.

---

## Stage 7 — Create the app and fill in the listings

In the Play Console: **Create app**. After that, the dashboard shows a
list of required tasks. It's worth filling everything in before
uploading the AAB.

### 7.1 Store listing (what the user sees)

The copy is already written, within the character limits and ready to
copy and paste: **[`docs/en/STORE_LISTING.md`](STORE_LISTING.md)** (the
original Portuguese version is at
[`loja/FICHA_DA_LOJA.md`](../../loja/FICHA_DA_LOJA.md)).

The two required images are also already generated:

| Item | Spec | File |
|---|---|---|
| App name | up to 30 characters | in `docs/en/STORE_LISTING.md` |
| Short description | up to 80 characters | in `docs/en/STORE_LISTING.md` |
| Full description | up to 4000 characters | in `docs/en/STORE_LISTING.md` |
| Icon | 512×512 PNG, 32-bit, up to 1 MB | ✅ `loja/icone_512.png` |
| Feature graphic | 1024×500 PNG/JPG | ✅ `loja/grafico_destaque_1024x500.png` |
| Screenshots | **at least 2**, up to 8 · shorter side ≥ 320 px, longer side ≤ 3840 px | ⬜ you need to take these |

Screenshots are the only part that depends on you, since they require the
app running on a device. The suggested script (which screens to
capture, in what order) and the `adb` commands to clean up the status bar
are in the same file.

### 7.2 Data safety

This form is mandatory and Google checks it. For **this** app, since it
has no internet permission and collects nothing, the answers are:

- *Does your app collect or share any of the user data types?* → **No**
- *Is all user data encrypted in transit?* → not applicable
- *Do you provide a way for users to request data deletion?* → not
  applicable

If you ever add ads, analytics or any third-party SDK, **this answer
changes** and needs to be updated.

### 7.3 Privacy policy

It's **mandatory**, even for apps that collect nothing. You need a public
URL. The fastest, free way:

1. Use the template in
   [`PRIVACY_POLICY.md`](PRIVACY_POLICY.md) (Portuguese original:
   [`POLITICA_DE_PRIVACIDADE.md`](../POLITICA_DE_PRIVACIDADE.md)).
2. Publish it as a GitHub Pages page (you already do this in the
   `protocolo-soap` project) or as a public Gist.
3. Paste the URL into the Play Console.

### 7.4 Content rating

Answer the IARC questionnaire. For a video converter with no content of
its own, the rating comes out as **Everyone / 3+**. Answer "no" to
everything about violence, sex, drugs and gambling; mark that there's no
interaction between users and no location sharing.

### 7.5 The other declarations

- **Target audience:** choose age ranges from 13 and up. Checking
  "children" activates the *Families* policy, which is much stricter —
  avoid it.
- **Ads:** *No, my app does not contain ads.*
- **App access:** *All features are available with no restrictions* (no
  login).
- **News / COVID / finance / health app:** no.
- **Sensitive permissions:** this app requests none. That's why
  `AndroidManifest.xml` removes `READ_MEDIA_VIDEO` — we use the system's
  file picker, which requires no permission. If you swap it for an
  in-app gallery, you'll need to fill in the *Photo and video permissions*
  declaration and record a video demonstrating its use.

---

## Stage 8 — The mandatory closed test (the slowest part)

**If your personal account was created after November 13, 2023**, you
can't publish straight to production. You first need to:

- run a **closed test** with **at least 12 testers**;
- have them stay enrolled for **14 straight days**;
- and have them **actually use** the app during that period — since 2026
  Google rejects requests when testers only installed the app and never
  opened it.

### How to do it

1. In the Play Console: **Testing → Closed testing → Create track**.
2. Create an **email list** with the 12+ Gmail addresses of your testers
   (it needs to be the Google account email tied to each person's
   device).
3. Send the AAB to that track.
4. Share the **opt-in link** the Console generates. Each person needs to
   open the link, accept the invitation and **install through the Play
   Store**.
5. Ask them to open the app **nearly every day** during the two weeks.
   Ask them to convert a GIF once in a while — that's what counts as
   usage.

### Practical tips

- Invite **15 people**, not 12: someone always fails to install it.
- If someone drops out midway, the 14-day counter does **not** reset;
  just don't let the total stay below 12 for too long.
- Make real use of the period: ask for feedback, fix crashes.
  Submissions with stability problems also get rejected.
- **Company** accounts (with a tax ID and D-U-N-S number) are exempt from
  this requirement.

---

## Stage 9 — Request production access and publish

After the 14 days with 12 active testers have passed, the **"Request
production access"** button appears. You fill in a short form describing:

- what you learned from the closed test;
- what changes you made based on tester feedback;
- how you plan to promote the app.

Write it honestly and with detail — generic answers get rejected. The
review takes 1 to 7 days.

Once approved, it's just: **Production → Create new release → upload the
AAB → Review → Start rollout**. The final review takes a few extra days
the first time.

---

## Stage 10 — After publishing

### Every update needs a new `versionCode`

In `pubspec.yaml`:

```yaml
version: 1.0.1+2
#       ^^^^^  ^
#       name   versionCode — ALWAYS higher than the previous one
```

The number after the `+` is what the Play Store uses to know it's a new
version. If you forget to bump it, the submission is rejected.

### Watch the dashboard

- **Vitals**: crash rate and ANR (app not responding) rate. Past 1.09%
  crashes per user, Google reduces the app's visibility on the store.
- **Reviews**: reply to them; it counts toward ranking.

### Keep an eye on `targetSdk`

Google requires the app to target a recent Android version:

| Deadline | Requirement |
|---|---|
| **08/31/2026** | new apps and updates must target **API 36** (Android 16) |
| 11/01/2026 | extension deadline, if you request one |

This project is already at `targetSdk = 36`. Roughly once a year, you'll
need to bump that number and resubmit.

---

## Traps that catch almost everyone

1. **Losing the keystore.** Back it up today, not later.
2. **Not starting the closed test early.** It's 14 fixed days; start it
   in the first week.
3. **Uploading a debug AAB.** Always
   `flutter build appbundle --release`.
4. **Forgetting the `versionCode`.** Bump it with every submission.
5. **A broken privacy policy.** The URL needs to be publicly accessible
   and stay online after approval.
6. **Screenshots with a messy status bar** (3% battery, notifications).
   Use demo mode: `adb shell settings put global sysui_demo_allowed 1`.
7. **App too large.** FFmpeg adds native libraries for every
   architecture, so the full package is large. This isn't a problem on
   the store: the AAB is split by ABI on Google's server and each user
   downloads only their device's architecture. For distributing an APK
   outside the store (testing, a direct link), use the per-architecture
   files the release workflow generates, not the universal one.
8. **Ignoring FFmpeg's license.** See [`LICENSES.md`](LICENSES.md)
   (Portuguese original: [`LICENCAS.md`](../LICENCAS.md)) — it's quick,
   but it needs to be done.

---

## Final checklist before submitting

Already handled in the repository:

- [x] Custom icon at every density + adaptive icon
- [x] 1024×500 feature graphic and 512×512 store icon
- [x] Listing copy written and within the character limits
- [x] FFmpeg license notice inside the app (*About → View licenses*)
- [x] Privacy policy template ready to publish
- [x] `targetSdk = 36`, required starting 08/31/2026
- [x] `flutter analyze` clean and tests passing (CI runs on every push)

Up to you:

- [ ] Keystore created **and backed up in two places**
- [ ] `flutter build appbundle --release` producing the `.aab`
- [ ] Release APK tested on a real phone
- [ ] `versionCode` higher than the previous submission's
- [ ] 2 to 8 screenshots of the app running
- [ ] Privacy policy published at a public URL
- [ ] Data Safety form answered
- [ ] Content rating completed
- [ ] 12+ testers invited to the closed test

---

## Official links

- [Play Console](https://play.google.com/console)
- [Create a developer account](https://play.google.com/console/signup)
- [Target API level requirement](https://support.google.com/googleplay/android-developer/answer/11926878)
- [Closed testing requirement (12 testers)](https://support.google.com/googleplay/android-developer/answer/14151465)
- [Data Safety form](https://support.google.com/googleplay/android-developer/answer/10787469)
- [Store listing image specs](https://support.google.com/googleplay/android-developer/answer/9866151)
- [Signing Flutter apps](https://docs.flutter.dev/deployment/android)

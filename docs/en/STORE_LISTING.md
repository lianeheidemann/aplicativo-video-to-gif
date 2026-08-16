# Store listing — ready-to-paste copy

Everything below already respects the Play Console's character limits.
Copy and paste it straight into the matching fields.

---

## App name (limit: 30 characters)

```
Video to GIF
```

## Short description (limit: 80 characters)

```
Convert videos to GIF and know the file size before you convert.
```

## Full description (limit: 4000 characters)

```
Turn any video into a GIF right on your phone, without sending anything to the internet.

KNOW THE SIZE BEFORE YOU CONVERT
Tired of waiting for a conversion to finish only to find out the file came out too big? The app shows the predicted size while you adjust the controls. Tap "Measure" and it converts clips of under a second to calibrate the prediction against your video — from then on the number is accurate.

FITS WHERE YOU NEED IT
The app tells you whether the GIF fits within WhatsApp's, X/Twitter's or Discord's limits. If it doesn't fit, one tap adjusts the settings automatically, trimming first whatever affects perceived quality the least.

WHAT YOU CONTROL
• Trim the start and end of the video
• Choose the crop shape: 1:1, 4:5, 9:16, 16:9, 4:3, 3:2 or the original
• Adjust the crop position
• Speed up to 4x or slow down to 0.25x
• Choose the resolution, from 160 px to 1080 px wide
• Set the frame rate, from 5 to 30
• Fine-tune the palette, color count and dithering

REAL QUALITY
Conversion uses a two-pass optimized palette: instead of the GIF format's generic colors, the app calculates the colors your video actually uses. That's the difference between a vivid GIF and a "washed out" one.

UNDERSTAND WHAT IT'S DOING
A help screen explains, in plain language, what each control does to the file size and in what order it's worth adjusting them.

REAL PRIVACY
Everything happens on your device. The app has no internet-access permission, collects no data, and doesn't request access to your gallery: you choose the video through Android's own picker, and the app only sees that one file.

SUPPORTED FORMATS
MP4, MOV, AVI, MKV, WEBM, 3GP and other common video formats.

No ads. No sign-up. No charges.
```

---

## Images

| File | Where to use it |
|---|---|
| `icone_512.png` | App icon on the store listing (512×512) |
| `grafico_destaque_1024x500.png` | Feature graphic (1024×500) |

To regenerate both, run from the project root:

```bash
pip install Pillow
python3 tool/gerar_icones.py
```

The same script also updates the launcher icon in
`android/app/src/main/res/mipmap-*/`.

### Screenshots (you need to generate these)

The Play Store requires **at least 2** and accepts up to 8. Shorter side
≥ 320 px, longer side ≤ 3840 px. Suggested shot list, in this order:

1. Home screen with the "Choose video" button
2. Editor showing the size panel with the green "Light" badge
3. Editor with the destination chips (WhatsApp / X / Discord)
4. Crop-shape section with the 9:16 crop applied
5. Help screen "What makes a GIF heavy"
6. Result screen with the finished GIF and the predicted-vs-real comparison

With the app running on a connected phone:

```bash
# clears the status bar so the screenshot looks presentable
adb shell settings put global sysui_demo_allowed 1
adb shell am broadcast -a com.android.systemui.demo -e command clock -e hhmm 1000
adb shell am broadcast -a com.android.systemui.demo -e command battery -e level 100 -e plugged false
adb shell am broadcast -a com.android.systemui.demo -e command network -e wifi show -e level 4
adb shell am broadcast -a com.android.systemui.demo -e command notifications -e visible false

adb exec-out screencap -p > loja/captura1.png

# restores the status bar to normal
adb shell am broadcast -a com.android.systemui.demo -e command exit
```

---

## Answers for the required forms

Kept here so you don't have to decide again on every submission. They hold
for the app **as it stands in this repository** — they change if you add
ads, analytics or any server upload.

| Form | Answer |
|---|---|
| Data safety — collects or shares data? | **No** |
| Ads | Does not contain ads |
| App access | All functionality available with no restrictions |
| Target audience | 13 years or older (don't check "children") |
| Content rating | IARC questionnaire — "no" to everything; expected result: Everyone / 3+ |
| News app | No |
| Financial / health / government features | No |
| Sensitive permissions | None requested |
| Privacy policy | Public URL with the content of `docs/POLITICA_DE_PRIVACIDADE.md` (or its English translation, `docs/en/PRIVACY_POLICY.md`, if you're publishing an English listing) |

## Categorization

- **Category:** Tools (or Photography — either fits; Tools has less
  direct competition from photo editors)
- **Suggested tags:** GIF, video converter, video editor, compression

# How the app predicts GIF size before converting

This document explains the model behind the number that shows up at the
bottom of the editor — and, at the end, gives practical recipes for picking
settings without needing to understand any of this.

---

## Why it can be predicted at all

A GIF is a sequence of frames where each frame is an image of at most 256
colors compressed with LZW. On top of that, FFmpeg only re-encodes the
rectangle that changed from one frame to the next (`diff_mode=rectangle`).

That splits frames into two kinds with very different prices. The **first**
one is a full image, because there's no previous frame to compare against.
The **rest** only cost the rectangle that changed. In practice, the size
follows this math quite well:

```
bytes  ≈  header + palette
          +  width × height × k_key
          +  (frames − 1) × width × height × k_delta
```

> **Why two `k` values instead of one.** Treating every frame as if it cost
> the same seems harmless, and it is — until you measure 1 second and predict
> 40. In a static scene the first frame is practically the whole file:
> diluted across 12 sample frames it looks very expensive, and multiplying
> that by 517 frames produces a prediction ten times bigger than the real
> file. That was exactly the flaw in the model's first version, and it
> showed up precisely in the most common kind of video people turn into
> GIFs: title cards, screen recordings, animated screenshots. The numbers
> are in [Measured accuracy](#measured-accuracy).

Everything in that formula is known before converting — **except the two
`k` values**, which are how much each pixel costs in bytes. And they depend
on two quite different things:

| | What it is | Knowable beforehand? |
|---|---|---|
| **Content** | how much the scene moves and how much detail it has | ❌ only by measuring |
| **Settings** | fps, colors, dither, scale, speed | ✅ just a calculation |

The model's core idea is to **separate the two**. That way the content only
needs to be measured once per video, and it stays valid while the user
adjusts every other control.

---

## The two halves of each `k`

```
k = video_complexity × settings_factor
```

### The complexity (measured once)

A number in bytes per pixel per frame, expressed under **reference
conditions**: 12 fps, 256 colors, balanced dither, single palette, 1x speed
and the image scaled to half its original width.

Typical values:

| Video type | complexity |
|---|---|
| Person talking, static camera | 0.05 – 0.10 |
| Ordinary phone footage | 0.12 – 0.20 |
| Moving camera, lots of texture | 0.25 – 0.40 |
| Confetti, fireworks, water, rain | 0.40 + |

Until the user taps "Measure", the app uses a guess derived from the
original file's bitrate (high bitrate per pixel = more complex scene). It's
a reasonable guess, with an announced margin of error of ±40–55%.

### The settings factor (calculated)

Each control becomes a multiplier. All of them equal 1.0 under the
reference conditions:

| Control | Formula | Applies to the 1st frame? | Why |
|---|---|---|---|
| FPS | `(12 / fps) ^ 0.30` | ❌ | more frames = more similar to each other, so each one costs less |
| Colors | `(colors / 256) ^ 0.45` | ✅ | fewer distinct symbols compress better |
| Dither | table: 0.72 to 1.55 | ✅ | dithering is noise, and noise compresses poorly |
| Palette | 0.95 to 1.30 | ✅ | a palette per frame prevents reusing the color table |
| Speed | `speed ^ 0.12` | ❌ | speeding up increases the difference between neighboring frames |
| Scale | `(reduction / 0.5) ^ 0.12` | ✅ | shrinking also smooths out detail and noise |

FPS and speed intentionally don't apply to the first frame: it's a still
image, and a still image doesn't get cheaper just because the video has
more frames per second.

The fractional exponents are the detail that makes the model work.
**Doubling the FPS doesn't double the file size** — it increases it by
roughly 62%, because half of the new frames are nearly identical to the
previous one. A linear model would be badly wrong exactly on the control
people touch the most.

---

## The "Measure" button

When the user taps **Measure**, the app:

1. picks 2 points within the selected clip (at 20% and 60%);
2. actually converts a window of under 1 second at each point, using the
   **same** settings the user chose;
3. converts the same window **a second time, cut down to the first frame**,
   reusing the palette it just generated (which is why it's almost free);
4. measures the real size of both files. The difference between them is,
   by construction, what the following frames cost;
5. **inverts the formula** to work out the video's two complexities:

   ```
   k_key = (bytes_1_frame − header) / (width × height)
           ÷ settings_factor_for_a_still_frame

   k_delta = (bytes_window − bytes_1_frame) / ((frames − 1) × width × height)
             ÷ settings_factor
   ```

6. combines the two samples, weighting the heavier one more — erring high
   is less annoying than promising 3 MB and delivering 12 MB.

It's this third encode that makes the model honest: without it there's no
way to separate the expensive frame from the cheap ones, and the cost of
the first one ends up spread across all of them.

It costs 2 to 5 seconds and drops the announced margin of error from ±55%
to ±15%.

And, because the complexity is independent of the settings, **the user can
keep adjusting every other control after measuring** without needing to
measure again. That's the reason the model is built this way.

On the result screen the app shows the difference between the prediction
and the real outcome. If that number stays systematically high for a
particular kind of video, it's a sign one of the exponents in the table
above deserves tuning.

---

## Measured accuracy

The model isn't judged by opinion. `tool/medir_precisao.py` generates five
synthetic videos covering the extremes of complexity, converts each one
with the app's exact filter chain and records the real sizes; the test
`test/size_estimator_medicoes_test.dart` feeds the model those measurements
and compares the prediction against the file that actually came out.

Output of 400×224 px, 12 FPS, 256 colors, balanced dither, 43.1 s
(517 frames), calibrated with two 1-second samples:

| Video | Real | Predicted | Error | Old model |
|---|---|---|---|---|
| Title card (static) | 0.04 MB | 0.02 MB | −44% | **+1683%** |
| Static background, moving object | 0.42 MB | 0.43 MB | +1% | +56% |
| Busy scene | 5.29 MB | 5.32 MB | +1% | +6% |
| Moving gradient | 17.81 MB | 16.62 MB | −7% | −6% |
| Noise (incompressible) | 42.80 MB | 42.98 MB | +0% | +1% |

Three important takeaways:

- **The old model wasn't bad at everything.** It nailed motion-heavy
  scenes, where the first frame is a minor detail among hundreds. It broke
  down the stiller the image got — and title cards, screen recordings and
  animated screenshots are exactly the videos people turn into GIFs most.
- **The title card still falls outside ±15%, and that's fine.** The file is
  39 KB: missing by 17 KB turns into −44% as a percentage and means nothing
  in practice. The relative ruler doesn't say much at that scale, which is
  why the test checks *absolute* error below 100 KB and *relative* error
  above it.
- **The gradient misses by the same −7% in both models**, which is
  expected: its problem isn't the first frame, it's that a moving gradient
  is the content that least resembles the rest of itself over time. It's
  the next place where the model has room to improve.

The measurements are reproducible: the sources use fixed seeds and colors
and are encoded with `-threads 1`, because both the `gradients` filter and
multi-threaded x264 vary from one run to the next and would make the test
flaky.

To redo the measurements (needs `ffmpeg` and `ffprobe` on the PATH):

```bash
python3 tool/medir_precisao.py
```

It prints the table and the block of constants ready to paste into the
test.

## The tests

`test/size_estimator_test.dart` covers:

- **monotonicity** — moving each control in the expected direction changes
  the size in the expected direction;
- **FPS sublinearity** — doubling the FPS increases the size by 30% to
  100%, never more than that;
- **calibration round-trip** — estimating with a known complexity and then
  recovering it from the result returns the same two numbers;
- **settings independence** — a complexity measured at 12 fps / 480 px
  correctly predicts a GIF at 20 fps / 320 px (error < 5%);
- **duration independence** — a nearly static scene measured over 1 second
  correctly predicts a 40-second conversion (error < 5%). This is the test
  that locks in the fix for the diluted-first-frame bug;
- **robustness** — absurd measurements fall back to the default value
  instead of crashing;
- **automatic adjustment** — the search for a target size always
  terminates and never changes the clip the user selected.

```bash
flutter test
```

---

## Practical recipes (the part that matters day to day)

### Which control to touch first

In order of "how much it saves for how much it costs":

1. **Duration** — a direct effect with no quality loss. Half the duration,
   half the size. It's almost always the best move.
2. **Resolution** — a squared effect. Going from 480 px to 240 px makes the
   file **4 times** smaller. The loss is visible, but GIFs are usually
   viewed small.
3. **FPS** — going from 24 to 12 is barely noticeable in a GIF, and saves
   ~38%. Below 8 fps it starts to feel choppy.
4. **Colors** — 128 colors go unnoticed in most scenes. Below 64, banding
   starts showing up in skies and skin tones.
5. **Dither** — touch it last. It's what damages gradients the most.

### Combinations that work

| Goal | Width | FPS | Colors | Dither | Typical size (5s) |
|---|---|---|---|---|---|
| WhatsApp sticker / reaction | 240 px | 12 | 128 | Light | 300 KB – 1 MB |
| Social media post | 480 px | 12 | 256 | Balanced | 1.5 – 4 MB |
| Screen demo / tutorial | 640 px | 10 | 64 | No dithering | 1 – 3 MB |
| Maximum quality, size not a concern | 720 px | 20 | 256 | High | 10 – 30 MB |

### Special cases

- **Screen recordings, drawings, text:** use **"No dithering"** and few
  colors. These images have flat areas that compress very well — dithering
  would only get in the way. You can get tiny files with perfect quality.
- **Sky, smoke, shadows, skin:** these are gradients, the GIF's worst case.
  Here it's worth raising the dither to "High" and accepting a bigger file
  — or lowering the resolution, which disguises the problem.
- **Static background with a moving object:** try the **"Motion-focused"**
  palette.
- **Scene that changes completely midway:** a single palette will get the
  colors wrong in one of the halves. Either use **"Palette per frame"**, or
  — better — split it into two GIFs.

### How to tell if the size is good

The app already classifies it, but here's the ruler:

| Size | Classification | In practice |
|---|---|---|
| up to 2 MB | Light | sends anywhere |
| 2 – 6 MB | Good | comfortable on social media and WhatsApp |
| 6 – 15 MB | Heavy | slow to load, some apps re-compress it |
| above 15 MB | Very heavy | many apps refuse it or ruin the quality |

And the single most useful number of all: **size per second**. If a GIF is
at 2 MB/s, no color tweak is going to save it — the fix is cutting the
duration or the resolution.

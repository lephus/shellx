### Task 9: App icon from the ShellX logo

**Files (fork):**
- Create: `design/shellx-logo.svg` (copy of shellx repo `web/public/favicon.svg`)
- Create: `scripts/shellx/gen_app_icons.sh` (`rsvg-convert` → every size of `Assets.xcassets/AppIcon.appiconset` light and `_dark`, `AppIcon-Debug.appiconset` with a "DEV" band drawn by `magick`, `AppIconLight`/`AppIconDark` imagesets, and `ShellXLogo` imageset for About/sidebar)
- Modify: `Assets.xcassets/AppIcon.appiconset/*`, `AppIcon-Debug.appiconset/*`, `AppIconLight`, `AppIconDark`, new `ShellXLogo.imageset`
- Test: `tests/test_shellx_app_icon.py`

**Interfaces:**
- Produces: image asset `ShellXLogo` (vector PDF or 1024 px PNG) used by About (Task 6) and the sidebar header (Task 10).

- [ ] **Step 1: Write the failing test**

```python
def test_app_icon_sizes():
    contents = json.load(open("Assets.xcassets/AppIcon.appiconset/Contents.json"))
    for img in contents["images"]:
        w, h = png_size(f"Assets.xcassets/AppIcon.appiconset/{img['filename']}")
        side = int(float(img["size"].split("x")[0]) * int(img["scale"][0]))
        assert (w, h) == (side, side), img["filename"]
def test_logo_source_matches_web():
    assert sha256("design/shellx-logo.svg") == EXPECTED_SHA256   # sha of shellx web/public/favicon.svg at copy time
```

- [ ] **Step 2: Run** — Expected: FAIL (old icons or missing logo).

- [ ] **Step 3: Write and run `gen_app_icons.sh`.**

- [ ] **Step 4: Run the test** — Expected: PASS. Build `--tag w1`; the Dock shows the "> <" logo.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(shellx): app icon and logo assets from the shellx.pro logo"
```


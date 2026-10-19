### Task 12: Vietnamese

**Files (fork):**
- Modify: `cmux.xcodeproj/project.pbxproj:14328` (`knownRegions` += `vi`)
- Modify: `scripts/localization_catalog.py:18` (`LOCALES` += `"vi"`)
- Modify: `Resources/Localizable.xcstrings` (~8,400 keys), `InfoPlist.xcstrings` (29), `ConfigPackErrors.xcstrings`, the 10 package catalogs — add `vi`
- Create: `scripts/shellx/l10n/vi-glossary.md`, `scripts/shellx/l10n/export_missing.py`, `scripts/shellx/l10n/import_translations.py`
- Test: existing localization tests + `tests/test_shellx_vi.py`

**Interfaces:**
- Consumes: all strings added in Tasks 6, 10, 11.
- Produces: `vi` complete in every catalog; `AppLanguage.vi` (already in `Packages/macOS/CmuxSettings/.../AppLanguage.swift:6`) now shows translated UI.

Glossary (binding): workspace → "phiên"; pane → "khung"; split → "chia khung"; tab/surface → "tab"; sidebar → "thanh bên"; command palette → "bảng lệnh"; notification → "thông báo"; agent → "agent"; browser → "trình duyệt"; machine → "máy"; settings → "Cài đặt"; terminal → "terminal"; keep `ShellX`, command names, file paths, key caps and `%@`/`%lld` placeholders verbatim and in the same order.

- [ ] **Step 1: Write the failing test**

```python
def test_vi_is_complete_and_placeholders_match():
    for path in CATALOGS:
        cat = json.load(open(path))
        for key, entry in cat["strings"].items():
            if entry.get("shouldTranslate") is False: continue
            vi = value(entry, "vi"); en = value(entry, "en")
            assert vi, f"{path}:{key} missing vi"
            assert placeholders(vi) == placeholders(en), f"{path}:{key}"
def test_key_shellx_strings_read_naturally():
    assert value_of("sidebar.pill.waiting", "vi") == "chờ bạn"
    assert value_of("sidebar.machine.thisMac", "vi") == "máy này"
```

- [ ] **Step 2: Run** `python3 -m pytest tests/test_shellx_vi.py -q` — Expected: FAIL.

- [ ] **Step 3: Translate in batches.** `export_missing.py` writes batches of ≤ 300 keys (key, English, comment) to JSON; translate each batch following the glossary (parallel agents are fine; each batch is independent); `import_translations.py` merges them, refusing any entry whose placeholders differ. Then read through the ~300 most visible strings (menus, sidebar, settings top level, notifications, title bar, About) as a Vietnamese user and fix awkward wording.

- [ ] **Step 4: Run** `python3 -m pytest tests/test_shellx_vi.py tests/test_localizable_xcstrings_structure.py tests/test_localization_catalog.py tests/test_localization_defaults.py tests/test_lint_xcstrings.py -q` and `python3 scripts/localization_catalog.py check` — Expected: PASS. Switch the app language to Tiếng Việt and check the sidebar, menus and settings.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(shellx): Vietnamese localization"
```


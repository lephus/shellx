# Task 12 one-off: builds task12/vi-fixes.json ({unit id: vi}) from the read-through inputs.
# Run from the repo root; import_translations.py --map consumes the output.
import json, os, sys
sys.path.insert(0, "scripts/shellx/l10n")
import export_missing as X
HERE = os.path.dirname(os.path.abspath(__file__))
L10N = os.path.dirname(HERE)
sys.path.insert(0, "scripts/shellx/l10n")
import import_translations as I
staged = I.load_staged(__import__("pathlib").Path(L10N))
key_fixes = json.load(open(f"{HERE}/key-fixes.json"))
alias = json.load(open(f"{HERE}/alias-suffixes.json"))
alias.update({
    "alias.setting.app.accent-color": "màu nhấn tô sáng màu phủ xanh tím màu nhấn hệ thống xanh ShellX",
    "alias.setting.keyboardShortcuts.shortcut-chords": "tiền tố chuỗi phím tổ hợp nhiều phím",
    "alias.setting.keyboardShortcuts.shortcuts": "phím tắt gán phím lệnh bàn phím",
    "alias.setting.networking.relayPreference": "ưu tiên relay tự động được quản lý đã chọn nhà cung cấp khu vực tài khoản",
    "alias.setting.settingsJSON.documentation": "tài liệu tham khảo lược đồ khóa cấu hình",
    "alias.setting.settingsJSON.open-file": "mở tệp cấu hình trình soạn thảo tùy chọn",
})
out = {}
for path, rel in X.covered_catalogs():
    strings = json.load(open(path))["strings"]
    for key, entry in strings.items():
        en = entry["localizations"]["en"]
        for suffix, source in X.source_units(en):
            uid = f"{rel}::{key}::{suffix}"
            if suffix == "value" and key in key_fixes:
                out[uid] = key_fixes[key]
            elif suffix == "value" and key.startswith("settings.search.") and key[len("settings.search."):] in alias:
                out[uid] = source + " " + alias[key[len("settings.search."):]]
            elif uid in staged:
                vi = staged[uid]["vi"]
                fixed = vi
                if source.startswith("[ShellX]"):
                    for bad in ("[shellx]", "[cmux]"):
                        if fixed.startswith(bad):
                            fixed = "[ShellX]" + fixed[len(bad):]
                fixed = fixed.replace("Cloud Machines", "Máy Cloud")
                if fixed != vi:
                    out[uid] = fixed
missing = [k for k in key_fixes if not any(u.split("::")[1] == k for u in out)]
print(len(out), "fixes; key fixes not found:", missing)
json.dump(out, open(f"{HERE}/vi-fixes.json", "w"), ensure_ascii=False, indent=1)

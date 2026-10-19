# SF Symbol to coolicon map (Task 8, spec §7.4 and §15)

Every literal SF Symbol name the macOS app used before the coolicons codemod
(`scripts/shellx/icon-literal-symbols.txt`) and the coolicon `ShellXIcon` draws
for it. `Packages/Shared/ShellXBrand/Sources/ShellXIcons/Resources/icon-map.json`
holds the same pairs; `tests/test_shellx_icons.py` keeps the two identical.

- **same**: the coolicon draws the same thing. coolicons are outline-only, so
  an SF `.fill` symbol maps to the outline coolicon (the call site's tint and
  size are unchanged).
- **nearest**: coolicons has no equivalent; the closest coolicon by meaning,
  with the reason (spec §15: "icon thay thế khi coolicons không có icon phù hợp").
- **derived**: not in the v4.1 set; built by `scripts/shellx/import_coolicons.py`
  from a coolicon (see `DERIVED` there and the `NOTICE` next to the catalog).

Names that are not in this table come from user configuration (custom
commands, workspace group icons, `sidebar.compactStatusIcons`, custom
sidebars) and are drawn as the SF Symbol of that name (Review Focus 3).

| SF Symbol | coolicon | match | note |
| --- | --- | --- | --- |
| `1.magnifyingglass` | `Search_Magnifying_Glass` | nearest | PDF actual size: no 1:1 zoom glyph, plain magnifier |
| `accessibility` | `User_Circle` | nearest | no accessibility glyph; person in a circle |
| `app.dashed` | `Dummy_Square` | nearest | no dashed app tile; placeholder square |
| `app.fill` | `Window` | nearest | application target: an app window |
| `apple.logo` | `Mobile` | nearest | no Apple logo (brand mark); the badge downloads the iPhone app |
| `applelogo` | `Command` | nearest | no Apple logo; the command key marks the Mac menu bar in theme thumbnails |
| `applewatch` | `Clock` | nearest | no watch; a watch face |
| `arrow.clockwise` | `Arrows_Reload_01` | same | reload / retry |
| `arrow.counterclockwise` | `Undo` | same | reset / restore |
| `arrow.counterclockwise.circle.fill` | `Undo` | nearest | no circled undo |
| `arrow.down.circle` | `Arrow_Circle_Down` | same |  |
| `arrow.down.to.line` | `Download` | same |  |
| `arrow.left` | `Arrow_Left_MD` | same |  |
| `arrow.left.arrow.right` | `Arrow_Left_Right` | same |  |
| `arrow.right` | `Arrow_Right_MD` | same |  |
| `arrow.right.circle` | `Arrow_Circle_Right` | same |  |
| `arrow.triangle.2.circlepath` | `Arrow_Reload_02` | same | sync / checking |
| `arrow.triangle.branch` | `Path` | nearest | no git-branch glyph; two joined nodes |
| `arrow.trianglehead.2.clockwise` | `Arrow_Reload_02` | same |  |
| `arrow.up` | `Arrow_Up_MD` | same |  |
| `arrow.up.and.down.and.arrow.left.and.right` | `Move` | same |  |
| `arrow.up.circle.fill` | `Arrow_Circle_Up` | same |  |
| `arrow.up.forward` | `Arrow_Up_Right_MD` | same |  |
| `arrow.up.left.and.arrow.down.right` | `Expand` | same | zoom to fit / expand |
| `arrow.up.right` | `Arrow_Up_Right_MD` | same |  |
| `arrowtriangle.right.fill` | `Play` | nearest | no solid triangle; play outline (progress status) |
| `bell` | `Bell` | same |  |
| `bell.badge` | `Bell_Notification` | same |  |
| `bell.fill` | `Bell_Ring` | nearest | no filled bell; ringing bell for an active notification |
| `bell.slash` | `Bell_Off` | same |  |
| `bell.slash.fill` | `Bell_Off` | same |  |
| `bolt` | `Play` | nearest | no lightning bolt; start / run |
| `bolt.fill` | `Play` | nearest | no lightning bolt; running / working status |
| `bolt.slash` | `Stop_Circle` | nearest | no struck-out bolt; stopped |
| `book` | `Book` | same |  |
| `books.vertical` | `Archive` | nearest | Vault (stored sessions): an archive box |
| `brain.head.profile` | `Bulb` | nearest | no brain; a bulb for the thinking agent |
| `bubble.left` | `Chat` | same |  |
| `bubble.left.and.bubble.right` | `Chat_Conversation` | same |  |
| `bubble.left.and.text.bubble.right` | `Chat_Conversation` | same |  |
| `button.programmable` | `Mobile_Button` | nearest | simulator side button: a phone with a button |
| `calendar` | `Calendar` | same |  |
| `camera` | `Camera` | same |  |
| `camera.viewfinder` | `Camera` | nearest | screenshot: camera |
| `character.cursor.ibeam` | `Text` | nearest | text input: the text glyph |
| `checklist` | `List_Checklist` | same |  |
| `checkmark` | `Check` | same |  |
| `checkmark.circle` | `Circle_Check` | same |  |
| `checkmark.circle.fill` | `Circle_Check` | same |  |
| `checkmark.shield` | `Shield_Check` | same |  |
| `checkmark.shield.fill` | `Shield_Check` | same |  |
| `checkmark.square` | `Checkbox_Check` | same |  |
| `checkmark.square.fill` | `Checkbox_Check` | same |  |
| `chevron.down` | `Chevron_Down` | same |  |
| `chevron.left` | `Chevron_Left` | same |  |
| `chevron.left.forwardslash.chevron.right` | `Code` | same |  |
| `chevron.left.slash.chevron.right` | `Code` | same |  |
| `chevron.right` | `Chevron_Right` | same |  |
| `chevron.up` | `Chevron_Up` | same |  |
| `circle` | `Circle` | same |  |
| `circle.dashed` | `Loading` | nearest | pending: no dashed circle, loading dots |
| `circle.fill` | `Circle_Fill` | derived | status dots: coolicons Circle with its inside filled (no solid circle in the set) |
| `circle.lefthalf.filled` | `Monitor` | nearest | browser theme 'system': follow the display |
| `clock` | `Clock` | same |  |
| `cloud` | `Cloud` | same |  |
| `cloud.fill` | `Cloud` | same |  |
| `crop` | `Crop` | same |  |
| `crown` | `Star` | nearest | no crown; a star for Pro |
| `cup.and.saucer.fill` | `Coffee` | same | keep awake |
| `curlybraces` | `Code` | nearest | no curly braces; code brackets |
| `curlybraces.square` | `Window_Code_Block` | nearest | no braces in a square; code in a window |
| `cursorarrow` | `Navigation` | nearest | pointer arrow |
| `cursorarrow.click` | `Mouse` | nearest | clickable element: mouse |
| `cursorarrow.motionlines` | `Navigation` | nearest | agent moving the pointer: pointer arrow |
| `cursorarrow.rays` | `Mouse` | nearest | computer use: mouse |
| `desktopcomputer` | `Desktop` | same |  |
| `display` | `Monitor` | same |  |
| `doc` | `File_Blank` | same |  |
| `doc.badge.questionmark` | `File_Close` | nearest | not a valid SF Symbol (the Vault status row drew nothing); drawn like doc.questionmark |
| `doc.fill` | `File_Blank` | same |  |
| `doc.on.clipboard` | `Copy` | nearest | copy to clipboard: copy |
| `doc.on.doc` | `Copy` | same |  |
| `doc.plaintext` | `File_Document` | same |  |
| `doc.questionmark` | `File_Close` | nearest | missing or unreadable file: file with a cross |
| `doc.richtext` | `File_Document` | same |  |
| `doc.text` | `File_Document` | same |  |
| `doc.text.magnifyingglass` | `File_Search` | same |  |
| `doc.viewfinder` | `File_Search` | nearest | file preview: file with a magnifier |
| `dock.rectangle` | `Bar_Bottom` | nearest | Dock: a window with a bottom bar |
| `dot.radiowaves.left.and.right` | `Wifi_High` | nearest | no broadcast waves; the wifi waves (Feed, nearby devices) |
| `ellipsis` | `More_Horizontal` | same |  |
| `ellipsis.circle` | `More_Horizontal` | nearest | no circled ellipsis |
| `exclamationmark.circle` | `Circle_Warning` | same |  |
| `exclamationmark.icloud` | `Cloud_Close` | nearest | cloud error: cloud with a cross |
| `exclamationmark.shield` | `Shield_Warning` | same |  |
| `exclamationmark.triangle` | `Triangle_Warning` | same |  |
| `exclamationmark.triangle.fill` | `Triangle_Warning` | same |  |
| `externaldrive` | `Data` | nearest | storage: stacked disks |
| `eye` | `Show` | same |  |
| `flag` | `Flag` | same |  |
| `folder` | `Folder` | same |  |
| `folder.badge.gearshape` | `Folder_Code` | nearest | synchronized (managed) folder: code folder |
| `folder.fill` | `Folder` | same |  |
| `forward.end.fill` | `Skip_Forward` | same |  |
| `gearshape` | `Settings` | same |  |
| `gearshape.2` | `Settings_Future` | nearest | two gears: the other gear |
| `gearshape.fill` | `Settings` | same |  |
| `globe` | `Globe` | same |  |
| `globe.americas.fill` | `Globe` | same |  |
| `hammer` | `Suitcase` | nearest | no hammer; a tool case for build |
| `hammer.circle` | `Suitcase` | nearest | no hammer; a tool case |
| `hammer.fill` | `Suitcase` | nearest | no hammer; a tool case for build |
| `hourglass` | `Timer` | nearest | no hourglass; a timer for waiting |
| `house` | `House_01` | same |  |
| `icloud.and.arrow.up` | `Cloud_Upload` | same |  |
| `icloud.slash` | `Cloud_Off` | same |  |
| `info.circle` | `Info` | same |  |
| `ipad` | `Tablet` | same |  |
| `iphone` | `Mobile` | same |  |
| `iphone.gen3` | `Mobile_Button` | same | phone with a home button |
| `iphone.slash` | `Mobile` | nearest | no struck-out phone |
| `key` | `Lock` | nearest | no key; a lock for credentials |
| `keyboard` | `Keyboard` | same |  |
| `keyboard.badge.ellipsis` | `Keyboard` | nearest | hotkey / recording: no badge |
| `ladybug` | `Code` | nearest | no bug; code (developer tools icon option) |
| `ladybug.fill` | `Code` | nearest | no bug; code (developer tools icon option) |
| `laptopcomputer` | `Laptop` | same |  |
| `largecircle.fill.circle` | `Radio_Fill` | same | selected radio button |
| `leaf` | `Leaf` | same |  |
| `leaf.fill` | `Leaf` | same |  |
| `line.3.horizontal` | `Hamburger_MD` | same | drag handle |
| `line.3.horizontal.decrease.circle` | `Filter` | nearest | filter (no circled variant) |
| `line.3.horizontal.decrease.circle.fill` | `Filter` | nearest | active filter: same glyph, the call site tints it |
| `link` | `Link` | same |  |
| `list.bullet` | `List_Unordered` | same |  |
| `list.bullet.rectangle` | `List_Unordered` | nearest | plan / property list: a list |
| `lock` | `Lock` | same |  |
| `lock.fill` | `Lock` | same |  |
| `lock.shield` | `Shield` | nearest | permission request / entitlements: shield |
| `lock.slash` | `Lock_Open` | nearest | not locked: open lock |
| `macwindow` | `Window` | same |  |
| `magnifyingglass` | `Search_Magnifying_Glass` | same |  |
| `memorychip` | `Data` | nearest | no memory chip; stacked storage |
| `message` | `Chat` | same |  |
| `mic.fill` | `User_Voice` | nearest | no microphone; a person speaking |
| `minus` | `Remove_Minus` | same |  |
| `minus.circle` | `Remove_Minus_Circle` | same |  |
| `minus.circle.fill` | `Remove_Minus_Circle` | same |  |
| `minus.magnifyingglass` | `Magnifying_Glass_Minus` | same |  |
| `minus.square` | `Add_Minus_Square` | same |  |
| `moon` | `Moon` | same |  |
| `moon.fill` | `Moon` | same |  |
| `moon.zzz` | `Moon` | nearest | sleep: moon (no zzz) |
| `network` | `Globe` | nearest | no network nodes; globe |
| `network.slash` | `Wifi_Off` | nearest | no network: wifi off |
| `paintbrush` | `Swatches_Palette` | nearest | themes: palette swatches |
| `paintbrush.pointed` | `Edit_Pencil_01` | nearest | design mode: pen |
| `paintbrush.pointed.fill` | `Edit_Pencil_Line_01` | nearest | design mode on: pen over a line (no filled pen) |
| `paintpalette` | `Swatches_Palette` | same |  |
| `paperclip` | `Paperclip_Attechment_Tilt` | same |  |
| `pause.circle` | `Pause_Circle` | same |  |
| `pause.circle.fill` | `Pause_Circle` | same |  |
| `pause.fill` | `Pause` | same |  |
| `person` | `User_01` | same |  |
| `person.2` | `Users` | same |  |
| `person.badge.plus` | `User_Add` | same |  |
| `person.crop.circle` | `User_Circle` | same |  |
| `person.crop.circle.badge.exclamationmark` | `User_Close` | nearest | account problem: user with a cross |
| `person.crop.circle.badge.plus` | `User_Add` | nearest | add account: no circled variant |
| `person.crop.circle.fill` | `User_Circle` | same |  |
| `person.fill` | `User_01` | same |  |
| `photo` | `Image_01` | same |  |
| `pin.fill` | `Map_Pin` | nearest | no push pin; the map pin |
| `play.circle` | `Play_Circle` | same |  |
| `play.fill` | `Play` | same |  |
| `play.rectangle` | `Monitor_Play` | nearest | scheme / video: screen with play |
| `play.rectangle.fill` | `Monitor_Play` | nearest | scheme / video: screen with play |
| `plus` | `Add_Plus` | same |  |
| `plus.circle` | `Add_Plus_Circle` | same |  |
| `plus.magnifyingglass` | `Magnifying_Glass_Plus` | same |  |
| `plus.square` | `Add_Plus_Square` | same |  |
| `point.3.filled.connected.trianglepath.dotted` | `Share_Android` | nearest | subagents: three connected nodes |
| `power.circle` | `Arrows_Reload_01` | nearest | no power glyph; installing an update relaunches |
| `printer` | `Printer` | same |  |
| `puzzlepiece.extension` | `Puzzle` | same |  |
| `qrcode` | `Qr_Code` | same |  |
| `questionmark` | `Help` | same |  |
| `questionmark.bubble` | `Circle_Help` | nearest | agent question: no question bubble |
| `questionmark.circle` | `Circle_Help` | same |  |
| `questionmark.circle.fill` | `Circle_Help` | same |  |
| `questionmark.square` | `Square_Help` | same |  |
| `questionmark.square.dashed` | `Square_Help` | nearest | unknown symbol placeholder: no dashed square |
| `rectangle.3.group` | `Layers` | nearest | interface file: stacked layers |
| `rectangle.bottomhalf.inset.filled` | `Bar_Bottom` | nearest | split down: window with a bottom bar |
| `rectangle.connected.to.line.below` | `Window_Terminal` | nearest | terminal tab: terminal window |
| `rectangle.on.rectangle` | `Copy` | nearest | two rectangles |
| `rectangle.portrait.and.arrow.right` | `Log_Out` | nearest | sign out / move out: arrow leaving a box |
| `rectangle.portrait.on.rectangle.portrait` | `Layers` | nearest | a workspace: stacked layers |
| `rectangle.righthalf.inset.filled` | `Bar_Right` | nearest | split right: window with a right bar |
| `rectangle.split.2x1` | `Columns` | nearest | split layout: two columns |
| `rectangle.stack` | `Layers` | nearest | workspace: stacked layers |
| `rectangle.stack.badge.play` | `Move` | nearest | move tab: move arrows |
| `rectangle.stack.badge.plus` | `Add_To_Queue` | nearest | new workspace: stack with a plus |
| `rotate.left` | `Undo` | nearest | rotate left: counter-clockwise arrow |
| `rotate.right` | `Redo` | nearest | rotate right: clockwise arrow |
| `safari` | `Compass` | same | Safari's compass |
| `scope` | `Radio_Fill` | nearest | no crosshair; ring with a dot as the target |
| `scribble` | `Edit_Pencil_Line_02` | nearest | draw / annotate: pen |
| `shippingbox` | `Archive` | nearest | package: a box |
| `shippingbox.fill` | `Download_Package` | nearest | update / bundle package |
| `sidebar.left` | `Window_Sidebar` | same |  |
| `sidebar.right` | `Bar_Right` | nearest | right sidebar: window with a right bar |
| `sidebar.squares.left` | `Window_Sidebar` | nearest | custom sidebars: sidebar window |
| `slider.horizontal.3` | `Slider_02` | same |  |
| `sparkle` | `Star` | nearest | no sparkle; a star |
| `sparkle.magnifyingglass` | `Search_Magnifying_Glass` | nearest | smart search: magnifier |
| `sparkles` | `Star` | nearest | no sparkles; a star |
| `sparkles.rectangle.stack` | `Star` | nearest | agent sessions: a star |
| `speaker.minus` | `Volume_Minus` | same |  |
| `speaker.plus` | `Volume_Plus` | same |  |
| `speaker.wave.2` | `Volume_Max` | same |  |
| `speaker.wave.2.fill` | `Volume_Max` | same |  |
| `square` | `Checkbox_Unchecked` | same | unchecked box |
| `square.and.arrow.down` | `Save` | nearest | save to disk: floppy |
| `square.and.arrow.down.on.square` | `Download` | nearest | download: arrow to line |
| `square.and.arrow.up` | `Share_iOS_Export` | same |  |
| `square.dashed` | `Dummy_Square` | nearest | unknown element: placeholder square |
| `square.grid.2x2` | `More_Grid_Small` | nearest | gallery: grid |
| `square.on.square` | `Copy` | nearest | two squares (app switcher) |
| `square.on.square.dashed` | `Copy` | nearest | canvas layout: overlapping squares |
| `square.split.1x2` | `Rows` | nearest | split down: two rows |
| `square.split.2x1` | `Columns` | nearest | split right: two columns |
| `square.stack` | `Layers` | nearest | several tabs: stacked layers |
| `stop.circle` | `Stop_Circle` | same |  |
| `sun.max` | `Sun` | same |  |
| `swift` | `File_Code` | nearest | no Swift logo; a code file |
| `table` | `Table` | same |  |
| `tablecells` | `Table` | same |  |
| `tag` | `Tag` | same |  |
| `terminal` | `Terminal` | same |  |
| `terminal.fill` | `Terminal` | same |  |
| `testtube.2` | `List_Check` | nearest | no test tube; a checked list for tests |
| `text.alignleft` | `Text_Align_Left` | same |  |
| `text.bubble` | `Chat_Dots` | nearest | speech bubble with text |
| `text.viewfinder` | `Text` | nearest | copy screen text: the text glyph |
| `textformat` | `Font` | same | Aa |
| `textformat.size` | `Heading` | nearest | text size / headings: H |
| `translate` | `Globe` | nearest | no translate glyph; globe for language |
| `trash` | `Trash_Full` | same | bin with lines, like SF trash |
| `tray.full` | `Archive` | nearest | inbox: an archive box |
| `video` | `Camera` | nearest | no video camera; camera |
| `video.fill` | `Camera` | nearest | camera in use: camera |
| `viewfinder` | `Crop` | nearest | screenshot area: corner brackets |
| `wand.and.sparkles` | `Star` | nearest | no wand; a star (automation) |
| `wand.and.stars` | `Main_Component` | nearest | custom sidebar: a component |
| `wifi.slash` | `Wifi_Off` | same |  |
| `wrench.and.screwdriver` | `Window_Code_Block` | nearest | developer tools: window with code (no tools glyph) |
| `wrench.and.screwdriver.fill` | `Window_Code_Block` | nearest | developer tools: window with code (no tools glyph) |
| `xmark` | `Close_MD` | same |  |
| `xmark.circle` | `Close_Circle` | same |  |
| `xmark.circle.fill` | `Close_Circle` | same |  |
| `xmark.octagon` | `Stop_Sign` | nearest | force stop: stop sign |
| `xmark.rectangle` | `Window_Close` | nearest | exited: window with a cross |

## Not covered yet

The pane tab bar comes from the vendored Bonsplit package (`vendor/bonsplit`),
which draws its own SF Symbols: tab icons (`createTab(icon:)` names such as
`terminal`, `globe`, `rectangle.connected.to.line.below`), the pin, close,
mute and zoom glyphs on a tab, and the tab-bar buttons configured through
`CmuxButtonIcon.systemImage`. Moving those to coolicons needs an icon hook in
Bonsplit (for example a resolver closure on `BonsplitConfiguration` that the
app sets to `ShellXIcon.image`) and a submodule bump; it is outside the
`Sources/` and `Packages/` codemod.

from pathlib import Path

from docx import Document
from docx.enum.section import WD_SECTION
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Inches, Pt, RGBColor


OUT = Path(__file__).with_name("Remote_Controller_Finalization_Plan.docx")


PAGES = [
    {
        "title": "Page 1 - Final Product Mission, Failure List, and Release Bar",
        "body": [
            "This project is no longer treated as a prototype. The release target is a local Wi-Fi phone remote controller that feels dependable enough to hand to another person, launch without instructions beyond the package guide, and use for ordinary laptop work without fighting the controls. The current failure is not that the app has no features; it is that several features behave like separate experiments. The finishing pass must unify them into one coordinate system, one input model, one polished phone layout, and one speed profile that is honest about what a free Node local-network version can do.",
            "The top priority is fixing the phone display cursor. The actual Windows cursor reaches the taskbar, but the phone overlay appears to glitch or stop near the bottom. That means input is reaching the laptop while visual feedback is wrong. The implementation must stop guessing from only the screenshot frame and instead use a verified coordinate chain: Windows cursor position, selected monitor logical bounds, selected monitor physical capture size, DPI scale, canvas draw rectangle, viewport crop, zoom pan, and the final phone pixel position. If any link cannot be trusted, diagnostics must expose it on the host and in a hidden debug state so the bug can be reproduced without guessing.",
            "The second priority is turning zoom into a real usability feature. The user needs a toggle that enlarges the area around the mouse, follows the cursor when zoomed, and can be disabled instantly when manual navigation is better. This is not just a checkbox; it requires a viewport controller that keeps the cursor comfortably inside a safe zone, pans near screen edges, avoids jitter, and clamps correctly on every monitor size.",
            "The third priority is making touchpad control feel finished. Relative movement must be faster, more predictable, and adjustable. Single tap should left click, double tap should right click, press and hold should right click as an alternate path, double tap then drag should hold left click so tabs and windows can move, and edge-hold should keep moving like a joystick. These gestures need timing thresholds, haptic feedback, cancellation rules, and tests.",
            "The final release bar is simple: the phone screen must match where the laptop cursor really is; zoom-follow must visibly work; multi-monitor switching must preserve accuracy; the UI must feel premium and minimal; the package must launch cleanly; and the tests must protect these behaviors before we call it publishable.",
        ],
        "goals": [
            "Define final release as a usable local Wi-Fi controller, not a demo.",
            "Treat the cursor-bottom glitch as a coordinate-system defect until proven otherwise.",
            "Make zoom-follow, touchpad gestures, multi-monitor accuracy, speed, and packaging mandatory release gates.",
        ],
    },
    {
        "title": "Page 2 - Coordinate Truth Layer and Bottom-Cursor Defect Fix",
        "body": [
            "The coordinate truth layer is the most important engineering cleanup. Right now the app has several coordinate spaces: host monitor bounds, screenshot dimensions, input library cursor coordinates, phone canvas CSS pixels, device pixel ratio, zoom crop coordinates, and touchpad hint coordinates. The bottom-cursor bug proves that at least two of these spaces are being mixed. The fix is to create a single shared conversion module on the phone side and a matching host-side contract. Every cursor draw, direct-touch point, zoom center, and follow target must pass through that contract.",
            "The host stream frame should include explicit monitor geometry for the selected display: logical bounds, physical capture width and height, scale factor, source id, and an optional cursor point with a declared coordinateSpace value. If the cursor provider reports logical pixels, the payload must say logical. If it reports physical pixels, the payload must say physical. If the app cannot know, it should send both the raw point and the inferred point, then the client can prefer the calibrated one. This avoids the current silent guessing where a 125 percent Windows scale makes the drawn cursor look like it cannot reach the taskbar.",
            "The phone client will add a function named conceptually `mapHostCursorToFrame(cursor, monitor, frame)`. It will convert the cursor to physical frame coordinates, clamp it only at the actual frame edge, and return normalized x/y for the viewport. Clamping must be a last step and must never hide a scaling error. When the cursor reaches the Windows taskbar, the normalized y must approach 1.0 and the rendered dot must reach the bottom of the captured screen area on the phone.",
            "The display renderer must also stop using stale frame dimensions when monitor data exists. The selected monitor’s physical capture size is the authoritative visual size. The screenshot bitmap natural size is a validation signal. If they disagree, diagnostics should record the mismatch and the renderer should use the bitmap dimensions for drawImage while mapping cursor coordinates through the calibrated ratio. This protects against screenshot libraries that return compressed images with dimensions that do not perfectly match reported monitor bounds.",
            "Tests must simulate 100 percent, 125 percent, 150 percent, portrait monitors, negative monitor origins, stacked displays, and a cursor at each corner including the bottom taskbar edge. The pass condition is not merely that input works; the phone overlay must visually map to the same edge.",
        ],
        "goals": [
            "Add an explicit host-to-phone coordinate contract with coordinate space metadata.",
            "Fix cursor drawing at the bottom edge on scaled Windows displays.",
            "Add tests for every monitor edge and common DPI scale.",
        ],
    },
    {
        "title": "Page 3 - Multi-Monitor Selection, Resolution Accuracy, and Calibration",
        "body": [
            "Multi-monitor support must become predictable rather than decorative. The monitor selector needs to show each display with its true relative layout, resolution, scaling, orientation, and selected state. When the user switches displays, the stream, input mapping, cursor overlay, zoom viewport, and touchpad hint should all reset or transfer intentionally. A selected display change should never leave the zoom pan or cursor from the previous display active.",
            "The host should expose a monitor audit object for each display. That object should include bounds, scaleFactor, captureSize, primary flag, sourceId, and whether the capture backend returned a matching screenshot. If the display is 2560 by 1440 at 125 percent scaling, the app must know which values are logical and which are physical. If the input adapter uses logical coordinates while the screenshot uses physical pixels, the conversion must be done once in the coordinate layer rather than patched separately inside drawing and input code.",
            "A lightweight calibration screen should be available from Settings, but it should not be required for normal use. Calibration mode will show four target zones on the phone display: top-left, top-right, bottom-left, bottom-right. The user can move the cursor to each target or tap a confirm button while the host reads the real cursor position. From those samples the app can compute whether the cursor provider is logical, physical, offset, or inverted by a source mismatch. The result should be stored per monitor id and invalidated if resolution, source id, or scale factor changes.",
            "The client should also expose a hidden debug snapshot for us while building: selectedMonitorId, frame width/height, bitmap natural width/height, monitor logical bounds, monitor scale factor, cursor raw host point, cursor converted frame point, viewport zoom, pan x/y, canvas draw rectangle, and final canvas cursor x/y. This will let us test the reported glitch directly instead of relying on a screenshot and vibes.",
            "Acceptance for multi-monitor is concrete. On each display, cursor overlay reaches all four corners; direct-touch taps land where they appear; touchpad relative motion is independent of display size; zoom-follow does not jump after switching monitors; and the monitor sheet stays minimal with only the controls needed to select the display and understand its dimensions.",
        ],
        "goals": [
            "Make monitor data explicit, visible, and testable.",
            "Reset or transfer state cleanly on display change.",
            "Add optional per-monitor calibration for stubborn Windows/backend mismatches.",
        ],
    },
    {
        "title": "Page 4 - Zoom, Mouse-Follow, Edge Pan, and Cursor Magnification",
        "body": [
            "Zoom must be rebuilt as a viewport controller, not a loose range slider. The user needs three related behaviors: pinch-to-zoom around the point being touched, automatic mouse follow when enabled, and a visible enlargement around the cursor so the phone screen becomes easier to inspect. The current follow behavior is not enough because it may pan the viewport without making the area around the cursor feel intentionally enlarged.",
            "The new design should have a clear Follow toggle in the bottom rail and a matching setting. When Follow is on and zoom is above 100 percent, the viewport should keep the cursor inside a central safe rectangle. If the cursor approaches the left edge, pan horizontally toward the cursor. If it approaches the bottom taskbar, pan vertically until the cursor is comfortably visible unless the viewport is already clamped at the real bottom. If only one axis needs adjustment, only that axis should move. The movement should use smoothing so it feels attracted to the cursor, but it must snap faster when the cursor is almost out of view.",
            "The enlargement feature should support two modes. The first mode is normal zoom-follow, where the entire display canvas is zoomed into the cursor region. The second is a cursor lens overlay, a small circular or rounded rectangular magnifier around the cursor when the overall zoom is still 100 percent. The lens should be optional because it costs rendering work. It should use the already received frame image, crop a small source rectangle around the cursor, draw it enlarged on top of the stream, and keep the cursor dot visible but not oversized.",
            "Pinch zoom should center on the midpoint between the fingers, not randomly around the current viewport. Mouse-follow should not fight active two-finger panning; while the user is manually panning, follow should pause for a short cooldown and then resume. This prevents the app from feeling like it is pulling against the user.",
            "Acceptance is visual. When the cursor moves toward the taskbar while zoomed, the phone display should pan down until the cursor is centered or clamped correctly at the true bottom. When Follow is off, zoom should behave manually. When Lens is on, the area around the cursor should visibly enlarge even without full-screen zoom.",
        ],
        "goals": [
            "Build one viewport controller for pinch, pan, follow, and clamping.",
            "Add a Follow toggle that visibly centers or attracts toward the mouse.",
            "Add an optional cursor lens/magnifier that enlarges the mouse area.",
        ],
    },
    {
        "title": "Page 5 - Touchpad, Mouse Speed, Gestures, and Dragging",
        "body": [
            "The touchpad should feel like a laptop trackpad, not a debug box. The core mode is relative movement: dragging a finger moves the laptop cursor by a scaled delta. The movement curve should be faster by default, with mild acceleration for long swipes and precision mode for small adjustments. The app needs to distinguish between deliberate movement, taps, long presses, double taps, and double-tap drags without making the user think about modes.",
            "The speed model should use three inputs: base sensitivity, acceleration, and precision modifier. Base sensitivity is the slider value. Acceleration increases movement when the finger is moving quickly or the edge-hold joystick is active. Precision mode lowers the curve for careful placement. The default should be fast enough that crossing a 2560 pixel screen does not require endless swiping, but still stable enough to click small UI controls. The settings sheet should show Sensitivity with a practical range and possibly a simple Fast / Balanced / Precise segmented control later.",
            "Gestures should be finalized as follows. Single tap sends a left click. Double tap sends a right click unless the second tap becomes a drag gesture. Press and hold also sends right click with haptic confirmation for users who expect a laptop-style context-click. Double tap and drag holds the left button until release, allowing tabs, windows, sliders, and selection boxes to move. Edge hold keeps moving in the edge direction like a joystick, with speed rising as the finger presses farther into the edge zone.",
            "Dragging tabs needs special care because browser tabs require the left button to stay down while movement events continue. The implementation must send pointer.down immediately when double-tap drag starts, mark subsequent pointer.move messages as dragging, and send pointer.up on release or cancel. If the WebSocket closes, Stop is pressed, or the page hides, the host must release all held buttons. This prevents stuck mouse buttons.",
            "The phone touchpad visual should be smaller than before, clean, and free of pointless status text. A small cursor hint may remain, but the real proof is the stream cursor overlay. Button clutter stays out. Haptics should communicate tap, right-click, and drag start without becoming noisy.",
        ],
        "goals": [
            "Implement a faster but controllable movement curve.",
            "Finalize single tap, double tap, hold, double-tap drag, and edge-hold joystick behavior.",
            "Guarantee held buttons are released on every cancellation path.",
        ],
    },
    {
        "title": "Page 6 - Keyboard, Scrolling, Text Entry, and Daily-Use Controls",
        "body": [
            "The keyboard path must feel like the iPhone keyboard, because that was a core requirement. The keyboard button should focus a hidden native input so iOS opens its real keyboard. Tapping the button again should blur it and close the keyboard. The input bridge should send inserted text, Enter, Backspace where possible, and paste larger text intentionally. The fallback keyboard sheet can remain for special keys, but it should not compete visually with the native keyboard button.",
            "Text entry has to avoid duplicate characters and weird focus loops. The native bridge should clear itself after each input event, handle beforeinput for line breaks, and recover focus if iOS briefly drops it. When the page enters keyboard-open state, the display should remain at the top and the layout should shrink around the visual viewport so the keyboard sits underneath instead of covering the important monitor area.",
            "Scrolling should be implemented as a natural touchpad gesture or a compact control. Two-finger touchpad movement can become scroll if we can reliably distinguish it from display pinch gestures. If that proves unreliable in Safari, the cleaner option is a small temporary scroll mode button or a two-finger area on the touchpad only. Scroll speed should be adjustable and tested against vertical pages, horizontal tracks, and inactive windows.",
            "The minimum control rail should include Keyboard, Follow, Display, and Settings. Display opens monitor selection. Settings contains sensitivity, zoom, follow/lens toggles, haptics, halo, quality, and proof/debug tools. Anything used only for development must be hidden behind a debug disclosure or host console. The phone experience should not show move counters, proof banners, or raw diagnostics during normal use.",
            "Special keys remain useful but should be grouped. The keyboard sheet can contain Esc, Tab, Enter, Backspace, Delete, arrow keys, Ctrl, Alt, Shift, Win, Copy, Paste, Undo, Redo, Screenshot, and Lock. These should be large enough to tap, with consistent button sizes and no text clipping.",
        ],
        "goals": [
            "Make the native iPhone keyboard toggle reliable.",
            "Keep daily controls minimal while preserving special keys.",
            "Add polished scrolling behavior that does not conflict with zoom gestures.",
        ],
    },
    {
        "title": "Page 7 - Streaming Speed, Latency, and Rendering Optimization",
        "body": [
            "The current stream is functional but not final. Sending base64 JPEG frames through JSON over WebSocket is simple, but it adds size overhead, parsing cost, and latency. For the free local Wi-Fi version, the realistic optimization path is staged: first reduce wasted redraws and improve frame scheduling; second move binary JPEG/WebP frames over WebSocket; third consider WebRTC only if needed later. The immediate goal is to make the existing architecture feel much faster without exploding scope.",
            "The host should capture at an adaptive rate. During active pointer movement, it should target a faster interval with lower image quality. During idle viewing, it can slow down and sharpen. When the phone page is hidden, it should pause or send rare keepalive frames. The app already has some adaptive behavior, but it needs stronger measurement and fewer unnecessary state broadcasts during input. Every pointer move should not trigger heavy state churn.",
            "The client should draw frames efficiently. It should decode the image once, draw only when the image changes or viewport changes, and avoid running expensive follow logic every time if the cursor has not moved. The cursor overlay should update from input acknowledgements immediately, then reconcile with the next stream frame. This gives the feeling of responsiveness even when screenshots arrive more slowly.",
            "Binary frames are the main transport upgrade. The protocol can keep JSON control messages but send stream payloads as binary with a small JSON metadata header or a separate metadata message. Removing base64 can cut roughly one third of frame size. If WebP capture is practical on Windows through the chosen library or post-processing pipeline, test it against JPEG for speed and visual quality. The rule is simple: lower latency beats perfect image quality while controlling the cursor.",
            "Diagnostics should become useful for us and invisible for normal users. Host console should show capture time, frame bytes, approximate fps, active quality mode, input RTT, dropped frames, and connected phone count. Phone debug state should expose the same values. The visible phone UI should stay clean.",
        ],
        "goals": [
            "Optimize adaptive capture and client drawing before changing architecture.",
            "Move toward binary frame transport to reduce overhead.",
            "Keep diagnostics available for development but hidden from daily UI.",
        ],
    },
    {
        "title": "Page 8 - Premium Mobile UI, Layout Polish, and Usability",
        "body": [
            "The phone UI should look intentional: black and gold, minimal, balanced, and free of development leftovers. The first screen after pairing should show the monitor capture at the top, the compact status strip above it, a smaller touchpad below, and a bottom rail with the few controls that matter. No proof banners, raw move counters, or checklist text should appear in normal controller mode.",
            "The top strip should not cover the screen capture. It should live above the canvas or become a slim overlay with reserved space. The monitor capture must have a predictable aspect ratio and align to the top in portrait mode. When the iPhone browser toolbar or keyboard changes the visual viewport height, the layout should recompute without overlap. The touchpad should not dominate the page; it should be large enough for comfortable gestures but leave visual priority to the display.",
            "The cursor overlay should be visible but restrained. The dot should not be huge. A small gold dot with a subtle ring is enough. The optional lens can provide enlargement without making the cursor itself oversized. Precision mode can change the halo style, but normal mode should stay calm.",
            "Controls need consistent sizing. The bottom rail buttons should share width and height, use short labels, and have active states. Keyboard should clearly activate. Follow should visibly toggle. Display should open monitor selection. Settings should contain everything else. Sheets should slide from the bottom, respect safe areas, and never cover the keyboard in a way that blocks text input.",
            "Visual QA must be run on simulated iPhone portrait, iPhone landscape, desktop browser, and at least one narrow viewport. The app must avoid overlapping text, hidden buttons, layout gaps, and bottom controls under the Safari toolbar. Screenshots should be captured and reviewed during implementation, not only tests.",
        ],
        "goals": [
            "Remove normal-mode development clutter from the phone UI.",
            "Make display, touchpad, and rail layout stable under viewport changes.",
            "Preserve the black/gold premium theme with restrained cursor visuals.",
        ],
    },
    {
        "title": "Page 9 - Security, Pairing, Authenticator Codes, and Packaging",
        "body": [
            "The local Wi-Fi version can stay free. The publishable package should launch from a zip, install dependencies included in the bundle, open the host console, show the phone URL and PIN clearly, and provide a stop script that releases input and kills the correct server process. The README should be short enough for a sibling to use without knowing Node. The app should remain local-network by default and should not expose control to the public internet.",
            "Pairing should keep the current safety shape: short-lived PIN, host approval, trusted device option, and a Stop control that releases all input. The authenticator-app idea can work, but it should be added carefully. A TOTP QR code per trusted laptop would let a phone generate rotating codes for repeat connection. It should not replace first-time laptop approval. The safe model is: first pair with PIN and approve on laptop, then optionally enroll a TOTP secret for that trusted phone or laptop profile. Later connections can require the current TOTP code plus the remembered trust key.",
            "For different networks, Tailscale remains the free recommended path. The package should detect and display a Tailscale URL when available. Mobile data without VPN should not be supported by opening ports automatically because that creates security and router problems. The host console should explain Same Wi-Fi and Tailscale in clean language, while the phone controller should not show proof checklist clutter.",
            "Packaging must include a real smoke test. Extract the zip to a temporary directory, start on a non-default port, verify health, verify the phone URL page loads, stop the server, and confirm no listener remains. The zip hash and size should be recorded in the final output. If npm audit reports dependency warnings, we should log them and plan a dependency hardening pass rather than hiding them.",
            "Publishing readiness means the app can be sent to someone else and launched. It does not mean public cloud hosting. It means local network, clear security boundaries, real input safety, clean packaging, and clear instructions.",
        ],
        "goals": [
            "Keep the default product free and local-network safe.",
            "Design TOTP as an optional trusted-device upgrade, not a replacement for first approval.",
            "Maintain zip launch, stop, and smoke-test reliability.",
        ],
    },
    {
        "title": "Page 10 - Execution Order, Acceptance Checklist, and Done Definition",
        "body": [
            "The implementation order should prevent churn. First, fix coordinate truth and cursor overlay because every other visual feature depends on it. Second, rebuild zoom-follow and optional cursor lens because they rely on correct cursor coordinates. Third, tune touchpad speed, gestures, and drag behavior because those drive daily usability. Fourth, clean the mobile layout and remove normal-mode clutter. Fifth, optimize stream speed and frame transport. Sixth, update security, packaging, docs, and release tests.",
            "Step one implementation tasks: add explicit cursor coordinateSpace metadata to stream frames and input acknowledgements; create one phone-side coordinate module; map logical and physical coordinates correctly for scaled displays; add debug snapshot output; update tests for 100, 125, 150 percent scaling and monitor edges; verify the phone overlay reaches the taskbar bottom.",
            "Step two implementation tasks: replace scattered zoom pan code with one viewport controller; add Follow toggle state; add safe-zone attraction; pause follow during manual pinch/pan; add optional cursor lens; test zoom at cursor, follow on, follow off, edge clamping, and taskbar visibility.",
            "Step three implementation tasks: tune default speed upward; add acceleration; preserve precision mode; finalize single tap left click, double tap right click, long press right click, double-tap drag, edge-hold joystick, and cancellation release; add tests for drag tabs and stuck-button prevention.",
            "Step four implementation tasks: redesign the portrait layout, keep top strip out of the capture, shrink touchpad to a comfortable size, remove debug/proof clutter from normal mode, keep Keyboard/Follow/Display/Settings as the rail, and visually test iPhone portrait and landscape.",
            "Step five implementation tasks: reduce state broadcasts during input, update capture intervals, draw immediate cursor overlay from acks, explore binary frame transport, and measure input RTT, capture time, frame bytes, fps, and dropped ticks.",
            "Step six implementation tasks: rebuild the zip, run extraction smoke tests, keep Tailscale support clean, write short launch instructions, and document the TOTP design as a future or included security feature depending on time.",
            "The project is done only when the phone cursor visually matches the laptop cursor on the taskbar, zoom-follow visibly enlarges and follows the mouse when enabled, Follow off behaves normally, touchpad gestures work without buttons, tab dragging works, speed feels improved, tests pass, the UI looks finished, and the zip launches on a clean extraction.",
        ],
        "goals": [
            "Implement in dependency order: coordinates, zoom, touchpad, UI, speed, packaging.",
            "Use tests and visual phone screenshots as release gates.",
            "Call the goal complete only when the app feels publishable, not merely patched.",
        ],
    },
]


def set_cell_shading(cell, fill):
    tc_pr = cell._tc.get_or_add_tcPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:fill"), fill)
    tc_pr.append(shd)


def set_cell_margins(cell, top=80, bottom=80, start=120, end=120):
    tc_pr = cell._tc.get_or_add_tcPr()
    tc_mar = tc_pr.first_child_found_in("w:tcMar")
    if tc_mar is None:
        tc_mar = OxmlElement("w:tcMar")
        tc_pr.append(tc_mar)
    for m, v in (("top", top), ("bottom", bottom), ("start", start), ("end", end)):
        node = tc_mar.find(qn(f"w:{m}"))
        if node is None:
            node = OxmlElement(f"w:{m}")
            tc_mar.append(node)
        node.set(qn("w:w"), str(v))
        node.set(qn("w:type"), "dxa")


def add_page(doc, page, index):
    if index:
        doc.add_page_break()

    heading = doc.add_paragraph()
    heading.style = doc.styles["Heading 1"]
    run = heading.add_run(page["title"])
    run.bold = True

    for paragraph in page["body"]:
        p = doc.add_paragraph(paragraph)
        p.style = doc.styles["Normal"]

    table = doc.add_table(rows=1, cols=1)
    table.autofit = False
    table.style = "Table Grid"
    cell = table.cell(0, 0)
    set_cell_shading(cell, "E8EEF5")
    set_cell_margins(cell)
    first = cell.paragraphs[0]
    first.style = doc.styles["Goal Box"]
    first.add_run("Completion goals for this page").bold = True
    for goal in page["goals"]:
        p = cell.add_paragraph(goal)
        p.style = doc.styles["List Bullet"]


def build_doc():
    doc = Document()
    section = doc.sections[0]
    section.page_width = Inches(8.5)
    section.page_height = Inches(11)
    section.top_margin = Inches(1)
    section.bottom_margin = Inches(1)
    section.left_margin = Inches(1)
    section.right_margin = Inches(1)
    section.header_distance = Inches(0.492)
    section.footer_distance = Inches(0.492)

    styles = doc.styles
    normal = styles["Normal"]
    normal.font.name = "Calibri"
    normal._element.rPr.rFonts.set(qn("w:eastAsia"), "Calibri")
    normal.font.size = Pt(9.5)
    normal.paragraph_format.space_after = Pt(4)
    normal.paragraph_format.line_spacing = 1.08

    h1 = styles["Heading 1"]
    h1.font.name = "Calibri"
    h1._element.rPr.rFonts.set(qn("w:eastAsia"), "Calibri")
    h1.font.size = Pt(13.5)
    h1.font.color.rgb = RGBColor(0x2E, 0x74, 0xB5)
    h1.paragraph_format.space_before = Pt(0)
    h1.paragraph_format.space_after = Pt(6)
    h1.paragraph_format.keep_with_next = True

    bullet = styles["List Bullet"]
    bullet.font.name = "Calibri"
    bullet.font.size = Pt(8.8)
    bullet.paragraph_format.space_after = Pt(2)
    bullet.paragraph_format.left_indent = Inches(0.32)
    bullet.paragraph_format.first_line_indent = Inches(-0.14)

    goal_style = styles.add_style("Goal Box", 1)
    goal_style.font.name = "Calibri"
    goal_style.font.size = Pt(8.8)
    goal_style.font.color.rgb = RGBColor(0x0B, 0x25, 0x45)
    goal_style.paragraph_format.space_after = Pt(2)

    title = doc.add_paragraph()
    title.alignment = WD_ALIGN_PARAGRAPH.CENTER
    title.paragraph_format.space_after = Pt(5)
    tr = title.add_run("Remote Desktop Controller Finalization Manual")
    tr.bold = True
    tr.font.size = Pt(15)
    tr.font.color.rgb = RGBColor(0x0B, 0x25, 0x45)

    subtitle = doc.add_paragraph()
    subtitle.alignment = WD_ALIGN_PARAGRAPH.CENTER
    subtitle.paragraph_format.space_after = Pt(8)
    sr = subtitle.add_run("10-page implementation plan for cursor accuracy, zoom-follow, touchpad control, speed, polish, security, packaging, and publish readiness.")
    sr.font.size = Pt(8.5)
    sr.font.color.rgb = RGBColor(0x55, 0x55, 0x55)

    for i, page in enumerate(PAGES):
        add_page(doc, page, i)

    footer = section.footer.paragraphs[0]
    footer.text = "Remote Controller finalization plan"
    footer.alignment = WD_ALIGN_PARAGRAPH.RIGHT
    footer.runs[0].font.size = Pt(8)
    footer.runs[0].font.color.rgb = RGBColor(0x55, 0x55, 0x55)

    doc.save(OUT)
    return OUT


if __name__ == "__main__":
    print(build_doc())

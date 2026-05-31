# Phone Controller Premium Polish Plan

## Page 1 - Final Layout, Spacing, And Visual Hierarchy

The phone controller must feel like a purpose-built remote desktop surface, not a debug prototype. The final portrait layout will be arranged as a clean vertical instrument panel: a compact status/control bar at the top, the remote display directly under it, the touchpad immediately under the display, two large click buttons, and then three equal-width action buttons for Keyboard, Display, and Settings. Nothing should float over the screen capture. The remote display must never be covered by the title, latency, quality, or Stop controls. The user should be able to glance at the top bar, understand the connection state, and then forget it is there.

The current top bar problem is caused by the fixed visual status strip sitting over the screen area. The fix is to make the top strip part of the portrait grid instead of an overlay. It will occupy its own row above the canvas. The screen will begin below that row, with enough top spacing that Safari browser chrome, safe-area insets, and the app header do not cause collisions. The status strip will use a compact, premium information hierarchy: left side shows the active display name and connection state; right side contains Stop. Quality and latency should be reduced or hidden in the main surface because they are secondary diagnostics and currently make the bar too wide and noisy. If latency remains visible, it must be very small and must not compete with Stop.

The black gap between the remote display and the touchpad must be removed. The grid rows should be explicit and balanced: top strip, remote screen, touchpad surface, click buttons, action rail. The touchpad must expand into available vertical space instead of leaving dead space. The touchpad status text such as "Moves sent 1170 / ack 1191 - connected" is debug information and must be removed from the normal UI. The touchpad can still keep hidden diagnostics internally, but the visible pad surface should look quiet and premium. If any visible state is needed, use subtle border/accent changes on active touch, not text.

The control rail must be rebuilt as three equal buttons. Keyboard, Display, and Settings should have the same width, height, alignment, border radius, and typography. They should not wrap or crowd. The Keyboard button must be large enough to hit comfortably with a thumb and should use the same event model as Display and Settings, with a reliable click/tap path on iPhone Safari. The rail should not show old experimental controls like Pad, Tap, Prec, Drag, R, Keys, Mon, or Set. Those names are confusing and no longer match the design.

The theme will shift from the current teal-dark prototype palette to a premium black-and-gold system. The background should be deep black, not gray-green. Panels should use near-black surfaces with fine warm borders. Gold should be the active accent, not a large decorative wash. Buttons should use restrained gold highlights, warm text, and dark fills. Stop remains a danger action, but it should harmonize with the palette using dark red and warm border tones. The design should feel minimal, expensive, and calm: no loud gradients, no debug badges, no clutter, no visible proof banner, no unneeded labels.

Completion goals for Page 1:
- The top status strip is not positioned over the remote display in portrait mode.
- The remote display starts below the top strip and is fully visible inside its canvas.
- The touchpad begins directly under the display with no large dead gap.
- The touchpad debug status text is removed from normal view.
- The action rail contains exactly three equal buttons: Keyboard, Display, Settings.
- The color system reads as premium black and gold, with no teal-dominant controller surfaces.
- The Same-Wi-Fi proof banner remains absent from the normal phone controller.

## Page 2 - Interaction Reliability, Keyboard Behavior, And Remote Control Surface

The remote display and the touchpad have different jobs. The display preview is for seeing and navigating the captured desktop view. The touchpad is for moving the laptop cursor and clicking. This separation must remain clear. On the display, two fingers pinch to zoom the preview. After zooming, one finger drags the zoomed preview left, right, up, or down. A single touch on the display should not accidentally click the laptop, because the user now has a dedicated touchpad and click buttons. This reduces accidental input and makes the controller safer.

The touchpad must remain the primary mouse input source. Moving a finger inside the touchpad sends pointer movement to the laptop. The cursor dot inside the touchpad can remain as a visual hint, but it should look like a premium focus point instead of a toy marker. Left Click and Right Click remain large and obvious. The touchpad surface should not show debug counts. It should respond visually while being touched, using a gold border glow or subtle active state. Movement should continue to be sent immediately, and acknowledgement tracking can stay in diagnostics for testing only.

The Keyboard button must be fixed. On iPhone Safari, native keyboard focus can be fragile when a hidden input is too small, covered, unfocusable, or triggered in a way Safari does not treat as user intent. The implementation will make the keyboard bridge input more reliable while keeping it visually invisible: it should be focusable, placed in a stable fixed location, not covered by another element, and triggered directly from the button's pointer/click event. The button should toggle open and closed. When open, the controller gets a keyboard-open state, the button shows active styling, the hidden input receives focus, and typed characters are sent. When closed, the input blurs and the active state clears.

Display and Settings sheets must continue to work. The action rail buttons should open their sheets without layout breakage. Sheets should rise above the bottom area cleanly, with gold-accented headers and practical spacing. The Keyboard button should not open a sheet; it should open the iPhone keyboard. The Display button opens monitor selection. The Settings button opens session settings. The older keyboard sheet may remain available internally only if needed, but the primary behavior should be the native iPhone keyboard because that is what the user asked for.

The top controls must be usable without crowding the screen. Display name and connection state stay readable. Stop stays large enough to hit intentionally. Quality and latency should be moved out of the main bar or visually minimized because they are not core actions during normal use. If they remain in diagnostics or settings, that is fine. The controller should prioritize the actual work: see the screen, move the cursor, click, type, switch monitor, stop control.

Completion goals for Page 2:
- Keyboard reliably focuses the native iPhone keyboard from the main Keyboard button.
- Keyboard button toggles active/open and inactive/closed states.
- Display button opens monitor selection.
- Settings button opens settings.
- Display pinch zoom still works.
- One-finger pan on the zoomed display still works.
- Touchpad movement still sends real pointer movement.
- Left Click and Right Click still send the correct buttons.
- Debug-only input counters are not visible on the touchpad.

## Page 3 - Verification, Cache Refresh, And Phone-Ready Delivery

The polish pass is only complete if the actual phone receives the new interface. The service worker cache name must be bumped so the phone does not keep stale CSS or JavaScript. The final URL should include a new version query parameter. After implementation, the laptop host should restart cleanly with screen capture mode and real input enabled. The final response must give the phone URL, current PIN, and a short explanation of what changed. The user should not have to guess whether the host is running.

Automated checks must cover the important behavior. The existing phone test suite should be updated so it expects the new minimal rail, hidden proof banner, no touchpad debug status, and display-only zoom/pan behavior. It should keep proving the clock-sync fix, touchpad movement, click buttons, keyboard forwarding, display/settings sheet access, acceptance internals where needed, and portrait layout. The JavaScript syntax check must pass before restart. A mobile Playwright layout probe should confirm that the top strip bottom is above the canvas top, the canvas bottom is directly above the touchpad top, the touchpad has enough height, the rail has three equal buttons, and the proof banner is not present.

The visual QA standard is practical and strict. The page should not look like a developer dashboard. It should look like a premium black remote controller with warm gold accents. No visible text should describe debug internals. Button text must fit. The three lower buttons must have stable dimensions and equal tracks. The keyboard button must be easy to tap. The display should not be hidden behind the status strip. The touchpad should visually fill its area. Sheets should not accidentally sit open or cover the main controls unless intentionally opened.

The final host restart should preserve the expected same-Wi-Fi flow. Real input should be on. The host should advertise the same LAN URL. The phone URL should include the new cache-busting version. The PIN should be fresh. If the PIN expires before the user tests it, the host console can produce a new one automatically, but the final answer should still report the current one at delivery time.

Completion goals for Page 3:
- Service worker cache is bumped.
- Phone URL uses a new version query parameter.
- JavaScript syntax check passes.
- Phone Playwright test suite passes.
- Mobile layout probe confirms no top-strip overlap.
- Mobile layout probe confirms touchpad connects directly below display.
- Mobile layout probe confirms the rail text is exactly Keyboard, Display, Settings.
- Host is restarted after changes.
- Real input is enabled after restart.
- Final answer gives the phone URL and current PIN.

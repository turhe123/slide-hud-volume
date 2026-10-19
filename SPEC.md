# SlideHudVolume — specification

**Tagline:** Replace the volume pop-up with a slim bar you can drag, and change volume in fine steps from your keys.

**Category:** Audio

**Inspired by (paid):** VolumeGlass ($7.99 one-time)

**Frameworks:** SwiftUI, AppKit, CoreAudio, CoreGraphics, ApplicationServices, ServiceManagement

**Donation URL (Support button):** https://ko-fi.com/leodavidai

## Spec

What the paid app does: VolumeGlass is a 7.99 dollar one-time purchase that gives the Mac a custom volume indicator where you can drag the bar to set the exact level. It earned a launch on Product Hunt, and the thread asking Apple for a better volume pop-up is long and active. Other tools such as Hudlum, SlimHUD and FineTune show how many people want finer control and a nicer indicator, so there is clear demand. Our free version is a lean takeover of the volume keys.

Feature set: Intercept the hardware volume up, volume down and mute keys, suppress the stock overlay, and apply the change ourselves with selectable step sizes of coarse, normal, fine and extra fine. Show a slim floating bar near the bottom or top of the screen that fades after two seconds. Let the user click or drag directly on the bar to set an exact level. Show a percentage number, a speaker glyph that reflects the level, and the current output device name. Holding option while pressing the keys uses the finest step. Aim for roughly 400 lines.

UI spec: The HUD is a borderless, non-activating NSPanel at status window level, hosting a SwiftUI view with a rounded material background of about 220 by 44 points. It shows the glyph, the bar and the percentage. It ignores mouse events except when the pointer is over it, so it never blocks clicks. A MenuBarExtra offers Enable Takeover, a position picker with Bottom Center, Top Center and Bottom Left, a step size picker, a size slider, a fade delay slider, and Launch at login. The first-run state shows an explanation and a button that opens the Accessibility pane. Without permission the HUD still works via its drag bar, but key capture is disabled.

Technical approach: Create a CGEventTap at the session level listening for system defined events, filter on the auxiliary control button subtype, and check the key codes for sound up, sound down and mute. Return nil from the tap callback to swallow the event so macOS shows no stock overlay. Because event taps need permission, call the Accessibility trust check with the prompt option and poll until granted. Set the volume with the Core Audio virtual main volume property on the default output device, falling back to per-channel scalars, and mute with the mute property. Listen for volume changes from other sources with a property listener so the HUD also reflects them. Convert steps so that the normal step is one sixteenth, fine is one sixty-fourth. Persist options with AppStorage and register login item with SMAppService.

Edge cases and error handling: If the output device has no software volume, such as some HDMI monitors, show a Device has no volume control message on the HUD instead of failing silently, and let the event pass through unswallowed. If the event tap is disabled by timeout, re-enable it in the callback. Respect the full screen and multiple-display setups by showing the HUD on the display containing the mouse. Avoid showing the HUD while the screen is locked. Handle Bluetooth device switching by re-registering listeners when the default output changes.

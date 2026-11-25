# Native UI/accessibility audit — Phase 5 local checkpoint

References reviewed on 2026-11-25: [Apple accessibility modifiers](https://developer.apple.com/documentation/swiftui/view-accessibility)
and [progress indicators](https://developer.apple.com/design/human-interface-guidelines/progress-indicators).
This is a source review, not an accessibility certification or a rendered audit.

Reviewed the existing photo gallery/canvas, organized Mac export sheet and new
independent project voice-note screen. No existing scan controls were modified.

P2-PHOTO: corrupt images previously left an endless loading spinner. The canvas now
shows an explicit unavailable state, decodes thumbnails off the main actor and
guards cancellation. Its task follows the actual image data. Gallery actions can
wrap into a vertical layout for smaller widths or larger text. Hidden Mac keyboard
shortcut buttons are excluded from accessibility traversal.

P2-EXPORT-UI: size estimation previously performed photo metadata I/O from body.
It now runs in a cancellable presentation task with detached I/O and guards stale
options/storage roots. The progress bar has a localized label and percentage.
Native Form/Picker/Toggle, NSSavePanel and ShareLink remain the interaction pattern.
Estimates remain approximate and are not peak disk/memory guarantees.

Voice-note controls use native lists, explicit association, permission confirmation,
localized text, duration labels, a labeled playback slider and confirmed deletion.
Back/dismiss guards protect an active recording or an unstaged failed-save clip.

EN/DE catalog checks run locally; this does not establish translation quality in
context or Dynamic Type/VoiceOver behavior. No screenshots were generated or
reviewed. Complete library, House/technical viewers, Studio, inspectors, menus,
multi-window, keyboard/focus, contrast, reduced motion, iPhone/iPad rotation and
large project performance remain open for actual Apple-host review.

Manual checklist: narrow/wide Mac windows, light/dark, EN/DE, largest iOS text,
VoiceOver labels/actions, keyboard navigation, unavailable photo and export
failure/cancel; change options/storage while estimates load. Run both full schemes
and capture real app screenshots. No Apple build/UI test was run on Windows.

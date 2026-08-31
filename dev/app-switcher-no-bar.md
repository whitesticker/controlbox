# Next/Previous application does not show the Command-Tab bar

**Symptom:** Mapping a button to Next application or Previous application switches apps, but the application switcher strip never appears. A real Command-Tab hold shows the bar.

**Cause:** The action posted Command-Tab as one chord and released Command in the same shot. macOS only draws the switcher while Command stays down; a tap that short is treated as a silent swap to the last app.

**Fix:** Keep Command held after Tab so the bar can appear. Previous application also keeps Shift down; releasing Shift in the same shot was why only Next showed the strip. Another tap moves the highlight. Modifiers lift about a second after the last tap, or immediately if another action fires.

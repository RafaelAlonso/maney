# Buttons in the shell (the fab "+", the mobile "Mais" trigger) carry their
# only accessible text in aria-label — the visible glyph is decorative. Without
# this, Capybara's `have_button`/`click_button` match only the element's own
# text/value/title and never see aria-label, so `have_button("Lançar")` finds
# nothing even though the button is right there.
Capybara.enable_aria_label = true

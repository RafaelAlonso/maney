require "rails_helper"

RSpec.describe "The closed group", type: :system do
  # One pass through the whole door: invited, consented, set up, deleted,
  # restored. The request specs cover each acceptance criterion on its own;
  # this is the proof they compose in a real browser.
  it "carries a person from invitation to their own budget and back from deletion" do
    fill_in "Primeiro mês", with: "2026-03"
    fill_in "Saldo inicial (R$)", with: "1.000,00"
    click_button "Começar"

    click_link "Config"
    click_link "Pessoas"
    fill_in "invitation[email_address]", with: "irma@example.com"
    click_button "Convidar"
    expect(page).to have_content("irma@example.com")
    expect(page).to have_content("pendente")

    perform_enqueued_jobs

    # The real token only ever existed inside the request that issued it — only
    # its digest is stored. Reissuing here is how the example gets a live link
    # without reading the mail queue, and it exercises the supersede path too.
    token = Invitation.last.reissue!

    click_link "Config"
    click_button "sair"

    visit signup_path(token: token)
    expect(page).to have_content("O que coletamos")
    check "user[consent]"
    fill_in "Senha", with: "senha-da-irma"
    fill_in "Repita a senha", with: "senha-da-irma"
    click_button "criar conta"

    # Her own first-run setup, on an empty budget.
    expect(page).to have_current_path(setup_path)
    fill_in "Primeiro mês", with: "2026-03"
    fill_in "Saldo inicial (R$)", with: "0,00"
    click_button "Começar"
    expect(page).to have_content("saldo atual")
    expect(page).not_to have_content("1.000,00")

    click_link "Config"
    click_link "excluir minha conta"
    expect(page).to have_content("30 dias")
    click_button "excluir minha conta"
    expect(page).to have_current_path(new_session_path)

    fill_in "E-mail", with: "irma@example.com"
    fill_in "Senha", with: "senha-da-irma"
    click_button "entrar"
    expect(page).to have_content("Sua conta está excluída")
    click_button "restaurar minha conta"
    expect(page).to have_content("saldo atual")
  end
end

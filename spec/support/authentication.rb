# The person every example runs as.
#
# From Task 3 on, owned models answer `none` when there is no current user — so
# a current user has to exist before an example builds a Setting, a card or an
# expense, or the ~50 spec files that create records at the top of a `before`
# block would silently build nothing and assert against an empty database.
module AuthenticationHelpers
  PASSWORD = "segredo-de-teste"

  # `Current` lives in the example's thread, but the patch below runs inside
  # ActionDispatch's integration session, which cannot see the example's
  # instance variables. This is the handoff between the two.
  module Holder
    singleton_class.attr_accessor :session
  end

  def current_user = @current_user

  def create_user!(email_address: "rafael@example.com", admin: false)
    User.create!(email_address:, password: PASSWORD, admin:)
  end

  # Establishes the person for code running in the spec's own thread. Request
  # specs additionally need `authenticate_request` for the cookie the app reads.
  def sign_in(user)
    @current_user = user
    Session.create!(user:).tap do |session|
      Current.session = session
      Holder.session = session
    end
  end

  def authenticate_request
    post session_path, params: { email_address: current_user.email_address, password: PASSWORD }
  end

  def authenticate_browser
    visit new_session_path
    fill_in "E-mail", with: current_user.email_address
    fill_in "Senha", with: PASSWORD
    click_button "entrar"
    # `click_button` returns as soon as the click fires — it does not wait for
    # the resulting navigation to land. The example's own `before` block mutates
    # the database the instant this method returns, and the server runs in this
    # same process against the same connection: an in-flight sign-in request
    # then reads a database being rewritten underneath it. That is not
    # theoretical — the log shows a `Setting Create` from the example's thread
    # landing between two queries of the redirect's own `GET /`.
    #
    # Waiting for the *landing page* is what closes that window, and it has to
    # be the page, not the form. Turbo disables the submit button while the form
    # is in flight, and Capybara's button selector ignores disabled buttons, so
    # "the entrar button is gone" goes true the moment the POST leaves the
    # browser — before the server has even read it. `disabled: :all` looks at
    # the DOM instead, and the path check proves the whole POST → `/` → `/setup`
    # chain finished rendering.
    #
    # `/setup` is the deterministic destination: every example signs in as a
    # brand-new person, and a person with no Setting is sent there by
    # `require_setup` (see the `driven_by` block in spec/support/system.rb).
    expect(page).to have_no_button("entrar", disabled: :all)
    expect(page).to have_current_path(setup_path)
  end

  # Leaves the spec's own thread with nobody signed in. Does not touch the
  # cookie — see `sign_out_request`.
  def sign_out
    Current.session = nil
    Holder.session = nil
    @current_user = nil
  end

  # For request specs: drops the app's cookie as well.
  def sign_out_request
    user = current_user
    delete session_path
    @current_user = user # kept so the example can still name the credentials
    Current.session = nil
    Holder.session = nil
  end

  # Builds records as somebody else, then hands the example back to its own
  # person. Only the spec thread's `Current` moves — the cookie a request spec
  # is holding still belongs to whoever signed in.
  def as(user)
    previous_session = Current.session
    previous_user = @current_user
    sign_in(user)
    yield
  ensure
    @current_user = previous_user
    Current.session = previous_session
    Holder.session = previous_session
  end
end

# `ActiveSupport::CurrentAttributes` is reset by the Rails executor when a
# request completes, so after `get root_path` the *example* would be left with no
# current user — and from Task 3 on every owned model would answer `none`,
# breaking the ~77 places where a request spec asserts on a record after the
# request. Put the example's session back on the way out. Test-only: in the app
# a request always re-reads its session from the cookie.
module RestoreCurrentSessionAfterRequest
  def process(...)
    super
  ensure
    Current.session ||= AuthenticationHelpers::Holder.session
  end
end
ActionDispatch::Integration::Session.prepend(RestoreCurrentSessionAfterRequest)

RSpec.configure do |config|
  config.include AuthenticationHelpers

  # `:no_current_user` opts an example out — used by the claim spec, which needs
  # a database with no person in it at all.
  config.before(:each) do |example|
    # The person every example runs as is Rafael: on a real install the claimed
    # account is the admin, and specs that need a plain member create one.
    sign_in(create_user!(admin: true)) unless example.metadata[:no_current_user]
  end

  config.before(:each, type: :request) do |example|
    authenticate_request unless example.metadata[:no_current_user]
  end

  config.after(:each) { AuthenticationHelpers::Holder.session = nil }
end

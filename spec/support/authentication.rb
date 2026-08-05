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

  def create_user!(email_address: "rafael@example.com")
    User.create!(email_address:, password: PASSWORD)
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
    # the resulting redirect to land. Without this, the example's own `before`
    # block (which mutates the database right after this method returns) can
    # race the still-in-flight sign-in navigation, and an unrelated request
    # occasionally observes the database mid-transition. Polling for the
    # sign-in form's own disappearance blocks until the redirect has actually
    # landed, on whatever page it lands on.
    expect(page).to have_no_button("entrar")
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
    sign_in(create_user!) unless example.metadata[:no_current_user]
  end

  config.before(:each, type: :request) do |example|
    authenticate_request unless example.metadata[:no_current_user]
  end

  config.after(:each) { AuthenticationHelpers::Holder.session = nil }
end

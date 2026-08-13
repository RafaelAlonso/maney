module Users
  # The nightly sweep: every account whose 30-day grace period has run out,
  # erased for good. Scheduled from `config/recurring.yml` in production and
  # runnable by hand with `bin/rails users:purge`, which reports these outcomes
  # to the operator.
  #
  # Each account is purged inside its own rescue on purpose. One person's row
  # failing must not take the rest of the night's batch down with it — and
  # because `Users::Purge` is itself transactional, a failure leaves that
  # account whole rather than half-erased.
  class PurgeDueAccountsJob < ApplicationJob
    # The address is captured before the purge, because after it there is no
    # row left to read it from.
    Outcome = Data.define(:email_address, :error)

    def perform
      User.purgeable.map { |user| purge(user) }
    end

    private

    def purge(user)
      email_address = user.email_address

      Users::Purge.new(user).call
      Rails.logger.info("Purged account #{email_address}")
      Outcome.new(email_address:, error: nil)
    rescue StandardError => error
      Rails.logger.error("Could not purge account #{email_address}: #{error.class}: #{error.message}")
      Outcome.new(email_address:, error:)
    end
  end
end

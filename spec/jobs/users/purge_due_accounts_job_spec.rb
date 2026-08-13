require "rails_helper"

RSpec.describe Users::PurgeDueAccountsJob do
  def deleted_user!(email_address:, deleted_at:)
    create_user!(email_address:).tap { |user| user.update!(deleted_at:) }
  end

  it "erases only the accounts whose grace period has run out" do
    due = deleted_user!(email_address: "fora@example.com", deleted_at: 31.days.ago)
    still_restorable = deleted_user!(email_address: "dentro@example.com", deleted_at: 29.days.ago)

    described_class.perform_now

    expect(User.find_by(id: due.id)).to be_nil
    expect(User.find_by(id: still_restorable.id)).to eq(still_restorable)
  end

  it "reports the address of every account it erased" do
    deleted_user!(email_address: "fora@example.com", deleted_at: 31.days.ago)

    outcomes = described_class.perform_now

    expect(outcomes.map(&:email_address)).to eq([ "fora@example.com" ])
    expect(outcomes.map(&:error)).to eq([ nil ])
  end

  # The reason each account is purged inside its own rescue: a nightly sweep
  # that aborts on the first bad row silently leaves every account behind it
  # unerased, past the grace period it promised.
  it "keeps going when one account cannot be erased, and says which failed" do
    failing = deleted_user!(email_address: "quebra@example.com", deleted_at: 31.days.ago)
    healthy = deleted_user!(email_address: "fora@example.com", deleted_at: 32.days.ago)

    allow(Users::Purge).to receive(:new).and_call_original
    allow(Users::Purge).to receive(:new).with(failing) do
      instance_double(Users::Purge).tap do |purge|
        allow(purge).to receive(:call).and_raise(ActiveRecord::InvalidForeignKey, "still referenced")
      end
    end

    outcomes = described_class.perform_now

    expect(User.find_by(id: healthy.id)).to be_nil
    expect(User.find_by(id: failing.id)).to eq(failing)

    failed = outcomes.find { |outcome| outcome.email_address == "quebra@example.com" }
    expect(failed.error).to be_a(ActiveRecord::InvalidForeignKey)
  end

  it "does nothing at all when no account is due" do
    deleted_user!(email_address: "dentro@example.com", deleted_at: 29.days.ago)

    expect { described_class.perform_now }.not_to change(User, :count)
  end
end

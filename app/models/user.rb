class User < ApplicationRecord
  # How long a deleted account stays restorable. Everything about the deletion
  # window — the copy, the restore screen, the nightly purge — derives from
  # this one constant and from `deleted_at`, which is why deleting again after a
  # restore gets a fresh window for free.
  DELETION_GRACE = 30.days

  has_secure_password
  has_many :sessions, dependent: :destroy

  # Ticked on the signup form and never stored: the consent *record* is
  # `consented_at` plus `consent_policy_version`. Validating it in the :signup
  # context means an unticked box produces no INSERT at all.
  attr_accessor :consent

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  # `allow_nil: false` because AcceptanceValidator defaults to allowing nil —
  # built for forms that post "0" via a hidden field when the box is
  # unchecked. This form has no such field, so an absent checkbox is nil, and
  # without overriding the default that nil would sail straight through.
  validates :consent, acceptance: true, on: :signup, allow_nil: false

  # Keyed on the password salt, so setting a new password invalidates any reset
  # link still sitting in an inbox.
  generates_token_for :password_reset, expires_in: 15.minutes do
    password_salt&.last(10)
  end

  # Inclusive on purpose, so this scope and `purge_due?` agree at the exact
  # boundary. A row the app already refuses to sign in must also be one the
  # nightly task picks up.
  scope :purgeable, -> { where.not(deleted_at: nil).where(deleted_at: ..DELETION_GRACE.ago) }

  def access_revoked? = access_revoked_at.present?
  def deleted? = deleted_at.present?
  def restorable? = deleted? && deleted_at > DELETION_GRACE.ago
  def purge_due? = deleted? && !restorable?

  def days_until_erasure
    return 0 unless deleted?

    ((deleted_at + DELETION_GRACE).to_date - Date.current).to_i
  end
end

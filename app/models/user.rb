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

  # Reachable account: the row exists *and* the person can still use it. Deleted
  # (restorable or purge-due) and access-revoked rows survive in the table but
  # answer `false` here, so sign-in, password reset and the invite guard can all
  # ask one question instead of re-deriving "is this account really gone?".
  scope :active, -> { where(deleted_at: nil, access_revoked_at: nil) }

  def access_revoked? = access_revoked_at.present?
  def deleted? = deleted_at.present?
  def active? = !deleted? && !access_revoked?
  def restorable? = deleted? && deleted_at > DELETION_GRACE.ago
  def purge_due? = deleted? && !restorable?

  # Rounded *up*, so an account with any grace left never reads "0 dias": while
  # `restorable?` is true the remaining time is > 0, so `ceil` lands on at least
  # 1. (A day-count via `to_date` truncated that last partial day to 0 and told
  # a still-restorable person they were already erased.) Only the restore screen
  # reads this, and only for restorable accounts, so the purge-due case where
  # this goes to 0 or negative never renders.
  def days_until_erasure
    return 0 unless deleted?

    ((deleted_at + DELETION_GRACE - Time.current) / 1.day).ceil
  end

  # Signing out every device at once is half of what deletion means: the app has
  # to become unreachable immediately, while the data stays untouched for 30
  # days. Nothing is erased here — that is Users::Purge, a month later.
  def delete_account!
    transaction do
      update!(deleted_at: Time.current)
      sessions.destroy_all
    end
  end

  def restore_account! = update!(deleted_at: nil)
end

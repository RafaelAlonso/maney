# A pending invitation: the group's door, before anyone has walked through it.
#
# Deliberately *not* an OwnedByUser model. An invitation exists before anyone
# owns it and belongs to the group rather than to a budget; `invited_by` records
# who sent it, which is provenance, not ownership, and scopes nothing.
class Invitation < ApplicationRecord
  EXPIRY = 7.days
  DELIVERY_STATES = %w[sending sent failed].freeze

  belongs_to :invited_by, class_name: "User"

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true
  validates :delivery_state, inclusion: { in: DELIVERY_STATES }

  scope :pending, -> { where(accepted_at: nil, cancelled_at: nil) }

  class << self
    # Returns the invitation *and* the raw token, which is the only moment the
    # token exists in this process: it goes into the emailed URL and nowhere
    # else. Only the digest is stored, so a leaked database backup hands nobody
    # a live link.
    def issue(email_address:, invited_by:)
      token = new_token
      invitation = create!(email_address:, invited_by:, token_digest: digest(token),
                           expires_at: EXPIRY.from_now)
      [ invitation, token ]
    end

    def find_by_token(token)
      return nil if token.blank?

      find_by(token_digest: digest(token))
    end

    def digest(token) = Digest::SHA256.hexdigest(token)

    def new_token = SecureRandom.urlsafe_base64(32)
  end

  # Supersedes rather than duplicates: the previously mailed link stops working
  # the instant this returns, so there is never more than one live link per
  # address and a token that went astray in a failed or forwarded email cannot
  # be redeemed later.
  def reissue!
    token = self.class.new_token
    update!(token_digest: self.class.digest(token), expires_at: EXPIRY.from_now,
            delivery_state: "sending")
    token
  end

  def pending? = accepted_at.nil? && cancelled_at.nil?
  def expired? = expires_at.past?
  def redeemable? = pending? && !expired?
  def cancel! = update!(cancelled_at: Time.current)
end

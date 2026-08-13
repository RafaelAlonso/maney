module Users
  # The other end of deletion: everything one person owns, gone for good.
  #
  # Runs outside a request, where `Current.user` is nil and every owned model
  # therefore answers `none` — so every read and write here says `unscoped`
  # explicitly, exactly as Users::Claim does.
  class Purge
    # Children before parents: `delete_all` does not cascade, and the foreign
    # keys are real. The *set* is asserted against Claim::TABLES in the spec
    # rather than derived from it, because only the order is hand-made — a table
    # added to the schema without being added here fails that assertion.
    DELETION_ORDER = %w[
      budgets expenses installment_purchases card_schedules incomes settings categories cards
    ].freeze

    def initialize(user)
      @user = user
    end

    def call
      ActiveRecord::Base.transaction do
        DELETION_ORDER.each do |table|
          table.classify.constantize.unscoped.where(user_id: @user.id).delete_all
        end

        # It holds their email address, which is the one piece of them left
        # outside the tables above.
        Invitation.where(email_address: @user.email_address).delete_all

        # The other direction: invitations *they* sent. `invited_by_id` is a
        # `null: false` foreign key with no ON DELETE clause, so leaving these
        # behind would make `@user.destroy!` below hit a live reference and
        # roll back the whole purge. Deleting is also the right semantics —
        # a pending invitation whose inviter no longer exists is not something
        # an erasure feature keeps.
        Invitation.where(invited_by_id: @user.id).delete_all

        @user.sessions.delete_all
        @user.destroy!
      end
    end
  end
end

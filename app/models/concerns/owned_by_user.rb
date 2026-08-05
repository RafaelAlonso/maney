# One person's rows. Included by every table that holds budgeting data, so that
# the whole Budgeting:: layer keeps its existing queries and merely gains an
# `AND user_id = ?` — no formula moves, which is what keeps the migrated totals
# identical.
module OwnedByUser
  extend ActiveSupport::Concern

  included do
    belongs_to :user, default: -> { Current.user }

    # Deny by default: with nobody signed in an owned model answers *nothing*
    # rather than everything. A forgotten `Current` then shows an empty screen
    # instead of somebody else's budget — the failure mode that matters is the
    # one you can see.
    #
    # The one place that must read across people is Users::Claim, which says
    # `unscoped` explicitly.
    default_scope { Current.user ? where(user_id: Current.user.id) : none }
  end
end

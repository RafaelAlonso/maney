module Users
  # The one-shot migration of a pre-account database: every row that belongs to
  # nobody becomes the first person's. Refuses to finish unless the data is
  # provably the same on the way out as on the way in.
  #
  # If exactly one person already exists and owns nothing yet, that person is
  # adopted instead of a new one being created — the supported recovery for an
  # operator who created an account before running this task. Any other
  # existing-person state (two or more, or one that already owns rows) raises
  # AlreadyClaimed; see `call`.
  class Claim
    AlreadyClaimed = Class.new(StandardError)
    Tampered = Class.new(StandardError)

    Result = Data.define(:user, :rows_attached)

    # Per table, what a lost, duplicated or reassigned row would move. Read with
    # raw SQL on purpose: OwnedByUser's default_scope cannot reach a fingerprint
    # taken this way, which is the only reason it can be trusted to compare a
    # before and an after that sit on opposite sides of the backfill.
    FINGERPRINT = {
      "settings" => { numeric: %w[initial_balance_cents alert_threshold_percent], dates: %w[first_month] },
      "categories" => { numeric: [], dates: [] },
      "cards" => { numeric: [], dates: [] },
      "card_schedules" => { numeric: %w[closing_day due_day], dates: %w[valid_from] },
      "incomes" => { numeric: %w[amount_cents], dates: %w[date] },
      "expenses" => { numeric: %w[amount_cents installment_number], dates: %w[date] },
      "installment_purchases" => { numeric: %w[total_cents installments_count first_installment], dates: %w[date] },
      "budgets" => { numeric: %w[amount_cents], dates: %w[month] }
    }.freeze

    # Derived from FINGERPRINT, not hand-maintained alongside it: two
    # independently listed sets of "every owned table" can only drift apart, and
    # the dangerous direction is a table backfilled by `attach` that FINGERPRINT
    # never learns to verify — exactly the class of bug this migration exists to
    # rule out. One list, one source of truth.
    TABLES = FINGERPRINT.keys.freeze

    def initialize(email_address:, password:)
      @email_address = email_address
      @password = password
    end

    def call
      raise AlreadyClaimed if User.count > 1

      # The operational trap this guards against: `db:migrate` stops asking for
      # `users:claim`, the operator's first instinct is "I need an account to
      # log in" and creates one by hand before running this task. That person
      # is then indistinguishable from a real prior claim UNLESS they own
      # nothing yet — so adopting them (rather than creating a second person)
      # is only safe while both of these hold. Either one failing means either
      # a real claim already happened, or this account already has its own
      # data, and in both cases raising is the only safe answer.
      user = User.first
      raise AlreadyClaimed if user && owns_rows?(user)

      ActiveRecord::Base.transaction do
        before = fingerprint
        # Adopt rather than create when the guard above passed: this is the
        # accidentally-created account being folded into the migration, not a
        # second person, so its email and password are left exactly as they
        # are.
        user ||= User.create!(email_address: @email_address, password: @password)
        attached = TABLES.sum { |table| attach(table, user) }
        verify!(before)
        Result.new(user:, rows_attached: attached)
      end
    end

    private

    def owns_rows?(user)
      TABLES.any? { |table| table.classify.constantize.unscoped.exists?(user_id: user.id) }
    end

    def attach(table, user)
      table.classify.constantize.unscoped.where(user_id: nil).update_all(user_id: user.id)
    end

    def verify!(before)
      raise Tampered, "the data changed during the migration — nothing was saved" unless fingerprint == before

      # Checked against FINGERPRINT's keys, not TABLES: the whole point of this
      # pass is to catch a TABLES that itself forgot a table, so it cannot share
      # the same possibly-truncated list it is meant to be verifying.
      left_behind = FINGERPRINT.keys.select { |table| connection.select_value("SELECT 1 FROM #{table} WHERE user_id IS NULL LIMIT 1") }
      return if left_behind.empty?

      raise Tampered, "#{left_behind.join(', ')} still hold rows belonging to nobody — nothing was saved"
    end

    def fingerprint
      FINGERPRINT.to_h do |table, columns|
        selects = [ "COUNT(*) AS row_count", "COALESCE(SUM(id), 0) AS id_sum" ]
        columns[:numeric].each { |column| selects << "COALESCE(SUM(#{column}), 0) AS sum_#{column}" }
        columns[:dates].each do |column|
          selects << "MIN(#{column}) AS min_#{column}"
          selects << "MAX(#{column}) AS max_#{column}"
        end
        [ table, connection.select_one("SELECT #{selects.join(', ')} FROM #{table}") ]
      end
    end

    def connection = ActiveRecord::Base.connection
  end
end

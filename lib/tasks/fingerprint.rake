# A deterministic, diffable summary of everything a database holds. Its only
# purpose is proving a restored backup carries the same money as the original:
# `bin/restore-drill` runs it against production and against the restore and
# diffs the two, so an empty diff is the proof.
#
# Two halves, and both are needed:
#
#   * the `user` sections run the real `Budgeting::MonthSummary` engine, so the
#     restore is proved to produce the same month totals a person would read
#     on screen;
#   * the `table` sections aggregate every persisted column, so a value the
#     month totals happen not to reach — a future installment, a budget, a
#     card's closing day, a password — still moves the report when it changes.
#
# Amounts print as raw integer cents — no locale formatting, nothing that could
# differ between two machines. Every line begins with `user `, `table ` or two
# spaces: `bin/restore-drill` filters both sides with that grammar.
namespace :db do
  desc "Print a deterministic, diffable fingerprint of every user's data"
  task fingerprint: :environment do
    connection = ActiveRecord::Base.connection

    # MonthSummary derives figures relative to a date. Nothing it reports here
    # depends on that date today, but pinning it costs one line and stops a
    # future change from making a drill that straddles midnight look like a
    # failed restore.
    today = ENV["TODAY"] ? Date.parse(ENV["TODAY"]) : Date.current

    # Read from Users::Claim::FINGERPRINT rather than repeating its table list:
    # that constant is already documented as the single source of truth for
    # "every owned table", precisely so a table added later cannot end up
    # verified in one place and unverified in the other. `users` is appended
    # because it is the one table nobody owns and everybody needs.
    aggregated = Users::Claim::FINGERPRINT
    tables = (aggregated.keys + [ "users" ]).sort

    # Columns FINGERPRINT deliberately leaves out because a lost or duplicated
    # row does not move them — but a corrupted restore does. Summarised as a
    # checksum over the sorted values: it is short, it is type-agnostic, and for
    # `password_digest` it proves the credential survived without writing a
    # password hash into a file that gets diffed and pasted around.
    checksummed = {
      "cards" => %w[user_id name archived_at],
      "card_schedules" => %w[user_id card_id],
      "categories" => %w[user_id name role],
      "budgets" => %w[user_id category_id],
      "settings" => %w[user_id],
      "incomes" => %w[user_id name],
      "expenses" => %w[user_id name payment_method category_id card_id installment_purchase_id],
      "installment_purchases" => %w[user_id name card_id category_id],
      "users" => %w[email_address password_digest]
    }

    # Sorted in Ruby, never by the database: a restore into a freshly
    # initialised container need not share production's collation, and a
    # reordered report is a false MISMATCH.
    checksum = lambda do |table, column|
      values = connection.select_values(
        "SELECT #{connection.quote_column_name(column)} FROM #{connection.quote_table_name(table)}"
      )
      Digest::SHA256.hexdigest(values.map(&:to_s).sort.join("\n"))[0, 12]
    end

    months_with_entries = lambda do
      dates = Income.pluck(:date) + Expense.where.not(date: nil).pluck(:date)
      dates.map(&:beginning_of_month).uniq.sort
    end

    User.all.to_a.sort_by(&:email_address).each do |user|
      # OwnedByUser denies by default: read without a Current.user, every table
      # below answers `none` and the fingerprint would happily "match" a restore
      # of nothing. This wrapping is what makes the report per-person, too.
      Current.set(session: Session.new(user:)) do
        puts "user #{user.email_address}"
        puts "  cards=#{Card.count} categories=#{Category.count} " \
             "incomes=#{Income.count} expenses=#{Expense.count} " \
             "installment_purchases=#{InstallmentPurchase.count}"

        months_with_entries.call.each do |month|
          summary = Budgeting::MonthSummary.new(month:, today:)
          puts "  #{month.strftime('%Y-%m')} " \
               "incomes_total=#{summary.incomes_total_cents} " \
               "current_balance=#{summary.current_balance_cents} " \
               "estimated_balance=#{summary.estimated_balance_cents}"
        end
      end
    end

    # Read globally, with raw SQL, exactly as `Users::Claim#fingerprint` does:
    # OwnedByUser's default_scope cannot reach a read taken this way, so these
    # sections see every row regardless of who is signed in.
    tables.each do |table|
      quoted_table = connection.quote_table_name(table)
      puts "table #{table}"
      puts "  rows=#{connection.select_value("SELECT COUNT(*) FROM #{quoted_table}")}"
      # `.to_i`: Postgres sums a bigint into a numeric, which renders as "0.0".
      # Every column summed here counts whole things or cents, so an integer is
      # both exact and the one rendering that cannot drift between adapters.
      puts "  id_sum=#{connection.select_value("SELECT COALESCE(SUM(id), 0) FROM #{quoted_table}").to_i}"

      columns = aggregated.fetch(table, { numeric: [], dates: [] })
      columns[:numeric].each do |column|
        quoted_column = connection.quote_column_name(column)
        puts "  sum_#{column}=#{connection.select_value("SELECT COALESCE(SUM(#{quoted_column}), 0) FROM #{quoted_table}").to_i}"
      end
      columns[:dates].each do |column|
        quoted_column = connection.quote_column_name(column)
        puts "  min_#{column}=#{connection.select_value("SELECT MIN(#{quoted_column}) FROM #{quoted_table}")}"
        puts "  max_#{column}=#{connection.select_value("SELECT MAX(#{quoted_column}) FROM #{quoted_table}")}"
      end
      checksummed.fetch(table, []).sort.each do |column|
        puts "  checksum_#{column}=#{checksum.call(table, column)}"
      end
    end
  end
end

# A deterministic, diffable summary of everything a database holds. Its only
# purpose is proving a restored backup carries the same money as the original:
# `bin/restore-drill` runs it against production and against the restore and
# diffs the two, so an empty diff is the proof.
#
# Amounts print as raw integer cents — no locale formatting, nothing that could
# differ between two machines.
namespace :db do
  desc "Print a deterministic, diffable fingerprint of every user's data"
  task fingerprint: :environment do
    # MonthSummary derives figures relative to a date. Nothing it reports here
    # depends on that date today, but pinning it costs one line and stops a
    # future change from making a drill that straddles midnight look like a
    # failed restore.
    today = ENV["TODAY"] ? Date.parse(ENV["TODAY"]) : Date.current

    months_with_entries = lambda do
      dates = Income.pluck(:date) + Expense.where.not(date: nil).pluck(:date)
      dates.map(&:beginning_of_month).uniq.sort
    end

    User.order(:email_address).each do |user|
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
  end
end

module Budgeting
  # Each account's balance for one month, and the movements behind it. Derived on
  # read, never stored, same rule as BalanceChain: a retroactive entry changes
  # every month ahead.
  #
  # The Conta principal opens the first month with saldo inicial; every other
  # account opens at 0 and receives money through a transfer. Incomes come in,
  # débito/dinheiro expenses (bill payments included, on their own date) go out,
  # transfers move money between accounts. Crédito purchases never touch an
  # account. Because every income and every débito/dinheiro expense belongs to
  # exactly one account and transfers net to zero, the accounts always add up to
  # BalanceChain's "saldo atual" — `total_closing_cents` is that same number.
  class AccountBalances
    Movement = Data.define(:date, :name, :amount_cents, :record, :balance_after_cents)

    attr_reader :month

    def initialize(month:)
      @month = month.beginning_of_month
    end

    # The balance carried into the month.
    def opening_cents(account) = opening_by_account.fetch(account.id, 0)

    # The account's "saldo" for the month: opening plus the month's net,
    # independent of today — the same semantics as "saldo atual".
    def closing_cents(account) = opening_cents(account) + month_net_by_account.fetch(account.id, 0)

    # Archived accounts included: their money is still the person's.
    def total_closing_cents = Account.all.sum { |account| closing_cents(account) }

    def movements(account)
      balance = opening_cents(account)
      raw_movements(account).sort_by { |entry| [ entry[:date], entry[:record].created_at ] }.map do |entry|
        balance += entry[:amount_cents]
        Movement.new(**entry, balance_after_cents: balance)
      end
    end

    private

    def timeline_started?
      first = Setting.instance&.first_month
      first.present? && month >= first
    end

    def opening_by_account
      @opening_by_account ||= timeline_started? ? carried_by_account : {}
    end

    # Everything dated before the month, summed at once rather than chained month
    # by month — same result, one query per source.
    def carried_by_account
      net = net_by_account(...month)
      primary = Account.find_by(role: "primary")
      net[primary.id] += Setting.instance.initial_balance_cents if primary
      net
    end

    def month_net_by_account
      @month_net_by_account ||= timeline_started? ? net_by_account(month.all_month) : {}
    end

    # One grouped query per source, over every account at once.
    def net_by_account(dates)
      net = Hash.new(0)
      Income.where(date: dates).group(:account_id).sum(:amount_cents).each { |id, cents| net[id] += cents }
      # Installments carry `date: nil` and are always crédito, so this excludes them.
      Expense.where(payment_method: %w[debit cash], date: dates).group(:account_id).sum(:amount_cents)
             .each { |id, cents| net[id] -= cents }
      Transfer.where(date: dates).group(:to_account_id).sum(:amount_cents).each { |id, cents| net[id] += cents }
      Transfer.where(date: dates).group(:from_account_id).sum(:amount_cents).each { |id, cents| net[id] -= cents }
      net
    end

    def raw_movements(account)
      return [] unless timeline_started?

      dates = month.all_month
      incomes = account.incomes.where(date: dates).map do |income|
        { date: income.date, name: income.name, amount_cents: income.amount_cents, record: income }
      end
      expenses = account.expenses.where(payment_method: %w[debit cash], date: dates).map do |expense|
        { date: expense.date, name: expense.name, amount_cents: -expense.amount_cents, record: expense }
      end
      transfers_in = account.transfers_in.where(date: dates).includes(:from_account).map do |transfer|
        { date: transfer.date, name: transfer.note.presence || "transferência de #{transfer.from_account.name}",
          amount_cents: transfer.amount_cents, record: transfer }
      end
      transfers_out = account.transfers_out.where(date: dates).includes(:to_account).map do |transfer|
        { date: transfer.date, name: transfer.note.presence || "transferência para #{transfer.to_account.name}",
          amount_cents: -transfer.amount_cents, record: transfer }
      end
      incomes + expenses + transfers_in + transfers_out
    end
  end
end

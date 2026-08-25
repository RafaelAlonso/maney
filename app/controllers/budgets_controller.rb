class BudgetsController < ApplicationController
  # Inline budget edit from the category dashboard. The client never holds a
  # Budget id (a month may have no row yet), so this is a single upsert keyed by
  # category + month (read from params[:month] through current_month). It renders
  # a Turbo Stream replacing the dashboard's budget editor with the new figure.
  def create
    @category = Category.find(params[:category_id])
    @summary = Budgeting::MonthSummary.new(month: current_month)
    cents = BrlMoney.parse(params[:budget_amount])

    if cents.nil?
      @error = "não é um valor válido"
      return render :create, status: :unprocessable_entity
    end

    budget = Budget.find_or_initialize_by(category: @category, month: current_month)
    budget.amount_cents = cents
    if budget.save
      @summary = Budgeting::MonthSummary.new(month: current_month) # re-read after the write
      render :create
    else
      @error = budget.errors.full_messages.to_sentence
      render :create, status: :unprocessable_entity
    end
  end
end

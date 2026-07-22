class HomeController < ApplicationController
  def show
    @categories = Category.order(:name)
    @budgets = Budget.where(month: current_month).index_by(&:category_id)
  end
end

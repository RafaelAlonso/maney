class HomeController < ApplicationController
  def show
    @summary = Budgeting::MonthSummary.new(month: current_month)
    @categories = Category.order(:name)
  end
end

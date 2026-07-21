module ApplicationHelper
  def brl(cents)
    "R$ #{BrlMoney.format(cents)}"
  end
end

module ApplicationHelper
  def brl(cents)
    return "—" if cents.nil?
    "R$ #{BrlMoney.format(cents)}"
  end
end

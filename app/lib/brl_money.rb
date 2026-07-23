require "bigdecimal"

module BrlMoney
  module_function

  # "1.234,56" | "1234,56" | "-50" | "R$ 900" -> integer cents; nil if invalid.
  #
  # The dot is ambiguous without the comma: with a comma, the comma is the
  # decimal separator and every dot is a thousands separator (as before).
  # Without a comma, a single dot followed by 1 or 2 digits to the end IS the
  # decimal ("12.34" -> R$ 12,34); any other pattern (two dots, or three digits
  # after the dot) is thousands ("1.000" -> R$ 1.000,00), matching the display format.
  def parse(text)
    stripped = text.to_s.gsub(/[R$\s]/, "")
    if stripped.include?(",")
      normalized = stripped.delete(".").tr(",", ".")
    elsif stripped.match?(/\A-?\d+\.\d{1,2}\z/)
      normalized = stripped
    else
      normalized = stripped.delete(".")
    end
    return nil unless normalized.match?(/\A-?\d+(\.\d{1,2})?\z/)
    (BigDecimal(normalized) * 100).to_i
  end

  def format(cents)
    sign = cents.negative? ? "-" : ""
    whole, fraction = cents.abs.divmod(100)
    "#{sign}#{whole.to_s.gsub(/(\d)(?=(\d{3})+\z)/, '\1.')},#{fraction.to_s.rjust(2, '0')}"
  end
end

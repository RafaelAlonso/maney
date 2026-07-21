require "bigdecimal"

module BrlMoney
  module_function

  # "1.234,56" | "1234,56" | "-50" | "R$ 900" -> integer cents; nil se inválido.
  def parse(text)
    normalized = text.to_s.gsub(/[R$\s.]/, "").tr(",", ".")
    return nil unless normalized.match?(/\A-?\d+(\.\d{1,2})?\z/)
    (BigDecimal(normalized) * 100).to_i
  end

  def format(cents)
    sign = cents.negative? ? "-" : ""
    reais, centavos = cents.abs.divmod(100)
    "#{sign}#{reais.to_s.gsub(/(\d)(?=(\d{3})+\z)/, '\1.')},#{centavos.to_s.rjust(2, '0')}"
  end
end

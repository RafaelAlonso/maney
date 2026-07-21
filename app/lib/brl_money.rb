require "bigdecimal"

module BrlMoney
  module_function

  # "1.234,56" | "1234,56" | "-50" | "R$ 900" -> integer cents; nil se inválido.
  def parse(text)
    normalized = text.to_s.gsub(/[R$\s.]/, "").tr(",", ".")
    return nil unless normalized.match?(/\A-?\d+(\.\d{1,2})?\z/)
    (BigDecimal(normalized) * 100).to_i
  end
end

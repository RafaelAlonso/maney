require "bigdecimal"

module BrlMoney
  module_function

  # "1.234,56" | "1234,56" | "-50" | "R$ 900" -> integer cents; nil se inválido.
  #
  # O ponto é ambíguo sem a vírgula: com vírgula, ela é o separador decimal e
  # todo ponto é milhar (como já era). Sem vírgula, um único ponto seguido de
  # 1 ou 2 dígitos até o fim É o decimal ("12.34" -> R$ 12,34); qualquer outro
  # padrão (dois pontos, ou três dígitos após o ponto) é milhar ("1.000" ->
  # R$ 1.000,00), igual ao formato de exibição.
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
    reais, centavos = cents.abs.divmod(100)
    "#{sign}#{reais.to_s.gsub(/(\d)(?=(\d{3})+\z)/, '\1.')},#{centavos.to_s.rjust(2, '0')}"
  end
end

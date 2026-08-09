/// Validacao de formato + digitos verificadores de CNPJ.
class CnpjValidator {
  CnpjValidator._();

  static String stripFormatting(String cnpj) => cnpj.replaceAll(RegExp(r'[^0-9]'), '');

  static bool isValid(String rawCnpj) {
    final cnpj = stripFormatting(rawCnpj);
    if (cnpj.length != 14) return false;
    if (RegExp(r'^(\d)\1*$').hasMatch(cnpj)) return false;

    final numbers = cnpj.split('').map(int.parse).toList();

    int calcDigit(List<int> base, List<int> weights) {
      var sum = 0;
      for (var i = 0; i < base.length; i++) {
        sum += base[i] * weights[i];
      }
      final rest = sum % 11;
      return rest < 2 ? 0 : 11 - rest;
    }

    const weights1 = [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
    const weights2 = [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];

    final digit1 = calcDigit(numbers.sublist(0, 12), weights1);
    if (digit1 != numbers[12]) return false;

    final digit2 = calcDigit(numbers.sublist(0, 13), weights2);
    if (digit2 != numbers[13]) return false;

    return true;
  }

  static String format(String rawCnpj) {
    final cnpj = stripFormatting(rawCnpj);
    if (cnpj.length != 14) return rawCnpj;
    return '${cnpj.substring(0, 2)}.${cnpj.substring(2, 5)}.${cnpj.substring(5, 8)}/'
        '${cnpj.substring(8, 12)}-${cnpj.substring(12, 14)}';
  }
}

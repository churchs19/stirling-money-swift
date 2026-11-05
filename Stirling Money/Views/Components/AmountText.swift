import SwiftUI

/// A money amount in local currency, red when negative, with aligned digits.
struct AmountText: View {
    let amount: Decimal

    init(_ amount: Decimal) {
        self.amount = amount
    }

    var body: some View {
        Text(amount, format: .localCurrency)
            .monospacedDigit()
            .foregroundStyle(amount < 0 ? .red : .primary)
    }
}

#Preview {
    VStack {
        AmountText(1250.75)
        AmountText(-342.18)
    }
}

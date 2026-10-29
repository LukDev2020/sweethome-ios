import SwiftUI

// MARK: - Disguise Calculator View
//
// A fully functional calculator that is visually indistinguishable from
// the iOS system calculator. It performs real arithmetic.
//
// Secret trigger: when the user presses "=" and the current input matches
// a known secret code (911, 999, or the user's duress code),
// DisguiseModeService reveals the real app and optionally fires a silent SOS.
//
// Design rules:
//   — No safety branding, no SOS button, no app name.
//   — Dark theme matching the iOS built-in calculator.
//   — The view is a drop-in sheet or full-screen cover: nothing in the
//     navigation bar or title gives away its purpose.

struct DisguiseCalculatorView: View {

    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var disguise = DisguiseModeService.shared

    // MARK: - Calculator State

    @State private var display: String = "0"
    @State private var storedValue: Double = 0
    @State private var currentOperator: CalcOperator? = nil
    @State private var shouldResetDisplay: Bool = false
    @State private var justEvaluated: Bool = false

    // Raw digit/operator sequence typed by the user (for secret code detection).
    // We track only digit characters; operators and = reset it intentionally
    // except when we need to check the code before resetting.
    @State private var inputSequence: String = ""

    // Trigger the reveal animation
    @State private var isRevealing: Bool = false

    // MARK: - Layout Constants

    private let buttonSpacing: CGFloat = 12
    private let buttonSize: CGFloat = {
        let screen = UIScreen.main.bounds.width
        return (screen - 5 * 12) / 4
    }()

    // MARK: - Colors (iOS calculator palette)

    private let bgColor        = Color(red: 0.0,  green: 0.0,  blue: 0.0)
    private let funcColor      = Color(red: 0.647, green: 0.647, blue: 0.647)
    private let funcLabelColor = Color.black
    private let opColor        = Color(red: 1.0,  green: 0.584, blue: 0.0)
    private let numColor       = Color(red: 0.2,  green: 0.2,  blue: 0.2)
    private let labelColor     = Color.white

    // MARK: - Button Layout

    private let rows: [[CalcButton]] = [
        [.clear, .plusMinus, .percent, .divide],
        [.digit("7"), .digit("8"), .digit("9"), .multiply],
        [.digit("4"), .digit("5"), .digit("6"), .subtract],
        [.digit("1"), .digit("2"), .digit("3"), .add],
        [.digit("0"), .decimal, .equals],
    ]

    // MARK: - Body

    var body: some View {
        ZStack {
            bgColor.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                displayArea
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
                buttonGrid
                    .padding(.horizontal, buttonSpacing)
                    .padding(.bottom, 20)
            }
        }
        .opacity(isRevealing ? 0 : 1)
        .animation(.easeIn(duration: 0.25), value: isRevealing)
        // Hide the navigation bar so there's no title to reveal the app.
        .navigationBarHidden(true)
        .statusBar(hidden: false)
        .preferredColorScheme(.dark)
    }

    // MARK: - Display

    private var displayArea: some View {
        HStack {
            Spacer()
            Text(formattedDisplay)
                .font(.system(size: displayFontSize, weight: .light, design: .default))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.1), value: display)
        }
        .frame(height: 100)
    }

    private var displayFontSize: CGFloat {
        let len = formattedDisplay.count
        if len <= 6  { return 96 }
        if len <= 9  { return 72 }
        if len <= 12 { return 52 }
        return 40
    }

    private var formattedDisplay: String {
        // If the raw string already contains a decimal point or is an error,
        // return as-is.
        if display == "Error" { return "Error" }
        if display.contains(".") {
            // Trim trailing zeros after decimal only if not actively typing
            if justEvaluated {
                return trimTrailingZeros(display)
            }
            return display
        }
        // Format with grouping separators
        if let value = Double(display) {
            return formatNumber(value)
        }
        return display
    }

    // MARK: - Button Grid

    private var buttonGrid: some View {
        VStack(spacing: buttonSpacing) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(spacing: buttonSpacing) {
                    ForEach(rows[rowIndex], id: \.id) { button in
                        calcButton(button)
                    }
                }
            }
        }
    }

    // MARK: - Individual Button

    @ViewBuilder
    private func calcButton(_ button: CalcButton) -> some View {
        let isWide = button == .digit("0")
        let size = isWide
            ? CGSize(width: buttonSize * 2 + buttonSpacing, height: buttonSize)
            : CGSize(width: buttonSize, height: buttonSize)

        Button {
            handleTap(button)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: buttonSize / 2)
                    .fill(buttonBackground(button))
                    .frame(width: size.width, height: size.height)

                HStack {
                    if isWide { Spacer().frame(width: buttonSize * 0.38) }
                    Text(button.label)
                        .font(.system(size: button.labelSize, weight: .regular))
                        .foregroundColor(buttonLabel(button))
                    if isWide { Spacer() }
                }
                .frame(width: size.width, height: size.height)
            }
        }
        .buttonStyle(CalcButtonStyle())
        .frame(width: size.width, height: size.height)
    }

    private func buttonBackground(_ button: CalcButton) -> Color {
        switch button {
        case .clear, .plusMinus, .percent:
            return funcColor
        case .add, .subtract, .multiply, .divide, .equals:
            // Highlight the active operator
            if case .equals = button { return opColor }
            if let op = currentOperator, button == op.calcButton {
                // When operator is active and display hasn't been reset yet,
                // swap colors (white button, orange label)
                return shouldResetDisplay ? .white : opColor
            }
            return opColor
        default:
            return numColor
        }
    }

    private func buttonLabel(_ button: CalcButton) -> Color {
        switch button {
        case .clear, .plusMinus, .percent:
            return funcLabelColor
        case .add, .subtract, .multiply, .divide:
            if let op = currentOperator, button == op.calcButton, shouldResetDisplay {
                return opColor
            }
            return labelColor
        default:
            return labelColor
        }
    }

    // MARK: - Input Handling

    private func handleTap(_ button: CalcButton) {
        switch button {

        case .digit(let d):
            appendDigit(d)

        case .decimal:
            appendDecimal()

        case .add:
            applyOperator(.add)

        case .subtract:
            applyOperator(.subtract)

        case .multiply:
            applyOperator(.multiply)

        case .divide:
            applyOperator(.divide)

        case .equals:
            evaluate()

        case .clear:
            clear()

        case .plusMinus:
            toggleSign()

        case .percent:
            applyPercent()
        }
    }

    // MARK: - Digit & Decimal

    private func appendDigit(_ digit: String) {
        justEvaluated = false

        if shouldResetDisplay {
            display = digit == "0" ? "0" : digit
            shouldResetDisplay = false
            inputSequence = digit
        } else {
            if display == "0" && digit != "0" {
                display = digit
            } else if display == "0" && digit == "0" {
                // no-op — don't allow leading zeros
            } else {
                guard display.count < 15 else { return }
                display += digit
            }
            inputSequence += digit
        }
    }

    private func appendDecimal() {
        justEvaluated = false
        if shouldResetDisplay {
            display = "0."
            shouldResetDisplay = false
            inputSequence = "0."
            return
        }
        if !display.contains(".") {
            display += "."
        }
    }

    // MARK: - Operators

    private func applyOperator(_ op: CalcOperator) {
        justEvaluated = false

        // If we already have an operator and a new value, chain the calculation
        if let existingOp = currentOperator, !shouldResetDisplay {
            if let lhs = Double(display) {
                let result = compute(storedValue, lhs, op: existingOp)
                storedValue = result
                display = rawString(result)
            }
        } else {
            storedValue = Double(display) ?? 0
        }

        currentOperator = op
        shouldResetDisplay = true
        inputSequence = ""
    }

    // MARK: - Evaluate

    private func evaluate() {
        // Check secret code BEFORE we wipe the display.
        let code = inputSequence
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let isSecret = disguise.isSecretCalculatorCode(code)

        guard let op = currentOperator else {
            // No operator — check if the entire display is a secret code
            // (user typed "911" then "=" without any operator)
            let directCode = display.trimmingCharacters(in: .whitespacesAndNewlines)
            if disguise.isSecretCalculatorCode(directCode) {
                triggerReveal()
                return
            }
            justEvaluated = true
            return
        }

        let rhs = Double(display) ?? 0
        let result = compute(storedValue, rhs, op: op)

        if isSecret {
            // Show the result briefly, then reveal
            display = rawString(result)
            currentOperator = nil
            shouldResetDisplay = true
            inputSequence = ""
            justEvaluated = true
            triggerReveal()
            return
        }

        display = rawString(result)
        storedValue = result
        currentOperator = nil
        shouldResetDisplay = true
        inputSequence = ""
        justEvaluated = true
    }

    // MARK: - Utility Operations

    private func clear() {
        if display != "0" && !shouldResetDisplay {
            display = "0"
        } else {
            display = "0"
            storedValue = 0
            currentOperator = nil
        }
        inputSequence = ""
        shouldResetDisplay = false
        justEvaluated = false
    }

    private func toggleSign() {
        if let value = Double(display) {
            let toggled = -value
            display = rawString(toggled)
        }
    }

    private func applyPercent() {
        if let value = Double(display) {
            let result = value / 100.0
            display = rawString(result)
            justEvaluated = true
        }
    }

    // MARK: - Arithmetic Engine

    private func compute(_ lhs: Double, _ rhs: Double, op: CalcOperator) -> Double {
        switch op {
        case .add:      return lhs + rhs
        case .subtract: return lhs - rhs
        case .multiply: return lhs * rhs
        case .divide:
            guard rhs != 0 else {
                display = "Error"
                return 0
            }
            return lhs / rhs
        }
    }

    // MARK: - Number Formatting

    /// Convert a Double to the minimal string representation used in the display state.
    private func rawString(_ value: Double) -> String {
        if value.isNaN || value.isInfinite {
            return "Error"
        }
        // If the value is an integer (no fractional part), show without decimal
        if value.truncatingRemainder(dividingBy: 1) == 0,
           abs(value) < 1e15 {
            return String(Int64(value))
        }
        // Otherwise show up to 10 significant digits
        let s = String(format: "%.10g", value)
        return s
    }

    /// Format a Double with thousands separators for the display label.
    private func formatNumber(_ value: Double) -> String {
        if value.isNaN || value.isInfinite { return "Error" }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 10
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = true

        return formatter.string(from: NSNumber(value: value)) ?? display
    }

    /// Remove trailing zeros from a decimal string (e.g. "3.50" → "3.5", "3.00" → "3").
    private func trimTrailingZeros(_ s: String) -> String {
        guard s.contains(".") else { return s }
        var result = s
        while result.hasSuffix("0") { result.removeLast() }
        if result.hasSuffix(".") { result.removeLast() }
        return result
    }

    // MARK: - Secret Reveal

    private func triggerReveal() {
        // Fade the calculator out, then hand off to DisguiseModeService.
        withAnimation(.easeIn(duration: 0.2)) {
            isRevealing = true
        }
        // Short delay so the animation can play before state changes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            Task { @MainActor in
                disguise.handleSecretGestureDetected()
            }
        }
    }
}

// MARK: - Calculator Button Model

private enum CalcButton: Equatable {
    case digit(String)
    case decimal
    case add, subtract, multiply, divide, equals
    case clear, plusMinus, percent

    var id: String {
        switch self {
        case .digit(let d): return "d_\(d)"
        case .decimal:      return "dec"
        case .add:          return "add"
        case .subtract:     return "sub"
        case .multiply:     return "mul"
        case .divide:       return "div"
        case .equals:       return "eq"
        case .clear:        return "clr"
        case .plusMinus:    return "pm"
        case .percent:      return "pct"
        }
    }

    var label: String {
        switch self {
        case .digit(let d): return d
        case .decimal:      return "."
        case .add:          return "+"
        case .subtract:     return "−"
        case .multiply:     return "×"
        case .divide:       return "÷"
        case .equals:       return "="
        case .clear:        return "AC"
        case .plusMinus:    return "+/−"
        case .percent:      return "%"
        }
    }

    var labelSize: CGFloat {
        switch self {
        case .digit, .decimal: return 40
        case .add, .subtract, .multiply, .divide, .equals: return 44
        case .clear, .plusMinus, .percent: return 28
        }
    }
}

// MARK: - Operator Model

private enum CalcOperator {
    case add, subtract, multiply, divide

    var calcButton: CalcButton {
        switch self {
        case .add:      return .add
        case .subtract: return .subtract
        case .multiply: return .multiply
        case .divide:   return .divide
        }
    }
}

// MARK: - Button Press Style

private struct CalcButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .opacity(configuration.isPressed ? 0.75 : 1.0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

// MARK: - Preview

#if DEBUG
struct DisguiseCalculatorView_Previews: PreviewProvider {
    static var previews: some View {
        DisguiseCalculatorView()
            .environmentObject(AppCoordinator())
            .preferredColorScheme(.dark)
    }
}
#endif

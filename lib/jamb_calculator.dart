import 'package:flutter/material.dart';

/// Call this from any screen's calculator button to show the JAMB-style
/// basic calculator as a bottom sheet.
void showJambCalculator(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const JambCalculatorSheet(),
  );
}

class JambCalculatorSheet extends StatefulWidget {
  const JambCalculatorSheet({super.key});

  @override
  State<JambCalculatorSheet> createState() => _JambCalculatorSheetState();
}

class _JambCalculatorSheetState extends State<JambCalculatorSheet> {
  String _display = '0';
  double? _stored;
  String? _pendingOp;
  bool _shouldResetDisplay = false;

  void _inputDigit(String digit) {
    setState(() {
      if (_display == '0' || _shouldResetDisplay) {
        _display = digit;
        _shouldResetDisplay = false;
      } else {
        _display += digit;
      }
    });
  }

  void _inputDecimal() {
    setState(() {
      if (_shouldResetDisplay) {
        _display = '0.';
        _shouldResetDisplay = false;
        return;
      }
      if (!_display.contains('.')) _display += '.';
    });
  }

  void _clear() {
    setState(() {
      _display = '0';
      _stored = null;
      _pendingOp = null;
      _shouldResetDisplay = false;
    });
  }

  void _setOperator(String op) {
    setState(() {
      _stored = double.tryParse(_display) ?? 0;
      _pendingOp = op;
      _shouldResetDisplay = true;
    });
  }

  void _equals() {
    if (_pendingOp == null || _stored == null) return;
    final current = double.tryParse(_display) ?? 0;
    double result;
    switch (_pendingOp) {
      case '+':
        result = _stored! + current;
        break;
      case '-':
        result = _stored! - current;
        break;
      case '×':
        result = _stored! * current;
        break;
      case '÷':
        result = current == 0 ? 0 : _stored! / current;
        break;
      default:
        result = current;
    }
    setState(() {
      _display = result == result.roundToDouble() ? result.toInt().toString() : result.toString();
      _stored = null;
      _pendingOp = null;
      _shouldResetDisplay = true;
    });
  }

  Widget _button(String label, {Color? bg, Color? fg, VoidCallback? onTap}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: AspectRatio(
          aspectRatio: 1.3,
          child: Material(
            color: bg ?? Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onTap ?? () => _inputDigit(label),
              child: Center(
                child: Text(label, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: fg)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(color: scheme.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
      padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(color: scheme.onSurfaceVariant.withOpacity(0.4), borderRadius: BorderRadius.circular(4)),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Calculator', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
            alignment: Alignment.centerRight,
            child: Text(_display, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 12),
          Row(children: [_button('7'), _button('8'), _button('9'), _button('÷', onTap: () => _setOperator('÷'))]),
          Row(children: [_button('4'), _button('5'), _button('6'), _button('×', onTap: () => _setOperator('×'))]),
          Row(children: [_button('1'), _button('2'), _button('3'), _button('-', onTap: () => _setOperator('-'))]),
          Row(children: [
            _button('C', bg: scheme.errorContainer, fg: scheme.onErrorContainer, onTap: _clear),
            _button('0'),
            _button('.', onTap: _inputDecimal),
            _button('+', onTap: () => _setOperator('+')),
          ]),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(onPressed: _equals, child: const Text('=', style: TextStyle(fontSize: 20))),
          ),
        ],
      ),
    );
  }
}

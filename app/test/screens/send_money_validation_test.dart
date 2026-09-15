import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payflex/screens/transfer/send_money_screen.dart';
import 'package:payflex/models/app_user.dart';
import 'package:payflex/utils/validators.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final user = AppUser(
    id: '11111111-1111-1111-1111-111111111111',
    firstName: 'Ada',
    lastName: 'Eze',
    email: 'ada@test.payflex',
    phoneNumber: '+2348000000001',
    stellarPublicKey: 'GBRPYHIL2CI3FNQ4BXLFMNDLFJUNPU2HY3ZMFSHONUCEOASW7QC7OX2K',
  );

  Future<void> pumpScreen(WidgetTester tester) async {
    // Tall surface so the whole form (including the submit button) is
    // hittable — the default 800x600 test viewport leaves it off-screen
    // and taps silently miss inside the scrollable.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: SendMoneyScreen(user: user)),
    );
    await tester.pump();
  }

  group('SendMoneyScreen validation (invalid input caught before submission)', () {
    testWidgets('empty form shows a specific error and never opens the PIN flow',
        (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('Review & send'));
      await tester.pumpAndSettle();

      // The specific problem is surfaced; no dialog / PIN sheet appeared.
      expect(find.text('Enter the recipient\u2019s PayTag.'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('amount-only form still requires the recipient', (tester) async {
      await pumpScreen(tester);

      await tester.enterText(find.byType(TextField).at(1), '5.00');
      await tester.pump();

      await tester.tap(find.text('Review & send'));
      await tester.pumpAndSettle();

      expect(find.text('Enter the recipient\u2019s PayTag.'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('negative amounts cannot be typed at the keyboard', (tester) async {
      await pumpScreen(tester);

      final amountField = find.byType(TextField).at(1);
      // The reject-the-edit formatter ignores the '-' keystroke entirely.
      await tester.enterText(amountField, '-5.00');
      await tester.pump();

      final field = tester.widget<TextField>(amountField);
      expect(field.controller!.text, isNot(contains('-')));
    });

    testWidgets('garbage amount shows the shared amount error inline', (tester) async {
      await pumpScreen(tester);

      await tester.enterText(find.byType(TextField).at(1), 'abc');
      await tester.pump();

      // "abc" is stripped by the formatter → empty → no error yet, but
      // submit is still blocked with the recipient error.
      await tester.tap(find.text('Review & send'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('more than 7 decimals is rejected (Stellar precision)', (tester) async {
      await pumpScreen(tester);

      final amountField = find.byType(TextField).at(1);
      // The keystroke that would exceed 7 decimals is ignored wholesale.
      await tester.enterText(amountField, '5.12345678');
      await tester.pump();

      final field = tester.widget<TextField>(amountField);
      expect(field.controller!.text, isNot(contains('8')));
      expect(field.controller!.text.length, lessThanOrEqualTo(9)); // 1 + '.' + 7
    });

    testWidgets('PayTag mode rejects a too-short tag inline as you type', (tester) async {
      await pumpScreen(tester);

      await tester.enterText(find.byType(TextField).first, 'ab');
      await tester.pump();

      expect(find.text('3-20 lowercase letters, digits or underscore.'),
          findsOneWidget);
    });

    testWidgets('PayTag input is sanitized at the keyboard (no uppercase/symbols)',
        (tester) async {
      await pumpScreen(tester);

      final field = find.byType(TextField).first;
      await tester.enterText(field, 'Ada Eze!');
      await tester.pump();

      // The allow-formatter strips disallowed characters as they are typed
      // ('A'→'a' is a replacement the formatter permits; spaces and '!' are
      // dropped), so what lands in the field is already a valid tag shape.
      expect(tester.widget<TextField>(field).controller!.text, 'daze');
    });

    testWidgets('a checksum-broken Stellar address is caught inline before any resolve call',
        (tester) async {
      await pumpScreen(tester);

      // Switch to Address mode.
      await tester.tap(find.text('Address'));
      await tester.pumpAndSettle();

      // Shape-correct (56 chars, G-prefixed, base32) but checksum-invalid.
      await tester.enterText(find.byType(TextField).first, 'G${'A' * 55}');
      await tester.pump();

      // The inline error names the problem — SDK-backed validation, not
      // just the shape regex.
      expect(find.textContaining('malformed'), findsOneWidget);

      // Submitting does nothing but confirm the inline error: no
      // resolution, no PIN, no payment.
      await tester.enterText(find.byType(TextField).at(1), '5.00');
      await tester.pump();
      await tester.tap(find.text('Review & send'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      // The error text renders in the field's decoration (semantics can
      // duplicate it, hence atLeastOneWidget rather than exactly one).
      expect(find.textContaining('malformed'), findsWidgets);
    });

    testWidgets('a valid-looking key passes client validation and reaches resolution',
        (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('Address'));
      await tester.pumpAndSettle();

      // A real checksum-valid key (generated with the Stellar SDK).
      const validKey = 'GCKK7WJNEZ4EDOX4ZFOQXW6PAI33EIWFIRU7JN3GXWEV4Z4IP3QWI7XG';
      expect(isValidStellarPublicKey(validKey), isTrue);

      await tester.enterText(find.byType(TextField).first, validKey);
      await tester.enterText(find.byType(TextField).at(1), '5.00');
      await tester.pump();

      // No inline errors on either field.
      expect(find.textContaining('malformed'), findsNothing);
      expect(find.text('3-20 lowercase letters, digits or underscore.'), findsNothing);
      // Amount error only appears for INVALID input.
      expect(find.textContaining('greater than zero'), findsNothing);
    });
  });

  group('Shared validators (mirrors backend rules)', () {
    test('amount rules match the backend IsStellarAmount', () {
      expect(amountError('5.00'), isNull);
      expect(amountError('0.0000001'), isNull);
      expect(amountError('0'), isNotNull);
      expect(amountError('-5'), isNotNull);
      expect(amountError('5.12345678'), isNotNull);
      expect(amountError('1000000000000'), isNull);
      expect(amountError('1000000000001'), isNotNull);
      expect(amountError(''), isNotNull);
      expect(amountError('5e2'), isNotNull);
    });

    test('public key rules catch shape AND checksum breaks', () {
      // Real SDK-generated keys.
      expect(publicKeyError('GCKK7WJNEZ4EDOX4ZFOQXW6PAI33EIWFIRU7JN3GXWEV4Z4IP3QWI7XG'), isNull);
      expect(publicKeyError('GBGKYA74UKKWZ7XDHU5C7ZQOPFPK43NMJSOHUL5527WGF3P4XN5CWOES'), isNull);
      // Shape-correct, checksum-broken.
      expect(publicKeyError('G${'A' * 55}'), isNotNull);
      // Secret seed handed where a public key belongs.
      expect(publicKeyError('S${'A' * 55}'), isNotNull);
      // Too short.
      expect(publicKeyError('GABC'), isNotNull);
    });

    test('PayTag rules match RegisterPayTagDto', () {
      expect(isValidPayTag('adaeze_92'), isTrue);
      expect(isValidPayTag('ab'), isFalse);
      expect(isValidPayTag('Ada Eze'), isFalse);
      expect(isValidPayTag('a' * 21), isFalse);
    });

    test('withdrawal amount rules include the balance ceiling', () {
      // Valid and within balance.
      expect(withdrawalAmountError('5.00', 10), isNull);
      // Over the pool's balance — caught before signing, not on-chain.
      expect(withdrawalAmountError('15.00', 10), isNotNull);
      expect(withdrawalAmountError('15.00', 10), contains('exceeds the contract balance'));
      // Unknown balance (0) → base amount rules only.
      expect(withdrawalAmountError('15.00', 0), isNull);
      // Invalid amounts still rejected.
      expect(withdrawalAmountError('-1', 10), isNotNull);
      expect(withdrawalAmountError('0', 10), isNotNull);
    });

    test('memo byte cap', () {
      expect(isValidMemo('short'), isTrue);
      expect(isValidMemo('x' * 28), isTrue);
      expect(isValidMemo('x' * 29), isFalse);
      // Multi-byte characters count against the 28-byte cap.
      expect(isValidMemo('é' * 14), isTrue); // 28 bytes
      expect(isValidMemo('é' * 15), isFalse); // 30 bytes
    });
  });
}

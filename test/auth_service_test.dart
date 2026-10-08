import 'package:flutter_test/flutter_test.dart';
import 'package:measure_reality/data/auth_service.dart';

void main() {
  group('login name rules', () {
    test('only the first word counts, capitals do not matter', () {
      expect(AuthService.firstNameOf('Sunny Alam Chaudhary'), 'sunny');
      expect(AuthService.firstNameOf('Sunny Alam'), 'sunny');
      expect(AuthService.firstNameOf('  SUNNY  '), 'sunny');
      expect(AuthService.firstNameOf('sUnNy'), 'sunny');
    });

    test('pretty first name', () {
      expect(AuthService.prettyFirstName('sUNNY alam'), 'Sunny');
    });

    test('initials', () {
      const u = AuthUser(id: '1', name: 'sunny alam chaudhary', phone: '', email: '');
      expect(u.initials, 'SC');
      const v = AuthUser(id: '2', name: 'sunny', phone: '', email: '');
      expect(v.initials, 'S');
    });
  });

  group('saved login', () {
    test('keeps the session token', () {
      const u = AuthUser(id: '1', name: 'Sunny Alam', phone: '9876543210', email: 'a@b.co', token: 'abc');
      final back = AuthUser.fromJson(u.toJson());
      expect(back, isNotNull);
      expect(back!.token, 'abc');
      expect(back.name, 'Sunny Alam');
    });

    test('rejects broken data', () {
      expect(AuthUser.fromJson(null), isNull);
      expect(AuthUser.fromJson({'id': '', 'name': 'x'}), isNull);
    });
  });

  group('validation', () {
    test('name', () {
      expect(AuthService.validateName(''), isNotNull);
      expect(AuthService.validateName('S'), isNotNull);
      expect(AuthService.validateName('Sunny Alam'), isNull);
    });

    test('phone', () {
      expect(AuthService.validatePhone('12'), isNotNull);
      expect(AuthService.validatePhone('98765 43210'), isNull);
      expect(AuthService.validatePhone('+91 98765-43210'), isNull);
    });

    test('email', () {
      expect(AuthService.validateEmail('abc'), isNotNull);
      expect(AuthService.validateEmail('a@b.co'), isNull);
    });
  });
}

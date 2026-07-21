import 'package:equatable/equatable.dart';

class AppUser extends Equatable {
  final String id;
  final String email;
  final String? name;
  final String? photoUrl;
  final String? zetraId;
  final String? zetraMail;

  const AppUser({
    required this.id,
    required this.email,
    this.name,
    this.photoUrl,
    this.zetraId,
    this.zetraMail,
  });

  factory AppUser.empty() => const AppUser(id: '', email: '');

  bool get isEmpty => id.isEmpty;
  bool get isNotEmpty => id.isNotEmpty;

  @override
  List<Object?> get props => [id, email, name, photoUrl, zetraId, zetraMail];
}

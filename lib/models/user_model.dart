import 'dart:convert';

class UserModel {
  final String id;
  final String email;
  final String displayName;
  final String? photoUrl;
  final DateTime? lastLoginAt;
  final Map<String, dynamic>? preferences;

  UserModel({
    required this.id,
    required this.email,
    required this.displayName,
    this.photoUrl,
    this.lastLoginAt,
    this.preferences,
  });

  /// Create UserModel from JSON
  factory UserModel.fromJson(String jsonString) {
    final Map<String, dynamic> json = jsonDecode(jsonString);
    return UserModel(
      id: json['id'] ?? '',
      email: json['email'] ?? '',
      displayName: json['displayName'] ?? '',
      photoUrl: json['photoUrl'],
      lastLoginAt: json['lastLoginAt'] != null 
          ? DateTime.parse(json['lastLoginAt']) 
          : null,
      preferences: json['preferences'],
    );
  }

  /// Convert UserModel to JSON string
  String toJson() {
    final Map<String, dynamic> json = {
      'id': id,
      'email': email,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'lastLoginAt': lastLoginAt?.toIso8601String(),
      'preferences': preferences,
    };
    return jsonEncode(json);
  }

  /// Create a copy with updated fields
  UserModel copyWith({
    String? id,
    String? email,
    String? displayName,
    String? photoUrl,
    DateTime? lastLoginAt,
    Map<String, dynamic>? preferences,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      preferences: preferences ?? this.preferences,
    );
  }

  @override
  String toString() {
    return 'UserModel(id: $id, email: $email, displayName: $displayName)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UserModel &&
        other.id == id &&
        other.email == email &&
        other.displayName == displayName &&
        other.photoUrl == photoUrl;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        email.hashCode ^
        displayName.hashCode ^
        photoUrl.hashCode;
  }
}
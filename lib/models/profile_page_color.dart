import 'package:flutter/material.dart';

class ProfilePageColorOption {
  const ProfilePageColorOption({
    required this.key,
    required this.label,
    required this.color,
  });

  final String key;
  final String label;
  final Color color;
}

class ProfilePageColors {
  const ProfilePageColors._();

  static const String defaultKey = 'yellow';
  static const Set<String> standardKeys = {'blue', 'yellow', 'green'};

  static const List<ProfilePageColorOption> options = [
    ProfilePageColorOption(key: 'red', label: '赤', color: Color(0xFFD00303)),
    ProfilePageColorOption(
      key: 'magenta',
      label: 'マゼンタ',
      color: Color(0xFFFF2CB3),
    ),
    ProfilePageColorOption(key: 'blue', label: '青', color: Color(0xFF2D9CFF)),
    ProfilePageColorOption(
      key: 'yellow',
      label: '黄色',
      color: Color(0xFFF1D600),
    ),
    ProfilePageColorOption(key: 'green', label: '緑', color: Color(0xFF00C875)),
    ProfilePageColorOption(key: 'purple', label: '紫', color: Color(0xFFA855F7)),
    ProfilePageColorOption(key: 'gray', label: 'グレー', color: Color(0xFFAAB2BD)),
    ProfilePageColorOption(key: 'brown', label: '茶色', color: Color(0xFFC9854B)),
    ProfilePageColorOption(key: 'pink', label: '桃色', color: Color(0xFFFFC1D9)),
    ProfilePageColorOption(
      key: 'light_blue',
      label: '水色',
      color: Color(0xFF36CFFF),
    ),
    ProfilePageColorOption(
      key: 'orange',
      label: 'オレンジ',
      color: Color(0xFFFF7A1A),
    ),
    ProfilePageColorOption(
      key: 'yellow_green',
      label: '黄緑',
      color: Color(0xFF9BD600),
    ),
    ProfilePageColorOption(
      key: 'red_purple',
      label: '赤紫',
      color: Color(0xFF882255),
    ),
    ProfilePageColorOption(
      key: 'emerald',
      label: 'エメラルド',
      color: Color(0xFF20E0D0),
    ),
  ];

  static bool isValidKey(String? key) =>
      options.any((option) => option.key == key);

  static String normalizeKey(String? key) =>
      isValidKey(key) ? key! : defaultKey;

  static Color colorFor(String? key) {
    final normalized = normalizeKey(key);
    return options.firstWhere((option) => option.key == normalized).color;
  }
}

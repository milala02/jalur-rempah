import 'package:flutter/material.dart';

class DslSyntaxHighlightController extends TextEditingController {
  DslSyntaxHighlightController({super.text});

  static final RegExp _tokenRegex = RegExp(
    r'(#[^\n]*)|(\b(?:aturan|jika|maka|dan|atau|biar|maks)\b)|(\b(?:di|harga|stok_pasar|stok_kapal|koin|kapasitas_sisa|rute_ke|harga_terakhir|ambil|musim)\b)|(\b(?:beli|jual|berlayar|tunggu|simpan)\b)|(\b(?:Banda|Ternate|Surabaya|Malaka|Makassar|Batavia|pala|cengkeh|garam|kain|lada_hitam|kayu_manis|kayu_cendana|kapur_barus|beras|kopi_jawa)\b)|(\b\d+\b)',
    caseSensitive: false,
  );

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseStyle = style ??
        TextStyle(
          fontFamily: 'monospace',
          fontSize: 13.5,
          color: isDark ? Colors.white : Colors.black87,
        );

    final keywordStyle = baseStyle.copyWith(
      color: isDark ? const Color(0xFF60A5FA) : const Color(0xFF1D4ED8),
      fontWeight: FontWeight.bold,
    );
    final sensorStyle = baseStyle.copyWith(
      color: isDark ? const Color(0xFFC084FC) : const Color(0xFF7E22CE),
      fontWeight: FontWeight.w600,
    );
    final actionStyle = baseStyle.copyWith(
      color: isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309),
      fontWeight: FontWeight.w700,
    );
    final entityStyle = baseStyle.copyWith(
      color: isDark ? const Color(0xFF34D399) : const Color(0xFF047857),
      fontWeight: FontWeight.w600,
    );
    final numberStyle = baseStyle.copyWith(
      color: isDark ? const Color(0xFFF87171) : const Color(0xFFB91C1C),
    );
    final commentStyle = baseStyle.copyWith(
      color: Colors.grey,
      fontStyle: FontStyle.italic,
    );

    final children = <TextSpan>[];
    final src = text;
    int lastEnd = 0;

    for (final match in _tokenRegex.allMatches(src)) {
      if (match.start > lastEnd) {
        children.add(
          TextSpan(
            text: src.substring(lastEnd, match.start),
            style: baseStyle,
          ),
        );
      }

      final tokenText = match.group(0)!;
      TextStyle tokenStyle = baseStyle;
      if (match.group(1) != null) {
        tokenStyle = commentStyle;
      } else if (match.group(2) != null) {
        tokenStyle = keywordStyle; // jika, maka, aturan, dan, atau, biar, maks
      } else if (match.group(3) != null) {
        tokenStyle = sensorStyle; // di, harga, stok_kapal, dll
      } else if (match.group(4) != null) {
        tokenStyle = actionStyle; // beli, jual, berlayar, tunggu, simpan
      } else if (match.group(5) != null) {
        tokenStyle = entityStyle; // pelabuhan & komoditas
      } else if (match.group(6) != null) {
        tokenStyle = numberStyle;
      }

      children.add(TextSpan(text: tokenText, style: tokenStyle));
      lastEnd = match.end;
    }

    if (lastEnd < src.length) {
      children.add(
        TextSpan(
          text: src.substring(lastEnd),
          style: baseStyle,
        ),
      );
    }

    return TextSpan(style: baseStyle, children: children);
  }
}

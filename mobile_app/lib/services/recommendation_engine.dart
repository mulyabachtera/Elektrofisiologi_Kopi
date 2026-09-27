import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════
//  PBEDS (Plant Bioelectric Early Detection System)
//  Recommendation Engine — Rekomendasi Perawatan Tanaman Kopi
//
//  Dasar Biologi:
//  - Sinyal bioelektrik (Action Potential / Variation Potential)
//    berkorelasi dengan tekanan turgor sel dan kondisi osmotik
//  - Z-score tinggi = deviasi besar dari baseline = stres fisiologis
//  - Stres osmotik umumnya disebabkan kekurangan air atau nutrisi
//
//  Referensi kebutuhan tanaman kopi:
//  - Air: 200-300mm/bulan (setara 7-10 hari sekali penyiraman)
//  - N (Urea): 200-300g/pohon/tahun, bagi 3 aplikasi
//  - P (SP-36): 100-150g/pohon/tahun
//  - K (KCl): 150-200g/pohon/tahun
//  - Mg (Kieserit): 50-100g/pohon jika defisiensi
// ═══════════════════════════════════════════════════════════════

enum KondisiCuaca { cerah, mendung, hujanRingan, hujanDeras }

class PlantRecommendation {
  final String rekomendasiSiram;
  final String urgensiSiram;        // "SEGERA" | "DALAM X HARI" | "BELUM PERLU"
  final int hariSiram;              // estimasi hari ke depan (0 = sekarang)
  final String rekomendasiPupuk;
  final String dosis;
  final String caraPemakaian;
  final String waktuTerbaik;
  final String peringatan;
  final Color warnaPrioritas;
  final IconData iconPrioritas;

  const PlantRecommendation({
    required this.rekomendasiSiram,
    required this.urgensiSiram,
    required this.hariSiram,
    required this.rekomendasiPupuk,
    required this.dosis,
    required this.caraPemakaian,
    required this.waktuTerbaik,
    required this.peringatan,
    required this.warnaPrioritas,
    required this.iconPrioritas,
  });
}

class RecommendationEngine {
  /// Generate rekomendasi berdasarkan status AI + cuaca
  static PlantRecommendation generate({
    required String status,
    required double zScore,
    required KondisiCuaca cuaca,
  }) {
    switch (status) {
      case 'NORMAL':
        return _rekomendasiNormal(cuaca, zScore);
      case 'STRES':
        return _rekomendasiStres(cuaca, zScore);
      case 'KRITIS':
        return _rekomendasiKritis(cuaca);
      default:
        return _rekomendasiDefault();
    }
  }

  // ── NORMAL ─────────────────────────────────────────────────
  static PlantRecommendation _rekomendasiNormal(KondisiCuaca cuaca, double z) {
    // Semakin mendekati batas atas (z mendekati 1.5), semakin hati-hati
    final bool mendekatiBatas = z.abs() > 1.0;

    String siram, urgensi, pupuk, dosis, cara, waktu, peringatan;
    int hari;

    switch (cuaca) {
      case KondisiCuaca.cerah:
        hari = mendekatiBatas ? 7 : 14;
        siram = 'Siram dalam $hari hari ke depan';
        urgensi = 'DALAM $hari HARI';
        pupuk = 'NPK 16-16-16';
        dosis = '200 gram per pohon';
        cara = 'Taburkan merata di sekitar drip-line (tepi tajuk)';
        waktu = 'Pagi hari setelah penyiraman, setiap 3 bulan';
        peringatan = 'Hindari pupuk di musim kemarau panjang tanpa siram dulu';
        break;

      case KondisiCuaca.mendung:
        hari = 10;
        siram = 'Siram dalam $hari hari ke depan';
        urgensi = 'DALAM $hari HARI';
        pupuk = 'NPK 16-16-16';
        dosis = '200 gram per pohon';
        cara = 'Taburkan di sekitar drip-line pohon';
        waktu = 'Sore hari saat mendung, kelembaban tanah ideal';
        peringatan = 'Monitor curah hujan, sesuaikan jadwal siram';
        break;

      case KondisiCuaca.hujanRingan:
        hari = 14;
        siram = 'Belum perlu disiram — manfaatkan air hujan';
        urgensi = 'BELUM PERLU';
        pupuk = 'NPK 16-16-16 + KCl';
        dosis = 'NPK 200g + KCl 100g per pohon';
        cara = 'Taburkan granular di sekitar drip-line sebelum hujan';
        waktu = 'Aplikasi saat hujan ringan adalah waktu TERBAIK — pupuk larut sempurna';
        peringatan = 'Pastikan hujan < 20mm/hari agar pupuk tidak terbawa aliran air';
        break;

      case KondisiCuaca.hujanDeras:
        hari = 14;
        siram = 'Tidak perlu disiram — curah hujan cukup';
        urgensi = 'TIDAK PERLU';
        pupuk = 'Tunda aplikasi pupuk';
        dosis = '-';
        cara = '-';
        waktu = 'Tunggu 2-3 hari setelah hujan berhenti';
        peringatan = '⚠️ Pupuk saat hujan deras berisiko terbawa air (runoff) — efisiensi < 20%';
        break;
    }

    return PlantRecommendation(
      rekomendasiSiram : siram,
      urgensiSiram     : urgensi,
      hariSiram        : hari,
      rekomendasiPupuk : pupuk,
      dosis            : dosis,
      caraPemakaian    : cara,
      waktuTerbaik     : waktu,
      peringatan       : peringatan,
      warnaPrioritas   : const Color(0xFF2E7D32), // hijau gelap
      iconPrioritas    : Icons.check_circle_rounded,
    );
  }

  // ── STRES ──────────────────────────────────────────────────
  static PlantRecommendation _rekomendasiStres(KondisiCuaca cuaca, double z) {
    String siram, urgensi, pupuk, dosis, cara, waktu, peringatan;
    int hari;

    switch (cuaca) {
      case KondisiCuaca.cerah:
        hari = 2;
        siram = 'Siram dalam 1-2 hari ke depan!';
        urgensi = 'SEGERA (1-2 HARI)';
        pupuk = 'Foliar Urea 2% + ZnSO₄ 0.5%';
        dosis = 'Urea 20g + ZnSO₄ 5g dilarutkan dalam 1 liter air';
        cara = 'Semprotkan merata ke seluruh permukaan daun (abaxial & adaxial)';
        waktu = 'Pagi hari (06:00-08:00) saat stomata terbuka, angin tenang';
        peringatan = '⚠️ Jangan aplikasikan pupuk granular — risiko membakar akar yang stres. '
            'Prioritaskan penyiraman dulu.';
        break;

      case KondisiCuaca.mendung:
        hari = 3;
        siram = 'Siram dalam 2-3 hari ke depan';
        urgensi = 'DALAM 3 HARI';
        pupuk = 'Foliar Urea 1.5% (dosis dikurangi saat mendung)';
        dosis = '15g Urea dalam 1 liter air';
        cara = 'Semprot daun saat mendung — stomata lebih terbuka';
        waktu = 'Pagi-siang saat mendung, sebelum hujan';
        peringatan = 'Monitor kelembaban tanah. Jika > 80%, tunda penyiraman.';
        break;

      case KondisiCuaca.hujanRingan:
        hari = 5;
        siram = 'Belum perlu disiram — hujan membantu pemulihan';
        urgensi = 'DALAM 4-5 HARI';
        pupuk = 'Kieserit (MgSO₄) — Magnesium untuk pemulihan stres';
        dosis = '50 gram per pohon';
        cara = 'Taburkan di sekitar perakaran, biarkan hujan melarutkan';
        waktu = 'Saat hujan ringan berlangsung';
        peringatan = 'Mg membantu pemulihan klorofil yang rusak akibat stres. '
            'Jangan aplikasi NPK dulu — tunggu tanaman pulih.';
        break;

      case KondisiCuaca.hujanDeras:
        hari = 5;
        siram = 'Tidak perlu disiram — hujan berlebihan';
        urgensi = 'TIDAK PERLU';
        pupuk = 'Tunda semua aplikasi pupuk';
        dosis = '-';
        cara = '-';
        waktu = 'Tunggu 3-5 hari setelah hujan reda';
        peringatan = '⚠️ Stres bisa disebabkan genangan air (hypoxia akar). '
            'Periksa drainase tanah di sekitar pohon!';
        break;
    }

    return PlantRecommendation(
      rekomendasiSiram : siram,
      urgensiSiram     : urgensi,
      hariSiram        : hari,
      rekomendasiPupuk : pupuk,
      dosis            : dosis,
      caraPemakaian    : cara,
      waktuTerbaik     : waktu,
      peringatan       : peringatan,
      warnaPrioritas   : const Color(0xFFF57C00), // oranye
      iconPrioritas    : Icons.warning_rounded,
    );
  }

  // ── KRITIS ─────────────────────────────────────────────────
  static PlantRecommendation _rekomendasiKritis(KondisiCuaca cuaca) {
    String siram, urgensi;

    if (cuaca == KondisiCuaca.hujanDeras) {
      siram = 'PERIKSA DRAINASE! Mungkin ada genangan air.';
      urgensi = 'SEGERA PERIKSA';
    } else {
      siram = 'SIRAM SEKARANG! Jangan tunda lebih dari 6 jam!';
      urgensi = 'DARURAT — SEKARANG';
    }

    return PlantRecommendation(
      rekomendasiSiram : siram,
      urgensiSiram     : urgensi,
      hariSiram        : 0,
      rekomendasiPupuk : '🚫 JANGAN PUPUK DULU',
      dosis            : '-',
      caraPemakaian    : 'Tidak ada pupuk saat kondisi kritis',
      waktuTerbaik     : 'Pupuk kembali 3-5 hari SETELAH tanaman pulih ke status Normal',
      peringatan       : '🚨 KRITIS: Tanaman mengalami depolarisasi membran ekstrem. '
          'Siram dengan 10-15 liter air bersih per pohon. '
          'Pupuk saat kondisi kritis = memperparah kerusakan sel!',
      warnaPrioritas   : const Color(0xFFD32F2F), // merah
      iconPrioritas    : Icons.emergency_rounded,
    );
  }

  static PlantRecommendation _rekomendasiDefault() {
    return const PlantRecommendation(
      rekomendasiSiram : 'Selesaikan scan terlebih dahulu',
      urgensiSiram     : '-',
      hariSiram        : -1,
      rekomendasiPupuk : '-',
      dosis            : '-',
      caraPemakaian    : '-',
      waktuTerbaik     : '-',
      peringatan       : '-',
      warnaPrioritas   : Colors.grey,
      iconPrioritas    : Icons.help_outline_rounded,
    );
  }
}

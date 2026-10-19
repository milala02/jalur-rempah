export interface RuleTemplate {
  readonly id: string;
  readonly title: string;
  readonly description: string;
  readonly source: string;
}

export const RULE_TEMPLATES: readonly RuleTemplate[] = [
  {
    id: 'pedagang-pala-banda-batavia',
    title: 'Jalur Klasik Pala (Banda - Batavia)',
    description:
      'Membeli pala di Banda saat stok melimpah, berlayar ke Batavia untuk menjualnya, dan membawa pulang garam dari Surabaya.',
    source: `# Templat 1: Jalur Klasik Pala (Banda <-> Batavia)
aturan jual_pala_di_batavia:
  jika di(Batavia) dan stok_kapal(pala) > 0
  maka jual(pala, semua)

aturan beli_pala_di_banda:
  jika di(Banda) dan harga(pala) <= 85 dan muatan_bebas() > 0
  maka beli(pala, maks)

aturan berangkat_ke_batavia:
  jika stok_kapal(pala) > 0
  maka berlayar(Batavia)

aturan kembali_ke_banda:
  jika stok_kapal(pala) == 0 dan bukan di(Banda)
  maka berlayar(Banda)
`,
  },
  {
    id: 'pedagang-cengkeh-ternate-malaka',
    title: 'Ekspedisi Cengkeh & Kain (Ternate - Malaka)',
    description:
      'Membeli cengkeh di Ternate untuk dijual di Malaka, lalu membeli kain di Malaka untuk dijual kembali di Ternate.',
    source: `# Templat 2: Pertukaran Dua Arah Cengkeh & Kain
aturan jual_cengkeh:
  jika di(Malaka) dan stok_kapal(cengkeh) > 0
  maka jual(cengkeh, semua)

aturan jual_kain:
  jika di(Ternate) dan stok_kapal(kain) > 0
  maka jual(kain, semua)

aturan beli_cengkeh_ternate:
  jika di(Ternate) dan harga(cengkeh) <= 110 dan muatan_bebas() > 0
  maka beli(cengkeh, maks)

aturan beli_kain_malaka:
  jika di(Malaka) dan harga(kain) <= 55 dan muatan_bebas() > 0
  maka beli(kain, maks)

aturan layar_ke_malaka:
  jika stok_kapal(cengkeh) > 0
  maka berlayar(Malaka)

aturan layar_ke_ternate:
  jika bukan di(Ternate)
  maka berlayar(Ternate)
`,
  },
  {
    id: 'pemburu-selisih-nusantara',
    title: 'Pemburu Margin Segitiga Timur-Barat',
    description:
      'Membandingkan harga tujuan secara real-time sebelum membeli rempah di Maluku atau garam di Surabaya.',
    source: `# Templat 3: Pemburu Margin Real-Time
aturan jual_pala_untung:
  jika stok_kapal(pala) > 0 dan harga(pala) > 75
  maka jual(pala, semua)

aturan jual_cengkeh_untung:
  jika stok_kapal(cengkeh) > 0 dan harga(cengkeh) > 95
  maka jual(cengkeh, semua)

aturan jual_garam_untung:
  jika stok_kapal(garam) > 0 dan harga(garam) > 22
  maka jual(garam, semua)

aturan beli_pala_selisih:
  jika di(Banda) dan harga_di(Batavia, pala) - harga(pala) > 20 dan muatan_bebas() > 0
  maka beli(pala, maks)

aturan beli_cengkeh_selisih:
  jika di(Ternate) dan harga_di(Batavia, cengkeh) - harga(cengkeh) > 25 dan muatan_bebas() > 0
  maka beli(cengkeh, maks)

aturan beli_garam_surabaya:
  jika di(Surabaya) dan harga(garam) <= 22 dan muatan_bebas() > 0
  maka beli(garam, maks)

aturan antar_ke_batavia:
  jika stok_kapal(pala) > 0 atau stok_kapal(cengkeh) > 0
  maka berlayar(Batavia)

aturan antar_garam_ke_banda:
  jika stok_kapal(garam) > 0
  maka berlayar(Banda)

aturan cari_muatan_di_surabaya:
  jika di(Batavia)
  maka berlayar(Surabaya)

aturan cari_muatan_di_banda:
  jika bukan di(Banda)
  maka berlayar(Banda)
`,
  },
  {
    id: 'pedagang-aman-anti-grounded',
    title: 'Pedagang Konservatif (Cadangan Kas Aman)',
    description:
      'Menjaga cadangan koin untuk perawatan kapal dan menjual muatan kapan pun kapal terkunci (grounded).',
    source: `# Templat 4: Pedagang Konservatif Anti-Grounded
aturan jual_darurat_pala:
  jika stok_kapal(pala) > 0 dan (di(Batavia) atau di(Surabaya) atau koin() < 5)
  maka jual(pala, semua)

aturan beli_pala_aman:
  jika di(Banda) dan koin() > 200 dan harga(pala) < 85 dan muatan_bebas() > 0
  maka beli(pala, maks)

aturan layar_jual:
  jika stok_kapal(pala) > 0
  maka berlayar(Surabaya)

aturan layar_beli:
  jika stok_kapal(pala) == 0 dan bukan di(Banda)
  maka berlayar(Banda)
`,
  },
] as const;

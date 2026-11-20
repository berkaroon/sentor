# Sentor

> Bu proje https://github.com/ProxySeer/FastCommander-Releases baz alınarak üretilmiştir.

**Sentor**, macOS 13 (Ventura) ve üzeri sistemler için SwiftUI ve düşük seviyeli POSIX/Darwin dosya sistemi API'leri ile geliştirilmiş sade, hızlı ve veri bütünlüğü odaklı bir dosya aktarım, eşitleme ve karşılaştırma uygulamasıdır.

## Özellikler

- **Copy, Move, Mirror (Sync), Delete ve Compare (`Karşılaştır`):** Kopyalama, taşıma, ayna eşitleme, güvenli silme (`Fast Unlink`, `Zero-Fill`, `DoD 3-Pass`) ve iki klasör/disk arası hızlı karşılaştırma modları.
- **Yüksek Performanslı POSIX Motoru:** Çoklu iş parçacıklı paralel işçi havuzu, aynı APFS birimi içinde `clonefile` (Copy-on-Write) desteği, büyük dosyalarda Direct I/O (`F_NOCACHE`) ve hizalı bellek tamponları.
- **%100 Bayt Düzeyinde Doğrulama:** Aktarım sonrasında dosya boyutu ve baş/son bloklarla sınırlı kalmayıp dosyanın tamamını baştan sona bayt bayt doğrulama ve bozulma tespitinde otomatik onarım.
- **Üzerine Yazma Politikaları:** `Overwrite` (üzerine yaz), `Ask me` (Windows tarzı tekil/toplu çakışma karşılaştırma ekranı ve günceli koruma seçeneğiyle bana sor) ve `Never` (asla).
- **Hızlı Klasör Karşılaştırma (`getattrlistbulk`):** macOS `getattrlistbulk` tabanlı paralel indeksleme ile iki klasörü veya diski hızlıca tarar; `same`, `time diff` ve `diff` etiketleriyle filtreleme sunar.
- **Kuyruk, Geçmiş, Favoriler ve Mini Notch HUD:** Sıralı aktarım kuyruğu, işlem geçmişi, favori klasörler, ekran üstü Mini HUD ve açık/koyu tema ile Türkçe/İngilizce arayüz desteği.
- **Veri Güvenliği ve Bütünlük Korumaları:**
  - Eşitleme/kopyalama/taşıma sırasında hedefin kaynağın üst/ata klasörü olmasını engelleme.
  - Kaynak alt klasörlerinde okuma izni hatası olduğunda klasörü boş saymak yerine işlemi hata ile durdurup hedefteki yedekleri koruma.
  - Hedefteki sembolik bağlantı (`symlink`) üzerinden hedef dışı dosyalara yazmayı engelleme (`lstat`, `O_NOFOLLOW`, `CLONE_NOFOLLOW`).
  - Hardlink, symlink veya APFS büyük/küçük harf farkıyla aynı fiziksel dosyaya (`inode`) işaret eden yolların kaynağı 0 bayta düşürmesini engelleme.
  - Güvenli silmede (`Shred`) sembolik bağlantıların hedef dosyayı bozmasını önleyip yalnızca bağlantının kendisini kaldırma.
  - Önceden iptal edilmiş taşıma işlemlerinin yürütülmesini kesin olarak engelleme.

## Gereksinimler

- macOS 13.0+ (Ventura veya üzeri)
- Swift 5.9+ / Xcode Command Line Tools (`xcode-select --install`)

## Kurulum ve Derleme

Projeyi doğrudan kaynak koddan çalıştırmak için:

```bash
swift run
```

Release sürümünü derlemek için:

```bash
swift build -c release
```

`.app` paketi ve `.dmg` kurulum dosyası oluşturmak için (`dist/Sentor.app` ve `dist/Sentor.dmg`):

```bash
./scripts/build_dmg.sh
```

> [!NOTE]
> Ad-hoc imzalı hazır bir `.app` veya `.dmg` paketi indirildiğinde macOS Gatekeeper tanımsız geliştirici uyarısı verirse, uygulamayı `/Applications` klasörüne taşıdıktan sonra Terminal'de şu komutu çalıştırabilirsiniz:
> ```bash
> xattr -cr /Applications/Sentor.app
> ```

## Lisans

Bu proje [MIT Lisansı](LICENSE) ile lisanslanmıştır.

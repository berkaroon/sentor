import SwiftUI
import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case en, tr, es, fr, de, it, pt, ja, zh, ko, ru, ar
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .en: return "English"
        case .tr: return "Türkçe"
        case .es: return "Español"
        case .fr: return "Français"
        case .de: return "Deutsch"
        case .it: return "Italiano"
        case .pt: return "Português"
        case .ja: return "日本語"
        case .zh: return "中文"
        case .ko: return "한국어"
        case .ru: return "Русский"
        case .ar: return "العربية"
        }
    }
}

enum PathItemKind {
    case folder
    case file
    case unknown

    static func detect(_ path: String) -> PathItemKind {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unknown }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: trimmed, isDirectory: &isDir) {
            return isDir.boolValue ? .folder : .file
        }
        let ext = (trimmed as NSString).pathExtension
        return ext.isEmpty ? .folder : .file
    }

    func label(_ lang: AppLanguage) -> String {
        switch (self, lang) {
        case (.folder, .tr): return "Klasör"
        case (.folder, .es): return "Carpeta"
        case (.folder, .fr): return "Dossier"
        case (.folder, .de): return "Ordner"
        case (.folder, .it): return "Cartella"
        case (.folder, .pt): return "Pasta"
        case (.folder, .ja): return "フォルダ"
        case (.folder, .zh): return "文件夹"
        case (.folder, .ko): return "폴더"
        case (.folder, .ru): return "Папка"
        case (.folder, .ar): return "مجلد"
        case (.folder, _): return "Folder"

        case (.file, .tr): return "Dosya"
        case (.file, .es): return "Archivo"
        case (.file, .fr): return "Fichier"
        case (.file, .de): return "Datei"
        case (.file, .it): return "File"
        case (.file, .pt): return "Arquivo"
        case (.file, .ja): return "ファイル"
        case (.file, .zh): return "文件"
        case (.file, .ko): return "파일"
        case (.file, .ru): return "Файл"
        case (.file, .ar): return "ملف"
        case (.file, _): return "File"

        case (.unknown, _): return ""
        }
    }

    var icon: String {
        switch self {
        case .folder: return "folder.fill"
        case .file: return "doc.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}

enum L10n {
    static func source(_ l: AppLanguage) -> String {
        switch l {
        case .tr: return "Kaynak"
        case .es: return "Origen"
        case .fr: return "Source"
        case .de: return "Quelle"
        case .it: return "Origine"
        case .pt: return "Origem"
        case .ja: return "コピー元"
        case .zh: return "源路径"
        case .ko: return "원본"
        case .ru: return "Источник"
        case .ar: return "المصدر"
        case .en: return "Source"
        }
    }

    static func destination(_ l: AppLanguage) -> String {
        switch l {
        case .tr: return "Hedef"
        case .es: return "Destino"
        case .fr: return "Destination"
        case .de: return "Ziel"
        case .it: return "Destinazione"
        case .pt: return "Destino"
        case .ja: return "コピー先"
        case .zh: return "目标路径"
        case .ko: return "대상"
        case .ru: return "Назначение"
        case .ar: return "الوجهة"
        case .en: return "Destination"
        }
    }

    static func targetToDelete(_ l: AppLanguage) -> String {
        switch l {
        case .tr: return "Silinecek Hedef"
        case .es: return "Objetivo a Eliminar"
        case .fr: return "Cible à Supprimer"
        case .de: return "Löschziel"
        case .it: return "Destinazione da Eliminare"
        case .pt: return "Alvo para Excluir"
        case .ja: return "削除対象"
        case .zh: return "删除目标"
        case .ko: return "삭제 대상"
        case .ru: return "Цель удаления"
        case .ar: return "هدف الحذف"
        case .en: return "Target to Delete"
        }
    }

    static func browse(_ l: AppLanguage) -> String {
        switch l {
        case .tr: return "Gözat"
        case .es: return "Examinar"
        case .fr: return "Parcourir"
        case .de: return "Durchsuchen"
        case .it: return "Sfoglia"
        case .pt: return "Procurar"
        case .ja: return "参照"
        case .zh: return "浏览"
        case .ko: return "찾아보기"
        case .ru: return "Обзор"
        case .ar: return "استعراض"
        case .en: return "Browse"
        }
    }

    static func dropHint(_ l: AppLanguage) -> String {
        switch l {
        case .tr: return "Dosya veya klasör sürükleyip bırakın"
        case .es: return "Arrastra y suelta archivo o carpeta"
        case .fr: return "Glisser-déposer fichier ou dossier"
        case .de: return "Datei oder Ordner hierher ziehen"
        case .it: return "Trascina qui file o cartella"
        case .pt: return "Arraste e solte arquivo ou pasta"
        case .ja: return "ファイルまたはフォルダをドロップ"
        case .zh: return "拖放文件或文件夹到此处"
        case .ko: return "파일 또는 폴더를 끌어다 놓으세요"
        case .ru: return "Перетащите файл или папку"
        case .ar: return "اسحب وأفلت ملفاً أو مجلداً"
        case .en: return "Drop file or folder here"
        }
    }

    static func overwrite(_ l: AppLanguage) -> String {
        switch l {
        case .tr: return "Üzerine Yazma:"
        case .es: return "Sobrescribir:"
        case .fr: return "Écraser :"
        case .de: return "Überschreiben:"
        case .it: return "Sovrascrivi:"
        case .pt: return "Sobrescrever:"
        case .ja: return "上書き:"
        case .zh: return "覆盖规则:"
        case .ko: return "덮어쓰기:"
        case .ru: return "Перезапись:"
        case .ar: return "الاستبدال:"
        case .en: return "Overwrite:"
        }
    }

    static func shredMode(_ l: AppLanguage) -> String {
        switch l {
        case .tr: return "Silme Modu:"
        case .es: return "Modo Borrado:"
        case .fr: return "Suppression :"
        case .de: return "Löschmodus:"
        case .it: return "Eliminazione:"
        case .pt: return "Modo Exclusão:"
        case .ja: return "削除方式:"
        case .zh: return "删除模式:"
        case .ko: return "삭제 방식:"
        case .ru: return "Удаление:"
        case .ar: return "وضع الحذف:"
        case .en: return "Shred Mode:"
        }
    }

    static func start(_ l: AppLanguage) -> String {
        switch l {
        case .tr: return "Başlat"
        case .es: return "Iniciar"
        case .fr: return "Démarrer"
        case .de: return "Starten"
        case .it: return "Avvia"
        case .pt: return "Iniciar"
        case .ja: return "開始"
        case .zh: return "开始"
        case .ko: return "시작"
        case .ru: return "Старт"
        case .ar: return "بدء"
        case .en: return "Start"
        }
    }

    static func pause(_ l: AppLanguage) -> String {
        switch l {
        case .tr: return "Duraklat"
        case .es: return "Pausar"
        case .fr: return "Pause"
        case .de: return "Pause"
        case .it: return "Pausa"
        case .pt: return "Pausar"
        case .ja: return "一時停止"
        case .zh: return "暂停"
        case .ko: return "일시정지"
        case .ru: return "Пауза"
        case .ar: return "إيقاف مؤقت"
        case .en: return "Pause"
        }
    }

    static func transferring(_ l: AppLanguage) -> String {
        switch l {
        case .tr: return "Aktarılıyor..."
        case .es: return "Transfiriendo..."
        case .fr: return "Transfert en cours..."
        case .de: return "Übertragung läuft..."
        case .it: return "Trasferimento..."
        case .pt: return "Transferindo..."
        case .ja: return "転送中..."
        case .zh: return "传输中..."
        case .ko: return "전송 중..."
        case .ru: return "Передача..."
        case .ar: return "جاري النقل..."
        case .en: return "Transferring..."
        }
    }

    static func ready(_ l: AppLanguage) -> String {
        switch l {
        case .tr: return "Hazır"
        case .es: return "Listo"
        case .fr: return "Prêt"
        case .de: return "Bereit"
        case .it: return "Pronto"
        case .pt: return "Pronto"
        case .ja: return "準備完了"
        case .zh: return "就绪"
        case .ko: return "준비됨"
        case .ru: return "Готово"
        case .ar: return "جاهز"
        case .en: return "Ready"
        }
    }

    static func completed(_ l: AppLanguage) -> String {
        switch l {
        case .tr: return "Tamamlandı"
        case .es: return "Completado"
        case .fr: return "Terminé"
        case .de: return "Abgeschlossen"
        case .it: return "Completato"
        case .pt: return "Concluído"
        case .ja: return "完了"
        case .zh: return "已完成"
        case .ko: return "완료됨"
        case .ru: return "Завершено"
        case .ar: return "مكتمل"
        case .en: return "Completed"
        }
    }

    static func speed(_ l: AppLanguage) -> String {
        switch l {
        case .tr: return "Hız"
        case .es: return "Velocidad"
        case .fr: return "Vitesse"
        case .de: return "Tempo"
        case .it: return "Velocità"
        case .pt: return "Velocidade"
        case .ja: return "速度"
        case .zh: return "速度"
        case .ko: return "속도"
        case .ru: return "Скорость"
        case .ar: return "السرعة"
        case .en: return "Speed"
        }
    }

    static func files(_ l: AppLanguage) -> String {
        switch l {
        case .tr: return "Dosyalar"
        case .es: return "Archivos"
        case .fr: return "Fichiers"
        case .de: return "Dateien"
        case .it: return "File"
        case .pt: return "Arquivos"
        case .ja: return "ファイル数"
        case .zh: return "文件数"
        case .ko: return "파일"
        case .ru: return "Файлы"
        case .ar: return "الملفات"
        case .en: return "Files"
        }
    }

    static func transferred(_ l: AppLanguage) -> String {
        switch l {
        case .tr: return "Aktarılan"
        case .es: return "Transferido"
        case .fr: return "Transféré"
        case .de: return "Übertragen"
        case .it: return "Trasferito"
        case .pt: return "Transferido"
        case .ja: return "転送済み"
        case .zh: return "已传输"
        case .ko: return "전송됨"
        case .ru: return "Передано"
        case .ar: return "المنقول"
        case .en: return "Transferred"
        }
    }

    static func diffPreviewTitle(_ l: AppLanguage) -> String {
        switch l {
        case .tr: return "Karşılaştırma & Dosya Önizleme"
        case .es: return "Vista Previa y Diferencias"
        case .fr: return "Aperçu & Différences"
        case .de: return "Diff- & Dateivorschau"
        case .it: return "Anteprima Diff & File"
        case .pt: return "Prévia de Diff e Arquivos"
        case .ja: return "差分・ファイルプレビュー"
        case .zh: return "差异与文件预览"
        case .ko: return "차이점 및 파일 미리보기"
        case .ru: return "Предпросмотр различий"
        case .ar: return "معاينة الفروقات والملفات"
        case .en: return "Dry-Run Diff & File Preview"
        }
    }

    static func settingsTitle(_ l: AppLanguage) -> String {
        switch l {
        case .tr: return "Motor & Tercihler"
        case .es: return "Motor y Preferencias"
        case .fr: return "Moteur & Préférences"
        case .de: return "Engine & Einstellungen"
        case .it: return "Motore & Preferenze"
        case .pt: return "Motor e Preferências"
        case .ja: return "エンジンと設定"
        case .zh: return "引擎与偏好设置"
        case .ko: return "엔진 및 설정"
        case .ru: return "Движок и настройки"
        case .ar: return "المحرك والتفضيلات"
        case .en: return "Engine & Preferences"
        }
    }

    static func interfaceLanguage(_ l: AppLanguage) -> String {
        switch l {
        case .tr: return "Arayüz Dili"
        case .es: return "Idioma de Interfaz"
        case .fr: return "Langue de l'interface"
        case .de: return "Oberflächensprache"
        case .it: return "Lingua Interfaccia"
        case .pt: return "Idioma da Interface"
        case .ja: return "表示言語"
        case .zh: return "界面语言"
        case .ko: return "인터페이스 언어"
        case .ru: return "Язык интерфейса"
        case .ar: return "لغة الواجهة"
        case .en: return "Interface Language"
        }
    }

    static func appearance(_ l: AppLanguage) -> String {
        switch l {
        case .tr: return "Görünüm / Tema"
        case .es: return "Apariencia / Tema"
        case .fr: return "Apparence / Thème"
        case .de: return "Erscheinungsbild"
        case .it: return "Aspetto / Tema"
        case .pt: return "Aparência / Tema"
        case .ja: return "外観 / テーマ"
        case .zh: return "外观 / 主题"
        case .ko: return "화면 모드 / 테마"
        case .ru: return "Оформление / Тема"
        case .ar: return "المظهر / السمة"
        case .en: return "Appearance / Theme"
        }
    }

    static func themeName(_ mode: AppThemeMode, _ l: AppLanguage) -> String {
        switch (mode, l) {
        case (.creamLight, .tr): return "Krem Açık"
        case (.creamLight, .es): return "Crema Claro"
        case (.creamLight, .fr): return "Crème Clair"
        case (.creamLight, .de): return "Creme Hell"
        case (.creamLight, .it): return "Crema Chiaro"
        case (.creamLight, .pt): return "Creme Claro"
        case (.creamLight, .ja): return "クリームライト"
        case (.creamLight, .zh): return "奶油浅色"
        case (.creamLight, .ko): return "크림 라이트"
        case (.creamLight, .ru): return "Кремовая светлая"
        case (.creamLight, .ar): return "كريمي فاتح"
        case (.creamLight, _): return "Cream Light"

        case (.oledDark, .tr): return "OLED Koyu"
        case (.oledDark, .es): return "OLED Oscuro"
        case (.oledDark, .fr): return "OLED Sombre"
        case (.oledDark, .de): return "OLED Dunkel"
        case (.oledDark, .it): return "OLED Scuro"
        case (.oledDark, .pt): return "OLED Escuro"
        case (.oledDark, .ja): return "OLED ダーク"
        case (.oledDark, .zh): return "OLED 深色"
        case (.oledDark, .ko): return "OLED 다크"
        case (.oledDark, .ru): return "OLED Тёмная"
        case (.oledDark, .ar): return "OLED داكن"
        case (.oledDark, _): return "OLED Dark"
        }
    }

    static func addToQueue(_ l: AppLanguage) -> String {
        switch l {
        case .tr: return "Kuyruğa Ekle"
        case .es: return "Añadir a Cola"
        case .fr: return "Ajouter à la file"
        case .de: return "Zur Warteschlange"
        case .it: return "Aggiungi in Coda"
        case .pt: return "Adicionar à Fila"
        case .ja: return "キューに追加"
        case .zh: return "添加到队列"
        case .ko: return "대기열에 추가"
        case .ru: return "В очередь"
        case .ar: return "أضف للقائمة"
        case .en: return "Add to Queue"
        }
    }

    static func cancel(_ l: AppLanguage) -> String {
        switch l {
        case .tr: return "İptal"
        case .es: return "Cancelar"
        case .fr: return "Annuler"
        case .de: return "Abbrechen"
        case .it: return "Annulla"
        case .pt: return "Cancelar"
        case .ja: return "キャンセル"
        case .zh: return "取消"
        case .ko: return "취소"
        case .ru: return "Отмена"
        case .ar: return "إلغاء"
        case .en: return "Cancel"
        }
    }

    static func stop(_ l: AppLanguage) -> String {
        switch l {
        case .tr: return "Durdur"
        case .es: return "Detener"
        case .fr: return "Arrêter"
        case .de: return "Stopp"
        case .it: return "Ferma"
        case .pt: return "Parar"
        case .ja, .zh: return "停止"
        case .ko: return "중지"
        case .ru: return "Стоп"
        case .ar: return "إيقاف"
        case .en: return "Stop"
        }
    }

    static func doubleCheck(_ l: AppLanguage) -> String {
        switch l {
        case .tr: return "Çift Kontrol"
        case .es: return "Doble Verificación"
        case .fr: return "Double Vérif."
        case .de: return "Doppelprüfung"
        case .it: return "Doppio Controllo"
        case .pt: return "Dupla Verif."
        case .ja: return "二重検証"
        case .zh: return "双重校验"
        case .ko: return "이중 검증"
        case .ru: return "Двойная проверка"
        case .ar: return "فحص مزدوج"
        case .en: return "Double-Check"
        }
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case workspace
    case compare
    case history
    case favorites
    case settings

    var id: String { rawValue }

    func title(_ lang: AppLanguage) -> String {
        switch (self, lang) {
        case (.workspace, .tr): return "Aktarımlar"
        case (.workspace, .es): return "Transferencias"
        case (.workspace, .fr): return "Transferts"
        case (.workspace, .de): return "Übertragungen"
        case (.workspace, .it): return "Trasferimenti"
        case (.workspace, .pt): return "Transferências"
        case (.workspace, .ja): return "転送"
        case (.workspace, .zh): return "传输"
        case (.workspace, .ko): return "전송"
        case (.workspace, .ru): return "Передачи"
        case (.workspace, .ar): return "التحويلات"
        case (.workspace, _): return "Transfers"

        case (.compare, .tr): return "Karşılaştır"
        case (.compare, .es): return "Comparar"
        case (.compare, .fr): return "Comparer"
        case (.compare, .de): return "Vergleichen"
        case (.compare, .it): return "Confronta"
        case (.compare, .pt): return "Comparar"
        case (.compare, .ja): return "比較"
        case (.compare, .zh): return "比较"
        case (.compare, .ko): return "비교"
        case (.compare, .ru): return "Сравнение"
        case (.compare, .ar): return "مقارنة"
        case (.compare, _): return "Compare"

        case (.history, .tr): return "Geçmiş"
        case (.history, .es): return "Historial"
        case (.history, .fr): return "Historique"
        case (.history, .de): return "Verlauf"
        case (.history, .it): return "Cronologia"
        case (.history, .pt): return "Histórico"
        case (.history, .ja): return "履歴"
        case (.history, .zh): return "历史"
        case (.history, .ko): return "기록"
        case (.history, .ru): return "История"
        case (.history, .ar): return "السجل"
        case (.history, _): return "History"

        case (.favorites, .tr): return "Favoriler"
        case (.favorites, .es): return "Favoritos"
        case (.favorites, .fr): return "Favoris"
        case (.favorites, .de): return "Favoriten"
        case (.favorites, .it): return "Preferiti"
        case (.favorites, .pt): return "Favoritos"
        case (.favorites, .ja): return "お気に入り"
        case (.favorites, .zh): return "收藏夹"
        case (.favorites, .ko): return "즐겨찾기"
        case (.favorites, .ru): return "Избранное"
        case (.favorites, .ar): return "المفضلة"
        case (.favorites, _): return "Favorites"

        case (.settings, .tr): return "Ayarlar"
        case (.settings, .es): return "Ajustes"
        case (.settings, .fr): return "Réglages"
        case (.settings, .de): return "Einstellungen"
        case (.settings, .it): return "Impostazioni"
        case (.settings, .pt): return "Ajustes"
        case (.settings, .ja): return "設定"
        case (.settings, .zh): return "设置"
        case (.settings, .ko): return "설정"
        case (.settings, .ru): return "Настройки"
        case (.settings, .ar): return "الإعدادات"
        case (.settings, _): return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .workspace: return "arrow.left.arrow.right.circle"
        case .compare: return "rectangle.split.2x1"
        case .history: return "clock.arrow.circlepath"
        case .favorites: return "star"
        case .settings: return "slider.horizontal.3"
        }
    }
}

// MARK: - Fast Folder Compare Models
enum CompareMatchKind: Int, Comparable, Sendable {
    case same = 0
    case timeDiff = 1
    case diff = 2

    static func < (lhs: CompareMatchKind, rhs: CompareMatchKind) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var badgeTitle: String {
        switch self {
        case .same: return "same"
        case .timeDiff: return "time diff"
        case .diff: return "diff"
        }
    }

    var bgColor: Color {
        switch self {
        case .same: return SentorTheme.copySageBg
        case .timeDiff: return SentorTheme.diffAmberBg
        case .diff: return SentorTheme.deleteRoseBg
        }
    }

    var fgColor: Color {
        switch self {
        case .same: return SentorTheme.copySageFg
        case .timeDiff: return SentorTheme.diffAmberFg
        case .diff: return SentorTheme.deleteRoseFg
        }
    }
}

struct FastIndexedFile: Sendable {
    let relativePath: String
    let size: Int64
    let mtimeSec: TimeInterval
}

struct CompareFileRow: Identifiable, Sendable {
    var id: String { relativePath }
    let relativePath: String
    let kind: CompareMatchKind
    let leftFile: FastIndexedFile?
    let rightFile: FastIndexedFile?
}

enum TransferMode: String, CaseIterable, Identifiable, Codable {
    case copy, move, sync, diff, delete
    var id: String { rawValue }

    func title(_ lang: AppLanguage) -> String {
        switch (self, lang) {
        case (.copy, .tr): return "Kopyala"
        case (.copy, .es): return "Copiar"
        case (.copy, .fr): return "Copier"
        case (.copy, .de): return "Kopieren"
        case (.copy, .it): return "Copia"
        case (.copy, .pt): return "Copiar"
        case (.copy, .ja): return "コピー"
        case (.copy, .zh): return "复制"
        case (.copy, .ko): return "복사"
        case (.copy, .ru): return "Копировать"
        case (.copy, .ar): return "نسخ"
        case (.copy, _): return "Copy"

        case (.move, .tr): return "Taşı"
        case (.move, .es): return "Mover"
        case (.move, .fr): return "Déplacer"
        case (.move, .de): return "Verschieben"
        case (.move, .it): return "Sposta"
        case (.move, .pt): return "Mover"
        case (.move, .ja): return "移動"
        case (.move, .zh): return "移动"
        case (.move, .ko): return "이동"
        case (.move, .ru): return "Переместить"
        case (.move, .ar): return "نقل"
        case (.move, _): return "Move"

        case (.sync, .tr): return "Eşitle"
        case (.sync, .es): return "Sincronizar"
        case (.sync, .fr): return "Synchroniser"
        case (.sync, .de): return "Spiegeln"
        case (.sync, .it): return "Sincronizza"
        case (.sync, .pt): return "Espelhar"
        case (.sync, .ja): return "ミラー同期"
        case (.sync, .zh): return "镜像同步"
        case (.sync, .ko): return "미러 동기화"
        case (.sync, .ru): return "Синхр."
        case (.sync, .ar): return "مزامنة"
        case (.sync, _): return "Mirror"

        case (.diff, .tr): return "Önizleme"
        case (.diff, .es): return "Vista previa"
        case (.diff, .fr): return "Aperçu"
        case (.diff, .de): return "Vorschau"
        case (.diff, .it): return "Anteprima"
        case (.diff, .pt): return "Prévia"
        case (.diff, .ja): return "プレビュー"
        case (.diff, .zh): return "预览"
        case (.diff, .ko): return "미리보기"
        case (.diff, .ru): return "Просмотр"
        case (.diff, .ar): return "معاينة"
        case (.diff, _): return "Preview"

        case (.delete, .tr): return "Sil"
        case (.delete, .es): return "Eliminar"
        case (.delete, .fr): return "Supprimer"
        case (.delete, .de): return "Löschen"
        case (.delete, .it): return "Elimina"
        case (.delete, .pt): return "Excluir"
        case (.delete, .ja): return "削除"
        case (.delete, .zh): return "删除"
        case (.delete, .ko): return "삭제"
        case (.delete, .ru): return "Удалить"
        case (.delete, .ar): return "حذف"
        case (.delete, _): return "Delete"
        }
    }

    var icon: String {
        switch self {
        case .copy: return "doc.on.doc"
        case .move: return "arrow.right.doc.on.clipboard"
        case .sync: return "arrow.triangle.2.circlepath"
        case .diff: return "eye"
        case .delete: return "trash"
        }
    }

    var bgColor: Color {
        switch self {
        case .copy: return SentorTheme.copySageBg
        case .move: return SentorTheme.movePeachBg
        case .sync: return SentorTheme.syncLavenderBg
        case .diff: return SentorTheme.diffAmberBg
        case .delete: return SentorTheme.deleteRoseBg
        }
    }

    var fgColor: Color {
        switch self {
        case .copy: return SentorTheme.copySageFg
        case .move: return SentorTheme.movePeachFg
        case .sync: return SentorTheme.syncLavenderFg
        case .diff: return SentorTheme.diffAmberFg
        case .delete: return SentorTheme.deleteRoseFg
        }
    }
}

enum OverwriteRule: String, CaseIterable, Identifiable, Codable {
    case always, ask, never
    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self)) ?? "ask"
        switch raw {
        case "always": self = .always
        case "never": self = .never
        case "ask", "ifSizeOrDateDifferent", "ifNewer": self = .ask
        default: self = .ask
        }
    }

    func title(_ lang: AppLanguage) -> String {
        switch (self, lang) {
        case (.always, .tr): return "Üzerine yaz"
        case (.always, .es): return "Sobrescribir"
        case (.always, .fr): return "Écraser"
        case (.always, .de): return "Überschreiben"
        case (.always, .ja): return "上書き"
        case (.always, .zh): return "覆盖"
        case (.always, .ko): return "덮어쓰기"
        case (.always, .ru): return "Перезаписать"
        case (.always, .ar): return "استبدال"
        case (.always, _): return "Overwrite"

        case (.ask, .tr): return "Bana sor"
        case (.ask, .es): return "Preguntarme"
        case (.ask, .fr): return "Me demander"
        case (.ask, .de): return "Fragen"
        case (.ask, .ja): return "確認する"
        case (.ask, .zh): return "询问我"
        case (.ask, .ko): return "확인"
        case (.ask, .ru): return "Спросить"
        case (.ask, .ar): return "اسألني"
        case (.ask, _): return "Ask me"

        case (.never, .tr): return "Asla"
        case (.never, .es): return "Nunca"
        case (.never, .fr): return "Jamais"
        case (.never, .de): return "Nie"
        case (.never, .ja): return "スキップ"
        case (.never, .zh): return "从不"
        case (.never, .ko): return "건너뛰기"
        case (.never, .ru): return "Никогда"
        case (.never, .ar): return "أبداً"
        case (.never, _): return "Never"
        }
    }

    func description(_ lang: AppLanguage) -> String {
        switch (self, lang) {
        case (.always, .tr): return "Size danışmadan daima üzerine kopyalama yapar."
        case (.always, _): return "Always overwrites existing files without asking."
        case (.ask, .tr): return "Tekrarlanan dosya olduğunda size danışır."
        case (.ask, _): return "Asks you when a duplicate file already exists."
        case (.never, .tr): return "Aynı isim ve uzantıdaki dosyaları asla aktarmaz."
        case (.never, _): return "Never transfers files with the same name and extension."
        }
    }
}

struct FileConflictInfo: Identifiable {
    let id = UUID()
    let relativePath: String
    let fileName: String
    let sourceSize: Int64
    let sourceMtime: Date
    let destSize: Int64
    let destMtime: Date
}

enum FileConflictAction {
    case overwrite, skip, keepNewer, cancel
}

struct FileConflictDecision {
    let action: FileConflictAction
    let applyToAll: Bool
}

enum ShredPassOption: String, CaseIterable, Identifiable, Codable {
    case fastUnlink, zeroFill, dodThreePass
    var id: String { rawValue }

    func title(_ lang: AppLanguage) -> String {
        switch (self, lang) {
        case (.fastUnlink, .tr): return "Hızlı Sil (0-geçiş)"
        case (.fastUnlink, _): return "Fast Unlink (0-pass)"
        case (.zeroFill, .tr): return "Sıfırla (1-geçiş)"
        case (.zeroFill, _): return "Zero-Fill (1-pass)"
        case (.dodThreePass, .tr): return "DoD 5220.22-M (3-geçiş)"
        case (.dodThreePass, _): return "DoD 5220.22-M (3-pass)"
        }
    }
}

enum DiffKind: String {
    case missingInDest, sizeMismatch, dateMismatch, missingInSource

    func badge(_ lang: AppLanguage) -> (text: String, bg: Color, fg: Color) {
        switch (self, lang) {
        case (.missingInDest, .tr): return ("Yeni", SentorTheme.copySageBg, SentorTheme.copySageFg)
        case (.missingInDest, _): return ("New", SentorTheme.copySageBg, SentorTheme.copySageFg)
        case (.sizeMismatch, .tr): return ("Boyut Farklı", SentorTheme.movePeachBg, SentorTheme.movePeachFg)
        case (.sizeMismatch, _): return ("Size Diff", SentorTheme.movePeachBg, SentorTheme.movePeachFg)
        case (.dateMismatch, .tr): return ("Güncel", SentorTheme.diffAmberBg, SentorTheme.diffAmberFg)
        case (.dateMismatch, _): return ("Modified", SentorTheme.diffAmberBg, SentorTheme.diffAmberFg)
        case (.missingInSource, .tr): return ("Fazla", SentorTheme.deleteRoseBg, SentorTheme.deleteRoseFg)
        case (.missingInSource, _): return ("Orphan", SentorTheme.deleteRoseBg, SentorTheme.deleteRoseFg)
        }
    }
}

struct FileDiffItem: Identifiable {
    let id = UUID()
    let relativePath: String
    let kind: DiffKind
    let sourceSize: String
    let destSize: String
    let modifiedDate: String
}

struct TransferSessionTab: Identifiable {
    let id = UUID()
    var mode: TransferMode
    var sourcePath: String
    var destinationPath: String
    var overwriteRule: OverwriteRule
    var shredPass: ShredPassOption = .fastUnlink
    var enableBlockClone: Bool = true
    var preserveTimestamps: Bool = true
    var diskBanner: String
    var samePhysicalDisk: Bool
}

struct QueueJob: Identifiable, Codable {
    var id = UUID()
    var mode: TransferMode
    var sourcePath: String
    var destinationPath: String
    var overwriteRule: OverwriteRule
    var shredPass: ShredPassOption
    var enableBlockClone: Bool
    var preserveTimestamps: Bool
    var title: String
    var paths: String
    var sizeText: String
    var verifyAfterCopy: Bool
    var fileCount: Int? = nil
}

enum TransferOutcome: String, Codable {
    case completed, cancelled, failed

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .completed: return language == .tr ? "Tamamlandı" : "Completed"
        case .cancelled: return language == .tr ? "İptal edildi" : "Cancelled"
        case .failed: return language == .tr ? "Başarısız" : "Failed"
        }
    }
}

struct HistoryRecord: Identifiable, Codable {
    var id = UUID()
    var mode: TransferMode
    var source: String
    var destination: String
    var summary: String
    var timestamp: String
    var isPinned: Bool
    var outcome: TransferOutcome? = nil
    var detail: String? = nil
}

struct FavoriteFolder: Identifiable, Codable {
    var id = UUID()
    var name: String
    var path: String
    var diskType: String
}

struct SavedSessionState: Codable, Equatable {
    var mode: TransferMode
    var sourcePath: String
    var destinationPath: String
    var overwriteRule: OverwriteRule
    var enableBlockClone: Bool
    var preserveTimestamps: Bool
}

struct SentorSettings: Codable {
    var language: AppLanguage = .en
    var themeMode: AppThemeMode = .creamLight
    var takeTurnsOnSameDisk: Bool = true
    var useDirectIO: Bool = true
    var verifyAfterTransfer: Bool = true
    var autoTuneWorkers: Bool = true
    var chunkSizeIndex: Int = 2
    var maxParallelFiles: Int = 16
    var deleteWorkers: Int = 32
    var enableMiniHUD: Bool = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        language = try c.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .en
        themeMode = try c.decodeIfPresent(AppThemeMode.self, forKey: .themeMode) ?? .creamLight
        takeTurnsOnSameDisk = try c.decodeIfPresent(Bool.self, forKey: .takeTurnsOnSameDisk) ?? true
        useDirectIO = try c.decodeIfPresent(Bool.self, forKey: .useDirectIO) ?? true
        verifyAfterTransfer = try c.decodeIfPresent(Bool.self, forKey: .verifyAfterTransfer) ?? true
        autoTuneWorkers = try c.decodeIfPresent(Bool.self, forKey: .autoTuneWorkers) ?? true
        chunkSizeIndex = try c.decodeIfPresent(Int.self, forKey: .chunkSizeIndex) ?? 2
        maxParallelFiles = try c.decodeIfPresent(Int.self, forKey: .maxParallelFiles) ?? 16
        deleteWorkers = try c.decodeIfPresent(Int.self, forKey: .deleteWorkers) ?? 32
        enableMiniHUD = try c.decodeIfPresent(Bool.self, forKey: .enableMiniHUD) ?? true
    }
}

enum SentorMockData {
    static let initialSession = TransferSessionTab(
        mode: .copy,
        sourcePath: "",
        destinationPath: "",
        overwriteRule: .ask,
        enableBlockClone: false,
        diskBanner: "Inspecting volumes...",
        samePhysicalDisk: false
    )

    static let sampleDiffs: [FileDiffItem] = [
        FileDiffItem(relativePath: "Assets/hero_banner_4k.png", kind: .missingInDest, sourceSize: "18.4 MB", destSize: "—", modifiedDate: "Today, 11:42"),
        FileDiffItem(relativePath: "Core/transfer_engine.swift", kind: .sizeMismatch, sourceSize: "42.1 KB", destSize: "38.7 KB", modifiedDate: "Today, 10:15"),
        FileDiffItem(relativePath: "Docs/README.tr.md", kind: .dateMismatch, sourceSize: "12.8 KB", destSize: "12.8 KB", modifiedDate: "Yesterday, 19:20"),
        FileDiffItem(relativePath: "Temp/old_cache_dump.bin", kind: .missingInSource, sourceSize: "—", destSize: "124.0 MB", modifiedDate: "Nov 10, 08:04")
    ]

    static let sampleQueue: [QueueJob] = []

    static let sampleHistory: [HistoryRecord] = [
        HistoryRecord(mode: .copy, source: "~/Pictures/LightroomCatalog", destination: "/Volumes/CrucialX9/Catalog", summary: "1,420 files · 9.4 GB · 910 MB/s avg", timestamp: "Today, 09:40", isPinned: true),
        HistoryRecord(mode: .sync, source: "~/Documents/Contracts", destination: "/Volumes/iCloudMirror/Contracts", summary: "84 files mirrored · 2 orphans pruned", timestamp: "Yesterday, 18:12", isPinned: true),
        HistoryRecord(mode: .delete, source: "~/Downloads/TempInstallers", destination: "—", summary: "312 files · Fast Unlink · 0.4s", timestamp: "Nov 12, 22:05", isPinned: false)
    ]

    static let sampleFavorites: [FavoriteFolder] = [
        FavoriteFolder(name: "Projects Workspace", path: "~/Projects", diskType: "APFS NVMe"),
        FavoriteFolder(name: "Crucial X9 Backup", path: "/Volumes/CrucialX9/Backups", diskType: "USB 3.2 SSD"),
        FavoriteFolder(name: "NAS Archive", path: "/Volumes/NAS_Archive", diskType: "SMB3 Network"),
        FavoriteFolder(name: "Downloads", path: "~/Downloads", diskType: "APFS NVMe")
    ]
}

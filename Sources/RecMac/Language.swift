import Foundation

/// 앱 언어 (옵션 메뉴에서 바꿀 수 있음)
enum AppLanguage: String, CaseIterable, Identifiable {
    case ko, en
    var id: String { rawValue }

    var title: String {
        switch self {
        case .ko: return "한국어"
        case .en: return "English"
        }
    }

    static let storageKey = "language"

    static var current: AppLanguage {
        if let raw = UserDefaults.standard.string(forKey: storageKey), let lang = AppLanguage(rawValue: raw) {
            return lang
        }
        return Locale.preferredLanguages.first?.hasPrefix("ko") == true ? .ko : .en
    }
}

/// 한국어 / 영어 문구 중 현재 언어에 맞는 것을 고른다
func tr(_ ko: String, _ en: String) -> String {
    AppLanguage.current == .ko ? ko : en
}

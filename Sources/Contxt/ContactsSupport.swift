// Reads the user's contacts so they can be added as ring destinations.
// Asking for access here (and only here) is what shows the Contacts prompt.

import Contacts
import Foundation

struct ContactEntry: Identifiable {
    let id: String
    let name: String
    let email: String?
    let phone: String?
    let telegram: String?
    let photo: Data?
}

enum ContactsAccess {
    case unknown, granted, denied
}

final class ContactsLoader: ObservableObject {
    @Published var entries: [ContactEntry] = []
    @Published var access: ContactsAccess = .unknown

    func load() {
        let store = CNContactStore()
        store.requestAccess(for: .contacts) { granted, _ in
            DispatchQueue.main.async { self.access = granted ? .granted : .denied }
            guard granted else { return }

            let keys: [CNKeyDescriptor] = [
                CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
                CNContactEmailAddressesKey as CNKeyDescriptor,
                CNContactPhoneNumbersKey as CNKeyDescriptor,
                CNContactInstantMessageAddressesKey as CNKeyDescriptor,
                CNContactSocialProfilesKey as CNKeyDescriptor,
                CNContactThumbnailImageDataKey as CNKeyDescriptor,
            ]
            let request = CNContactFetchRequest(keysToFetch: keys)
            request.sortOrder = .userDefault

            var result: [ContactEntry] = []
            try? store.enumerateContacts(with: request) { contact, _ in
                let name = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
                guard !name.isEmpty else { return }
                result.append(ContactEntry(
                    id: contact.identifier,
                    name: name,
                    email: contact.emailAddresses.first.map { String($0.value) },
                    phone: contact.phoneNumbers.first?.value.stringValue,
                    telegram: Self.telegramHandle(in: contact),
                    photo: contact.thumbnailImageData
                ))
            }
            DispatchQueue.main.async { self.entries = result }
        }
    }

    /// Contacts has no Telegram field, so look for a handle the user stored as
    /// an instant-message or social-profile entry (service Telegram, a t.me
    /// link, or a bare @name). Returned without the leading "@".
    private static func telegramHandle(in contact: CNContact) -> String? {
        var candidates: [(service: String, value: String)] = contact.instantMessageAddresses.map {
            ($0.value.service, $0.value.username)
        }
        candidates += contact.socialProfiles.map { ($0.value.service, $0.value.username) }
        for (service, raw) in candidates {
            var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let isTelegram = service.localizedCaseInsensitiveContains("telegram") || value.contains("t.me/")
            if let range = value.range(of: "t.me/") { value = String(value[range.upperBound...]) }
            guard isTelegram || value.hasPrefix("@") else { continue }
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "@/ "))
            if !value.isEmpty { return value }
        }
        return nil
    }
}

// Reads the user's contacts so they can be added as ring destinations.
// Asking for access here (and only here) is what shows the Contacts prompt.

import Contacts
import Foundation

struct ContactEntry: Identifiable {
    let id: String
    let name: String
    let email: String?
    let phone: String?
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
                    photo: contact.thumbnailImageData
                ))
            }
            DispatchQueue.main.async { self.entries = result }
        }
    }
}

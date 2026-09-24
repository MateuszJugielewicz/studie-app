import Foundation

enum StudioValidator {
    /// Human-readable problems that block submission for review.
    static func problems(in studio: Studio) -> [String] {
        var problems: [String] = []
        if studio.name.trimmingCharacters(in: .whitespaces).count < 3 { problems.append("Add your studio's name.") }
        if studio.description.count < 40 { problems.append("Write a description of at least 40 characters.") }
        if studio.photoUrls.isEmpty { problems.append("Add at least one photo.") }
        if studio.address.street.isEmpty || studio.address.city.isEmpty { problems.append("Add the studio's address.") }
        if studio.latitude == 0 && studio.longitude == 0 { problems.append("Place your studio on the map.") }
        if studio.contact.email.isEmpty && studio.contact.phone.isEmpty { problems.append("Add an email or phone number.") }
        if studio.sessionTypes.isEmpty || studio.sessionTypes.contains(where: { $0.hourlyRate <= 0 }) { problems.append("Set a price for each session type.") }
        if studio.openingHours.allSatisfy(\.isClosed) { problems.append("Set your opening hours.") }
        if studio.genres.isEmpty { problems.append("Pick at least one genre.") }
        return problems
    }
}

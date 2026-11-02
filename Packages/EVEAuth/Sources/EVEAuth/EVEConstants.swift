import Foundation

public enum EVEConstants {
    public static let clientID = "a3159d301b8d450a86f4a95f26e55fd9"
    public static let callbackScheme = "eveauthcanopus"

    public static let authorizeURL  = URL(string: "https://login.eveonline.com/v2/oauth/authorize")!
    public static let tokenURL      = URL(string: "https://login.eveonline.com/v2/oauth/token")!
    public static let jwksURL       = URL(string: "https://login.eveonline.com/oauth/jwks")!
    public static let revokeURL     = URL(string: "https://login.eveonline.com/v2/oauth/revoke")!
    public static let esiBase       = URL(string: "https://esi.evetech.net/latest")!
    public static let imageBase     = URL(string: "https://images.evetech.net")!

    public static let userAgent = "Canopus/1.0 (gercogunlimited@gmail.com)"

    public static let scopes: [String] = [
        "publicData",
        "esi-alliances.read_contacts.v1",
        "esi-assets.read_assets.v1",
        "esi-calendar.read_calendar_events.v1",
        "esi-calendar.respond_calendar_events.v1",
        "esi-characters.read_blueprints.v1",
        "esi-characters.read_contacts.v1",
        "esi-characters.read_corporation_roles.v1",
        "esi-characters.read_fatigue.v1",
        "esi-characters.read_freelance_jobs.v1",
        "esi-characters.read_loyalty.v1",
        "esi-characters.read_notifications.v1",
        "esi-characters.read_standings.v1",
        "esi-characters.write_contacts.v1",
        "esi-clones.read_clones.v1",
        "esi-clones.read_implants.v1",
        "esi-contracts.read_character_contracts.v1",
        "esi-corporations.read_contacts.v1",
        "esi-corporations.read_projects.v1",
        "esi-corporations.read_structures.v1",
        "esi-fittings.read_fittings.v1",
        "esi-fittings.write_fittings.v1",
        "esi-fleets.read_fleet.v1",
        "esi-fleets.write_fleet.v1",
        "esi-industry.read_character_jobs.v1",
        "esi-industry.read_character_mining.v1",
        "esi-industry.read_corporation_mining.v1",
        "esi-killmails.read_killmails.v1",
        "esi-location.read_location.v1",
        "esi-location.read_online.v1",
        "esi-location.read_ship_type.v1",
        "esi-mail.organize_mail.v1",
        "esi-mail.read_mail.v1",
        "esi-mail.send_mail.v1",
        "esi-markets.read_character_orders.v1",
        "esi-planets.manage_planets.v1",
        "esi-search.search_structures.v1",
        "esi-skills.read_skillqueue.v1",
        "esi-skills.read_skills.v1",
        "esi-ui.open_window.v1",
        "esi-ui.write_waypoint.v1",
        "esi-universe.read_structures.v1",
        "esi-wallet.read_character_wallet.v1",
    ]

    public static var scopeString: String { scopes.joined(separator: " ") }
}

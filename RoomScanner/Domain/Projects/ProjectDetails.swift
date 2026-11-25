import Foundation

struct ProjectDetails:Codable,Equatable {
    var street:String?
    var postcode:String?
    var city:String?
    var notes:String?
    var parties:[ProjectParty]?
    var preferences:ProjectPreferences?
    var valid:Bool {
        [street,postcode,city,notes].allSatisfy { ($0?.count ?? 0) <= 4000 } &&
        (parties?.count ?? 0) <= 100 && (parties?.allSatisfy(\.valid) ?? true)
    }
}
struct ProjectParty:Codable,Equatable,Identifiable {
    var id = UUID()
    var role:String?
    var name:String?
    var company:String?
    var phone:String?
    var email:String?
    var notes:String?
    static let roles = ["Client / Bauherr","Architect","Site manager","Renovation company","MEP planner","Other"]
    var valid:Bool { [role,name,company,phone,email,notes].allSatisfy { ($0?.count ?? 0) <= 4000 } }
}
struct ProjectPreferences:Codable,Equatable {
    var language:String?
    var units:String?
    var exportFormat:String?
    var voice:Bool?
    var photos:Bool?
    var storage:String?
}

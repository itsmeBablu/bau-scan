import Foundation

struct ProjectDetails:Codable,Equatable {
    var street:String?
    var postcode:String?
    var city:String?
    var notes:String?
    var floorNames:[Int:String]? = nil
    var parties:[ProjectParty]?
    var preferences:ProjectPreferences?
    var valid:Bool {
        [street,postcode,city,notes].allSatisfy { ($0?.count ?? 0) <= 4000 } &&
        (floorNames?.count ?? 0) <= 1101 && (floorNames?.allSatisfy { (-100...1000).contains($0.key) && !$0.value.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && $0.value.count <= 120 } ?? true) &&
        (parties?.count ?? 0) <= 100 && (parties?.allSatisfy(\.valid) ?? true)
    }
}
struct ProjectParty:Codable,Equatable,Identifiable {
    struct CustomDetail:Codable,Equatable,Identifiable {
        var id = UUID()
        var key:String = ""
        var value:String = ""
        var valid:Bool { key.count <= 240 && value.count <= 4000 }
    }
    var id = UUID()
    var role:String?
    var name:String?
    var company:String?
    var branch:String? = nil
    var address:String? = nil
    var website:String? = nil
    var phone:String?
    var email:String?
    var notes:String?
    var otherDetails:[CustomDetail]? = nil
    static let roles = ["Client / Bauherr","Architect","Builder","Planner","Site manager","Renovation company","MEP planner","Other"]
    var valid:Bool {
        [role,name,company,branch,address,website,phone,email,notes].allSatisfy { ($0?.count ?? 0) <= 4000 } &&
        (otherDetails?.count ?? 0) <= 50 && (otherDetails?.allSatisfy(\.valid) ?? true)
    }
}
struct ProjectPreferences:Codable,Equatable {
    var language:String?
    var units:String?
    var exportFormat:String?
    var voice:Bool?
    var photos:Bool?
    var storage:String?
}

import Foundation
import WaiveraData

/// The web's names for the participant fields a profile change compares.
enum ProfileLabels {
    static func label(_ field: ProfileField.Field) -> String {
        switch field {
        case .dateOfBirth: TasksStrings.text("tasks.field.birth")
        case .firstName: TasksStrings.text("tasks.field.firstName")
        case .lastName: TasksStrings.text("tasks.field.lastName")
        case .email: TasksStrings.text("tasks.field.email")
        case .mobile: TasksStrings.text("tasks.field.mobile")
        case .waiver: TasksStrings.text("tasks.field.waiver")
        case .waiverId: TasksStrings.text("tasks.field.waiverId")
        case .ssn: TasksStrings.text("tasks.field.ssn")
        case .certification: TasksStrings.text("tasks.field.certification")
        case .cpocStart: TasksStrings.text("tasks.field.cpocStart")
        case .cpocEnd: TasksStrings.text("tasks.field.cpocEnd")
        }
    }
}

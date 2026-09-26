import Foundation

public enum EditorEligibility {
    public static func allows(role: String, editable: Bool?, enabled: Bool?, readOnly: Bool?, valueSettable: Bool) -> Bool {
        guard enabled != false, readOnly != true, editable != false else { return false }
        return editable == true || (["AXTextArea", "AXTextField", "AXComboBox"].contains(role) && valueSettable)
    }
}
